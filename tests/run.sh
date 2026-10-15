#!/usr/bin/env bash

set -u

ROOT=$(cd "$(dirname "$0")/.." && pwd)
TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/kairos_test.XXXXXX") || exit 1
trap 'rm -rf "$TEST_ROOT"' EXIT HUP INT TERM

fail() {
    printf '測試失敗：%s\n' "$1" >&2
    exit 1
}

expect_file() {
    [ -f "$1" ] || fail "找不到檔案 $1"
}

expect_dir() {
    [ -d "$1" ] || fail "找不到目錄 $1"
}

test_syntax() {
    /bin/bash -n \
        "$ROOT/kairos" \
        "$ROOT/organize_raw_by_date.sh" \
        "$ROOT/rename_raw.sh" \
        "$ROOT/afterraw.sh" \
        "$ROOT/tests/run.sh" || fail "Shell 語法檢查未通過"

    # macOS 內建 bash 3.2 會把緊接在 $變數 後面的中文字元當成變數名稱的一部分，必須寫成 ${變數}
    if LC_ALL=C grep -n $'\\$[A-Za-z_][A-Za-z0-9_]*[\x80-\xff]' \
        "$ROOT/kairos" \
        "$ROOT/organize_raw_by_date.sh" \
        "$ROOT/rename_raw.sh" \
        "$ROOT/afterraw.sh"; then
        fail "變數後面緊接非 ASCII 字元時必須加大括號"
    fi
}

test_organize_raw_by_date() {
    local test_dir="$TEST_ROOT/organize"
    local source_dir="$test_dir/source/DCIM"
    local target_root="$test_dir/target"
    local mock_bin="$test_dir/bin"
    local test_script="$test_dir/organize_raw_by_date.sh"
    local output

    mkdir -p "$source_dir/相機 A" "$target_root" "$mock_bin"
    sed \
        -e "s|^SOURCE_DIR=.*|SOURCE_DIR=\"$source_dir\"|" \
        -e "s|^TARGET_ROOT=.*|TARGET_ROOT=\"$target_root\"|" \
        "$ROOT/organize_raw_by_date.sh" > "$test_script"
    chmod +x "$test_script"

    cat > "$mock_bin/exiftool" <<'MOCK'
#!/usr/bin/env bash

for argument in "$@"; do
    if [ "$argument" = "-s3" ]; then
        source=${!#}
        case "${source##*/}" in
            ORIGINAL.*) printf '20260815\n' ;;
            FALLBACK.*) printf '20260816\n' ;;
            NO_DATE.*) ;;
        esac
        exit 0
    fi
done

if [ "${MOCK_SKIP_COPY:-0}" = "1" ]; then
    exit 2
fi
if [ "${MOCK_OTHER_ERROR:-0}" = "1" ]; then
    printf 'Error: simulated read failure\n' >&2
    exit 3
fi

date_pattern=""
condition=""
previous=""
for argument in "$@"; do
    if [ "$previous" = "-d" ]; then
        date_pattern="$argument"
    fi
    if [ "$previous" = "-if" ]; then
        condition="$argument"
    fi
    previous="$argument"
done

source_root=${!#}
duplicate_count=0
while IFS= read -r -d '' source; do
    name=${source##*/}
    date=""
    case "$condition:$name" in
        *'not defined $DateTimeOriginal'*:FALLBACK.*) date="20260816" ;;
        *'not defined $DateTimeOriginal'*:*) ;;
        *'defined $DateTimeOriginal'*:ORIGINAL.*) date="20260815" ;;
    esac
    [ -n "$date" ] || continue
    destination=${date_pattern//%Y%m%d/$date}
    mkdir -p "$destination"
    if [ -e "$destination/$name" ]; then
        printf "Error: '%s' already exists - %s\n" "$destination/$name" "$source" >&2
        duplicate_count=$((duplicate_count + 1))
    else
        cp "$source" "$destination/$name"
    fi
done < <(find "$source_root" -type f -print0)

if [ "$duplicate_count" -gt 0 ]; then
    exit 1
fi
exit 0
MOCK
    chmod +x "$mock_bin/exiftool"

    printf 'ORIGINAL' > "$source_dir/相機 A/ORIGINAL.ArW"
    printf 'FALLBACK' > "$source_dir/相機 A/FALLBACK.CR2"
    if ! output=$(PATH="$mock_bin:$PATH" "$test_script" 2>&1); then
        fail "RAW 日期分類預期成功：$output"
    fi
    expect_file "$target_root/20260815/ORIGINAL.ArW"
    expect_file "$target_root/20260816/FALLBACK.CR2"
    [[ "$output" = *"驗證進度："*"100% (2/2)"* ]] || fail "驗證進度條未完成到 100%：$output"

    if ! output=$(PATH="$mock_bin:$PATH" "$test_script" 2>&1); then
        fail "目的檔內容相同時不應該失敗：$output"
    fi
    [[ "$output" = *"已存在，略過複製並交由內容驗證：2 個 RAW 檔案"* ]] || fail "未摘要已存在的 RAW：$output"
    [[ "$output" != *"already exists"* ]] || fail "不應把已存在且相同的 RAW 顯示成 Error"

    if output=$(MOCK_OTHER_ERROR=1 PATH="$mock_bin:$PATH" "$test_script" 2>&1); then
        fail "非重複檔案的 ExifTool 錯誤不應被忽略"
    fi
    [[ "$output" = *"simulated read failure"* ]] || fail "真正的 ExifTool 錯誤沒有保留"

    printf 'DIFFERENT' > "$target_root/20260815/ORIGINAL.ArW"
    if output=$(MOCK_SKIP_COPY=1 PATH="$mock_bin:$PATH" "$test_script" 2>&1); then
        fail "內容不一致時應該失敗"
    fi
    [[ "$output" = *"檔案內容不一致"* ]] || fail "未回報內容不一致"

    printf 'ORIGINAL' > "$target_root/20260815/ORIGINAL.ArW"
    rm -f "$target_root/20260816/FALLBACK.CR2"
    if output=$(MOCK_SKIP_COPY=1 PATH="$mock_bin:$PATH" "$test_script" 2>&1); then
        fail "目的檔缺失時應該失敗"
    fi
    [[ "$output" = *"找不到目的地檔案"* ]] || fail "未回報目的檔缺失"

    printf 'FALLBACK' > "$target_root/20260816/FALLBACK.CR2"
    printf 'NO DATE' > "$source_dir/相機 A/NO_DATE.DNG"
    if output=$(MOCK_SKIP_COPY=1 PATH="$mock_bin:$PATH" "$test_script" 2>&1); then
        fail "缺少拍攝日期時應該失敗"
    fi
    [[ "$output" = *"缺少或無效的 DateTimeOriginal/CreateDate"* ]] || fail "未回報日期 metadata 缺失"
}

test_rename_raw() {
    local test_dir="$TEST_ROOT/rename"
    local source_dir="$test_dir/Transfer"
    local target_root="$test_dir/攝影"
    local test_script="$test_dir/rename_raw.sh"
    local project="$target_root/店家 A"

    mkdir -p "$source_dir/店家 A-20260815" "$source_dir/不處理" "$source_dir/空店-20260815" "$target_root"
    printf 'ARW' > "$source_dir/店家 A-20260815/IMG0001.ARW"
    printf 'DNG' > "$source_dir/店家 A-20260815/IMG0002.dng"
    printf 'CR2' > "$source_dir/店家 A-20260815/20260815_IMG0003.CR2"
    printf 'KEEP' > "$source_dir/不處理/IMG0004.ARW"
    printf 'TEXT' > "$source_dir/空店-20260815/readme.txt"

    sed \
        -e "s|^SOURCE_DIR=.*|SOURCE_DIR=\"$source_dir\"|" \
        -e "s|TARGET_DIR=\"/Users/robbie/Dropbox/__攝影/\${store_name}\"|TARGET_DIR=\"$target_root/\${store_name}\"|" \
        "$ROOT/rename_raw.sh" > "$test_script"
    chmod +x "$test_script"
    "$test_script" > "$test_dir/output.log" 2>&1 || fail "Transfer RAW 搬移程序失敗"

    expect_dir "$project/RAW"
    expect_dir "$project/PSD"
    expect_dir "$project/IG"
    expect_dir "$project/FB"
    expect_file "$project/RAW/20260815_IMG0001.ARW"
    expect_file "$project/RAW/20260815_IMG0002.dng"
    expect_file "$project/RAW/20260815_IMG0003.CR2"
    expect_file "$source_dir/不處理/IMG0004.ARW"
    [ ! -e "$source_dir/店家 A-20260815/IMG0001.ARW" ] || fail "ARW 來源檔未搬移"
}

write_dashboard_mocks() {
    local mock_dir="$TEST_ROOT/dashboard"

    mkdir -p "$mock_dir/photos/Stone House/RAW" "$mock_dir/photos/New Project/IG" "$mock_dir/photos/Empty"
    touch -t 202608010000 "$mock_dir/photos/Stone House/RAW/photo.ARW"
    touch -t 202608160000 "$mock_dir/photos/New Project/IG/photo.JpEg"
    touch -t 202608200000 "$mock_dir/photos/Stone House/RAW/photo.xmp" "$mock_dir/photos/Stone House"
    printf 'Stone House\n' > "$mock_dir/current_photo_edit_dir"
    cat > "$mock_dir/gum" <<'MOCK'
#!/usr/bin/env bash

command_name="$1"
shift
case "$command_name" in
    style) printf '%s\n' "${!#}" ;;
    choose)
        header=""
        while [ "$#" -gt 0 ]; do
            case "$1" in
                --header) header="$2"; shift 2 ;;
                --height) shift 2 ;;
                --) shift; break ;;
                *) exit 2 ;;
            esac
        done
        printf '%s' "$header" >> "$KAIROS_MENU_LOG"
        printf '\t%s' "$@" >> "$KAIROS_MENU_LOG"
        printf '\n' >> "$KAIROS_MENU_LOG"
        IFS= read -r selection || exit 130
        index=1
        for option in "$@"; do
            if [ "$selection" = "$index" ]; then
                printf '%s\n' "$option"
                exit 0
            fi
            index=$((index + 1))
        done
        exit 130
        ;;
    confirm)
        printf 'confirm' >> "$KAIROS_MENU_LOG"
        printf '\t%s' "$@" >> "$KAIROS_MENU_LOG"
        printf '\n' >> "$KAIROS_MENU_LOG"
        IFS= read -r selection || exit 130
        [ "$selection" = "y" ]
        ;;
    *) exit 2 ;;
esac
MOCK
    chmod +x "$mock_dir/gum"

    for worker in organize-worker rename-worker afterraw-worker; do
        cat > "$mock_dir/$worker" <<'MOCK'
#!/usr/bin/env bash

printf '%s' "${0##*/}" >> "$KAIROS_WORKER_LOG"
for argument in "$@"; do
    printf '\t%s' "$argument" >> "$KAIROS_WORKER_LOG"
done
printf '\n' >> "$KAIROS_WORKER_LOG"
exit "${KAIROS_FAKE_STATUS:-0}"
MOCK
        chmod +x "$mock_dir/$worker"
    done
}

set_input_queue() {
    : > "$TEST_ROOT/dashboard/queue"
    for value in "$@"; do
        printf '%s\n' "$value" >> "$TEST_ROOT/dashboard/queue"
    done
}

run_dashboard() {
    local status=0
    KAIROS_GUM_BIN="$TEST_ROOT/dashboard/gum" \
    KAIROS_WORKER_LOG="$TEST_ROOT/dashboard/workers.log" \
    KAIROS_MENU_LOG="$TEST_ROOT/dashboard/menus.log" \
    KAIROS_ORGANIZE_SCRIPT="$TEST_ROOT/dashboard/organize-worker" \
    KAIROS_RENAME_SCRIPT="$TEST_ROOT/dashboard/rename-worker" \
    KAIROS_AFTERRAW_SCRIPT="$TEST_ROOT/dashboard/afterraw-worker" \
    KAIROS_PHOTO_ROOT="$TEST_ROOT/dashboard/photos" \
    KAIROS_CURRENT_EDIT_FILE="$TEST_ROOT/dashboard/current_photo_edit_dir" \
    KAIROS_FAKE_STATUS="${KAIROS_FAKE_STATUS:-0}" \
        "$ROOT/kairos" < "$TEST_ROOT/dashboard/queue" > "$TEST_ROOT/dashboard/output.log" 2>&1 || status=$?
    return "$status"
}

expect_dashboard_call() {
    local expected="$1"
    local actual
    actual=$(sed -n '1p' "$TEST_ROOT/dashboard/workers.log" 2>/dev/null || true)
    [ "$actual" = "$expected" ] || fail "TUI dispatch 不符：預期「${expected}」，實際「${actual}」"
}

reset_dashboard_log() {
    : > "$TEST_ROOT/dashboard/workers.log"
    : > "$TEST_ROOT/dashboard/menus.log"
}

test_dashboard() {
    local pause=""
    local status=0

    write_dashboard_mocks

    reset_dashboard_log
    set_input_queue "1" "$pause" "4"
    run_dashboard || fail "記憶卡選單執行失敗"
    expect_dashboard_call "organize-worker"
    [ "$(sed -n '1p' "$TEST_ROOT/dashboard/menus.log")" = $'選擇要進行的程序\t1  傳輸記憶卡 RAW 檔案\t2  轉移 RAW 檔案\t3  修圖\t0  離開' ] \
        || fail "主選單應使用方向鍵選單並顯示完整選項"

    reset_dashboard_log
    set_input_queue "2" "$pause" "4"
    run_dashboard || fail "Transfer 選單執行失敗"
    expect_dashboard_call "rename-worker"

    reset_dashboard_log
    set_input_queue "3" "1" "1" "y" "9" "4"
    run_dashboard || fail "AfterRAW 重新修圖選單執行失敗"
    expect_dashboard_call $'afterraw-worker\t--redo\tNew Project'
    grep -F $'confirm\t--default=false' "$TEST_ROOT/dashboard/menus.log" > /dev/null \
        || fail "重新修圖執行前應要求確認，且預設為取消"

    reset_dashboard_log
    set_input_queue "3" "1" "1" "n" "9" "4"
    run_dashboard || fail "取消重新修圖後返回選單失敗"
    [ ! -s "$TEST_ROOT/dashboard/workers.log" ] || fail "取消重新修圖不應執行 worker"

    reset_dashboard_log
    set_input_queue "3" "1" "2" "9" "4"
    run_dashboard || fail "AfterRAW 前置選單執行失敗"
    expect_dashboard_call $'afterraw-worker\t--pre\tNew Project'
    [ "$(sed -n '2p' "$TEST_ROOT/dashboard/menus.log")" = $'選擇修圖專案\tNew Project\tStone House\tEmpty\t0  返回主選單' ] \
        || fail "應先列出專案，依照片修改時間排序，忽略上次專案、目錄及 XMP 的修改時間"
    [ "$(sed -n '3p' "$TEST_ROOT/dashboard/menus.log")" = $'專案：New Project\t1  重新修圖\t2  前置作業\t3  載入 RAW\t4  開啟 PSD 檔案\t5  IG＋FB 後置輸出\t6  僅 IG 後置輸出\t7  僅 FB 後置輸出\t0  重新選擇專案\t9  返回主選單' ] \
        || fail "選定專案後的操作選項不符"
    [ "$(sed -n '4p' "$TEST_ROOT/dashboard/menus.log")" = $'專案：New Project\t1  重新修圖\t2  前置作業\t3  載入 RAW\t4  開啟 PSD 檔案\t5  IG＋FB 後置輸出\t6  僅 IG 後置輸出\t7  僅 FB 後置輸出\t0  重新選擇專案\t9  返回主選單' ] \
        || fail "AfterRAW 程序完成後應自動返回目前專案的操作選單"
    ! grep -F "按 Enter 返回儀表板" "$TEST_ROOT/dashboard/output.log" > /dev/null \
        || fail "AfterRAW 程序完成後不應要求按 Enter 返回儀表板"

    reset_dashboard_log
    set_input_queue "3" "2" "3" "1" "9" "4"
    run_dashboard || fail "AfterRAW 載入選單執行失敗"
    expect_dashboard_call $'afterraw-worker\t--load-raw\tStone House'

    reset_dashboard_log
    set_input_queue "3" "2" "4" "1" "9" "4"
    run_dashboard || fail "AfterRAW 開啟 PSD 選單執行失敗"
    expect_dashboard_call $'afterraw-worker\t--open-psd\tStone House'

    reset_dashboard_log
    set_input_queue "3" "2" "5" "1" "9" "4"
    run_dashboard || fail "AfterRAW IG＋FB 選單執行失敗"
    expect_dashboard_call $'afterraw-worker\tStone House'

    reset_dashboard_log
    set_input_queue "3" "2" "6" "1" "9" "4"
    run_dashboard || fail "AfterRAW IG 選單執行失敗"
    expect_dashboard_call $'afterraw-worker\t--ig\tStone House'

    reset_dashboard_log
    set_input_queue "3" "2" "7" "1" "9" "4"
    run_dashboard || fail "AfterRAW FB 選單執行失敗"
    expect_dashboard_call $'afterraw-worker\t--fb\tStone House'

    reset_dashboard_log
    set_input_queue "3" "2" "3" "2" "9" "4"
    run_dashboard || fail "AfterRAW 指定 RAW 載入執行失敗"
    expect_dashboard_call $'afterraw-worker\t--load-raw\t--file\tphoto.ARW\tStone House'
    [ "$(sed -n '4p' "$TEST_ROOT/dashboard/menus.log")" = $'專案：Stone House｜載入 RAW｜選擇 RAW 檔案（ESC 返回操作選單）\t全部 RAW 檔案\tphoto.ARW' ] \
        || fail "RAW 檔案選單應列出全部選項與 RAW 檔名，以 ESC 返回，且不列出 sidecar"

    reset_dashboard_log
    set_input_queue "3" "2" "7" "2" "9" "4"
    run_dashboard || fail "AfterRAW 指定 RAW FB 輸出執行失敗"
    expect_dashboard_call $'afterraw-worker\t--fb\t--file\tphoto.ARW\tStone House'

    reset_dashboard_log
    set_input_queue "3" "2" "1" "2" "y" "9" "4"
    run_dashboard || fail "AfterRAW 指定 RAW 重新修圖執行失敗"
    expect_dashboard_call $'afterraw-worker\t--redo\t--file\tphoto.ARW\tStone House'
    grep -F "photo.ARW 的 .xmp、.acr 檔案" "$TEST_ROOT/dashboard/menus.log" > /dev/null \
        || fail "指定 RAW 重新修圖的確認訊息應寫出檔名"

    reset_dashboard_log
    set_input_queue "3" "2" "3" "esc" "9" "4"
    run_dashboard || fail "RAW 檔案選單按 ESC 返回操作選單失敗"
    [ ! -s "$TEST_ROOT/dashboard/workers.log" ] || fail "RAW 檔案選單返回時不應執行 worker"
    [ "$(sed -n '5p' "$TEST_ROOT/dashboard/menus.log" | cut -f1)" = "專案：Stone House" ] \
        || fail "RAW 檔案選單返回後應回到目前專案的操作選單"

    reset_dashboard_log
    set_input_queue "3" "4" "4"
    run_dashboard || fail "AfterRAW 取消返回失敗"
    [ ! -s "$TEST_ROOT/dashboard/workers.log" ] || fail "取消選單不應執行 worker"

    reset_dashboard_log
    set_input_queue "3" "1" "8" "2" "6" "1" "9" "4"
    run_dashboard || fail "重新選擇專案失敗"
    expect_dashboard_call $'afterraw-worker\t--ig\tStone House'
    [ "$(wc -l < "$TEST_ROOT/dashboard/menus.log" | tr -d ' ')" = 8 ] \
        || fail "重新選擇專案應再次顯示專案與操作選單"

    reset_dashboard_log
    set_input_queue "3" "cancel" "4"
    run_dashboard || fail "取消專案選擇失敗"
    [ ! -s "$TEST_ROOT/dashboard/workers.log" ] || fail "尚未選定專案不應執行 worker"

    reset_dashboard_log
    set_input_queue "3" "1" "cancel" "4" "4"
    run_dashboard || fail "取消操作後返回專案清單失敗"
    [ ! -s "$TEST_ROOT/dashboard/workers.log" ] || fail "尚未選定操作不應執行 worker"

    mv "$TEST_ROOT/dashboard/photos" "$TEST_ROOT/dashboard/saved-photos"
    reset_dashboard_log
    set_input_queue "3" "$pause" "4"
    run_dashboard || fail "空專案清單應能返回主選單"
    [ ! -s "$TEST_ROOT/dashboard/workers.log" ] || fail "空專案清單不應執行 worker"

    reset_dashboard_log
    set_input_queue "1" "$pause" "4"
    KAIROS_FAKE_STATUS=7 run_dashboard || status=$?
    [ "$status" -eq 7 ] || fail "worker 失敗狀態未由 kairos 傳回（實際 ${status}）：$(sed -n '1,20p' "$TEST_ROOT/dashboard/output.log")"
}

test_afterraw_redo_arguments() {
    local output

    if output=$(/bin/bash "$ROOT/afterraw.sh" --redo --date 20260815 "專案" 2>&1); then
        fail "--redo 搭配 --date 應該失敗"
    fi
    [[ "$output" = *"--redo 是獨立重新修圖模式"* ]] || fail "未回報 --redo 參數衝突：$output"

    if output=$(/bin/bash "$ROOT/afterraw.sh" --redo --ig "專案" 2>&1); then
        fail "--redo 搭配 --ig 應該失敗"
    fi
    [[ "$output" = *"--redo 是獨立重新修圖模式"* ]] || fail "未回報 --redo 參數衝突：$output"
}

test_afterraw_file_arguments() {
    local output

    if output=$(/bin/bash "$ROOT/afterraw.sh" --pre --file 20260815_IMG0001.ARW --date 20260815 "專案" 2>&1); then
        fail "--file 搭配 --date 應該失敗"
    fi
    [[ "$output" = *"--file 不能與 --date 同時使用"* ]] || fail "未回報 --file 參數衝突：$output"

    if output=$(/bin/bash "$ROOT/afterraw.sh" --pre --file ../20260815_IMG0001.ARW "專案" 2>&1); then
        fail "--file 包含路徑應該失敗"
    fi
    [[ "$output" = *"--file 必須是 RAW 目錄內的 .ARW 或 .RAW 檔名"* ]] || fail "未回報 --file 格式錯誤：$output"

    if output=$(/bin/bash "$ROOT/afterraw.sh" --pre --file 20260815_IMG0001.xmp "專案" 2>&1); then
        fail "--file 指定非 RAW 檔應該失敗"
    fi
    [[ "$output" = *"--file 必須是 RAW 目錄內的 .ARW 或 .RAW 檔名"* ]] || fail "未回報 --file 副檔名錯誤：$output"
}

test_syntax
test_afterraw_redo_arguments
test_afterraw_file_arguments
test_organize_raw_by_date
test_rename_raw
test_dashboard

printf 'Kairos 測試全部通過。\n'
