#!/bin/bash

# Dropbox 設為「僅供線上存取」的檔案，在本機只是佔位檔（檔案旗標含 dataless），
# Photoshop 讀不到內容，會出現「無法辨識此類型的檔案」。
# make_available_offline 會找出這類檔案，讀取一次內容讓 Dropbox 下載到本機。
# 本檔由 afterraw.sh 以 source 載入。

# 固定用 macOS 內建的 stat；PATH 前面若有別的 stat（例如 conda 裝的 GNU 版），-f 的意義不同，會判斷錯誤
if [ -n "${KAIROS_STAT_BIN:-}" ]; then
    OFFLINE_STAT_BIN="$KAIROS_STAT_BIN"
elif [ -x /usr/bin/stat ]; then
    OFFLINE_STAT_BIN=/usr/bin/stat
else
    OFFLINE_STAT_BIN=stat
fi
OFFLINE_DOWNLOAD_PARALLEL="${KAIROS_OFFLINE_PARALLEL:-4}"
OFFLINE_VERIFY_SECONDS="${KAIROS_OFFLINE_VERIFY_SECONDS:-30}"
OFFLINE_FPCTL_BIN="${KAIROS_FILEPROVIDERCTL_BIN:-fileproviderctl}"
OFFLINE_MATERIALIZE_SECONDS="${KAIROS_OFFLINE_MATERIALIZE_SECONDS:-300}"

# 輸出「旗標 大小 區塊數」，旗標沒有時為 -
file_storage_info() {
    "$OFFLINE_STAT_BIN" -f '%Sf %z %b' -- "$1" 2>/dev/null
}

# 僅供線上存取的檔案有兩個特徵，符合任一個就視為尚未下載：
# 檔案旗標含 dataless；或檔案大小大於 0 但實際佔用的區塊數為 0（只有佔位檔，沒有內容）
file_is_online_only() {
    local info
    local flags
    local size
    local blocks

    info=$(file_storage_info "$1") || return 1
    flags="${info%% *}"
    info="${info#* }"
    size="${info%% *}"
    blocks="${info#* }"

    [[ "$flags" = *dataless* ]] && return 0
    [[ "$size" =~ ^[0-9]+$ ]] && [[ "$blocks" =~ ^[0-9]+$ ]] && [ "$size" -gt 0 ] && [ "$blocks" -eq 0 ]
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

# Dropbox 的佔位檔可能顯示大小為 0，此時單純讀取不會觸發下載（讀到檔案結尾就結束），
# 改用 fileproviderctl 要求系統把檔案內容下載下來，並等到大小不再是 0
materialize_empty_files() {
    local file
    local running=0
    local waited=0

    command -v "$OFFLINE_FPCTL_BIN" > /dev/null 2>&1 || return 0

    echo "有 ${#EMPTY_FILES[@]} 個檔案大小為 0，嘗試請 Dropbox 下載（最多等待 ${OFFLINE_MATERIALIZE_SECONDS} 秒）..."
    for file in "${EMPTY_FILES[@]}"; do
        "$OFFLINE_FPCTL_BIN" materialize "$file" > /dev/null 2>&1 &
        running=$((running + 1))
        if [ "$running" -ge "$OFFLINE_DOWNLOAD_PARALLEL" ]; then
            wait
            running=0
        fi
    done
    wait

    while true; do
        collect_empty_files "${EMPTY_FILES[@]}"
        if [ "${#EMPTY_FILES[@]}" -eq 0 ] || [ "$waited" -ge "$OFFLINE_MATERIALIZE_SECONDS" ]; then
            return 0
        fi
        sleep 1
        waited=$((waited + 1))
        if [ $((waited % 10)) -eq 0 ]; then
            echo "  等待 Dropbox 下載中，尚有 ${#EMPTY_FILES[@]} 個檔案..."
        fi
    done
}

# 參數為檔案路徑；每個檔案都完整讀取一次。
# 本機已有內容的檔案很快讀完；僅供線上存取的檔案會在讀取時由 Dropbox 下載。
# 不先依檔案狀態判斷是否需要下載，是因為實機上偵測曾漏掉這類檔案。
# 有檔案讀取失敗或仍是佔位檔時回傳 1
make_available_offline() {
    local file
    local index
    local running=0
    local waited=0
    local online_before=0
    local started="$SECONDS"
    local status_dir
    local sample=""
    local -a files=()
    local -a failed=()

    for file in "$@"; do
        [ -f "$file" ] && files+=("$file")
    done
    [ "${#files[@]}" -gt 0 ] || return 0

    status_dir=$(mktemp -d "${TMPDIR:-/tmp}/kairos_offline.XXXXXX") || return 1

    echo "確認 ${#files[@]} 個檔案可讀取；僅供線上存取的檔案會由 Dropbox 下載到本機，可能需要一些時間..."
    sample="$(basename "${files[0]}")（旗標、大小、區塊數：$(file_storage_info "${files[0]}" || echo '無法讀取')）"
    for index in "${!files[@]}"; do
        file="${files[$index]}"
        if file_is_online_only "$file"; then
            online_before=$((online_before + 1))
            echo "下載：$(basename "$file")"
        fi
        ( cat -- "$file" > /dev/null 2>&1 || : > "$status_dir/$index" ) &
        running=$((running + 1))
        if [ "$running" -ge "$OFFLINE_DOWNLOAD_PARALLEL" ]; then
            wait
            running=0
        fi
    done
    wait

    # 讀取完成後仍是佔位檔的，再等 Dropbox 一段時間
    while true; do
        failed=()
        for index in "${!files[@]}"; do
            if [ -e "$status_dir/$index" ] || file_is_online_only "${files[$index]}"; then
                failed+=("${files[$index]}")
            fi
        done
        if [ "${#failed[@]}" -eq 0 ] || [ "$waited" -ge "$OFFLINE_VERIFY_SECONDS" ]; then
            break
        fi
        sleep 1
        waited=$((waited + 1))
    done
    rm -rf "$status_dir"

    # 大小為 0 的檔案沒有內容，Photoshop 無法辨識
    collect_empty_files "${files[@]}"
    if [ "${#EMPTY_FILES[@]}" -gt 0 ]; then
        materialize_empty_files
    fi
    if [ "${#EMPTY_FILES[@]}" -gt 0 ]; then
        for file in "${EMPTY_FILES[@]}"; do
            echo "✗ 檔案大小為 0 位元組（沒有內容）：$(basename "$file")"
        done
        echo "共 ${#EMPTY_FILES[@]} 個檔案沒有內容，Photoshop 無法開啟。"
        echo "請先在 Finder 對該專案資料夾按右鍵選「設為可離線使用」，等 Dropbox 同步完成後重試；"
        echo "若仍是 0 位元組，請從原圖封存或 Dropbox 網頁版的歷史版本還原"
        return 1
    fi

    if [ "${#failed[@]}" -gt 0 ]; then
        for file in "${failed[@]}"; do
            echo "✗ 無法讀取或下載到本機：$file"
        done
        echo "請確認 Dropbox 已連線並正常同步後重試"
        return 1
    fi

    echo "✓ ${#files[@]} 個檔案皆可讀取（其中 ${online_before} 個原本僅供線上存取），耗時 $((SECONDS - started)) 秒"
    echo "  檢查範例：$sample"
    return 0
}
