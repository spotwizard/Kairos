#!/usr/bin/env bash

set -u

SOURCE_DIR="/Volumes/Untitled/DCIM"
TARGET_ROOT="/Users/robbie/Pictures/原圖"
# 記憶卡的磁碟區（DCIM 的上一層），複製與驗證都成功後自動退出
CARD_VOLUME=$(dirname -- "$SOURCE_DIR")
DISKUTIL_BIN="${KAIROS_DISKUTIL_BIN:-/usr/sbin/diskutil}"
EJECT_ATTEMPTS="${KAIROS_EJECT_ATTEMPTS:-3}"
EJECT_RETRY_SECONDS="${KAIROS_EJECT_RETRY_SECONDS:-3}"
RAW_EXTENSIONS=(
    3fr ari arq arw bay bmq cap cine cr2 cr3 crw cs1 dc2 dcr dcs dng
    drf eip erf fff gpr iiq k25 kdc mdc mef mos mrw nef nrw orf pef
    ptx pxn qtk raf raw rdc rw2 rwl rwz sr2 srf srw sti x3f
)

if [[ ! -d "$SOURCE_DIR" ]]; then
    printf '找不到來源目錄：%s\n' "$SOURCE_DIR" >&2
    exit 1
fi

if ! command -v exiftool >/dev/null 2>&1; then
    printf '找不到 ExifTool，請先執行：brew install exiftool\n' >&2
    exit 1
fi

mkdir -p "$TARGET_ROOT" || exit 1

EXIFTOOL_EXTENSIONS=()
for extension in "${RAW_EXTENSIONS[@]}"; do
    EXIFTOOL_EXTENSIONS+=( -ext "$extension" )
done

EXISTING_FILE_COUNT=0

move_by_date() {
    local tag="$1"
    local condition="$2"
    local error_file
    local exiftool_status
    local duplicate_count
    local has_other_errors=false

    error_file=$(mktemp "${TMPDIR:-/tmp}/kairos_exiftool.XXXXXX") || return 1
    exiftool -r "${EXIFTOOL_EXTENSIONS[@]}" \
        -if "$condition" \
        -o . \
        -d "$TARGET_ROOT/%Y%m%d" \
        "-Directory<$tag" \
        "$SOURCE_DIR" 2> "$error_file"
    exiftool_status=$?

    duplicate_count=$(awk '/already exists - / { count += 1 } END { print count + 0 }' "$error_file")
    if awk '/already exists - / { next } NF { found = 1 } END { exit found ? 0 : 1 }' "$error_file"; then
        has_other_errors=true
    fi
    awk '!/already exists - /' "$error_file" >&2
    rm -f -- "$error_file"

    EXISTING_FILE_COUNT=$((EXISTING_FILE_COUNT + duplicate_count))
    if (( exiftool_status != 0 )) && { (( duplicate_count == 0 )) || [[ "$has_other_errors" == true ]]; }; then
        return "$exiftool_status"
    fi

    return 0
}

print_verify_progress() {
    local current="$1"
    local total="$2"
    local width=30
    local filled=$((current * width / total))
    local percent=$((current * 100 / total))
    local completed
    local remaining

    printf -v completed '%*s' "$filled" ''
    printf -v remaining '%*s' "$((width - filled))" ''
    completed=${completed// /#}
    remaining=${remaining// /-}
    printf '\r驗證進度：[%s%s] %3d%% (%d/%d)' \
        "$completed" "$remaining" "$percent" "$current" "$total"
}

verify_copies() (
    local source metadata capture_date destination extension source_list
    local failed=0
    local current=0
    local total
    local find_extensions=()
    local source_files=()

    for extension in "${RAW_EXTENSIONS[@]}"; do
        if (( ${#find_extensions[@]} > 0 )); then
            find_extensions+=( -o )
        fi
        find_extensions+=( -iname "*.$extension" )
    done

    source_list=$(mktemp "${TMPDIR:-/tmp}/kairos_verify.XXXXXX") || return 1
    if ! find -L "$SOURCE_DIR" \
        \( -type d -name '.*' ! -path "$SOURCE_DIR" -prune \) -o \
        \( -type f \( "${find_extensions[@]}" \) -print0 \) > "$source_list"; then
        rm -f -- "$source_list"
        printf '驗證失敗（無法掃描來源目錄）：%s\n' "$SOURCE_DIR" >&2
        return 1
    fi
    while IFS= read -r -d '' source; do
        source_files+=("$source")
    done < "$source_list"
    rm -f -- "$source_list"

    total=${#source_files[@]}
    printf '\n開始驗證來源與目的地檔案，共 %d 個 RAW 檔案...\n' "$total"
    if (( total == 0 )); then
        return 0
    fi

    for source in "${source_files[@]}"; do
        current=$((current + 1))
        if ! metadata=$(exiftool -s3 \
            -d '%Y%m%d' \
            -DateTimeOriginal -CreateDate \
            "$source"); then
            printf '\n驗證失敗（無法讀取日期 metadata）：%s\n' "$source" >&2
            failed=$((failed + 1))
        else
            capture_date=${metadata%%$'\n'*}
            case "$capture_date" in
                [0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9])
                    destination="$TARGET_ROOT/$capture_date/$(basename -- "$source")"
                    if [[ ! -f "$destination" ]]; then
                        printf '\n驗證失敗（找不到目的地檔案）：%s\n' "$destination" >&2
                        failed=$((failed + 1))
                    elif ! cmp -s -- "$source" "$destination"; then
                        printf '\n驗證失敗（檔案內容不一致）：\n  來源：%s\n  目的地：%s\n' \
                            "$source" "$destination" >&2
                        failed=$((failed + 1))
                    fi
                    ;;
                *)
                    printf '\n驗證失敗（缺少或無效的 DateTimeOriginal/CreateDate）：%s\n' \
                        "$source" >&2
                (( failed += 1 ))
                    ;;
            esac
        fi

        print_verify_progress "$current" "$total"
    done
    printf '\n'

    (( failed == 0 ))
)

# Spotlight 等程式可能還在讀取記憶卡，退出失敗時稍等再試
eject_card() {
    local attempt=1
    local error_output=""

    if [[ ! -x "$DISKUTIL_BIN" ]]; then
        printf '⚠ 找不到 diskutil，無法自動退出記憶卡，請在 Finder 手動退出後再拔除。\n' >&2
        return 1
    fi

    printf '正在退出記憶卡：%s\n' "$CARD_VOLUME"
    while true; do
        if error_output=$("$DISKUTIL_BIN" eject "$CARD_VOLUME" 2>&1); then
            printf '✓ 已退出記憶卡，可以拔除。\n'
            return 0
        fi
        if (( attempt >= EJECT_ATTEMPTS )); then
            break
        fi
        sleep "$EJECT_RETRY_SECONDS"
        attempt=$((attempt + 1))
    done

    printf '%s\n' "$error_output" >&2
    printf '⚠ 無法退出記憶卡（可能有其他程式正在使用），請在 Finder 手動退出後再拔除。\n' >&2
    return 1
}

# 位元組數轉成容易閱讀的單位（與 Finder 相同，1 GB = 1000 MB）；第二個參數為 up 時無條件進位
format_size() {
    awk -v bytes="$1" -v mode="${2:-}" 'BEGIN {
        if (bytes >= 1000000000) { value = bytes / 1000000000; unit = "GB"; scale = 100 }
        else { value = bytes / 1000000; unit = "MB"; scale = 10 }
        scaled = value * scale
        if (mode == "up") { rounded = int(scaled); if (rounded < scaled) rounded += 1 }
        else { rounded = int(scaled + 0.5) }
        printf (scale == 100 ? "%.2f%s" : "%.1f%s"), rounded / scale, unit
    }'
}

# 複製前先確認目的地硬碟放得下尚未複製的 RAW；空間足夠時不顯示訊息，不足時回報尚需多少並回傳 1
check_free_space() {
    local list_file size original_date create_date path capture_date
    local required_bytes=0
    local available_kb available_bytes

    list_file=$(mktemp "${TMPDIR:-/tmp}/kairos_space.XXXXXX") || return 0
    # 個別檔案讀取失敗時 ExifTool 會回傳非 0，這裡只採用成功列出的檔案，讀取錯誤留給複製步驟回報
    exiftool -r -f -m -q "${EXIFTOOL_EXTENSIONS[@]}" \
        -d '%Y%m%d' \
        -p '$FileSize#	$DateTimeOriginal	$CreateDate	$Directory/$FileName' \
        "$SOURCE_DIR" > "$list_file" 2>/dev/null

    while IFS=$'\t' read -r size original_date create_date path; do
        case "$size" in
            ''|*[!0-9]*) continue ;;
        esac
        capture_date="$original_date"
        if [[ "$capture_date" == "-" ]]; then
            capture_date="$create_date"
        fi
        # 沒有拍攝日期的檔案不會被複製，已存在於目的地的檔案也會略過
        case "$capture_date" in
            [0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]) ;;
            *) continue ;;
        esac
        if [[ -e "$TARGET_ROOT/$capture_date/$(basename -- "$path")" ]]; then
            continue
        fi
        required_bytes=$((required_bytes + size))
    done < "$list_file"
    rm -f -- "$list_file"

    if (( required_bytes == 0 )); then
        return 0
    fi

    # 可用空間取「容量百分比」欄位的前一欄，磁碟名稱含空白時也不會取錯
    available_kb=$(df -Pk "$TARGET_ROOT" 2>/dev/null | awk 'NR > 1 {
        for (i = 2; i <= NF; i++) if ($i ~ /^[0-9]+%$/) { print $(i - 1); exit }
    }')
    case "$available_kb" in
        ''|*[!0-9]*)
            printf '⚠ 無法取得硬碟可用空間，略過空間檢查：%s\n' "$TARGET_ROOT" >&2
            return 0
            ;;
    esac
    available_bytes=$((available_kb * 1024))

    if (( required_bytes > available_bytes )); then
        printf '目前無法複製檔案，尚需%s硬碟空間\n' \
            "$(format_size "$((required_bytes - available_bytes))" up)" >&2
        return 1
    fi

    return 0
}

check_free_space || exit 1

status=0
move_by_date DateTimeOriginal 'defined $DateTimeOriginal'
result=$?
(( result == 0 || result == 2 )) || status=$result

move_by_date CreateDate \
    'not defined $DateTimeOriginal and defined $CreateDate'
result=$?
(( result == 0 || result == 2 )) || status=$result

if (( EXISTING_FILE_COUNT > 0 )); then
    printf '已存在，略過複製並交由內容驗證：%d 個 RAW 檔案。\n' "$EXISTING_FILE_COUNT"
fi

if verify_copies; then
    printf '驗證成功：所有 RAW 檔案的路徑與內容均正確。\n'
else
    if (( status == 0 )); then
        status=1
    fi
    printf '驗證未通過。\n' >&2
fi

if (( status == 0 )); then
    printf '複製與驗證完成。所有來源檔案均已保留。\n'
    # 退出失敗不影響已完成的複製，只提示手動退出
    eject_card || true
else
    printf '複製或驗證失敗。所有來源檔案均已保留。\n' >&2
fi

exit "$status"
