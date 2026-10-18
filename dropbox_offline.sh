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
            if [ $((waited % 10)) -eq 0 ]; then
                echo "  等待 Dropbox 下載中，尚有 ${#PENDING_FILES[@]} 個檔案..."
            fi
        done

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
