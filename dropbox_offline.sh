#!/bin/bash

# Dropbox 設為「僅供線上存取」的檔案，在本機只是佔位檔：大小為 0（或沒有實際內容），
# 並帶有 com.dropbox.placeholder 屬性；Photoshop 讀不到內容，會出現「無法辨識此類型的檔案」。
# 佔位檔的預設開啟程式是 Dropbox.app，對它執行 `open -a Dropbox` 會讓 Dropbox 下載檔案。
# make_available_offline 會找出這類檔案、請 Dropbox 下載，並等到下載完成。
# 本檔由 afterraw.sh 以 source 載入。

# 固定用 macOS 內建的 stat、xattr；PATH 前面若有別的版本（例如 conda 裝的 GNU 版），參數意義不同，會判斷錯誤
if [ -n "${KAIROS_STAT_BIN:-}" ]; then
    OFFLINE_STAT_BIN="$KAIROS_STAT_BIN"
elif [ -x /usr/bin/stat ]; then
    OFFLINE_STAT_BIN=/usr/bin/stat
else
    OFFLINE_STAT_BIN=stat
fi
if [ -n "${KAIROS_XATTR_BIN:-}" ]; then
    OFFLINE_XATTR_BIN="$KAIROS_XATTR_BIN"
elif [ -x /usr/bin/xattr ]; then
    OFFLINE_XATTR_BIN=/usr/bin/xattr
else
    OFFLINE_XATTR_BIN=xattr
fi
OFFLINE_OPEN_BIN="${KAIROS_OPEN_BIN:-open}"
OFFLINE_PGREP_BIN="${KAIROS_PGREP_BIN:-pgrep}"
OFFLINE_OSASCRIPT_BIN="${KAIROS_OSASCRIPT_BIN:-osascript}"
OFFLINE_KILLALL_BIN="${KAIROS_KILLALL_BIN:-killall}"
OFFLINE_CLEANUP_WAIT_SECONDS="${KAIROS_OFFLINE_CLEANUP_WAIT_SECONDS:-8}"
# Dropbox 下載完檔案後會用預設程式開啟它：RAW 會開在這些 app，旁邊的 .xmp、.acr 則跳出「未設定應用程式」對話框
OFFLINE_SIDE_EFFECT_APPS=(Preview Photos)
# 「未設定應用程式來打開文件」對話框上的按鈕文字（英文介面的對應文字寫在 AppleScript 內）
OFFLINE_DIALOG_CHOOSE_PREFIX="選擇應用程式"
OFFLINE_DIALOG_CANCEL="取消"
OFFLINE_DOWNLOAD_SECONDS="${KAIROS_OFFLINE_DOWNLOAD_SECONDS:-600}"

# 輸出「旗標 大小 區塊數」，旗標沒有時為 -
file_storage_info() {
    "$OFFLINE_STAT_BIN" -f '%Sf %z %b' -- "$1" 2>/dev/null
}

file_is_placeholder() {
    "$OFFLINE_XATTR_BIN" -p com.dropbox.placeholder "$1" > /dev/null 2>&1
}

# 僅供線上存取的檔案有三個特徵，符合任一個就視為尚未下載：
# 帶有 com.dropbox.placeholder 屬性；檔案旗標含 dataless；
# 或檔案大小大於 0 但實際佔用的區塊數為 0（只有佔位檔，沒有內容）
file_is_online_only() {
    local info
    local flags
    local size
    local blocks

    file_is_placeholder "$1" && return 0

    info=$(file_storage_info "$1") || return 1
    flags="${info%% *}"
    info="${info#* }"
    size="${info%% *}"
    blocks="${info#* }"

    [[ "$flags" = *dataless* ]] && return 0
    [[ "$size" =~ ^[0-9]+$ ]] && [[ "$blocks" =~ ^[0-9]+$ ]] && [ "$size" -gt 0 ] && [ "$blocks" -eq 0 ]
}

# 找出尚未下載的檔案放入 PENDING_FILES
collect_online_only_files() {
    local file

    PENDING_FILES=()
    for file in "$@"; do
        if file_is_online_only "$file"; then
            PENDING_FILES+=("$file")
        fi
    done
}

# 找出大小為 0 的檔案放入 EMPTY_FILES；旁邊的 .xmp、.acr 不檢查
collect_empty_files() {
    local file
    local info

    EMPTY_FILES=()
    for file in "$@"; do
        case "$file" in
            *.[Xx][Mm][Pp]|*.[Aa][Cc][Rr]) continue ;;
        esac
        info=$(file_storage_info "$file") || continue
        info="${info#* }"
        if [ "${info%% *}" = "0" ]; then
            EMPTY_FILES+=("$file")
        fi
    done
}

# 請 Dropbox 下載一個檔案：佔位檔交給 Dropbox.app 開啟（-g 不把它帶到前景），
# 其餘（例如 dataless）讀取一次內容觸發下載
request_download() {
    if file_is_placeholder "$1"; then
        "$OFFLINE_OPEN_BIN" -g -a Dropbox "$1" > /dev/null 2>&1
    else
        cat -- "$1" > /dev/null 2>&1
    fi
}

# 記錄哪些 app 在下載前已經開著，之後只關閉因下載才被開啟的，不動使用者原本開著的視窗
snapshot_running_apps() {
    local app

    OFFLINE_APPS_BEFORE=()
    for app in "${OFFLINE_SIDE_EFFECT_APPS[@]}"; do
        if "$OFFLINE_PGREP_BIN" -x "$app" > /dev/null 2>&1; then
            OFFLINE_APPS_BEFORE+=("$app")
        fi
    done
}

# 用「系統事件」找出「未設定應用程式來打開文件」對話框並按「取消」，輸出關閉的數量。
# 只認同時有「選擇應用程式…」與「取消」按鈕的對話框；不確定對話框屬於哪個程式，
# 所以檢查 CoreServicesUIAgent、Finder、Dropbox 三者。需要終端機的「輔助使用」權限（前置作業操作 Camera Raw 時已需要）
dismiss_no_app_dialogs() {
    "$OFFLINE_OSASCRIPT_BIN" - "$OFFLINE_DIALOG_CHOOSE_PREFIX" "$OFFLINE_DIALOG_CANCEL" <<'APPLESCRIPT' 2> /dev/null
on run argv
    set choosePrefixes to {item 1 of argv, "Choose Application"}
    set cancelNames to {item 2 of argv, "Cancel"}
    set closedCount to 0
    tell application "System Events"
        repeat with procItem in {"CoreServicesUIAgent", "Finder", "Dropbox"}
            set procName to procItem as text
            if exists process procName then
                set proc to process procName
                repeat with i from (count of windows of proc) to 1 by -1
                    try
                        set win to window i of proc
                        set isCandidate to (procName is "CoreServicesUIAgent")
                        if not isCandidate then
                            try
                                set isCandidate to ((subrole of win) is in {"AXDialog", "AXSystemDialog"})
                            end try
                        end if
                        if isCandidate then
                            set hasChoose to false
                            set cancelButton to missing value
                            repeat with uiItem in (entire contents of win)
                                try
                                    if class of uiItem is button then
                                        set buttonName to name of uiItem
                                        if buttonName is not missing value then
                                            repeat with choosePrefix in choosePrefixes
                                                if buttonName starts with (choosePrefix as text) then set hasChoose to true
                                            end repeat
                                            if cancelNames contains buttonName then set cancelButton to contents of uiItem
                                        end if
                                    end if
                                end try
                            end repeat
                            if hasChoose and cancelButton is not missing value then
                                click cancelButton
                                set closedCount to closedCount + 1
                            end if
                        end if
                    end try
                end repeat
            end if
        end repeat
    end tell
    return closedCount
end run
APPLESCRIPT
}

# 關閉對話框並累計到 OFFLINE_DIALOGS_CLOSED
dismiss_and_count_dialogs() {
    local closed

    closed=$(dismiss_no_app_dialogs)
    if [[ "$closed" =~ ^[0-9]+$ ]]; then
        OFFLINE_DIALOGS_CLOSED=$((OFFLINE_DIALOGS_CLOSED + closed))
    fi
    return 0
}

# Dropbox 在下載完成後才開啟檔案，對話框可能晚幾秒出現，
# 因此在 OFFLINE_CLEANUP_WAIT_SECONDS 秒內每秒檢查一次，出現就關閉
cleanup_download_side_effects() {
    local app
    local before
    local was_running
    local waited=0

    while true; do
        dismiss_and_count_dialogs
        [ "$waited" -ge "$OFFLINE_CLEANUP_WAIT_SECONDS" ] && break
        sleep 1
        waited=$((waited + 1))
    done
    for app in "${OFFLINE_SIDE_EFFECT_APPS[@]}"; do
        was_running=false
        for before in "${OFFLINE_APPS_BEFORE[@]}"; do
            [ "$before" = "$app" ] && was_running=true
        done
        if [ "$was_running" = false ] && "$OFFLINE_PGREP_BIN" -x "$app" > /dev/null 2>&1; then
            "$OFFLINE_OSASCRIPT_BIN" -e "tell application \"$app\" to quit" > /dev/null 2>&1
        fi
    done
    # 終端機沒有「輔助使用」權限時上面無法按按鈕；結束這個背景程式也能關掉由它顯示的對話框，系統會自動重新啟動它
    "$OFFLINE_KILLALL_BIN" CoreServicesUIAgent > /dev/null 2>&1
    if [ "$OFFLINE_DIALOGS_CLOSED" -gt 0 ]; then
        echo "已關閉 ${OFFLINE_DIALOGS_CLOSED} 個「未設定應用程式來打開文件」對話框"
    fi
    return 0
}

# 參數為檔案路徑；已在本機的檔案不處理。有檔案無法下載、下載逾時或沒有內容時回傳 1
make_available_offline() {
    local file
    local waited=0
    local requested
    local -a files=()

    for file in "$@"; do
        [ -f "$file" ] && files+=("$file")
    done
    [ "${#files[@]}" -gt 0 ] || return 0

    collect_online_only_files "${files[@]}"
    requested="${#PENDING_FILES[@]}"

    if [ "$requested" -gt 0 ]; then
        echo "有 ${requested} 個檔案僅供線上存取，正在請 Dropbox 下載到本機（最多等待 ${OFFLINE_DOWNLOAD_SECONDS} 秒）..."
        snapshot_running_apps
        OFFLINE_DIALOGS_CLOSED=0
        for file in "${PENDING_FILES[@]}"; do
            echo "下載：$(basename "$file")"
            request_download "$file"
        done

        while true; do
            collect_online_only_files "${PENDING_FILES[@]}"
            if [ "${#PENDING_FILES[@]}" -eq 0 ] || [ "$waited" -ge "$OFFLINE_DOWNLOAD_SECONDS" ]; then
                break
            fi
            sleep 1
            waited=$((waited + 1))
            # 下載期間先下載完的 .xmp、.acr 已經跳出對話框，每 5 秒關一次，避免一直疊上去
            if [ $((waited % 5)) -eq 0 ]; then
                dismiss_and_count_dialogs
            fi
            if [ $((waited % 10)) -eq 0 ]; then
                echo "  等待 Dropbox 下載中，尚有 ${#PENDING_FILES[@]} 個檔案..."
            fi
        done

        cleanup_download_side_effects

        if [ "${#PENDING_FILES[@]}" -gt 0 ]; then
            for file in "${PENDING_FILES[@]}"; do
                echo "✗ 尚未下載完成：$(basename "$file")"
            done
            echo "Dropbox 仍在下載或沒有回應。請開啟 Dropbox 確認同步狀態，"
            echo "或在 Finder 對該專案資料夾按右鍵選「設為可離線使用」，完成後重試"
            return 1
        fi
    fi

    # 下載完成後仍為 0 位元組的檔案沒有內容，Photoshop 無法辨識
    collect_empty_files "${files[@]}"
    if [ "${#EMPTY_FILES[@]}" -gt 0 ]; then
        for file in "${EMPTY_FILES[@]}"; do
            echo "✗ 檔案大小為 0 位元組（沒有內容）：$(basename "$file")"
        done
        echo "共 ${#EMPTY_FILES[@]} 個檔案沒有內容，Photoshop 無法開啟。"
        echo "請從原圖封存或 Dropbox 網頁版的歷史版本還原"
        return 1
    fi

    if [ "$requested" -gt 0 ]; then
        echo "✓ 已下載 ${requested} 個檔案到本機"
    else
        echo "✓ 檔案皆已在本機，不需從 Dropbox 下載"
    fi
    return 0
}
