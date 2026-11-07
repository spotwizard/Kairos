#!/bin/bash

# 執行指定的指令，並在執行期間讓 Mac 蓋上螢幕後也不睡眠。用法：keep_awake.sh 指令 [參數...]
# macOS 蓋上螢幕一定會睡眠，caffeinate 擋不住，只有 `pmset -a disablesleep 1` 可以，且需要管理者權限。
# 關閉睡眠與恢復設定都交給 root 的守護程序：它從 FIFO 讀資料，本程序結束時（包含被強制結束、
# 關掉終端機視窗）FIFO 的寫入端會由系統自動關閉，守護程序讀到結尾就恢復原本的睡眠設定。
# 取不到權限時仍照常執行指令，只是蓋上螢幕後 Mac 會睡眠。

if [ -z "${BASH_VERSION:-}" ] || shopt -oq posix; then
    exec /bin/bash "$0" "$@"
fi

set -u

SUDO_BIN="${KAIROS_SUDO_BIN:-sudo}"
PMSET_BIN="${KAIROS_PMSET_BIN:-/usr/bin/pmset}"
CAFFEINATE_BIN="${KAIROS_CAFFEINATE_BIN:-/usr/bin/caffeinate}"
GUARD_WAIT_SECONDS="${KAIROS_KEEP_AWAKE_WAIT_SECONDS:-5}"

if [ "$#" -eq 0 ]; then
    echo "用法：$0 指令 [參數...]" >&2
    exit 64
fi

# 不是 macOS（找不到 pmset）時沒有睡眠設定可改，直接執行指令
if ! command -v "$PMSET_BIN" > /dev/null 2>&1; then
    exec "$@"
fi

# 以 root 執行；$1 為 pmset 路徑
GUARD_SCRIPT='
pmset_bin=$1
previous=0
if "$pmset_bin" -g 2> /dev/null | grep -Eq "^[[:space:]]*SleepDisabled[[:space:]]+1"; then
    previous=1
fi
restore() {
    if [ "$previous" != 1 ]; then
        "$pmset_bin" -a disablesleep 0 > /dev/null 2>&1
    fi
}
trap "" HUP INT
trap "restore; exit 0" TERM
"$pmset_bin" -a disablesleep 1 > /dev/null 2>&1 || exit 1
cat > /dev/null
restore
'

sleep_disabled() {
    "$PMSET_BIN" -g 2> /dev/null | grep -Eq '^[[:space:]]*SleepDisabled[[:space:]]+1'
}

GUARD_PID=""
GUARD_ACTIVE=false
SLEEP_WAS_DISABLED=false
TMP_DIR=""

cleanup() {
    if [ "$GUARD_ACTIVE" = true ]; then
        GUARD_ACTIVE=false
        exec 3>&-
        wait "$GUARD_PID" 2> /dev/null
        if [ "$SLEEP_WAS_DISABLED" = false ] && sleep_disabled; then
            echo "⚠ 睡眠設定未能自動恢復，請在終端機執行：sudo pmset -a disablesleep 0"
        else
            echo "✓ 已恢復原本的睡眠設定"
        fi
    fi
    if [ -n "$TMP_DIR" ]; then
        rm -rf "$TMP_DIR"
    fi
}

trap cleanup EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

start_guard() {
    local waited=0

    if sleep_disabled; then
        SLEEP_WAS_DISABLED=true
    fi

    echo "需要輸入電腦的登入密碼，暫時關閉睡眠，讓 Mac 蓋上螢幕後仍繼續執行（程序結束後自動恢復）"
    if ! "$SUDO_BIN" -p "電腦登入密碼：" -v; then
        return 1
    fi

    TMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/kairos_keep_awake.XXXXXX") || return 1
    mkfifo "$TMP_DIR/guard" || return 1
    "$SUDO_BIN" -n /bin/bash -c "$GUARD_SCRIPT" kairos-keep-awake "$PMSET_BIN" \
        < "$TMP_DIR/guard" > /dev/null 2>&1 &
    GUARD_PID=$!
    exec 3> "$TMP_DIR/guard"
    GUARD_ACTIVE=true
    rm -rf "$TMP_DIR"
    TMP_DIR=""

    while ! sleep_disabled; do
        if [ "$waited" -ge "$GUARD_WAIT_SECONDS" ]; then
            return 1
        fi
        sleep 1
        waited=$((waited + 1))
    done
}

if start_guard; then
    echo "✓ 已暫時關閉睡眠：執行期間蓋上螢幕，Mac 仍會繼續執行"
else
    echo "⚠ 未能關閉睡眠：執行期間請不要蓋上螢幕，否則 Mac 會睡眠，程序會暫停到再次打開螢幕"
fi
echo ""

# 螢幕打開時也避免閒置睡眠；本程序結束時 caffeinate 自動結束
if command -v "$CAFFEINATE_BIN" > /dev/null 2>&1; then
    "$CAFFEINATE_BIN" -i -w "$$" 3>&- > /dev/null 2>&1 &
fi

# 子程序不可繼承 FIFO 寫入端，否則它在背景存活時守護程序不會恢復設定
"$@" 3>&-
exit $?
