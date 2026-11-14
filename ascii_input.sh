#!/bin/bash

# 把目前的輸入法切換成英數輸入法（系統設定中的英文鍵盤配置，通常是「ABC」），讓使用者輸入密碼時不會打成中文。
# 已經是英數輸入法時不做任何事。找不到 swift 或切換失敗時不回報錯誤，由使用者自行切換。

if [ -z "${BASH_VERSION:-}" ] || shopt -oq posix; then
    exec /bin/bash "$0" "$@"
fi

SWIFT_BIN="${KAIROS_SWIFT_BIN:-swift}"

command -v "$SWIFT_BIN" > /dev/null 2>&1 || exit 1

"$SWIFT_BIN" -e '
import Carbon
import Foundation

func sourceID(_ source: TISInputSource) -> String? {
    guard let pointer = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) else {
        return nil
    }
    return Unmanaged<CFString>.fromOpaque(pointer).takeUnretainedValue() as String
}

guard let ascii = TISCopyCurrentASCIICapableKeyboardLayoutInputSource()?.takeRetainedValue() else {
    exit(1)
}
if let current = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue(),
   sourceID(current) == sourceID(ascii) {
    exit(0)
}
exit(TISSelectInputSource(ascii) == 0 ? 0 : 1)
' > /dev/null 2>&1
