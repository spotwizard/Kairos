#!/usr/bin/env bash

set -u

SOURCE_DIR="/Volumes/Untitled/DCIM"
TARGET_ROOT="/Users/robbie/Pictures/原圖"
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
else
    printf '複製或驗證失敗。所有來源檔案均已保留。\n' >&2
fi

exit "$status"
