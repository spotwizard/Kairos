#!/usr/bin/env bash

# 可搜尋的單選清單：直接輸入文字篩選項目、↑↓ 移動、Enter 確認、Esc 返回、Backspace 刪除一個字。
# 搜尋不分英文大小寫；以空白分隔多個關鍵字時，項目必須包含全部關鍵字。
# 選定的項目輸出到 stdout；按 Esc 回傳 1，按 Ctrl+C 回傳 130。
# 只使用 macOS 內建 bash 3.2 可用的語法。
#
# 使用方式：search_select.sh <標題> <選項>...

if [ -z "${BASH_VERSION:-}" ] || shopt -oq posix; then
    exec /bin/bash "$0" "$@"
fi

# 以位元組處理輸入與比對，中文字以完整的 UTF-8 位元組序列存放，不受終端機語系影響
LC_ALL=C

HEADER="$1"
shift
OPTIONS=("$@")
COUNT=${#OPTIONS[@]}
HEIGHT="${KAIROS_SEARCH_SELECT_HEIGHT:-15}"
TTY=/dev/tty

[ "$COUNT" -gt 0 ] || exit 1

LOWER=()
while IFS= read -r line; do
    LOWER+=("$line")
done < <(printf '%s\n' "${OPTIONS[@]}" | LC_ALL=C tr 'A-Z' 'a-z')

# QUERY_CHARS 每個元素是一個完整字元，Backspace 時整個字刪除
QUERY_CHARS=()
QUERY=""
MATCHES=()
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

byte_value() {
    printf '%s' "$1" | od -An -tu1 | tr -d ' \n'
}

update_matches() {
    local i
    local word
    local matched
    local lowered_query
    local -a words=()

    QUERY=""
    for ((i = 0; i < ${#QUERY_CHARS[@]}; i++)); do
        QUERY="${QUERY}${QUERY_CHARS[i]}"
    done
    lowered_query=$(printf '%s' "$QUERY" | LC_ALL=C tr 'A-Z' 'a-z')
    read -r -a words <<< "$lowered_query"

    MATCHES=()
    for ((i = 0; i < COUNT; i++)); do
        matched=1
        if [ "${#words[@]}" -gt 0 ]; then
            for word in "${words[@]}"; do
                case "${LOWER[i]}" in
                    *"$word"*) ;;
                    *) matched=0; break ;;
                esac
            done
        fi
        [ "$matched" -eq 1 ] && MATCHES+=("$i")
    done
    CURSOR=0
    TOP=0
}

render() {
    local i
    local shown=0
    local match_count=${#MATCHES[@]}

    clear_drawn
    {
        printf '\033[38;5;99m%s\033[0m\n' "$HEADER"
        printf '\033[38;5;212m搜尋：\033[0m%s\033[7m \033[0m  \033[38;5;241m%d / %d\033[0m\n' \
            "$QUERY" "$match_count" "$COUNT"
        if [ "$match_count" -eq 0 ]; then
            printf '\033[38;5;241m  沒有符合的項目\033[0m\n'
            shown=1
        else
            for ((i = TOP; i < TOP + HEIGHT && i < match_count; i++)); do
                if [ "$i" -eq "$CURSOR" ]; then
                    printf '\033[38;5;212m> %s\033[0m\n' "${OPTIONS[MATCHES[i]]}"
                else
                    printf '  %s\n' "${OPTIONS[MATCHES[i]]}"
                fi
                shown=$((shown + 1))
            done
        fi
        printf '\n\033[38;5;241m輸入文字 搜尋 • backspace 刪除 • ↑↓ 移動 • enter 確認 • esc 返回\033[0m\n'
    } > "$TTY"
    DRAWN_LINES=$((shown + 4))
}

move_cursor() {
    local match_count=${#MATCHES[@]}

    [ "$match_count" -gt 0 ] || return 0
    CURSOR=$(((CURSOR + $1 + match_count) % match_count))
    if [ "$CURSOR" -lt "$TOP" ]; then
        TOP=$CURSOR
    elif [ "$CURSOR" -ge $((TOP + HEIGHT)) ]; then
        TOP=$((CURSOR - HEIGHT + 1))
    fi
}

add_char() {
    QUERY_CHARS+=("$1")
    update_matches
}

delete_char() {
    local last=$((${#QUERY_CHARS[@]} - 1))

    [ "$last" -ge 0 ] || return 0
    unset "QUERY_CHARS[$last]"
    update_matches
}

# 讀取中文等多位元組字元的後續位元組，組成完整字元
read_utf8_char() {
    local char="$1"
    local value
    local rest=0

    value=$(byte_value "$char")
    if [ "$value" -ge 240 ]; then
        rest=3
    elif [ "$value" -ge 224 ]; then
        rest=2
    elif [ "$value" -ge 192 ]; then
        rest=1
    else
        # 單獨出現的後續位元組不是有效字元，忽略
        return 0
    fi
    while [ "$rest" -gt 0 ]; do
        read_key
        char="${char}${KEY}"
        rest=$((rest - 1))
    done
    add_char "$char"
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

update_matches
while true; do
    render
    read_key
    case "$KEY" in
        $'\033')
            # 方向鍵會緊接著送出後續位元組；0.1 秒內沒有後續位元組就是單獨的 Esc
            stty min 0 time 1 < "$TTY"
            rest=$(dd bs=1 count=2 < "$TTY" 2> /dev/null)
            case "$rest" in
                "[A"|"OA") move_cursor -1 ;;
                "[B"|"OB") move_cursor 1 ;;
                "") finish 1 ;;
                \[[0-9])
                    # Delete、Page Up 等按鍵的序列較長，讀完剩餘位元組後忽略
                    while read_key && [ -n "$KEY" ]; do
                        case "$KEY" in
                            [0-9\;]) ;;
                            *) break ;;
                        esac
                    done
                    ;;
            esac
            stty min 1 time 0 < "$TTY"
            ;;
        $'\n'|$'\r')
            [ "${#MATCHES[@]}" -gt 0 ] && break
            ;;
        $'\177'|$'\010') delete_char ;;
        $'\003'|"") finish 130 ;;
        [[:print:]]) add_char "$KEY" ;;
        *)
            case "$KEY" in
                [[:cntrl:]]) ;;
                *) read_utf8_char "$KEY" ;;
            esac
            ;;
    esac
done

clear_drawn
restore_tty
printf '%s\n' "${OPTIONS[MATCHES[CURSOR]]}"
exit 0
