#!/bin/bash

# Dropbox 設為「僅供線上存取」的檔案，在本機只是佔位檔（檔案旗標含 dataless），
# Photoshop 讀不到內容，會出現「無法辨識此類型的檔案」。
# make_available_offline 會找出這類檔案，讀取一次內容讓 Dropbox 下載到本機。
# 本檔由 afterraw.sh 以 source 載入。

OFFLINE_STAT_BIN="${KAIROS_STAT_BIN:-stat}"
OFFLINE_DOWNLOAD_PARALLEL="${KAIROS_OFFLINE_PARALLEL:-4}"
OFFLINE_VERIFY_SECONDS="${KAIROS_OFFLINE_VERIFY_SECONDS:-30}"

file_is_online_only() {
    local flags

    flags=$("$OFFLINE_STAT_BIN" -f '%Sf' -- "$1" 2>/dev/null) || return 1
    [[ "$flags" = *dataless* ]]
}

# 參數為檔案路徑；已在本機的檔案不處理。有檔案無法下載時回傳 1
make_available_offline() {
    local file
    local running=0
    local waited=0
    local failed
    local -a pending=()

    for file in "$@"; do
        [ -f "$file" ] || continue
        if file_is_online_only "$file"; then
            pending+=("$file")
        fi
    done

    if [ "${#pending[@]}" -eq 0 ]; then
        echo "✓ 檔案皆已在本機，不需從 Dropbox 下載"
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
