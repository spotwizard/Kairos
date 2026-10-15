#!/usr/bin/env bash

# 多選清單：↑↓ 移動、空白鍵勾選、Enter 確認、Esc 返回。
# 沒有勾選任何項目就按 Enter 時，選定游標所在的項目。
# 選定的項目逐行輸出到 stdout；按 Esc 回傳 1，按 Ctrl+C 回傳 130。
# 只使用 macOS 內建 bash 3.2 可用的語法。
#
# 使用方式：multi_select.sh <標題> <選項>...

if [ -z "${BASH_VERSION:-}" ] || shopt -oq posix; then
    exec /bin/bash "$0" "$@"
fi

HEADER="$1"
shift
OPTIONS=("$@")
COUNT=${#OPTIONS[@]}
HEIGHT="${KAIROS_MULTI_SELECT_HEIGHT:-15}"
TTY=/dev/tty

[ "$COUNT" -gt 0 ] || exit 1
[ "$HEIGHT" -le "$COUNT" ] || HEIGHT=$COUNT

CHECKED=()
for ((i = 0; i < COUNT; i++)); do
    CHECKED[i]=0
done
CURSOR=0
TOP=0
DRAWN_LINES=0
TTY_STATE=$(stty -g < "$TTY") || exit 1

restore_tty() {
    stty "$TTY_STATE" < "$TTY"
    printf '\033[?25h\033[?7h' > "$TTY"
}

clear_drawn() {
    if [ "$DRAWN_LINES" -gt 0 ]; then
        printf '\r\033[%dA\033[J' "$DRAWN_LINES" > "$TTY"
    fi
}

# 讀取一個位元組到 KEY；Enter 會讀成換行字元，讀到檔案結尾時為空字串
read_key() {
    KEY=$(dd bs=1 count=1 < "$TTY" 2> /dev/null; printf x)
    KEY="${KEY%x}"
}

render() {
    local i
    local mark

    clear_drawn
    {
        printf '\033[38;5;99m%s\033[0m\n' "$HEADER"
        for ((i = TOP; i < TOP + HEIGHT; i++)); do
            if [ "${CHECKED[i]}" -eq 1 ]; then
                mark="✓"
            else
                mark="•"
            fi
            if [ "$i" -eq "$CURSOR" ]; then
                printf '\033[38;5;212m> %s %s\033[0m\n' "$mark" "${OPTIONS[i]}"
            elif [ "${CHECKED[i]}" -eq 1 ]; then
                printf '  \033[38;5;212m%s %s\033[0m\n' "$mark" "${OPTIONS[i]}"
            else
                printf '  %s %s\n' "$mark" "${OPTIONS[i]}"
            fi
        done
        printf '\n\033[38;5;241m↑↓ 移動 • 空白鍵 勾選 • enter 確認 • esc 返回\033[0m\n'
    } > "$TTY"
    DRAWN_LINES=$((HEIGHT + 3))
}

move_cursor() {
    CURSOR=$(((CURSOR + $1 + COUNT) % COUNT))
    if [ "$CURSOR" -lt "$TOP" ]; then
        TOP=$CURSOR
    elif [ "$CURSOR" -ge $((TOP + HEIGHT)) ]; then
        TOP=$((CURSOR - HEIGHT + 1))
    fi
}

finish() {
    clear_drawn
    restore_tty
    exit "$1"
}

trap 'finish 130' INT TERM HUP

# 關閉回顯、行緩衝與 Ctrl+C 訊號（改由程式自行處理），長行不自動換行以免重繪錯位
stty -echo -icanon -isig min 1 time 0 < "$TTY"
printf '\033[?25l\033[?7l' > "$TTY"

while true; do
    render
    read_key
    case "$KEY" in
        $'\033')
            # 方向鍵會緊接著送出後續位元組；0.1 秒內沒有後續位元組就是單獨的 Esc
            stty min 0 time 1 < "$TTY"
            rest=$(dd bs=1 count=2 < "$TTY" 2> /dev/null)
            stty min 1 time 0 < "$TTY"
            case "$rest" in
                "[A"|"OA") move_cursor -1 ;;
                "[B"|"OB") move_cursor 1 ;;
                "") finish 1 ;;
            esac
            ;;
        k) move_cursor -1 ;;
        j) move_cursor 1 ;;
        " "|x)
            CHECKED[CURSOR]=$((1 - CHECKED[CURSOR]))
            ;;
        $'\n'|$'\r')
            break
            ;;
        $'\003'|"") finish 130 ;;
    esac
done

clear_drawn
restore_tty

selected=0
for ((i = 0; i < COUNT; i++)); do
    if [ "${CHECKED[i]}" -eq 1 ]; then
        printf '%s\n' "${OPTIONS[i]}"
        selected=$((selected + 1))
    fi
done
if [ "$selected" -eq 0 ]; then
    printf '%s\n' "${OPTIONS[CURSOR]}"
fi
exit 0
