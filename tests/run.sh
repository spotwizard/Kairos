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
        "$ROOT/multi_select.sh" \
        "$ROOT/search_select.sh" \
        "$ROOT/dropbox_offline.sh" \
        "$ROOT/keep_awake.sh" \
        "$ROOT/tests/run.sh" || fail "Shell 語法檢查未通過"

    # macOS 內建 bash 3.2 會把緊接在 $變數 後面的中文字元當成變數名稱的一部分，必須寫成 ${變數}
    if LC_ALL=C grep -n $'\\$[A-Za-z_][A-Za-z0-9_]*[\x80-\xff]' \
        "$ROOT/kairos" \
        "$ROOT/organize_raw_by_date.sh" \
        "$ROOT/rename_raw.sh" \
        "$ROOT/afterraw.sh" \
        "$ROOT/multi_select.sh" \
        "$ROOT/search_select.sh" \
        "$ROOT/dropbox_offline.sh" \
        "$ROOT/keep_awake.sh"; then
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

    mkdir -p "$mock_dir/photos/Stone House/RAW" "$mock_dir/photos/New Project/IG" "$mock_dir/photos/Empty" \
        "$mock_dir/photos/咖啡/RAW" "$mock_dir/photos/街拍" "$mock_dir/photos/夕陽" \
        "$mock_dir/photos/橋樑" "$mock_dir/photos/人像"
    touch -t 202608260000 "$mock_dir/photos/咖啡/RAW/photo.ARW"
    # 「__」加數字開頭的目錄要排除；「__」加非數字、單一底線加數字的目錄仍列出
    mkdir -p "$mock_dir/photos/__2025/RAW" "$mock_dir/photos/__01 舊案" "$mock_dir/photos/__Archive" "$mock_dir/photos/_1 Note"
    touch -t 202608270000 "$mock_dir/photos/__2025/RAW/photo.ARW"
    touch -t 202608010000 "$mock_dir/photos/Stone House/RAW/photo.ARW" "$mock_dir/photos/Stone House/RAW/photo2.raw"
    touch -t 202608160000 "$mock_dir/photos/New Project/IG/photo.JpEg"
    touch -t 202608200000 "$mock_dir/photos/Stone House/RAW/photo.xmp" "$mock_dir/photos/Stone House"
    mkdir -p "$mock_dir/photos/Stone House/PSD"
    touch -t 202608010000 "$mock_dir/photos/Stone House/PSD/photo.psd" "$mock_dir/photos/Stone House/PSD/other.PSD" \
        "$mock_dir/photos/Stone House/PSD/notes.txt"
    # 隱藏目錄與攝影目錄根層的照片都不是專案，不應出現在專案清單
    mkdir -p "$mock_dir/photos/.cache/RAW"
    touch -t 202608250000 "$mock_dir/photos/.cache/RAW/hidden.ARW" "$mock_dir/photos/loose.jpg"
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

    cat > "$mock_dir/multi-select" <<'MOCK'
#!/usr/bin/env bash

# 以逗號分隔序號模擬勾選，例如 2,3；其他輸入視為按 Esc
# kairos 必須以 --exclusive-first 呼叫，讓「全部」與個別檔名互斥
[ "$1" = "--exclusive-first" ] || exit 3
shift
printf '%s' "$1" >> "$KAIROS_MENU_LOG"
shift
printf '\t%s' "$@" >> "$KAIROS_MENU_LOG"
printf '\n' >> "$KAIROS_MENU_LOG"
IFS= read -r selection || exit 1
found=false
IFS=',' read -r -a picks <<< "$selection"
for pick in "${picks[@]}"; do
    index=1
    for option in "$@"; do
        if [ "$pick" = "$index" ]; then
            printf '%s\n' "$option"
            found=true
        fi
        index=$((index + 1))
    done
done
[ "$found" = true ] || exit 1
MOCK
    chmod +x "$mock_dir/multi-select"

    # 以序號模擬選定專案；其他輸入視為按 Esc
    cat > "$mock_dir/search-select" <<'MOCK'
#!/usr/bin/env bash

printf '%s' "$1" >> "$KAIROS_MENU_LOG"
shift
printf '\t%s' "$@" >> "$KAIROS_MENU_LOG"
printf '\n' >> "$KAIROS_MENU_LOG"
IFS= read -r selection || exit 1
index=1
for option in "$@"; do
    if [ "$selection" = "$index" ]; then
        printf '%s\n' "$option"
        exit 0
    fi
    index=$((index + 1))
done
exit 1
MOCK
    chmod +x "$mock_dir/search-select"

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

write_keep_awake_mock() {
    cat > "$TEST_ROOT/dashboard/keep-awake" <<'MOCK'
#!/usr/bin/env bash

printf 'keep-awake\n' >> "$KAIROS_KEEP_AWAKE_LOG"
exec "$@"
MOCK
    chmod +x "$TEST_ROOT/dashboard/keep-awake"
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
    KAIROS_MULTI_SELECT_SCRIPT="$TEST_ROOT/dashboard/multi-select" \
    KAIROS_SEARCH_SELECT_SCRIPT="$TEST_ROOT/dashboard/search-select" \
    KAIROS_KEEP_AWAKE_SCRIPT="$TEST_ROOT/dashboard/keep-awake" \
    KAIROS_KEEP_AWAKE_LOG="$TEST_ROOT/dashboard/keep-awake.log" \
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
    : > "$TEST_ROOT/dashboard/keep-awake.log"
}

# 傳輸記憶卡、轉移 RAW、後置輸出要經由防止睡眠程式執行；需要操作畫面的操作不經過
expect_keep_awake() {
    if [ "$1" = true ]; then
        [ -s "$TEST_ROOT/dashboard/keep-awake.log" ] || fail "$2 應經由防止睡眠程式執行"
    else
        [ ! -s "$TEST_ROOT/dashboard/keep-awake.log" ] || fail "$2 不應經由防止睡眠程式執行"
    fi
}

test_dashboard() {
    local pause=""
    local status=0

    write_dashboard_mocks
    write_keep_awake_mock

    reset_dashboard_log
    set_input_queue "1" "$pause" "esc"
    run_dashboard || fail "記憶卡選單執行失敗"
    expect_dashboard_call "organize-worker"
    expect_keep_awake true "傳輸記憶卡 RAW 檔案"
    [ "$(sed -n '1p' "$TEST_ROOT/dashboard/menus.log")" = $'選擇要進行的程序（ESC 離開）\t1  傳輸記憶卡 RAW 檔案\t2  轉移 RAW 檔案\t3  修圖' ] \
        || fail "主選單應使用方向鍵選單並顯示完整選項"

    reset_dashboard_log
    set_input_queue "2" "$pause" "esc"
    run_dashboard || fail "Transfer 選單執行失敗"
    expect_dashboard_call "rename-worker"
    expect_keep_awake true "轉移 RAW 檔案"

    reset_dashboard_log
    set_input_queue "3" "1" "1" "y" "esc" "esc" "esc"
    run_dashboard || fail "AfterRAW 重新修圖選單執行失敗"
    expect_dashboard_call $'afterraw-worker\t--redo\tNew Project'
    expect_keep_awake false "重新修圖"
    grep -F $'confirm\t--default=false' "$TEST_ROOT/dashboard/menus.log" > /dev/null \
        || fail "重新修圖執行前應要求確認，且預設為取消"

    reset_dashboard_log
    set_input_queue "3" "1" "1" "n" "esc" "esc" "esc"
    run_dashboard || fail "取消重新修圖後返回選單失敗"
    [ ! -s "$TEST_ROOT/dashboard/workers.log" ] || fail "取消重新修圖不應執行 worker"

    reset_dashboard_log
    set_input_queue "3" "1" "2" "esc" "esc" "esc"
    run_dashboard || fail "AfterRAW 前置選單執行失敗"
    expect_dashboard_call $'afterraw-worker\t--pre\tNew Project'
    expect_keep_awake false "前置作業"
    [ "$(sed -n '2p' "$TEST_ROOT/dashboard/menus.log")" = $'選擇修圖專案（輸入文字搜尋，ESC 返回主選單）\tNew Project\tStone House\tEmpty\t_1 Note\t__Archive' ] \
        || fail "應先列出專案，依照片修改時間排序，忽略上次專案、目錄及 XMP 的修改時間，並排除「__」加數字開頭的目錄"
    [ "$(sed -n '3p' "$TEST_ROOT/dashboard/menus.log")" = $'專案：New Project（ESC 返回專案清單）\t1  重新修圖\t2  前置作業\t3  載入 RAW\t4  開啟 PSD 檔案\t5  輸出PSD+IG+FB\t6  輸出PSD\t7  輸出IG+FB\t8  輸出IG\t9  輸出FB' ] \
        || fail "選定專案後的操作選項不符"
    [ "$(sed -n '4p' "$TEST_ROOT/dashboard/menus.log")" = $'專案：New Project（ESC 返回專案清單）\t1  重新修圖\t2  前置作業\t3  載入 RAW\t4  開啟 PSD 檔案\t5  輸出PSD+IG+FB\t6  輸出PSD\t7  輸出IG+FB\t8  輸出IG\t9  輸出FB' ] \
        || fail "AfterRAW 程序完成後應自動返回目前專案的操作選單"
    ! grep -F "按 Enter 返回儀表板" "$TEST_ROOT/dashboard/output.log" > /dev/null \
        || fail "AfterRAW 程序完成後不應要求按 Enter 返回儀表板"
    ! grep -F "按 Enter 返回選單" "$TEST_ROOT/dashboard/output.log" > /dev/null \
        || fail "AfterRAW 程序成功時不應停住等待 Enter"

    reset_dashboard_log
    set_input_queue "3" "2" "3" "1" "$pause" "esc" "esc" "esc"
    KAIROS_FAKE_STATUS=5 run_dashboard || status=$?
    grep -F "按 Enter 返回選單" "$TEST_ROOT/dashboard/output.log" > /dev/null \
        || fail "AfterRAW 程序失敗時應停住，讓使用者看到錯誤訊息"
    status=0

    reset_dashboard_log
    set_input_queue "3" "2" "3" "1" "esc" "esc" "esc"
    run_dashboard || fail "AfterRAW 載入選單執行失敗"
    expect_dashboard_call $'afterraw-worker\t--load-raw\tStone House'
    expect_keep_awake false "載入 RAW"

    reset_dashboard_log
    set_input_queue "3" "2" "4" "1" "esc" "esc" "esc"
    run_dashboard || fail "AfterRAW 開啟 PSD 選單執行失敗"
    expect_dashboard_call $'afterraw-worker\t--open-psd\tStone House'
    expect_keep_awake false "開啟 PSD 檔案"

    reset_dashboard_log
    set_input_queue "3" "2" "5" "1" "esc" "esc" "esc"
    run_dashboard || fail "AfterRAW 輸出PSD+IG+FB 選單執行失敗"
    expect_dashboard_call $'afterraw-worker\tStone House'
    expect_keep_awake true "輸出PSD+IG+FB"
    [ "$(sed -n '4p' "$TEST_ROOT/dashboard/menus.log")" = $'專案：Stone House｜輸出PSD+IG+FB｜選擇 RAW 檔案\t全部 RAW 檔案\tphoto.ARW\tphoto2.raw' ] \
        || fail "輸出PSD+IG+FB 根據 RAW 產生，應列出 RAW 檔名"

    reset_dashboard_log
    set_input_queue "3" "2" "6" "1" "esc" "esc" "esc"
    run_dashboard || fail "AfterRAW 輸出PSD 選單執行失敗"
    expect_dashboard_call $'afterraw-worker\t--make-psd\tStone House'
    expect_keep_awake true "輸出PSD"
    [ "$(sed -n '4p' "$TEST_ROOT/dashboard/menus.log")" = $'專案：Stone House｜輸出PSD｜選擇 RAW 檔案\t全部 RAW 檔案\tphoto.ARW\tphoto2.raw' ] \
        || fail "輸出PSD 根據 RAW 產生，應列出 RAW 檔名"

    reset_dashboard_log
    set_input_queue "3" "2" "7" "1" "esc" "esc" "esc"
    run_dashboard || fail "AfterRAW 輸出IG+FB 選單執行失敗"
    expect_dashboard_call $'afterraw-worker\t--ig\t--fb\tStone House'
    expect_keep_awake true "輸出IG+FB"
    [ "$(sed -n '4p' "$TEST_ROOT/dashboard/menus.log")" = $'專案：Stone House｜輸出IG+FB｜選擇 PSD 檔案\t全部 PSD 檔案\tother.PSD\tphoto.psd' ] \
        || fail "輸出IG+FB 根據 PSD 產生，應列出 PSD 檔名"

    reset_dashboard_log
    set_input_queue "3" "2" "8" "1" "esc" "esc" "esc"
    run_dashboard || fail "AfterRAW 輸出IG 選單執行失敗"
    expect_dashboard_call $'afterraw-worker\t--ig\tStone House'
    expect_keep_awake true "輸出IG"

    reset_dashboard_log
    set_input_queue "3" "2" "9" "1" "esc" "esc" "esc"
    run_dashboard || fail "AfterRAW 輸出FB 選單執行失敗"
    expect_dashboard_call $'afterraw-worker\t--fb\tStone House'
    expect_keep_awake true "輸出FB"

    reset_dashboard_log
    set_input_queue "3" "2" "3" "2" "esc" "esc" "esc"
    run_dashboard || fail "AfterRAW 指定 RAW 載入執行失敗"
    expect_dashboard_call $'afterraw-worker\t--load-raw\t--file\tphoto.ARW\tStone House'
    [ "$(sed -n '4p' "$TEST_ROOT/dashboard/menus.log")" = $'專案：Stone House｜載入 RAW｜選擇 RAW 檔案\t全部 RAW 檔案\tphoto.ARW\tphoto2.raw' ] \
        || fail "RAW 檔案選單應列出全部選項與 RAW 檔名，以 ESC 返回，且不列出 sidecar"

    reset_dashboard_log
    set_input_queue "3" "2" "6" "2" "esc" "esc" "esc"
    run_dashboard || fail "AfterRAW 指定 RAW 輸出PSD 執行失敗"
    expect_dashboard_call $'afterraw-worker\t--make-psd\t--file\tphoto.ARW\tStone House'
    expect_keep_awake true "指定 RAW 的輸出PSD"

    reset_dashboard_log
    set_input_queue "3" "2" "9" "3" "esc" "esc" "esc"
    run_dashboard || fail "AfterRAW 指定 PSD 輸出FB 執行失敗"
    expect_dashboard_call $'afterraw-worker\t--fb\t--file\tphoto.psd\tStone House'
    expect_keep_awake true "指定 PSD 的輸出FB"
    grep -F "AfterRAW｜輸出FB｜photo.psd" "$TEST_ROOT/dashboard/output.log" > /dev/null \
        || fail "指定 PSD 輸出FB 時程序標題應顯示 PSD 檔名"

    reset_dashboard_log
    set_input_queue "3" "2" "1" "2" "y" "esc" "esc" "esc"
    run_dashboard || fail "AfterRAW 指定 RAW 重新修圖執行失敗"
    expect_dashboard_call $'afterraw-worker\t--redo\t--file\tphoto.ARW\tStone House'
    grep -F "photo.ARW 的 .xmp、.acr 檔案" "$TEST_ROOT/dashboard/menus.log" > /dev/null \
        || fail "指定 RAW 重新修圖的確認訊息應寫出檔名"

    reset_dashboard_log
    set_input_queue "3" "2" "3" "2,3" "esc" "esc" "esc"
    run_dashboard || fail "AfterRAW 多選 RAW 載入執行失敗"
    expect_dashboard_call $'afterraw-worker\t--load-raw\t--file\tphoto.ARW\t--file\tphoto2.raw\tStone House'
    grep -F "AfterRAW｜載入 RAW｜2 個 RAW 檔案" "$TEST_ROOT/dashboard/output.log" > /dev/null \
        || fail "多選 RAW 時程序標題應顯示檔案數量"

    reset_dashboard_log
    set_input_queue "3" "2" "1" "2,3" "y" "esc" "esc" "esc"
    run_dashboard || fail "AfterRAW 多選 RAW 重新修圖執行失敗"
    expect_dashboard_call $'afterraw-worker\t--redo\t--file\tphoto.ARW\t--file\tphoto2.raw\tStone House'
    grep -F "photo.ARW、photo2.raw 的 .xmp、.acr 檔案" "$TEST_ROOT/dashboard/menus.log" > /dev/null \
        || fail "多選 RAW 重新修圖的確認訊息應列出所有檔名"

    reset_dashboard_log
    set_input_queue "3" "2" "4" "2,3" "esc" "esc" "esc"
    run_dashboard || fail "AfterRAW 指定 PSD 開啟執行失敗"
    expect_dashboard_call $'afterraw-worker\t--open-psd\t--file\tother.PSD\t--file\tphoto.psd\tStone House'
    [ "$(sed -n '4p' "$TEST_ROOT/dashboard/menus.log")" = $'專案：Stone House｜開啟 PSD 檔案｜選擇 PSD 檔案\t全部 PSD 檔案\tother.PSD\tphoto.psd' ] \
        || fail "開啟 PSD 檔案應列出 PSD 目錄內的 .psd 檔名，而不是 RAW 檔名"
    grep -F "AfterRAW｜開啟 PSD 檔案｜2 個 PSD 檔案" "$TEST_ROOT/dashboard/output.log" > /dev/null \
        || fail "多選 PSD 時程序標題應顯示 PSD 檔案數量"

    reset_dashboard_log
    set_input_queue "3" "2" "5" "1,3" "esc" "esc" "esc"
    run_dashboard || fail "AfterRAW 勾選全部 RAW 執行失敗"
    expect_dashboard_call $'afterraw-worker\tStone House'

    reset_dashboard_log
    set_input_queue "3" "2" "3" "esc" "esc" "esc" "esc"
    run_dashboard || fail "RAW 檔案選單按 ESC 返回操作選單失敗"
    [ ! -s "$TEST_ROOT/dashboard/workers.log" ] || fail "RAW 檔案選單返回時不應執行 worker"
    [ "$(sed -n '5p' "$TEST_ROOT/dashboard/menus.log" | cut -f1)" = "專案：Stone House（ESC 返回專案清單）" ] \
        || fail "RAW 檔案選單返回後應回到目前專案的操作選單"

    reset_dashboard_log
    set_input_queue "3" "esc" "esc"
    run_dashboard || fail "AfterRAW 取消返回失敗"
    [ ! -s "$TEST_ROOT/dashboard/workers.log" ] || fail "取消選單不應執行 worker"
    [ "$(cut -f1 "$TEST_ROOT/dashboard/menus.log" | tr '\n' '|')" = "選擇要進行的程序（ESC 離開）|選擇修圖專案（輸入文字搜尋，ESC 返回主選單）|選擇要進行的程序（ESC 離開）|" ] \
        || fail "專案清單按 ESC 應返回主選單"

    reset_dashboard_log
    set_input_queue "3" "1" "esc" "2" "8" "1" "esc" "esc" "esc"
    run_dashboard || fail "操作選單 ESC 後重新選擇專案失敗"
    expect_dashboard_call $'afterraw-worker\t--ig\tStone House'
    [ "$(wc -l < "$TEST_ROOT/dashboard/menus.log" | tr -d ' ')" = 9 ] \
        || fail "重新選擇專案應再次顯示專案與操作選單"

    reset_dashboard_log
    set_input_queue "3" "cancel" "esc"
    run_dashboard || fail "取消專案選擇失敗"
    [ ! -s "$TEST_ROOT/dashboard/workers.log" ] || fail "尚未選定專案不應執行 worker"

    reset_dashboard_log
    set_input_queue "3" "1" "esc" "esc" "esc"
    run_dashboard || fail "取消操作後返回專案清單失敗"
    [ ! -s "$TEST_ROOT/dashboard/workers.log" ] || fail "尚未選定操作不應執行 worker"
    [ "$(cut -f1 "$TEST_ROOT/dashboard/menus.log" | tr '\n' '|')" = "選擇要進行的程序（ESC 離開）|選擇修圖專案（輸入文字搜尋，ESC 返回主選單）|專案：New Project（ESC 返回專案清單）|選擇修圖專案（輸入文字搜尋，ESC 返回主選單）|選擇要進行的程序（ESC 離開）|" ] \
        || fail "操作選單按 ESC 應返回專案清單，專案清單再按 ESC 返回主選單"

    mv "$TEST_ROOT/dashboard/photos" "$TEST_ROOT/dashboard/saved-photos"
    reset_dashboard_log
    set_input_queue "3" "$pause" "esc"
    run_dashboard || fail "空專案清單應能返回主選單"
    [ ! -s "$TEST_ROOT/dashboard/workers.log" ] || fail "空專案清單不應執行 worker"

    reset_dashboard_log
    set_input_queue "1" "$pause" "esc"
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
    [[ "$output" = *"--file 必須是檔名，不能包含路徑"* ]] || fail "未回報 --file 格式錯誤：$output"

    if output=$(/bin/bash "$ROOT/afterraw.sh" --pre --file 20260815_IMG0001.ARW --file 20260815_IMG0002.xmp "專案" 2>&1); then
        fail "多個 --file 中有非 RAW 檔應該失敗"
    fi
    [[ "$output" = *"--file 必須是 RAW 目錄內的 .ARW 或 .RAW 檔名"* ]] || fail "未檢查每一個 --file：$output"

    if output=$(/bin/bash "$ROOT/afterraw.sh" --pre --file 20260815_IMG0001.xmp "專案" 2>&1); then
        fail "--file 指定非 RAW 檔應該失敗"
    fi
    [[ "$output" = *"--file 必須是 RAW 目錄內的 .ARW 或 .RAW 檔名"* ]] || fail "未回報 --file 副檔名錯誤：$output"

    if output=$(/bin/bash "$ROOT/afterraw.sh" --open-psd --file 20260815_IMG0001.ARW "專案" 2>&1); then
        fail "開啟 PSD 時 --file 指定 RAW 檔應該失敗"
    fi
    [[ "$output" = *"--open-psd 的 --file 必須是 PSD 目錄內的 .psd 檔名"* ]] || fail "未回報開啟 PSD 的 --file 副檔名錯誤：$output"

    # 只輸出 IG、FB 時根據 PSD 產生，--file 必須是 PSD；輸出 PSD 時根據 RAW 產生，--file 必須是 RAW
    if output=$(/bin/bash "$ROOT/afterraw.sh" --ig --fb --file 20260815_IMG0001.ARW "專案" 2>&1); then
        fail "根據 PSD 輸出 IG／FB 時 --file 指定 RAW 檔應該失敗"
    fi
    [[ "$output" = *"根據 PSD 輸出 IG／FB 時，--file 必須是 PSD 目錄內的 .psd 檔名"* ]] || fail "未回報輸出 IG／FB 的 --file 副檔名錯誤：$output"

    if output=$(/bin/bash "$ROOT/afterraw.sh" --make-psd --file 20260815_IMG0001.psd "專案" 2>&1); then
        fail "輸出 PSD 時 --file 指定 PSD 檔應該失敗"
    fi
    [[ "$output" = *"--file 必須是 RAW 目錄內的 .ARW 或 .RAW 檔名"* ]] || fail "未回報輸出 PSD 的 --file 副檔名錯誤：$output"

    if output=$(/bin/bash "$ROOT/afterraw.sh" --make-psd --file 20260815_IMG0001.ARW --file 20260815_IMG0002.ARW "/nonexistent/專案" 2>&1); then
        fail "找不到專案資料夾應該失敗"
    fi
    [[ "$output" = *"找不到資料夾"* ]] || fail "輸出 PSD 搭配 RAW 檔名應通過參數檢查：$output"

    if output=$(/bin/bash "$ROOT/afterraw.sh" --pre --make-psd "專案" 2>&1); then
        fail "--pre 搭配 --make-psd 應該失敗"
    fi
    [[ "$output" = *"--pre 是獨立前置模式"* ]] || fail "未回報 --pre 與 --make-psd 衝突：$output"

    if output=$(/bin/bash "$ROOT/afterraw.sh" --open-psd --make-psd "專案" 2>&1); then
        fail "--open-psd 搭配 --make-psd 應該失敗"
    fi
    [[ "$output" = *"--open-psd 是獨立開啟模式"* ]] || fail "未回報 --open-psd 與 --make-psd 衝突：$output"
}

test_multi_select() {
    if ! command -v python3 > /dev/null 2>&1; then
        printf '略過多選清單按鍵測試：找不到 python3\n'
        return 0
    fi

    python3 - "$ROOT/multi_select.sh" "$TEST_ROOT/multi_select.out" <<'PY' || fail "多選清單按鍵測試未通過"
import os, pty, select, sys, time

script, out_path = sys.argv[1], sys.argv[2]


def drain(fd, seconds):
    end = time.time() + seconds
    while time.time() < end:
        ready, _, _ = select.select([fd], [], [], 0.02)
        if ready:
            try:
                os.read(fd, 4096)
            except OSError:
                return


def run(keys, options, height="15", flags=()):
    pid, fd = pty.fork()
    if pid == 0:
        os.environ["OUT"] = out_path
        os.environ["KAIROS_MULTI_SELECT_HEIGHT"] = height
        os.execv("/bin/bash", ["/bin/bash", "-c", 'exec /bin/bash "$0" "$@" > "$OUT"', script] + list(flags) + ["標題"] + options)
    drain(fd, 0.5)
    for key in keys:
        os.write(fd, key)
        drain(fd, 0.3)
    end = time.time() + 3
    while time.time() < end:
        done, raw = os.waitpid(pid, os.WNOHANG)
        if done:
            with open(out_path) as output:
                return raw >> 8, output.read()
        drain(fd, 0.05)
    os.kill(pid, 9)
    os.waitpid(pid, 0)
    return "timeout", ""


DOWN, UP, ENTER, ESC, SPACE = b"\x1b[B", b"\x1b[A", b"\r", b"\x1b", b" "
cases = [
    ("沒有勾選就按 Enter 選定游標項目", [DOWN, ENTER], ["全部", "甲.ARW", "乙.ARW"], "15", (0, "甲.ARW\n")),
    ("空白鍵勾選多個項目", [SPACE, DOWN, DOWN, SPACE, ENTER], ["全部", "甲.ARW", "乙.ARW"], "15", (0, "全部\n乙.ARW\n")),
    ("再按一次空白鍵取消勾選", [SPACE, SPACE, DOWN, ENTER], ["全部", "甲.ARW", "乙.ARW"], "15", (0, "甲.ARW\n")),
    ("向上移動循環到最後一項", [UP, ENTER], ["全部", "甲.ARW", "乙.ARW"], "15", (0, "乙.ARW\n")),
    ("清單超過高度時捲動", [DOWN, DOWN, DOWN, ENTER], ["a", "b", "c", "d", "e"], "2", (0, "d\n")),
    ("Esc 返回", [ESC], ["a", "b"], "15", (1, "")),
    ("互斥模式勾選全部會取消其他勾選", [DOWN, SPACE, DOWN, SPACE, UP, UP, SPACE, ENTER], ["全部", "甲.ARW", "乙.ARW"], "15", (0, "全部\n"), ["--exclusive-first"]),
    ("互斥模式勾選檔名會取消全部", [SPACE, DOWN, SPACE, ENTER], ["全部", "甲.ARW", "乙.ARW"], "15", (0, "甲.ARW\n"), ["--exclusive-first"]),
    ("互斥模式取消勾選不影響其他項目", [DOWN, SPACE, DOWN, SPACE, SPACE, ENTER], ["全部", "甲.ARW", "乙.ARW"], "15", (0, "甲.ARW\n"), ["--exclusive-first"]),
    ("Ctrl+C 中止", [b"\x03"], ["a", "b"], "15", (130, "")),
]
failed = False
for name, keys, options, height, expected, *flags in cases:
    actual = run(keys, options, height, flags[0] if flags else ())
    if actual != expected:
        failed = True
        print(f"多選清單：{name}，預期 {expected!r}，實際 {actual!r}")
sys.exit(1 if failed else 0)
PY
}

test_search_select() {
    if ! command -v python3 > /dev/null 2>&1; then
        printf '略過搜尋清單按鍵測試：找不到 python3\n'
        return 0
    fi

    python3 - "$ROOT/search_select.sh" "$TEST_ROOT/search_select.out" <<'PY' || fail "搜尋清單按鍵測試未通過"
import os, pty, select, sys, time

script, out_path = sys.argv[1], sys.argv[2]


def drain(fd, seconds):
    end = time.time() + seconds
    while time.time() < end:
        ready, _, _ = select.select([fd], [], [], 0.02)
        if ready:
            try:
                os.read(fd, 4096)
            except OSError:
                return


def run(keys, options, height="15"):
    pid, fd = pty.fork()
    if pid == 0:
        os.environ["OUT"] = out_path
        os.environ["KAIROS_SEARCH_SELECT_HEIGHT"] = height
        os.execv("/bin/bash", ["/bin/bash", "-c", 'exec /bin/bash "$0" "$@" > "$OUT"', script, "標題"] + options)
    drain(fd, 0.5)
    for key in keys:
        os.write(fd, key)
        drain(fd, 0.3)
    end = time.time() + 3
    while time.time() < end:
        done, raw = os.waitpid(pid, os.WNOHANG)
        if done:
            with open(out_path) as output:
                return raw >> 8, output.read()
        drain(fd, 0.05)
    os.kill(pid, 9)
    os.waitpid(pid, 0)
    return "timeout", ""


DOWN, UP, ENTER, ESC, BACKSPACE = b"\x1b[B", b"\x1b[A", b"\r", b"\x1b", b"\x7f"
PROJECTS = ["石屋 2026", "Stone House", "New Project", "海邊石頭"]
cases = [
    ("沒有輸入就按 Enter 選定第一項", [ENTER], PROJECTS, "15", (0, "石屋 2026\n")),
    ("上下鍵移動", [DOWN, DOWN, ENTER], PROJECTS, "15", (0, "New Project\n")),
    ("向上移動循環到最後一項", [UP, ENTER], PROJECTS, "15", (0, "海邊石頭\n")),
    ("英文搜尋不分大小寫", [b"s", b"T", b"o", ENTER], PROJECTS, "15", (0, "Stone House\n")),
    ("中文搜尋", ["石".encode(), DOWN, ENTER], PROJECTS, "15", (0, "海邊石頭\n")),
    ("一次送出多個中文字", ["海邊".encode(), ENTER], PROJECTS, "15", (0, "海邊石頭\n")),
    ("多個關鍵字必須全部符合", ["石 2026".encode(), ENTER], PROJECTS, "15", (0, "石屋 2026\n")),
    ("Backspace 刪除一個中文字", ["屋".encode(), BACKSPACE, "頭".encode(), ENTER], PROJECTS, "15", (0, "海邊石頭\n")),
    ("沒有符合時按 Enter 不選定", [b"zzz", ENTER, BACKSPACE * 3, b"new", ENTER], PROJECTS, "15", (0, "New Project\n")),
    ("清單超過高度時捲動", [DOWN, DOWN, DOWN, ENTER], ["a", "b", "c", "d", "e"], "2", (0, "d\n")),
    ("Delete 鍵不會輸入文字", [b"\x1b[3~", b"new", ENTER], PROJECTS, "15", (0, "New Project\n")),
    ("j、k 是搜尋文字", [b"k", ENTER], ["j1", "k1"], "15", (0, "k1\n")),
    ("輸入搜尋後 Esc 直接返回", [b"st", ESC], PROJECTS, "15", (1, "")),
    ("Esc 返回", [ESC], PROJECTS, "15", (1, "")),
    ("Ctrl+C 中止", [b"\x03"], PROJECTS, "15", (130, "")),
]
failed = False
for name, keys, options, height, expected in cases:
    actual = run(keys, options, height)
    if actual != expected:
        failed = True
        print(f"搜尋清單：{name}，預期 {expected!r}，實際 {actual!r}")
sys.exit(1 if failed else 0)
PY
}

test_dropbox_offline() {
    local dir="$TEST_ROOT/offline"
    local mock_bin="$dir/bin"
    local output

    mkdir -p "$mock_bin"

    # 以檔案旁的標記檔模擬狀態：.placeholder 為 Dropbox 佔位檔（大小 0、帶 com.dropbox.placeholder 屬性），
    # .dataless 為帶 dataless 旗標的檔案，.sparse 為大小 100 但區塊數 0，.empty 為單純 0 位元組
    cat > "$mock_bin/stat" <<'MOCK'
#!/bin/bash
file="${@: -1}"
if [ -e "${file}.placeholder" ] || [ -e "${file}.empty" ]; then
    echo "- 0 0"
elif [ -e "${file}.dataless" ]; then
    echo "dataless 100 0"
elif [ -e "${file}.sparse" ]; then
    echo "- 100 0"
else
    echo "- 100 8"
fi
MOCK
    cat > "$mock_bin/xattr" <<'MOCK'
#!/bin/bash
[ "$1" = "-p" ] && [ "$2" = "com.dropbox.placeholder" ] && [ -e "${3}.placeholder" ]
MOCK
    # open -g -a Dropbox 檔案：模擬 Dropbox 下載完成，佔位標記消失
    cat > "$mock_bin/open" <<'MOCK'
#!/bin/bash
[ -n "${MOCK_NO_DOWNLOAD:-}" ] || { rm -f "${4}.placeholder"; : > "$MOCK_RUNNING_DIR/launched.Preview"; : > "$MOCK_RUNNING_DIR/launched.Photos"; }
MOCK
    # cat 讀取 dataless 或區塊數為 0 的檔案後，標記消失
    cat > "$mock_bin/cat" <<'MOCK'
#!/bin/bash
rm -f "${2}.dataless" "${2}.sparse"
MOCK
    # pgrep：檔案 $dir/running.<app> 存在代表該 app 開著；osascript、killall 只記錄呼叫
    cat > "$mock_bin/pgrep" <<'MOCK'
#!/bin/bash
[ -e "$MOCK_RUNNING_DIR/running.${2}" ] || [ -e "$MOCK_RUNNING_DIR/launched.${2}" ]
MOCK
    cat > "$mock_bin/osascript" <<'MOCK'
#!/bin/bash
echo "$2" >> "$MOCK_RUNNING_DIR/osascript.log"
MOCK
    cat > "$mock_bin/killall" <<'MOCK'
#!/bin/bash
echo "$1" >> "$MOCK_RUNNING_DIR/killall.log"
MOCK
    chmod +x "$mock_bin/stat" "$mock_bin/xattr" "$mock_bin/open" "$mock_bin/cat" \
        "$mock_bin/pgrep" "$mock_bin/osascript" "$mock_bin/killall"

    run_offline() {
        MOCK_RUNNING_DIR="$dir" KAIROS_OFFLINE_CLEANUP_WAIT_SECONDS=0 \
            KAIROS_PGREP_BIN="$mock_bin/pgrep" KAIROS_OSASCRIPT_BIN="$mock_bin/osascript" KAIROS_KILLALL_BIN="$mock_bin/killall" \
            KAIROS_STAT_BIN="$mock_bin/stat" KAIROS_XATTR_BIN="$mock_bin/xattr" KAIROS_OPEN_BIN="$mock_bin/open" \
            PATH="$mock_bin:$PATH" /bin/bash -c 'source "$1"; shift; make_available_offline "$@"' _ \
            "$ROOT/dropbox_offline.sh" "$@" 2>&1
    }

    : > "$dir/本機.ARW"
    output=$(run_offline "$dir/本機.ARW") || fail "本機檔案不應失敗：$output"
    [[ "$output" = *"皆已在本機"* ]] || fail "未回報檔案皆已在本機：$output"
    [ ! -e "$dir/killall.log" ] || fail "沒有下載時不應關閉對話框"

    : > "$dir/佔位.ARW"
    : > "$dir/佔位.ARW.placeholder"
    output=$(run_offline "$dir/本機.ARW" "$dir/佔位.ARW") || fail "Dropbox 佔位檔下載失敗：$output"
    [[ "$output" = *"下載：佔位.ARW"* ]] || fail "未下載 Dropbox 佔位檔：$output"
    [[ "$output" != *"下載：本機.ARW"* ]] || fail "不應下載已在本機的檔案：$output"
    [[ "$output" = *"已下載 1 個檔案"* ]] || fail "未回報下載數量：$output"
    [ ! -e "$dir/佔位.ARW.placeholder" ] || fail "下載後檔案仍是佔位檔"

    # 下載後被開啟的 app 若原本沒開著就關閉；原本就開著的不動；並關閉「未設定應用程式」對話框
    rm -f "$dir/osascript.log" "$dir/killall.log" "$dir/launched.Preview" "$dir/launched.Photos"
    : > "$dir/佔位.ARW.placeholder"
    : > "$dir/running.Photos"
    output=$(run_offline "$dir/佔位.ARW") || fail "Dropbox 佔位檔下載失敗：$output"
    [ "$(cat "$dir/osascript.log" 2>/dev/null)" = 'tell application "Preview" to quit' ] \
        || fail "只應關閉下載前沒開著的 Preview：$(cat "$dir/osascript.log" 2>/dev/null)"
    [ "$(cat "$dir/killall.log" 2>/dev/null)" = "CoreServicesUIAgent" ] || fail "下載後應關閉「未設定應用程式」對話框"
    rm -f "$dir/running.Photos" "$dir/launched.Preview" "$dir/launched.Photos" "$dir/osascript.log" "$dir/killall.log"

    : > "$dir/線上.ARW"
    : > "$dir/線上.ARW.dataless"
    : > "$dir/稀疏.ARW"
    : > "$dir/稀疏.ARW.sparse"
    output=$(run_offline "$dir/線上.ARW" "$dir/稀疏.ARW") || fail "dataless 或區塊數為 0 的檔案下載失敗：$output"
    [[ "$output" = *"已下載 2 個檔案"* ]] || fail "未下載 dataless 與區塊數為 0 的檔案：$output"
    [ ! -e "$dir/線上.ARW.dataless" ] || fail "讀取後檔案仍標示為 dataless"

    # Dropbox 沒有完成下載：逾時後回報失敗，並提示 Finder 的做法
    : > "$dir/佔位.ARW.placeholder"
    if output=$(MOCK_NO_DOWNLOAD=1 KAIROS_OFFLINE_DOWNLOAD_SECONDS=0 run_offline "$dir/佔位.ARW"); then
        fail "下載未完成時應回傳失敗：$output"
    fi
    [[ "$output" = *"尚未下載完成：佔位.ARW"* ]] || fail "未回報下載未完成的檔案：$output"
    [[ "$output" = *"設為可離線使用"* ]] || fail "未提示在 Finder 設為可離線使用：$output"
    rm -f "$dir/佔位.ARW.placeholder"

    # 單純 0 位元組（不是佔位檔）沒有內容；旁邊的 .xmp 不檢查
    : > "$dir/空檔.ARW"
    : > "$dir/空檔.ARW.empty"
    : > "$dir/空檔.xmp"
    : > "$dir/空檔.xmp.empty"
    if output=$(run_offline "$dir/空檔.ARW" "$dir/空檔.xmp" "$dir/本機.ARW"); then
        fail "RAW 為 0 位元組時應回傳失敗：$output"
    fi
    [[ "$output" = *"檔案大小為 0 位元組（沒有內容）：空檔.ARW"* ]] || fail "未回報空檔：$output"
    [[ "$output" != *"空檔.xmp"* ]] || fail "不應把 0 位元組的 .xmp 視為錯誤：$output"
}

test_keep_awake() {
    local dir="$TEST_ROOT/keep_awake"
    local mock_bin="$dir/bin"
    local output
    local status
    local waited
    local wrapper_pid

    mkdir -p "$mock_bin"
    cat > "$mock_bin/sudo" <<'MOCK'
#!/usr/bin/env bash

non_interactive=false
while [ "$#" -gt 0 ]; do
    case "$1" in
        -p) shift 2 ;;
        -v) [ "${MOCK_SUDO_FAIL:-0}" = "1" ] && exit 1; exit 0 ;;
        -n) non_interactive=true; shift ;;
        *) break ;;
    esac
done
[ "$non_interactive" = true ] || exit 2
exec "$@"
MOCK
    cat > "$mock_bin/pmset" <<'MOCK'
#!/usr/bin/env bash

case "$1" in
    -g) printf ' SleepDisabled\t\t%s\n hibernatemode\t\t3\n' "$(cat "$MOCK_PMSET_STATE")" ;;
    -a) [ "$2" = "disablesleep" ] || exit 2; printf '%s' "$3" > "$MOCK_PMSET_STATE" ;;
    *) exit 2 ;;
esac
MOCK
    chmod +x "$mock_bin/sudo" "$mock_bin/pmset"

    run_keep_awake() {
        MOCK_PMSET_STATE="$dir/state" KAIROS_SUDO_BIN="$mock_bin/sudo" KAIROS_PMSET_BIN="$mock_bin/pmset" \
            KAIROS_CAFFEINATE_BIN="$mock_bin/missing-caffeinate" KAIROS_KEEP_AWAKE_WAIT_SECONDS=3 \
            /bin/bash "$ROOT/keep_awake.sh" "$@" 2>&1
    }

    # 執行期間關閉睡眠，結束後恢復，並傳回指令的結束狀態
    printf '0' > "$dir/state"
    status=0
    output=$(run_keep_awake /bin/bash -c 'printf "during=%s\n" "$(cat "$1")"; exit 3' child "$dir/state") || status=$?
    [ "$status" -eq 3 ] || fail "防止睡眠程式應傳回指令的結束狀態（實際 ${status}）：$output"
    [[ "$output" = *"during=1"* ]] || fail "執行期間應關閉睡眠：$output"
    [[ "$output" = *"已暫時關閉睡眠"* ]] || fail "未提示已關閉睡眠：$output"
    [ "$(cat "$dir/state")" = 0 ] || fail "結束後應恢復睡眠設定"
    [[ "$output" = *"已恢復原本的睡眠設定"* ]] || fail "未提示已恢復睡眠設定：$output"

    # 原本就關閉睡眠時，結束後維持關閉
    printf '1' > "$dir/state"
    output=$(run_keep_awake /bin/true) || fail "原本關閉睡眠時執行失敗：$output"
    [ "$(cat "$dir/state")" = 1 ] || fail "原本已關閉睡眠時，結束後不應改回會睡眠"

    # 取不到管理者權限時仍執行指令，並提示不要蓋上螢幕
    printf '0' > "$dir/state"
    output=$(MOCK_SUDO_FAIL=1 run_keep_awake /bin/bash -c 'echo ran') || fail "取不到權限時仍應執行指令：$output"
    [[ "$output" = *"ran"* ]] || fail "取不到權限時沒有執行指令：$output"
    [[ "$output" = *"請不要蓋上螢幕"* ]] || fail "取不到權限時應提示不要蓋上螢幕：$output"
    [ "$(cat "$dir/state")" = 0 ] || fail "取不到權限時不應改動睡眠設定"

    # 防止睡眠程式被強制結束時，仍會恢復睡眠設定
    printf '0' > "$dir/state"
    MOCK_PMSET_STATE="$dir/state" KAIROS_SUDO_BIN="$mock_bin/sudo" KAIROS_PMSET_BIN="$mock_bin/pmset" \
        KAIROS_CAFFEINATE_BIN="$mock_bin/missing-caffeinate" \
        /bin/bash "$ROOT/keep_awake.sh" /bin/sleep 30 > /dev/null 2>&1 &
    wrapper_pid=$!
    waited=0
    while [ "$(cat "$dir/state")" != 1 ]; do
        [ "$waited" -lt 50 ] || fail "強制結束測試：未關閉睡眠"
        sleep 0.1
        waited=$((waited + 1))
    done
    pkill -P "$wrapper_pid" sleep 2> /dev/null
    kill -9 "$wrapper_pid"
    wait "$wrapper_pid" 2> /dev/null
    waited=0
    while [ "$(cat "$dir/state")" != 0 ]; do
        [ "$waited" -lt 50 ] || fail "防止睡眠程式被強制結束後，睡眠設定未恢復"
        sleep 0.1
        waited=$((waited + 1))
    done

    # 沒有 pmset（不是 macOS）時直接執行指令
    output=$(KAIROS_PMSET_BIN="$mock_bin/missing-pmset" /bin/bash "$ROOT/keep_awake.sh" /bin/bash -c 'echo direct' 2>&1) \
        || fail "沒有 pmset 時執行失敗：$output"
    [ "$output" = "direct" ] || fail "沒有 pmset 時應直接執行指令：$output"
}

test_syntax
test_keep_awake
test_multi_select
test_search_select
test_dropbox_offline
test_afterraw_redo_arguments
test_afterraw_file_arguments
test_organize_raw_by_date
test_rename_raw
test_dashboard

printf 'Kairos 測試全部通過。\n'
