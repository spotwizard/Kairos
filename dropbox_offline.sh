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

# 參數為檔案路徑；已在本機的檔案不處理。有檔案無法下載時回傳 1
make_available_offline() {
    local file
    local running=0
    local waited=0
    local failed
    local sample=""
    local -a pending=()

    for file in "$@"; do
        [ -f "$file" ] || continue
        if [ -z "$sample" ]; then
            sample="$(basename "$file")（旗標、大小、區塊數：$(file_storage_info "$file" || echo '無法讀取')）"
        fi
        if file_is_online_only "$file"; then
            pending+=("$file")
        fi
    done

    if [ "${#pending[@]}" -eq 0 ]; then
        echo "✓ 檔案皆已在本機，不需從 Dropbox 下載"
        [ -z "$sample" ] || echo "  檢查範例：$sample"
        return 0
    fi

    echo "有 ${#pending[@]} 個檔案僅供線上存取，正在請 Dropbox 下載到本機..."
    for file in "${pending[@]}"; do
        echo "下載：$(basename "$file")"
        cat -- "$file" > /dev/null 2>&1 &
        running=$((running + 1))
        if [ "$running" -ge "$OFFLINE_DOWNLOAD_PARALLEL" ]; then
            wait
            running=0
        fi
    done
    wait

    while true; do
        failed=()
        for file in "${pending[@]}"; do
            if file_is_online_only "$file"; then
                failed+=("$file")
            fi
        done
        if [ "${#failed[@]}" -eq 0 ] || [ "$waited" -ge "$OFFLINE_VERIFY_SECONDS" ]; then
            break
        fi
        sleep 1
        waited=$((waited + 1))
    done

    if [ "${#failed[@]}" -gt 0 ]; then
        for file in "${failed[@]}"; do
            echo "✗ 無法下載到本機：$file"
        done
        echo "請確認 Dropbox 已連線並正常同步後重試"
        return 1
    fi

    echo "✓ 已下載 ${#pending[@]} 個檔案到本機"
    return 0
}
