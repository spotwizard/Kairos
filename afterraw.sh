#!/bin/bash

# 如果使用者用 `sh psd.sh ...` 之類方式執行，這支腳本（用到陣列與 process substitution）
# 會在 POSIX sh 下直接語法錯誤；因此在非 bash 環境自動改用 bash 重新執行。
if [ -z "${BASH_VERSION:-}" ] || shopt -oq posix; then
  exec /bin/bash "$0" "$@"
fi

# 解析參數
DO_REDO=false
DO_PRE=false
DO_LOAD_RAW=false
DO_OPEN_PSD=false
DO_MAKE_PSD=false
DO_IG=false
DO_FB=false
DATE_PREFIX=""
DATE_SPECIFIED=false
RAW_FILE_NAMES=()
FILE_SPECIFIED=false
FOLDER_NAME=""

while [ "$#" -gt 0 ]; do
    case "$1" in
        --redo) DO_REDO=true; DO_PRE=true ;;
        --pre|--pre-only) DO_PRE=true ;;
        --load-raw|--open-raw|--raw-only) DO_LOAD_RAW=true ;;
        --open-psd|--psd) DO_OPEN_PSD=true ;;
        --make-psd) DO_MAKE_PSD=true ;;
        --ig) DO_IG=true ;;
        --fb) DO_FB=true ;;
        --date)
            if [ "$#" -lt 2 ]; then
                echo "錯誤：--date 後面必須提供 YYYYMMDD 日期"
                exit 1
            fi
            DATE_PREFIX="$2"
            DATE_SPECIFIED=true
            shift
            ;;
        --date=*)
            DATE_PREFIX="${1#--date=}"
            DATE_SPECIFIED=true
            ;;
        --file)
            if [ "$#" -lt 2 ]; then
                echo "錯誤：--file 後面必須提供檔名"
                exit 1
            fi
            RAW_FILE_NAMES+=("$2")
            FILE_SPECIFIED=true
            shift
            ;;
        --file=*)
            RAW_FILE_NAMES+=("${1#--file=}")
            FILE_SPECIFIED=true
            ;;
        *) FOLDER_NAME="$1" ;;
    esac
    shift
done

if [ "$DATE_SPECIFIED" = true ] && ! [[ "$DATE_PREFIX" =~ ^[0-9]{8}$ ]]; then
    echo "錯誤：指定日期必須是 YYYYMMDD 格式，例如 20260705"
    exit 1
fi

# 後置輸出模式如果沒有指定 --make-psd、--ig 或 --fb，則根據 RAW 重新產生 PSD、IG、FB；
# 只指定 --ig／--fb 時，根據 PSD 目錄內現有的 PSD 重新產生 JPG，不重建 PSD
if [ "$DO_PRE" = false ] && [ "$DO_LOAD_RAW" = false ] && [ "$DO_OPEN_PSD" = false ] \
    && [ "$DO_MAKE_PSD" = false ] && [ "$DO_IG" = false ] && [ "$DO_FB" = false ]; then
    DO_MAKE_PSD=true
    DO_IG=true
    DO_FB=true
fi

OUTPUT_FROM_PSD=false
if [ "$DO_MAKE_PSD" = false ] && { [ "$DO_IG" = true ] || [ "$DO_FB" = true ]; }; then
    OUTPUT_FROM_PSD=true
fi

if [ "$FILE_SPECIFIED" = true ]; then
    for raw_file_name in "${RAW_FILE_NAMES[@]}"; do
        if [ -z "$raw_file_name" ] || [[ "$raw_file_name" = */* ]]; then
            echo "錯誤：--file 必須是檔名，不能包含路徑"
            exit 1
        fi
        # 開啟 PSD 與根據 PSD 輸出 JPG 的 --file 是 PSD 目錄內的檔名，其他模式是 RAW 目錄內的檔名
        if [ "$DO_OPEN_PSD" = true ] || [ "$OUTPUT_FROM_PSD" = true ]; then
            if ! [[ "$raw_file_name" =~ \.[Pp][Ss][Dd]$ ]]; then
                if [ "$DO_OPEN_PSD" = true ]; then
                    echo "錯誤：--open-psd 的 --file 必須是 PSD 目錄內的 .psd 檔名"
                else
                    echo "錯誤：根據 PSD 輸出 IG／FB 時，--file 必須是 PSD 目錄內的 .psd 檔名"
                fi
                exit 1
            fi
        elif ! [[ "$raw_file_name" =~ \.([Aa][Rr][Ww]|[Rr][Aa][Ww])$ ]]; then
            echo "錯誤：--file 必須是 RAW 目錄內的 .ARW 或 .RAW 檔名（不含路徑）"
            exit 1
        fi
    done
    if [ "$DATE_SPECIFIED" = true ]; then
        echo "錯誤：--file 不能與 --date 同時使用"
        exit 1
    fi
fi

if [ "$DO_REDO" = true ] && { [ "$DO_LOAD_RAW" = true ] || [ "$DO_OPEN_PSD" = true ] || [ "$DO_MAKE_PSD" = true ] || [ "$DO_IG" = true ] || [ "$DO_FB" = true ] || [ "$DATE_SPECIFIED" = true ]; }; then
    echo "錯誤：--redo 是獨立重新修圖模式，不能與 --load-raw、--open-psd、--make-psd、--ig、--fb 或 --date 同時使用"
    exit 1
fi

if [ "$DO_LOAD_RAW" = true ] && { [ "$DO_PRE" = true ] || [ "$DO_OPEN_PSD" = true ] || [ "$DO_MAKE_PSD" = true ] || [ "$DO_IG" = true ] || [ "$DO_FB" = true ]; }; then
    echo "錯誤：--load-raw 是獨立載入模式，不能與 --pre、--open-psd、--make-psd、--ig 或 --fb 同時使用"
    exit 1
fi

if [ "$DO_OPEN_PSD" = true ] && { [ "$DO_PRE" = true ] || [ "$DO_MAKE_PSD" = true ] || [ "$DO_IG" = true ] || [ "$DO_FB" = true ]; }; then
    echo "錯誤：--open-psd 是獨立開啟模式，不能與 --pre、--make-psd、--ig 或 --fb 同時使用"
    exit 1
fi

if [ "$DO_PRE" = true ] && { [ "$DO_MAKE_PSD" = true ] || [ "$DO_IG" = true ] || [ "$DO_FB" = true ]; }; then
    echo "錯誤：--pre 是獨立前置模式，不能與 --make-psd、--ig 或 --fb 同時使用"
    exit 1
fi

# 檢查是否提供了資料夾名稱
if [ -z "$FOLDER_NAME" ]; then
    echo "錯誤：請提供資料夾名稱作為參數"
    echo "使用方式:"
    echo "  重新修圖: $0 --redo [--file RAW檔名] <資料夾名稱>"
    echo "  前置作業: $0 --pre [--date YYYYMMDD | --file RAW檔名] <資料夾名稱>"
    echo "  載入 RAW: $0 --load-raw [--date YYYYMMDD | --file RAW檔名] <資料夾名稱|RAW目錄路徑>"
    echo "  開啟 PSD 檔案: $0 --open-psd [--file PSD檔名] <資料夾名稱>"
    echo "  輸出 PSD＋IG＋FB: $0 [--date YYYYMMDD | --file RAW檔名] <資料夾名稱>"
    echo "  輸出 PSD: $0 --make-psd [--date YYYYMMDD | --file RAW檔名] <資料夾名稱>"
    echo "  根據 PSD 輸出 IG／FB: $0 [--ig] [--fb] [--date YYYYMMDD | --file PSD檔名] <資料夾名稱>"
    exit 1
fi

# 設定基礎路徑
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
BASE_DIR="/Users/robbie/Dropbox/__攝影"
CURRENT_EDIT_FILE="$SCRIPT_DIR/.current_photo_edit_dir"
# shellcheck source=dropbox_offline.sh
source "$SCRIPT_DIR/dropbox_offline.sh"

if [ "$DO_LOAD_RAW" = true ] && [ -d "$FOLDER_NAME" ]; then
    TARGET_DIR=$(cd "$FOLDER_NAME" && pwd)
else
    TARGET_DIR="$BASE_DIR/$FOLDER_NAME"
fi

# 檢查目標資料夾是否存在
if [ ! -d "$TARGET_DIR" ]; then
    echo "錯誤：找不到資料夾「${FOLDER_NAME}」"
    echo "路徑：$TARGET_DIR"
    exit 1
fi

echo "找到資料夾：$TARGET_DIR"

# 開啟 PSD 與根據 PSD 輸出 IG／FB 只讀 PSD 目錄，不需要 RAW 目錄
SOURCE_IS_PSD=false
if [ "$DO_OPEN_PSD" = true ] || [ "$OUTPUT_FROM_PSD" = true ]; then
    SOURCE_IS_PSD=true
fi

# 檢查 RAW 來源資料夾是否存在
if [ "$SOURCE_IS_PSD" = true ]; then
    RAW_DIR=""
elif [ "$DO_LOAD_RAW" = true ] && [ ! -d "$TARGET_DIR/RAW" ]; then
    RAW_DIR="$TARGET_DIR"
else
    RAW_DIR="$TARGET_DIR/RAW"
fi

if [ "$SOURCE_IS_PSD" = false ] && [ ! -d "$RAW_DIR" ]; then
    if [ "$DO_LOAD_RAW" = true ]; then
        echo "錯誤：找不到 RAW 來源資料夾"
    else
        echo "錯誤：找不到 RAW 子資料夾"
    fi
    echo "路徑：$RAW_DIR"
    exit 1
fi

if [ "$SOURCE_IS_PSD" = false ] && [ "$FILE_SPECIFIED" = true ]; then
    for raw_file_name in "${RAW_FILE_NAMES[@]}"; do
        if [ ! -f "$RAW_DIR/$raw_file_name" ]; then
            echo "錯誤：找不到指定的 RAW 檔案"
            echo "路徑：$RAW_DIR/$raw_file_name"
            exit 1
        fi
    done
fi

if [ "$SOURCE_IS_PSD" = true ]; then
    :
elif [ "$DO_LOAD_RAW" = true ] && [ "$RAW_DIR" = "$TARGET_DIR" ]; then
    echo "使用指定資料夾作為 RAW 來源：$RAW_DIR"
else
    echo "進入 RAW 資料夾：$RAW_DIR"
fi

if [ "$DO_LOAD_RAW" = false ] && [ "$DO_OPEN_PSD" = false ] && ! command -v exiftool > /dev/null 2>&1; then
    echo "錯誤：找不到 exiftool，無法套用 Camera Raw 前置設定與更新 EXIF"
    exit 1
fi

PHOTOSHOP_APP="Adobe Photoshop 2026"
PHOTOSHOP_APP_DISPLAY="$PHOTOSHOP_APP"
PHOTOSHOP_APP_PATH=""
PHOTOSHOP_APP_BUNDLES=(
    "/Applications/Adobe Photoshop 2026/Adobe Photoshop 2026.app"
    "/Applications/Adobe Photoshop (Beta)/Adobe Photoshop (Beta).app"
)
CAMERA_RAW_WINDOW_MATCH="Camera Raw"
CAMERA_RAW_DENOISE_CHECKBOX="去除雜色"
CAMERA_RAW_DENOISE_CLICK_X_OFFSET=1398
CAMERA_RAW_DENOISE_CLICK_Y_OFFSET=917
CAMERA_RAW_DENOISE_SCROLL_DOWN_STEPS=8
CAMERA_RAW_OPEN_OBJECT_BUTTON="開啟物件"
CAMERA_RAW_DONE_BUTTON="完成"
CAMERA_RAW_DONE_BUTTON_EN="Done"
MANUAL_NOISE_REDUCTION_AMOUNT=20
CAMERA_RAW_CROP_WIDTH=4
CAMERA_RAW_CROP_HEIGHT=5
CAMERA_RAW_CROP_UNIT=3
CAMERA_RAW_RELOAD_WAIT_SECONDS=120
PREFLIGHT_WAIT_SECONDS=3600
# 批次去除雜色：開始處理應很快讓「開啟物件」暫時停用；未偵測到就繼續後續流程。
DENOISE_DISABLE_WAIT_BASE=20
DENOISE_DISABLE_WAIT_PER_FILE=0
DENOISE_DISABLE_WAIT_CAP=20
DENOISE_ENABLE_WAIT_BASE=600
DENOISE_ENABLE_WAIT_PER_FILE=180
DENOISE_ENABLE_WAIT_CAP=3600

plist_value() {
    local bundle="$1"
    local key="$2"
    /usr/libexec/PlistBuddy -c "Print :$key" "$bundle/Contents/Info.plist" 2>/dev/null
}

photoshop_bundle_executable_path() {
    local bundle="$1"
    local executable

    executable=$(plist_value "$bundle" "CFBundleExecutable") || return 1
    if [ -z "$executable" ]; then
        return 1
    fi

    echo "$bundle/Contents/MacOS/$executable"
}

photoshop_bundle_is_launchable() {
    local bundle="$1"
    local executable_path

    [ -d "$bundle" ] || return 1
    executable_path=$(photoshop_bundle_executable_path "$bundle") || return 1
    [ -x "$executable_path" ]
}

select_photoshop_app() {
    local bundle
    local display_name
    local executable_name
    local executable_path

    for bundle in "${PHOTOSHOP_APP_BUNDLES[@]}"; do
        if photoshop_bundle_is_launchable "$bundle"; then
            PHOTOSHOP_APP_PATH="$bundle"
            display_name=$(plist_value "$bundle" "CFBundleDisplayName")
            executable_name=$(plist_value "$bundle" "CFBundleExecutable")

            if [ -n "$display_name" ]; then
                PHOTOSHOP_APP_DISPLAY="$display_name"
            else
                PHOTOSHOP_APP_DISPLAY="$(basename "$bundle" .app)"
            fi

            if [ -n "$executable_name" ]; then
                PHOTOSHOP_APP="$executable_name"
            fi

            echo "使用 Photoshop：$PHOTOSHOP_APP_DISPLAY"
            return 0
        fi

        if [ -d "$bundle" ]; then
            executable_path=$(photoshop_bundle_executable_path "$bundle" || true)
            if [ -n "$executable_path" ]; then
                echo "⚠ 跳過不可啟動的 Photoshop：${bundle}（缺少可執行檔：${executable_path}）"
            else
                echo "⚠ 跳過不可啟動的 Photoshop：${bundle}（無法讀取 CFBundleExecutable）"
            fi
        fi
    done

    echo "錯誤：找不到可啟動的 Photoshop app"
    echo "請確認 Adobe Photoshop (Beta) 或 Adobe Photoshop 2026 已正確安裝。"
    return 1
}

select_photoshop_app || exit 1

denoise_disable_wait_max() {
    local file_count="$1"
    local wait_sec=$((DENOISE_DISABLE_WAIT_BASE + file_count * DENOISE_DISABLE_WAIT_PER_FILE))
    if [ "$wait_sec" -gt "$DENOISE_DISABLE_WAIT_CAP" ]; then
        wait_sec="$DENOISE_DISABLE_WAIT_CAP"
    fi
    echo "$wait_sec"
}

denoise_enable_wait_max() {
    local file_count="$1"
    local wait_sec=$((DENOISE_ENABLE_WAIT_BASE + (file_count - 1) * DENOISE_ENABLE_WAIT_PER_FILE))
    if [ "$wait_sec" -gt "$DENOISE_ENABLE_WAIT_CAP" ]; then
        wait_sec="$DENOISE_ENABLE_WAIT_CAP"
    fi
    echo "$wait_sec"
}

calculate_camera_raw_center_crop() {
    local raw_file="$1"
    local dimensions
    local default_crop_size
    local crop_area_width
    local crop_area_height
    local image_width
    local image_height
    local orientation

    dimensions=$(exiftool -s3 -f -DefaultCropSize -ImageWidth -ImageHeight -Orientation# "$raw_file" 2> /dev/null)
    default_crop_size=$(printf '%s\n' "$dimensions" | sed -n '1p')
    image_width=$(printf '%s\n' "$dimensions" | sed -n '2p')
    image_height=$(printf '%s\n' "$dimensions" | sed -n '3p')
    orientation=$(printf '%s\n' "$dimensions" | sed -n '4p')

    if [[ "$default_crop_size" =~ ^([0-9]+)[[:space:]]+([0-9]+)$ ]]; then
        crop_area_width="${BASH_REMATCH[1]}"
        crop_area_height="${BASH_REMATCH[2]}"
    else
        crop_area_width="$image_width"
        crop_area_height="$image_height"
    fi

    if ! [[ "$crop_area_width" =~ ^[0-9]+$ ]] || ! [[ "$crop_area_height" =~ ^[0-9]+$ ]] || [ "$crop_area_width" -le 0 ] || [ "$crop_area_height" -le 0 ]; then
        return 1
    fi

    awk -v image_width="$crop_area_width" \
        -v image_height="$crop_area_height" \
        -v orientation="${orientation:-1}" \
        -v crop_width="$CAMERA_RAW_CROP_WIDTH" \
        -v crop_height="$CAMERA_RAW_CROP_HEIGHT" '
        BEGIN {
            rotated = (orientation == 5 || orientation == 6 || orientation == 7 || orientation == 8)
            display_width = rotated ? image_height : image_width
            display_height = rotated ? image_width : image_height
            target_aspect = crop_width / crop_height
            image_aspect = display_width / display_height

            if (image_aspect > target_aspect) {
                crop_visible_width = display_height * target_aspect
                display_left = (display_width - crop_visible_width) / 2 / display_width
                display_right = 1 - display_left
                display_top = 0
                display_bottom = 1
            } else {
                crop_visible_height = display_width / target_aspect
                display_top = (display_height - crop_visible_height) / 2 / display_height
                display_bottom = 1 - display_top
                display_left = 0
                display_right = 1
            }

            if (orientation == 3 || orientation == 4) {
                crop_left = 1 - display_right
                crop_top = 1 - display_bottom
                crop_right = 1 - display_left
                crop_bottom = 1 - display_top
            } else if (orientation == 5 || orientation == 6) {
                crop_left = display_top
                crop_top = 1 - display_right
                crop_right = display_bottom
                crop_bottom = 1 - display_left
            } else if (orientation == 7 || orientation == 8) {
                crop_left = 1 - display_bottom
                crop_top = display_left
                crop_right = 1 - display_top
                crop_bottom = display_right
            } else {
                crop_left = display_left
                crop_top = display_top
                crop_right = display_right
                crop_bottom = display_bottom
            }

            printf "%.10f %.10f %.10f %.10f\n", crop_left, crop_top, crop_right, crop_bottom
        }
    '
}

raw_has_completed_sidecars() {
    local raw_file="$1"
    local base_name="${raw_file%.*}"

    [ -f "${base_name}.xmp" ] && [ -f "${base_name}.acr" ]
}

# 後置輸出的來源檔：根據 RAW 輸出時是找到的 RAW，根據 PSD 輸出時是找到的 PSD
OUTPUT_SOURCE_FILES=()
OUTPUT_SOURCE_LABEL="RAW"

source_output_basename_exists() {
    local output_base="$1"
    local source_file
    local source_name
    local source_base

    for source_file in "${OUTPUT_SOURCE_FILES[@]}"; do
        source_name=$(basename "$source_file")
        source_base="${source_name%.*}"
        if [ "$source_base" = "$output_base" ]; then
            return 0
        fi
    done

    return 1
}

cleanup_orphan_output_files() {
    local output_dir="$1"
    local label="$2"
    local file_type="$3"
    local output_file
    local output_name
    local output_base
    local deleted_count=0
    local failed_count=0
    local -a date_filter=()

    if [ -n "$DATE_PREFIX" ]; then
        date_filter=(-iname "${DATE_PREFIX}*")
    fi

    if [ ! -d "$output_dir" ]; then
        return 0
    fi

    echo "檢查 ${label} 無對應 ${OUTPUT_SOURCE_LABEL} 的輸出檔..."

    if [ "$file_type" = "psd" ]; then
        while IFS= read -r -d '' output_file; do
            output_name=$(basename "$output_file")
            output_base="${output_name%.*}"

            if source_output_basename_exists "$output_base"; then
                continue
            fi

            if rm -f -- "$output_file"; then
                echo "✓ 已刪除無對應 ${OUTPUT_SOURCE_LABEL} 的 ${label} 檔案：$output_name"
                deleted_count=$((deleted_count + 1))
            else
                echo "✗ 無對應 ${OUTPUT_SOURCE_LABEL} 但刪除失敗：$output_name"
                failed_count=$((failed_count + 1))
            fi
        done < <(find "$output_dir" -maxdepth 1 -type f "${date_filter[@]}" -iname "*.psd" -print0)
    else
        while IFS= read -r -d '' output_file; do
            output_name=$(basename "$output_file")
            output_base="${output_name%.*}"

            if source_output_basename_exists "$output_base"; then
                continue
            fi

            if rm -f -- "$output_file"; then
                echo "✓ 已刪除無對應 ${OUTPUT_SOURCE_LABEL} 的 ${label} 檔案：$output_name"
                deleted_count=$((deleted_count + 1))
            else
                echo "✗ 無對應 ${OUTPUT_SOURCE_LABEL} 但刪除失敗：$output_name"
                failed_count=$((failed_count + 1))
            fi
        done < <(find "$output_dir" -maxdepth 1 -type f "${date_filter[@]}" \( -iname "*.jpg" -o -iname "*.jpeg" \) -print0)
    fi

    if [ "$deleted_count" -eq 0 ] && [ "$failed_count" -eq 0 ]; then
        echo "✓ ${label} 沒有需要清理的輸出檔"
    fi

    if [ "$failed_count" -gt 0 ]; then
        return 1
    fi

    return 0
}

# 收集 PSD 目錄內要處理的 PSD：指定檔名時只取這些檔案（找不到的略過），否則取全部（或指定日期開頭）的 .psd
collect_psd_files() {
    local psd_file_name
    local psd_file

    PSD_DIR="$TARGET_DIR/PSD"
    PSD_FILES_FOUND=()

    if [ ! -d "$PSD_DIR" ]; then
        echo "錯誤：找不到 PSD 資料夾"
        echo "路徑：$PSD_DIR"
        return 1
    fi

    if [ "$FILE_SPECIFIED" = true ]; then
        for psd_file_name in "${RAW_FILE_NAMES[@]}"; do
            if [ ! -f "$PSD_DIR/$psd_file_name" ]; then
                echo "⊘ 找不到 PSD 檔案，略過：$psd_file_name"
                continue
            fi
            PSD_FILES_FOUND+=("$PSD_DIR/$psd_file_name")
            echo "找到 PSD 檔案：$psd_file_name"
        done
    else
        while IFS= read -r -d '' psd_file; do
            PSD_FILES_FOUND+=("$psd_file")
            echo "找到 PSD 檔案：$(basename "$psd_file")"
        done < <(find "$PSD_DIR" -maxdepth 1 -type f -iname "${DATE_PREFIX}*.psd" -print0)
    fi

    if [ ${#PSD_FILES_FOUND[@]} -eq 0 ] && [ "$FILE_SPECIFIED" = true ]; then
        echo "錯誤：找不到指定的 PSD 檔案"
        return 1
    fi

    return 0
}

prepare_output_dirs() {
    PSD_DIR="$TARGET_DIR/PSD"
    FB_DIR="$TARGET_DIR/FB"
    IG_DIR="$TARGET_DIR/IG"

    if [ "$DO_MAKE_PSD" = true ]; then
        if [ ! -d "$PSD_DIR" ]; then
            echo "建立 PSD 資料夾：$PSD_DIR"
            mkdir -p "$PSD_DIR" || return 1
        else
            echo "PSD 資料夾已存在：$PSD_DIR"
        fi
    fi

    if [ "$DO_FB" = true ]; then
        mkdir -p "$FB_DIR" || return 1
        echo "FB 輸出資料夾：$FB_DIR"
    fi
    if [ "$DO_IG" = true ]; then
        mkdir -p "$IG_DIR" || return 1
        echo "IG 輸出資料夾：$IG_DIR"
    fi

    return 0
}

# 指定檔名時，其他檔案的輸出檔不在處理範圍內，不做孤兒輸出清理
cleanup_orphan_outputs() {
    local cleanup_failed=false

    if [ "$FILE_SPECIFIED" = true ]; then
        return 0
    fi

    echo ""
    echo "開始清理無對應 ${OUTPUT_SOURCE_LABEL} 的輸出檔..."
    if [ "$DO_MAKE_PSD" = true ] && ! cleanup_orphan_output_files "$PSD_DIR" "PSD" "psd"; then
        cleanup_failed=true
    fi
    if [ "$DO_FB" = true ] && ! cleanup_orphan_output_files "$FB_DIR" "FB" "jpg"; then
        cleanup_failed=true
    fi
    if [ "$DO_IG" = true ] && ! cleanup_orphan_output_files "$IG_DIR" "IG" "jpg"; then
        cleanup_failed=true
    fi
    if [ "$cleanup_failed" = true ]; then
        echo "✗ 無對應 ${OUTPUT_SOURCE_LABEL} 的輸出檔清理失敗"
        return 1
    fi

    return 0
}

# 把路徑放進 JavaScript 單引號字串前，跳脫反斜線與單引號
js_quote() {
    local value="$1"

    value="${value//\\/\\\\}"
    value="${value//\'/\\\'}"
    printf "'%s'" "$value"
}

# 產生單一檔案的 Photoshop JavaScript。
# 有 RAW 時：以底版 PSD 放入 RAW、轉成智慧型物件並加上曝光度調整、在智慧型物件內縮成寬 4000px、置中後存回 PSD。
# 沒有 RAW 時：開啟現有 PSD，不修改也不存回。
# 之後依 DO_FB、DO_IG 從 PSD 輸出：FB 是智慧型物件內容，IG 是整張畫布。
build_output_js() {
    local psd_file="$1"
    local raw_file="$2"
    local fb_output="$3"
    local ig_output="$4"
    local js

    js="
var psdFile = $(js_quote "$psd_file");
var fbOutput = $(js_quote "$fb_output");
var igOutput = $(js_quote "$ig_output");
var idplacedLayerEditContents = stringIDToTypeID('placedLayerEditContents');

// JPG 儲存選項
var jpgOptions = new JPEGSaveOptions();
jpgOptions.quality = 7;
jpgOptions.embedColorProfile = true;
jpgOptions.formatOptions = FormatOptions.STANDARDBASELINE;

function saveJpgOverwrite(documentToSave, outputPath) {
    var jpgFile = new File(outputPath);
    if (jpgFile.exists) {
        jpgFile.remove();
    }
    documentToSave.saveAs(jpgFile, jpgOptions, true, Extension.LOWERCASE);
}

// 由上往下找第一個智慧型物件圖層（放入的 RAW）
function findSmartObjectLayer(documentToSearch) {
    for (var i = 0; i < documentToSearch.layers.length; i++) {
        var layer = documentToSearch.layers[i];
        if (layer.typename == 'ArtLayer' && layer.kind == LayerKind.SMARTOBJECT) {
            return layer;
        }
    }
    return null;
}

var doc = app.open(new File(psdFile));
var smartLayer = null;
"

    if [ -n "$raw_file" ]; then
        js+="
var rawFile = $(js_quote "$raw_file");

// 匯入 RAW 檔案作為新圖層
var idPlc = charIDToTypeID('Plc ');
var desc = new ActionDescriptor();
desc.putPath(charIDToTypeID('null'), new File(rawFile));
desc.putEnumerated(charIDToTypeID('FTps'), charIDToTypeID('QCSt'), charIDToTypeID('Qcsa'));
executeAction(idPlc, desc, DialogModes.NO);

// 移動圖層到最上層
if (doc.layers.length > 1) {
    doc.activeLayer.move(doc.layers[0], ElementPlacement.PLACEBEFORE);
}

// 轉換為智慧型物件
executeAction(stringIDToTypeID('newPlacedLayer'), undefined, DialogModes.NO);

// 第一次編輯智慧型物件：建立曝光度圖層
executeAction(idplacedLayerEditContents, undefined, DialogModes.NO);
var exposureDoc = app.activeDocument;
var mkDesc = new ActionDescriptor();
var adjRef = new ActionReference();
adjRef.putClass(charIDToTypeID('AdjL'));
mkDesc.putReference(charIDToTypeID('null'), adjRef);
var descType = new ActionDescriptor();
var descExposure = new ActionDescriptor();
descExposure.putDouble(stringIDToTypeID('offset'), 0.0042); // 偏移量
descExposure.putDouble(stringIDToTypeID('gammaCorrection'), 1.15); // Gamma 校正
descType.putObject(charIDToTypeID('Type'), stringIDToTypeID('exposure'), descExposure);
mkDesc.putObject(charIDToTypeID('Usng'), charIDToTypeID('AdjL'), descType);
executeAction(charIDToTypeID('Mk  '), mkDesc, DialogModes.NO);
exposureDoc.save();
exposureDoc.close();
app.activeDocument = doc;

// 第二次編輯智慧型物件：調整影像尺寸為寬度 4000px
executeAction(idplacedLayerEditContents, undefined, DialogModes.NO);
var resizeDoc = app.activeDocument;
var currentWidth = resizeDoc.width.as('px');
var targetWidth = 4000;
var newHeight = resizeDoc.height.as('px') * (targetWidth / currentWidth);
resizeDoc.resizeImage(UnitValue(targetWidth, 'px'), UnitValue(newHeight, 'px'), null, ResampleMethod.BICUBIC);
resizeDoc.save();
resizeDoc.close();
app.activeDocument = doc;

// 將智慧型物件置中對齊（在 4160px 寬的畫布上，4000px 智慧型物件會有左右各 80px 留白）
smartLayer = doc.activeLayer;
var bounds = smartLayer.bounds;
var layerCenterX = (bounds[0].as('px') + bounds[2].as('px')) / 2;
var layerCenterY = (bounds[1].as('px') + bounds[3].as('px')) / 2;
smartLayer.translate(doc.width.as('px') / 2 - layerCenterX, doc.height.as('px') / 2 - layerCenterY);

// 儲存 PSD
doc.save();
"
    fi

    if [ "$DO_FB" = true ]; then
        js+="
// FB：開啟智慧型物件內容，轉換為 sRGB 後導出 JPG，不存回
if (smartLayer == null) {
    smartLayer = findSmartObjectLayer(doc);
}
if (smartLayer == null) {
    doc.close(SaveOptions.DONOTSAVECHANGES);
    throw new Error('PSD 內找不到智慧型物件圖層，無法輸出 FB');
}
doc.activeLayer = smartLayer;
executeAction(idplacedLayerEditContents, undefined, DialogModes.NO);
var fbDoc = app.activeDocument;
fbDoc.convertProfile('sRGB IEC61966-2.1', Intent.RELATIVECOLORIMETRIC, true, false);
saveJpgOverwrite(fbDoc, fbOutput);
fbDoc.close(SaveOptions.DONOTSAVECHANGES);
app.activeDocument = doc;
"
    fi

    if [ "$DO_IG" = true ]; then
        js+="
// IG：整張畫布轉換為 sRGB 後導出 JPG，不存回
app.activeDocument = doc;
doc.convertProfile('sRGB IEC61966-2.1', Intent.RELATIVECOLORIMETRIC, true, false);
saveJpgOverwrite(doc, igOutput);
"
    fi

    js+="
doc.close(SaveOptions.DONOTSAVECHANGES);
"

    printf '%s' "$js"
}

# 依 JOB_PSD_FILES（與對應的 JOB_RAW_FILES，根據 PSD 輸出時為空字串）逐一交給 Photoshop 處理
run_photoshop_outputs() {
    local i
    local psd_file
    local raw_file
    local file_basename
    local fb_output
    local ig_output
    local js_code
    local modes=""
    local failed_count=0
    local -a exif_files

    if [ "$DO_MAKE_PSD" = true ]; then modes+="PSD "; fi
    if [ "$DO_IG" = true ]; then modes+="IG "; fi
    if [ "$DO_FB" = true ]; then modes+="FB "; fi

    echo ""
    if [ "$DO_MAKE_PSD" = true ]; then
        echo "開始將 RAW/ARW 檔案匯入到 PSD，並輸出：${modes}"
    else
        echo "開始根據 PSD 輸出：${modes}"
    fi
    echo ""

    for i in "${!JOB_PSD_FILES[@]}"; do
        psd_file="${JOB_PSD_FILES[$i]}"
        raw_file="${JOB_RAW_FILES[$i]}"
        file_basename=$(basename "$psd_file")
        file_basename="${file_basename%.*}"
        fb_output="$FB_DIR/${file_basename}.jpg"
        ig_output="$IG_DIR/${file_basename}.jpg"

        if [ -n "$raw_file" ]; then
            echo "處理：$(basename "$psd_file") ← $(basename "$raw_file")"
        else
            echo "處理：$(basename "$psd_file")"
        fi

        js_code=$(build_output_js "$psd_file" "$raw_file" "$fb_output" "$ig_output")

        # 使用 osascript 執行 Photoshop JavaScript
        if osascript - "$PHOTOSHOP_APP_PATH" "$js_code" <<'APPLESCRIPT' > /dev/null; then
on run argv
    set appPath to item 1 of argv as text
    set jsCode to item 2 of argv

    tell application appPath
        with timeout of 1800 seconds
            «event miscDjxM» jsCode
        end timeout
    end tell
end run
APPLESCRIPT
            echo "  ✓ 完成"
            # 更新 JPG 的 EXIF 時間為當下時間
            exif_files=()
            if [ "$DO_FB" = true ]; then exif_files+=("$fb_output"); fi
            if [ "$DO_IG" = true ]; then exif_files+=("$ig_output"); fi
            if [ ${#exif_files[@]} -gt 0 ]; then
                exiftool -overwrite_original -AllDates="now" "${exif_files[@]}" > /dev/null 2>&1
                echo "  ✓ EXIF 時間已更新"
            fi
        else
            echo "  ✗ 處理失敗"
            failed_count=$((failed_count + 1))
        fi
    done

    echo ""
    echo "所有檔案已處理完成（模式：${modes}）"
    if [ "$failed_count" -gt 0 ]; then
        echo "其中 ${failed_count} 個檔案處理失敗"
    fi

    # 關閉 Photoshop
    echo "正在關閉 Photoshop..."
    osascript - "$PHOTOSHOP_APP_PATH" <<'APPLESCRIPT' > /dev/null 2>&1
on run argv
    set appPath to item 1 of argv as text
    tell application appPath to quit
end run
APPLESCRIPT
    echo "✓ Photoshop 已關閉"
}

apply_camera_raw_preflight() {
    local raw_file="$1"
    local raw_name
    local xmp_file
    local crop_values
    local crop_left
    local crop_top
    local crop_right
    local crop_bottom
    local -a exiftool_args

    raw_name=$(basename "$raw_file")
    xmp_file="${raw_file%.*}.xmp"

    if ! crop_values=$(calculate_camera_raw_center_crop "$raw_file"); then
        echo "✗ 無法計算 4:5 置中裁切框：$raw_name"
        return 1
    fi
    read -r crop_left crop_top crop_right crop_bottom <<< "$crop_values"

    exiftool_args=(
        -XMP-crs:HasSettings=True
        -XMP-crs:RawFileName="$raw_name"
        -XMP-crs:LookName="Adobe Color"
        -XMP-crs:AutoLateralCA=1
        -XMP-crs:LensProfileEnable=1
        -XMP-crs:LensProfileSetup=Auto
        -XMP-crs:HasCrop=True
        -XMP-crs:CropTop="$crop_top"
        -XMP-crs:CropLeft="$crop_left"
        -XMP-crs:CropBottom="$crop_bottom"
        -XMP-crs:CropRight="$crop_right"
        -XMP-crs:CropAngle=0
        -XMP-crs:CropConstrainToWarp=0
        -XMP-crs:CropWidth="$CAMERA_RAW_CROP_WIDTH"
        -XMP-crs:CropHeight="$CAMERA_RAW_CROP_HEIGHT"
        -XMP-crs:CropUnit#="$CAMERA_RAW_CROP_UNIT"
    )

    if [ -f "$xmp_file" ]; then
        if exiftool -m -overwrite_original "${exiftool_args[@]}" "$xmp_file" > /dev/null; then
            echo "✓ 已更新 Camera Raw 前置設定與 4:5 置中裁切：$raw_name"
            return 0
        fi
    elif exiftool -m -o "$xmp_file" "${exiftool_args[@]}" "$raw_file" > /dev/null; then
        echo "✓ 已建立 Camera Raw 前置設定與 4:5 置中裁切：$raw_name"
        return 0
    fi

    echo "✗ Camera Raw 前置設定失敗：$raw_name"
    return 1
}

apply_camera_raw_manual_noise_reduction() {
    local raw_file="$1"
    local raw_name
    local xmp_file

    raw_name=$(basename "$raw_file")
    xmp_file="${raw_file%.*}.xmp"

    if [ ! -f "$xmp_file" ]; then
        echo "✗ 找不到 .xmp，無法套用雜訊減少：$raw_name"
        return 1
    fi

    if exiftool -m -overwrite_original \
        -XMP-crs:LuminanceSmoothing="$MANUAL_NOISE_REDUCTION_AMOUNT" \
        -XMP-crs:ColorNoiseReduction="$MANUAL_NOISE_REDUCTION_AMOUNT" \
        -XMP-crs:CropWidth="$CAMERA_RAW_CROP_WIDTH" \
        -XMP-crs:CropHeight="$CAMERA_RAW_CROP_HEIGHT" \
        -XMP-crs:CropUnit#="$CAMERA_RAW_CROP_UNIT" \
        "$xmp_file" > /dev/null; then
        echo "✓ 已套用雜訊明度/顏色=${MANUAL_NOISE_REDUCTION_AMOUNT} 與裁切比例 4:5：$raw_name"
        return 0
    fi

    echo "✗ 雜訊明度/顏色=${MANUAL_NOISE_REDUCTION_AMOUNT} 或裁切比例 4:5 設定失敗：$raw_name"
    return 1
}

apply_camera_raw_manual_noise_after_denoise() {
    local file
    local failed=0

    echo ""
    if [ "${DENOISE_BATCH_CONFIRMED:-0}" -eq 1 ]; then
        echo "「去除雜色」已自動確認完成，正在寫入手動雜色減少（明度與顏色=${MANUAL_NOISE_REDUCTION_AMOUNT}）到 .xmp..."
    elif [ "${DENOISE_UI_CLICKED:-0}" -eq 1 ]; then
        echo "已送出「去除雜色」點擊，但未能自動確認完成；仍會寫入手動雜色減少（明度與顏色=${MANUAL_NOISE_REDUCTION_AMOUNT}）到 .xmp..."
    else
        echo "未能自動點選「去除雜色」；仍會寫入手動雜色減少（明度與顏色=${MANUAL_NOISE_REDUCTION_AMOUNT}）到 .xmp..."
    fi
    echo "（Camera Raw 已先按「${CAMERA_RAW_DONE_BUTTON}」關閉；現在寫入 sidecar，下一步重新載入 RAW 後生效）"
    for file in "${FILES_TO_OPEN[@]}"; do
        if ! apply_camera_raw_manual_noise_reduction "$file"; then
            failed=$((failed + 1))
        fi
    done

    if [ "$failed" -gt 0 ]; then
        echo "✗ 有 ${failed} 個檔案未能寫入雜訊明度/顏色=${MANUAL_NOISE_REDUCTION_AMOUNT}"
        return 1
    fi

    return 0
}

wait_for_camera_raw_window() {
    local elapsed=0

    echo "等待 Camera Raw 視窗..."
    while [ "$elapsed" -lt "$PREFLIGHT_WAIT_SECONDS" ]; do
        if osascript - "$PHOTOSHOP_APP" "$CAMERA_RAW_WINDOW_MATCH" <<'APPLESCRIPT' > /dev/null 2>&1; then
on run argv
    set appName to item 1 of argv
    set windowMatch to item 2 of argv

    tell application "System Events"
        if not (exists process appName) then error "找不到 Photoshop process"
        tell process appName
            repeat with w in windows
                set wName to name of w as text
                if (wName contains windowMatch) or (wName contains ".ARW") or (wName contains ".RAW") or (wName contains ".DNG") or (exists button "開啟物件" of w) or (exists button "Open Object" of w) or (exists button "完成" of w) or (exists button "Done" of w) then return "ok"
            end repeat
        end tell
    end tell

    error "找不到 Camera Raw 視窗"
end run
APPLESCRIPT
            echo "✓ Camera Raw 視窗已開啟"
            return 0
        fi

        sleep 1
        elapsed=$((elapsed + 1))
    done

    echo "✗ 等待 Camera Raw 視窗逾時"
    return 1
}

select_all_camera_raw_files() {
    local file_count="${1:-1}"
    local bounds
    local x
    local y
    local width
    local height
    local first_x
    local last_x
    local film_y
    local max_film_x

    echo "正在全選 Camera Raw 內的 RAW 檔案..."
    bounds=$(
        osascript - "$PHOTOSHOP_APP" "$CAMERA_RAW_WINDOW_MATCH" <<'APPLESCRIPT' 2> /dev/null
on run argv
    set appName to item 1 of argv
    set windowMatch to item 2 of argv

    tell application "System Events"
        set frontmost of process appName to true
        tell process appName
            set rawWindowFound to false
            repeat with w in windows
                set wName to name of w as text
                if (wName contains windowMatch) or (wName contains ".ARW") or (wName contains ".RAW") or (wName contains ".DNG") or (exists button "開啟物件" of w) or (exists button "Open Object" of w) or (exists button "完成" of w) or (exists button "Done" of w) then
                    set rawWindowFound to true
                    set rawWindow to w
                    exit repeat
                end if
            end repeat
            if rawWindowFound is false then error "找不到 Camera Raw 視窗"
            set rawPosition to position of rawWindow
            set rawSize to size of rawWindow
            return (item 1 of rawPosition as text) & "," & (item 2 of rawPosition as text) & "," & (item 1 of rawSize as text) & "," & (item 2 of rawSize as text)
        end tell
    end tell
end run
APPLESCRIPT
    )

    if [ -z "$bounds" ]; then
        echo "✗ 無法取得 Camera Raw 視窗位置"
        return 1
    fi

    IFS=, read -r x y width height <<< "$bounds"
    case "$x,$y,$width,$height" in
        *[!0-9,]*)
            echo "✗ Camera Raw 視窗位置格式不正確：$bounds"
            return 1
            ;;
    esac

    first_x=$((x + 85))
    film_y=$((y + height - 270))
    max_film_x=$((x + width - 500))
    last_x=$((first_x + (file_count - 1) * 175))
    if [ "$last_x" -gt "$max_film_x" ]; then
        last_x="$max_film_x"
    fi

    if shift_click_ui_points "$first_x" "$film_y" "$last_x" "$film_y"; then
        osascript -e "tell application \"System Events\" to set frontmost of process \"$PHOTOSHOP_APP\" to true" \
                  -e "tell application \"System Events\" to keystroke \"a\" using {command down}" > /dev/null 2>&1 || true
        sleep 1
        echo "✓ 已送出全選指令"
        return 0
    fi

    echo "✗ 無法全選 Camera Raw 內的 RAW 檔案"
    return 1
}

get_camera_raw_checkbox_value() {
    local checkbox_name="$1"

    osascript - "$PHOTOSHOP_APP" "$CAMERA_RAW_WINDOW_MATCH" "$checkbox_name" <<'APPLESCRIPT' 2> /dev/null
on checkbox_checked_state(uiElement)
    try
        if (value of uiElement as integer) is 1 then return 1
    end try
    try
        if value of uiElement is true then return 1
    end try
    return 0
end checkbox_checked_state

on checkbox_name_matches(uiElement, checkboxName)
    set elementName to name of uiElement as text
    if elementName is checkboxName then return true
    if elementName contains "雜色" and checkboxName contains "雜色" then return true
    if elementName contains "Denoise" then return true
    try
        set elementDescription to description of uiElement as text
        if elementDescription contains "Denoise" or elementDescription contains "雜色" then return true
    end try
    return false
end checkbox_name_matches

on run argv
    set appName to item 1 of argv
    set windowMatch to item 2 of argv
    set checkboxName to item 3 of argv

    tell application "System Events"
        tell process appName
            set rawWindow to missing value
            repeat with w in windows
                set wName to name of w as text
                if (wName contains windowMatch) or (wName contains ".ARW") or (wName contains ".RAW") or (wName contains ".DNG") or (exists button "開啟物件" of w) or (exists button "Open Object" of w) or (exists button "完成" of w) or (exists button "Done" of w) then
                    set rawWindow to w
                    exit repeat
                end if
            end repeat
            if rawWindow is missing value then error "找不到 Camera Raw 視窗"
            if exists checkbox checkboxName of rawWindow then
                return (checkbox_checked_state(checkbox checkboxName of rawWindow) as text)
            end if
            repeat with uiElement in entire contents of rawWindow
                try
                    if class of uiElement is checkbox then
                        if (name of uiElement as text) is checkboxName then
                            if checkbox_checked_state(uiElement) is 1 then return "1"
                        end if
                    end if
                end try
            end repeat
            repeat with uiElement in entire contents of rawWindow
                try
                    if class of uiElement is checkbox then
                        if checkbox_name_matches(uiElement, checkboxName) then
                            return (checkbox_checked_state(uiElement) as text)
                        end if
                    end if
                end try
            end repeat
            error "找不到 checkbox: " & checkboxName
        end tell
    end tell
end run
APPLESCRIPT
}

wait_for_camera_raw_checkbox_value() {
    local checkbox_name="$1"
    local expected_value="$2"
    local elapsed=0
    local value

    while [ "$elapsed" -lt "$PREFLIGHT_WAIT_SECONDS" ]; do
        value=$(get_camera_raw_checkbox_value "$checkbox_name" || true)
        if [ "$value" = "$expected_value" ]; then
            return 0
        fi

        sleep 2
        elapsed=$((elapsed + 2))
    done

    return 1
}

get_camera_raw_button_enabled() {
    local button_name="$1"

    osascript - "$PHOTOSHOP_APP" "$CAMERA_RAW_WINDOW_MATCH" "$button_name" <<'APPLESCRIPT' 2> /dev/null
on run argv
    set appName to item 1 of argv
    set windowMatch to item 2 of argv
    set buttonName to item 3 of argv

    tell application "System Events"
        tell process appName
            set rawWindow to missing value
            repeat with w in windows
                set wName to name of w as text
                if (wName contains windowMatch) or (wName contains ".ARW") or (wName contains ".RAW") or (wName contains ".DNG") or (exists button "開啟物件" of w) or (exists button "Open Object" of w) or (exists button "完成" of w) or (exists button "Done" of w) then
                    set rawWindow to w
                    exit repeat
                end if
            end repeat
            if rawWindow is missing value then error "找不到 Camera Raw 視窗"
            if exists button buttonName of rawWindow then return (enabled of button buttonName of rawWindow as text)
            if buttonName is "開啟物件" then
                if exists button "Open Object" of rawWindow then return (enabled of button "Open Object" of rawWindow as text)
                repeat with uiElement in buttons of rawWindow
                    try
                        set elementName to name of uiElement as text
                        if elementName contains "開啟" or elementName contains "Open" then return (enabled of uiElement as text)
                    end try
                end repeat
            end if
            if buttonName is "完成" then
                if exists button "Done" of rawWindow then return (enabled of button "Done" of rawWindow as text)
            end if
            error "找不到 button: " & buttonName
        end tell
    end tell
end run
APPLESCRIPT
}

bring_photoshop_to_front() {
    osascript - "$PHOTOSHOP_APP" <<'APPLESCRIPT' > /dev/null 2>&1
on run argv
    set appName to item 1 of argv

    tell application "System Events"
        if not (exists process appName) then error "找不到 Photoshop process"
        set frontmost of process appName to true
    end tell
end run
APPLESCRIPT
}

wait_for_camera_raw_button_disabled() {
    local button_name="$1"
    local max_wait="${2:-120}"
    local elapsed=0
    local enabled

    while [ "$elapsed" -lt "$max_wait" ]; do
        enabled=$(get_camera_raw_button_enabled "$button_name" || true)
        if [ "$enabled" = "false" ]; then
            return 0
        fi
        if [ $((elapsed % 10)) -eq 0 ]; then
            echo "  等待 Camera Raw「${button_name}」暫時停用... ${elapsed}s（AX enabled=${enabled:-無法讀取}）"
        fi
        sleep 2
        elapsed=$((elapsed + 2))
    done

    return 1
}

wait_for_camera_raw_button_enabled() {
    local button_name="$1"
    local max_wait="${2:-$PREFLIGHT_WAIT_SECONDS}"
    local elapsed=0
    local enabled

    while [ "$elapsed" -lt "$max_wait" ]; do
        enabled=$(get_camera_raw_button_enabled "$button_name" || true)
        if [ "$enabled" = "true" ]; then
            return 0
        fi

        if [ $((elapsed % 30)) -eq 0 ]; then
            echo "  等待 Camera Raw「${button_name}」可用... ${elapsed}s（AX enabled=${enabled:-無法讀取}）"
        fi
        sleep 2
        elapsed=$((elapsed + 2))
    done

    return 1
}

scroll_camera_raw_panel() {
    local delta_y="$1"
    local repeat_count="$2"
    local bounds
    local x
    local y
    local width
    local height
    local panel_x
    local panel_y

    bounds=$(
        osascript - "$PHOTOSHOP_APP" "$CAMERA_RAW_WINDOW_MATCH" <<'APPLESCRIPT' 2> /dev/null
on run argv
    set appName to item 1 of argv
    set windowMatch to item 2 of argv

    tell application "System Events"
        set frontmost of process appName to true
        tell process appName
            set rawWindow to missing value
            repeat with w in windows
                set wName to name of w as text
                if (wName contains windowMatch) or (wName contains ".ARW") or (wName contains ".RAW") or (wName contains ".DNG") or (exists button "開啟物件" of w) or (exists button "Open Object" of w) or (exists button "完成" of w) or (exists button "Done" of w) then
                    set rawWindow to w
                    exit repeat
                end if
            end repeat
            if rawWindow is missing value then error "找不到 Camera Raw 視窗"
            set rawPosition to position of rawWindow
            set rawSize to size of rawWindow
            return (item 1 of rawPosition as text) & "," & (item 2 of rawPosition as text) & "," & (item 1 of rawSize as text) & "," & (item 2 of rawSize as text)
        end tell
    end tell
end run
APPLESCRIPT
    )

    if [ -z "$bounds" ]; then
        return 1
    fi

    IFS=, read -r x y width height <<< "$bounds"
    case "$x,$y,$width,$height" in
        *[!0-9,]*)
            return 1
            ;;
    esac

    # Keep the pointer inside the edit panel. The right toolbar/scrollbar area does
    # not reliably receive wheel events in Camera Raw.
    panel_x=$((x + width - 65))
    panel_y=$((y + height / 2))
    scroll_ui_wheel_at_point "$panel_x" "$panel_y" "$delta_y" "$repeat_count"
}

scroll_camera_raw_panel_to_top() {
    scroll_camera_raw_panel 1000 14
}

scroll_camera_raw_panel_step_down() {
    scroll_camera_raw_panel -180 1
}

click_camera_raw_denoise_known_position() {
    local bounds
    local x
    local y
    local width
    local height
    local click_x
    local click_y

    bounds=$(
        osascript - "$PHOTOSHOP_APP" "$CAMERA_RAW_WINDOW_MATCH" <<'APPLESCRIPT' 2>/dev/null
on run argv
    set appName to item 1 of argv
    set windowMatch to item 2 of argv

    tell application "System Events"
        set frontmost of process appName to true
        tell process appName
            set rawWindow to missing value
            repeat with w in windows
                set wName to name of w as text
                if (wName contains windowMatch) or (wName contains ".ARW") or (wName contains ".RAW") or (wName contains ".DNG") or (exists button "開啟物件" of w) or (exists button "Open Object" of w) or (exists button "完成" of w) or (exists button "Done" of w) then
                    set rawWindow to w
                    exit repeat
                end if
            end repeat
            if rawWindow is missing value then error "找不到 Camera Raw 視窗"
            set rawPosition to position of rawWindow
            set rawSize to size of rawWindow
            return (item 1 of rawPosition as text) & "," & (item 2 of rawPosition as text) & "," & (item 1 of rawSize as text) & "," & (item 2 of rawSize as text)
        end tell
    end tell
end run
APPLESCRIPT
    )

    if [ -z "$bounds" ]; then
        echo "  固定座標 fallback 失敗：找不到 Camera Raw 視窗位置"
        return 1
    fi

    IFS=, read -r x y width height <<< "$bounds"
    case "$x,$y,$width,$height" in
        *[!0-9,]*)
            echo "  固定座標 fallback 失敗：Camera Raw 視窗座標格式無效：${bounds}"
            return 1
            ;;
    esac

    click_x=$((x + CAMERA_RAW_DENOISE_CLICK_X_OFFSET))
    click_y=$((y + CAMERA_RAW_DENOISE_CLICK_Y_OFFSET))
    echo "  固定座標 fallback：Camera Raw 視窗=${x},${y},${width},${height}；點擊座標=${click_x},${click_y}（offset=${CAMERA_RAW_DENOISE_CLICK_X_OFFSET},${CAMERA_RAW_DENOISE_CLICK_Y_OFFSET}）"
    click_ui_point "$click_x" "$click_y"
}

scroll_camera_raw_panel_to_denoise_known_position() {
    local step=0

    echo "正在將 Camera Raw 右側面板捲到「${CAMERA_RAW_DENOISE_CHECKBOX}」固定位置..."
    if ! scroll_camera_raw_panel_to_top; then
        echo "⚠ 無法將 Camera Raw 右側面板捲到頂部"
        return 1
    fi

    while [ "$step" -lt "$CAMERA_RAW_DENOISE_SCROLL_DOWN_STEPS" ]; do
        if ! scroll_camera_raw_panel_step_down; then
            echo "⚠ 無法將 Camera Raw 右側面板往下捲動"
            return 1
        fi
        step=$((step + 1))
        sleep 0.2
    done

    echo "✓ 已完成固定捲動（往下 ${CAMERA_RAW_DENOISE_SCROLL_DOWN_STEPS} 次）"
    return 0
}

click_ui_point() {
    local x="$1"
    local y="$2"

    if ! command -v swift > /dev/null 2>&1; then
        return 1
    fi

    swift -e "import CoreGraphics; import Foundation
let p = CGPoint(x: Double($x), y: Double($y))
let down = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: p, mouseButton: .left)
let up = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: p, mouseButton: .left)
down?.post(tap: .cghidEventTap)
usleep(120000)
up?.post(tap: .cghidEventTap)" > /dev/null
}

click_camera_raw_button() {
    local button_name="$1"
    local bounds
    local x
    local y
    local width
    local height
    local click_x
    local click_y

    bounds=$(osascript - "$PHOTOSHOP_APP" "$CAMERA_RAW_WINDOW_MATCH" "$button_name" <<'APPLESCRIPT' 2>/dev/null
on run argv
    set appName to item 1 of argv
    set windowMatch to item 2 of argv
    set buttonName to item 3 of argv

    tell application "System Events"
        set frontmost of process appName to true
        tell process appName
            set rawWindow to missing value
            repeat with w in windows
                set wName to name of w as text
                if (wName contains windowMatch) or (wName contains ".ARW") or (wName contains ".RAW") or (wName contains ".DNG") or (exists button "開啟物件" of w) or (exists button "Open Object" of w) or (exists button "完成" of w) or (exists button "Done" of w) then
                    set rawWindow to w
                    exit repeat
                end if
            end repeat
            if rawWindow is missing value then error "找不到 Camera Raw 視窗"
            if not (exists button buttonName of rawWindow) then error "找不到 button"
            set btn to button buttonName of rawWindow
            set btnPos to position of btn
            set btnSize to size of btn
            set cx to (item 1 of btnPos) + ((item 1 of btnSize) div 2)
            set cy to (item 2 of btnPos) + ((item 2 of btnSize) div 2)
            return (cx as text) & "," & (cy as text)
        end tell
    end tell
end run
APPLESCRIPT
)

    if [ -z "$bounds" ]; then
        return 1
    fi

    IFS=, read -r click_x click_y <<< "$bounds"
    case "$click_x,$click_y" in
        *[!0-9,]*)
            return 1
            ;;
    esac

    click_ui_point "$click_x" "$click_y"
}

click_camera_raw_done_button() {
    local name

    echo "正在按 Camera Raw「${CAMERA_RAW_DONE_BUTTON}」（套用設定並關閉對話框，非「開啟物件」）..."
    for name in "$CAMERA_RAW_DONE_BUTTON" "$CAMERA_RAW_DONE_BUTTON_EN"; do
        if click_camera_raw_button "$name"; then
            echo "✓ 已按下「${name}」"
            return 0
        fi
    done

    echo "✗ 找不到或無法按下「${CAMERA_RAW_DONE_BUTTON}」/「${CAMERA_RAW_DONE_BUTTON_EN}」"
    return 1
}

wait_for_camera_raw_window_closed() {
    local max_wait="${1:-$CAMERA_RAW_RELOAD_WAIT_SECONDS}"
    local elapsed=0

    echo "等待 Camera Raw 對話框關閉..."
    while [ "$elapsed" -lt "$max_wait" ]; do
        if ! camera_raw_window_is_open; then
            echo "✓ Camera Raw 對話框已關閉"
            return 0
        fi
        sleep 1
        elapsed=$((elapsed + 1))
    done

    echo "✗ 等待 Camera Raw 關閉逾時"
    return 1
}

camera_raw_window_is_open() {
    osascript - "$PHOTOSHOP_APP" "$CAMERA_RAW_WINDOW_MATCH" <<'APPLESCRIPT' > /dev/null 2>&1
on run argv
    set appName to item 1 of argv
    set windowMatch to item 2 of argv

    tell application "System Events"
        if not (exists process appName) then error "no"
        tell process appName
            repeat with w in windows
                set wName to name of w as text
                if (wName contains windowMatch) or (wName contains ".ARW") or (wName contains ".RAW") or (wName contains ".DNG") or (exists button "開啟物件" of w) or (exists button "Open Object" of w) or (exists button "完成" of w) or (exists button "Done" of w) then return "ok"
            end repeat
        end tell
    end tell
    error "no"
end run
APPLESCRIPT
}

open_raw_files_in_photoshop() {
    local -a files=("$@")

    if [ ${#files[@]} -eq 0 ]; then
        echo "✗ 沒有 RAW 檔案可開啟"
        return 1
    fi

    if [ -z "$PHOTOSHOP_APP_PATH" ]; then
        echo "✗ 尚未選定可啟動的 Photoshop app"
        return 1
    fi

    # 用 AppleScript 對 Photoshop 發出單一個 open 指令，避免 macOS `open -a ... file1 file2`
    # 在某些情況下被 LaunchServices 拆成多個開啟事件，導致 Camera Raw 分批跳出。
    # 不先 activate；Camera Raw 開啟時 Photoshop 不回覆 activate，會誤報 AppleEvent -1712。
    osascript - "$PHOTOSHOP_APP_PATH" "${files[@]}" <<'APPLESCRIPT'
on run argv
    if (count of argv) < 2 then error "沒有檔案可開啟"

    set appPath to item 1 of argv as text
    set fileList to {}

    repeat with i from 2 to count of argv
        set filePath to item i of argv as text
        set end of fileList to (POSIX file filePath as alias)
    end repeat

    tell application appPath
        ignoring application responses
            open fileList
        end ignoring
    end tell
end run
APPLESCRIPT
}

open_psd_files_in_photoshop() {
    local -a files=("$@")

    if [ ${#files[@]} -eq 0 ]; then
        echo "✗ 沒有 PSD 檔案可開啟"
        return 1
    fi

    if [ -z "$PHOTOSHOP_APP_PATH" ]; then
        echo "✗ 尚未選定可啟動的 Photoshop app"
        return 1
    fi

    osascript - "$PHOTOSHOP_APP_PATH" "${files[@]}" <<'APPLESCRIPT'
on run argv
    if (count of argv) < 2 then error "沒有檔案可開啟"

    set appPath to item 1 of argv as text
    set fileList to {}

    repeat with i from 2 to count of argv
        set filePath to item i of argv as text
        set end of fileList to (POSIX file filePath as alias)
    end repeat

    tell application appPath
        activate
        open fileList
    end tell
end run
APPLESCRIPT
}

reload_raw_files_in_photoshop() {
    echo "重新載入 RAW 到 Camera Raw（讀取 .xmp／.acr）..."
    if ! open_raw_files_in_photoshop "${FILES_TO_OPEN[@]}"; then
        echo "✗ 無法重新開啟 RAW 檔案"
        return 1
    fi
    if ! wait_for_camera_raw_window; then
        return 1
    fi
    echo "✓ RAW 已重新載入，Camera Raw 視窗已開啟"
    return 0
}

close_camera_raw_with_done() {
    echo "正在將 Photoshop 切到前景，再偵測 Camera Raw「${CAMERA_RAW_DONE_BUTTON}」是否可用..."
    if ! bring_photoshop_to_front; then
        echo "✗ 無法將 Photoshop 切到前景"
        return 1
    fi
    sleep 1
    if ! wait_for_camera_raw_button_enabled "$CAMERA_RAW_DONE_BUTTON" "$CAMERA_RAW_RELOAD_WAIT_SECONDS"; then
        echo "✗ Camera Raw「${CAMERA_RAW_DONE_BUTTON}」目前無法使用"
        return 1
    fi
    echo "✓ Camera Raw「${CAMERA_RAW_DONE_BUTTON}」已可使用"
    if ! click_camera_raw_done_button; then
        return 1
    fi
    sleep 1
    if ! wait_for_camera_raw_window_closed "$CAMERA_RAW_RELOAD_WAIT_SECONDS"; then
        return 1
    fi
}

# 1=自動化有把握批次去除雜色已完成；0=請人工在 Camera Raw 檢查
DENOISE_BATCH_CONFIRMED=0
# 1=已找到並送出「去除雜色」點擊；0=連點擊都未能送出
DENOISE_UI_CLICKED=0

enable_camera_raw_denoise() {
    local file_count="${1:-1}"
    local disable_wait_max
    local enable_wait_max

    if ! [[ "$file_count" =~ ^[0-9]+$ ]] || [ "$file_count" -lt 1 ]; then
        file_count=1
    fi

    disable_wait_max=$(denoise_disable_wait_max "$file_count")
    enable_wait_max=$(denoise_enable_wait_max "$file_count")
    DENOISE_BATCH_CONFIRMED=0
    DENOISE_UI_CLICKED=0

    echo "共 ${file_count} 張 RAW：批次「${CAMERA_RAW_DENOISE_CHECKBOX}」處理中會持續等待（完成後提早結束，不會傻等滿額）"
    echo "  （偵測逾時上限：開始處理 ${disable_wait_max}s；全部完成 ${enable_wait_max}s／約 $(( (enable_wait_max + 59) / 60 )) 分鐘；不會按「${CAMERA_RAW_OPEN_OBJECT_BUTTON}」）"

    if ! scroll_camera_raw_panel_to_denoise_known_position; then
        echo "⚠ 無法將右側面板捲到「${CAMERA_RAW_DENOISE_CHECKBOX}」固定位置；仍嘗試用目前位置固定座標點擊"
    fi

    echo "正在用固定座標點擊 Camera Raw「${CAMERA_RAW_DENOISE_CHECKBOX}」（不搜尋文字）..."
    if ! click_camera_raw_denoise_known_position; then
        echo "⚠ 無法用固定座標點選「${CAMERA_RAW_DENOISE_CHECKBOX}」"
        DENOISE_BATCH_CONFIRMED=0
        DENOISE_UI_CLICKED=0
        return 0
    fi
    DENOISE_UI_CLICKED=1

    if verify_camera_raw_checkbox_checked "$CAMERA_RAW_DENOISE_CHECKBOX"; then
        :
    else
        echo "  （Accessibility 未讀到勾選；仍以「${CAMERA_RAW_OPEN_OBJECT_BUTTON}」恢復可按判斷是否全部完成）"
    fi

    echo "等待 Camera Raw 開始處理去除雜色（偵測「${CAMERA_RAW_OPEN_OBJECT_BUTTON}」暫時無法按）..."
    if wait_for_camera_raw_button_disabled "$CAMERA_RAW_OPEN_OBJECT_BUTTON" "$disable_wait_max"; then
        echo "✓ 偵測到去除雜色處理中..."
        echo "等待 Camera Raw 完成全部去除雜色（偵測「${CAMERA_RAW_OPEN_OBJECT_BUTTON}」恢復可按，最多 ${enable_wait_max}s）..."
        if wait_for_camera_raw_button_enabled "$CAMERA_RAW_OPEN_OBJECT_BUTTON" "$enable_wait_max"; then
            echo "✓ 偵測到「${CAMERA_RAW_OPEN_OBJECT_BUTTON}」已恢復可按（視為批次去除雜色已結束）"
            DENOISE_BATCH_CONFIRMED=1
            echo "✓ 已自動確認批次「${CAMERA_RAW_DENOISE_CHECKBOX}」"
        else
            echo "⚠ 在 ${enable_wait_max}s 內未能確認全部完成（多張時常需更久；前置仍會繼續，請人工確認）"
            DENOISE_BATCH_CONFIRMED=0
        fi
    else
        echo "  （${disable_wait_max}s 內未偵測到按鈕停用；略過恢復可按的長等待，前置流程繼續）"
        DENOISE_BATCH_CONFIRMED=0
    fi

    return 0
}

report_denoise_unconfirmed_files() {
    local file

    if [ "${DENOISE_BATCH_CONFIRMED:-0}" -eq 1 ]; then
        return 0
    fi

    echo ""
    echo "以下 RAW 未能自動確認「${CAMERA_RAW_DENOISE_CHECKBOX}」已成功（請在 Camera Raw 內人工檢查）："
    for file in "${FILES_TO_OPEN[@]}"; do
        echo "  - $(basename "$file")"
    done
}

verify_camera_raw_checkbox_checked() {
    local checkbox_name="$1"
    local value

    value=$(get_camera_raw_checkbox_value "$checkbox_name" || true)
    case "$value" in
        1|true|True|yes|on)
            echo "✓ 已確認：${checkbox_name}（AX 值=${value}）"
            return 0
            ;;
    esac

    echo "✗ 未確認：${checkbox_name}（AX 值=${value:-無法讀取}）"
    return 1
}

shift_click_ui_points() {
    local first_x="$1"
    local first_y="$2"
    local last_x="$3"
    local last_y="$4"

    if ! command -v swift > /dev/null 2>&1; then
        echo "錯誤：找不到 swift，無法送出 Shift 點擊事件"
        return 1
    fi

    swift -e "import CoreGraphics; import Foundation
func click(_ x: Double, _ y: Double, shift: Bool = false) {
    let p = CGPoint(x: x, y: y)
    let down = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: p, mouseButton: .left)
    let up = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: p, mouseButton: .left)
    if shift {
        down?.flags = .maskShift
        up?.flags = .maskShift
    }
    down?.post(tap: .cghidEventTap)
    usleep(120000)
    up?.post(tap: .cghidEventTap)
    usleep(300000)
}
click(Double($first_x), Double($first_y))
click(Double($last_x), Double($last_y), shift: true)" > /dev/null
}

scroll_ui_wheel() {
    local delta_y="$1"

    if ! command -v swift > /dev/null 2>&1; then
        echo "錯誤：找不到 swift，無法送出滾輪事件"
        return 1
    fi

    swift -e "import CoreGraphics; import Foundation; let event = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1, wheel1: Int32($delta_y), wheel2: 0, wheel3: 0); event?.post(tap: .cghidEventTap)" > /dev/null
}

scroll_ui_wheel_at_point() {
    local x="$1"
    local y="$2"
    local delta_y="$3"
    local repeat_count="$4"

    if ! command -v swift > /dev/null 2>&1; then
        echo "錯誤：找不到 swift，無法送出滾輪事件"
        return 1
    fi

    swift -e "import CoreGraphics; import Foundation; let p = CGPoint(x: $x, y: $y); CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: p, mouseButton: .left)?.post(tap: .cghidEventTap); usleep(150000); for _ in 0..<$repeat_count { CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1, wheel1: Int32($delta_y), wheel2: 0, wheel3: 0)?.post(tap: .cghidEventTap); usleep(120000) }" > /dev/null
}

write_current_photo_edit_dir() {
    if printf '%s\n' "$FOLDER_NAME" > "$CURRENT_EDIT_FILE"; then
        echo "✓ 已記錄目前修圖目錄：$CURRENT_EDIT_FILE"
        return 0
    fi

    echo "✗ 無法寫入目前修圖目錄：$CURRENT_EDIT_FILE"
    return 1
}

# 重新修圖：清除 RAW 目錄的 Camera Raw sidecar 與 PSD、IG、FB 目錄，再執行前置作業
if [ "$DO_REDO" = true ] && [ "$FILE_SPECIFIED" = true ]; then
    echo ""
    echo "開始重新修圖：清除指定 ${#RAW_FILE_NAMES[@]} 個 RAW 的 Camera Raw 設定與輸出成品..."

    for raw_file_name in "${RAW_FILE_NAMES[@]}"; do
        raw_file_base="${raw_file_name%.*}"
        for redo_file in \
            "$RAW_DIR/${raw_file_base}.xmp" \
            "$RAW_DIR/${raw_file_base}.acr" \
            "$TARGET_DIR/PSD/${raw_file_base}.psd" \
            "$TARGET_DIR/IG/${raw_file_base}.jpg" \
            "$TARGET_DIR/FB/${raw_file_base}.jpg"; do
            if [ ! -e "$redo_file" ]; then
                continue
            fi
            if ! rm -f -- "$redo_file"; then
                echo "✗ 無法刪除：$redo_file"
                exit 1
            fi
            echo "✓ 刪除：$redo_file"
        done
    done
elif [ "$DO_REDO" = true ]; then
    REDO_SIDECAR_COUNT=0

    echo ""
    echo "開始重新修圖：清除 Camera Raw 設定與輸出成品..."

    while IFS= read -r -d '' sidecar_file; do
        if ! rm -f "$sidecar_file"; then
            echo "✗ 無法刪除：$sidecar_file"
            exit 1
        fi
        echo "✓ 刪除：$(basename "$sidecar_file")"
        REDO_SIDECAR_COUNT=$((REDO_SIDECAR_COUNT + 1))
    done < <(find "$RAW_DIR" -maxdepth 1 -type f \( -iname "*.xmp" -o -iname "*.acr" \) -print0)
    echo "共刪除 ${REDO_SIDECAR_COUNT} 個 .xmp／.acr 檔案"

    for redo_output_dir in "$TARGET_DIR/PSD" "$TARGET_DIR/IG" "$TARGET_DIR/FB"; do
        if [ ! -e "$redo_output_dir" ]; then
            echo "⊘ 目錄不存在，略過：$redo_output_dir"
            continue
        fi
        if ! rm -rf "$redo_output_dir"; then
            echo "✗ 無法刪除目錄：$redo_output_dir"
            exit 1
        fi
        echo "✓ 刪除目錄：$redo_output_dir"
    done
fi

# 儲存 RAW 檔案
RAW_FILES_FOUND=()
FILES_TO_OPEN=()

if [ "$DO_OPEN_PSD" = true ]; then
    collect_psd_files || exit 1

    if [ ${#PSD_FILES_FOUND[@]} -eq 0 ]; then
        echo "沒有找到 .psd 檔案"
        exit 0
    fi

    echo ""
    if ! make_available_offline "${PSD_FILES_FOUND[@]}"; then
        exit 1
    fi

    echo ""
    echo "正在用 $PHOTOSHOP_APP_DISPLAY 開啟 PSD 檔案..."
    if ! open_psd_files_in_photoshop "${PSD_FILES_FOUND[@]}"; then
        echo "✗ 無法開啟 PSD 檔案"
        exit 1
    fi

    echo "✓ 已送出 PSD 開啟指令"
    exit 0
fi

# 根據 PSD 目錄內現有的 PSD 重新產生 IG、FB，不讀 RAW、不重建 PSD
if [ "$OUTPUT_FROM_PSD" = true ]; then
    collect_psd_files || exit 1

    if [ ${#PSD_FILES_FOUND[@]} -eq 0 ]; then
        if [ -n "$DATE_PREFIX" ]; then
            echo "沒有找到檔名以 ${DATE_PREFIX} 開頭的 .psd 檔案"
        else
            echo "沒有找到 .psd 檔案"
        fi
        exit 0
    fi

    echo ""
    echo "共找到 ${#PSD_FILES_FOUND[@]} 個 PSD 檔案"

    echo ""
    if ! make_available_offline "${PSD_FILES_FOUND[@]}"; then
        exit 1
    fi

    OUTPUT_SOURCE_FILES=("${PSD_FILES_FOUND[@]}")
    OUTPUT_SOURCE_LABEL="PSD"
    JOB_PSD_FILES=("${PSD_FILES_FOUND[@]}")
    JOB_RAW_FILES=()
    for psd_file in "${PSD_FILES_FOUND[@]}"; do
        JOB_RAW_FILES+=("")
    done

    echo ""
    prepare_output_dirs || exit 1
    cleanup_orphan_outputs || exit 1
    run_photoshop_outputs
    echo "完成！"
    exit 0
fi

if [ "$FILE_SPECIFIED" = true ]; then
    for raw_file_name in "${RAW_FILE_NAMES[@]}"; do
        RAW_FILES_FOUND+=("$RAW_DIR/$raw_file_name")
        echo "指定 RAW 檔案：$raw_file_name"
    done
else
    # 搜尋 .ARW 檔案
    while IFS= read -r -d '' arw_file; do
        RAW_FILES_FOUND+=("$arw_file")
        echo "找到 RAW 檔案：$(basename "$arw_file")"
    done < <(find "$RAW_DIR" -maxdepth 1 -type f -iname "${DATE_PREFIX}*.arw" -print0)

    # 搜尋 .RAW 檔案
    while IFS= read -r -d '' raw_file; do
        RAW_FILES_FOUND+=("$raw_file")
        echo "找到 RAW 檔案：$(basename "$raw_file")"
    done < <(find "$RAW_DIR" -maxdepth 1 -type f -iname "${DATE_PREFIX}*.raw" -print0)
fi

# 檢查是否有找到檔案
if [ ${#RAW_FILES_FOUND[@]} -eq 0 ]; then
    if [ -n "$DATE_PREFIX" ]; then
        echo "沒有找到檔名以 ${DATE_PREFIX} 開頭的 .ARW 或 .RAW 檔案"
    else
        echo "沒有找到 .ARW 或 .RAW 檔案"
    fi
    exit 0
fi

echo ""
if [ -n "$DATE_PREFIX" ]; then
    echo "指定日期：${DATE_PREFIX}（僅處理此前綴的檔案）"
fi
echo "共找到 ${#RAW_FILES_FOUND[@]} 個 RAW 檔案"

# Camera Raw 也會讀取 RAW 旁的 .xmp、.acr，一併確保在本機
OFFLINE_FILES=()
for offline_raw_file in "${RAW_FILES_FOUND[@]}"; do
    OFFLINE_FILES+=("$offline_raw_file")
    for offline_sidecar_ext in xmp acr; do
        if [ -f "${offline_raw_file%.*}.${offline_sidecar_ext}" ]; then
            OFFLINE_FILES+=("${offline_raw_file%.*}.${offline_sidecar_ext}")
        fi
    done
done
echo ""
if ! make_available_offline "${OFFLINE_FILES[@]}"; then
    exit 1
fi

if [ "$DO_LOAD_RAW" = true ]; then
    FILES_TO_OPEN=("${RAW_FILES_FOUND[@]}")

    echo ""
    echo "正在用 $PHOTOSHOP_APP_DISPLAY 載入 RAW 檔案..."
    if ! open_raw_files_in_photoshop "${FILES_TO_OPEN[@]}"; then
        echo "✗ 無法開啟 RAW 檔案"
        exit 1
    fi

    echo "✓ 已送出 RAW 開啟指令"
    if ! wait_for_camera_raw_window; then
        exit 1
    fi

    echo "載入完成。請在 Camera Raw / Photoshop 內繼續操作。"
    exit 0
fi

if [ "$DO_PRE" = true ]; then
    SKIPPED_PRE_RAW_COUNT=0

    echo ""
    echo "開始套用 Camera Raw 前置設定..."
    echo "此步驟會跳過同時已有 .xmp 與 .acr 的 RAW；其餘檔案會先寫入描述檔 Adobe顏色、光學與 4:5 置中裁切框等前置設定（不含雜訊明度/顏色）；RAW 載入後全選、勾選「去除雜色」並等待，先按「完成」關閉 Camera Raw，再寫入雜訊 20 到 .xmp，最後重新載入 RAW。"

    for file in "${RAW_FILES_FOUND[@]}"; do
        if raw_has_completed_sidecars "$file"; then
            echo "⊘ 跳過前置（已有 .xmp 與 .acr）：$(basename "$file")"
            SKIPPED_PRE_RAW_COUNT=$((SKIPPED_PRE_RAW_COUNT + 1))
            continue
        fi

        if apply_camera_raw_preflight "$file"; then
            FILES_TO_OPEN+=("$file")
        fi
    done

    if [ ${#FILES_TO_OPEN[@]} -eq 0 ]; then
        if [ "$SKIPPED_PRE_RAW_COUNT" -gt 0 ]; then
            echo "沒有需要前置處理的 RAW 檔案（已跳過 ${SKIPPED_PRE_RAW_COUNT} 個同時已有 .xmp 與 .acr 的檔案）"
            exit 0
        fi

        echo "沒有任何 RAW 檔案成功套用 Camera Raw 手動前置設定"
        exit 1
    fi

    echo ""
    echo "共套用 ${#FILES_TO_OPEN[@]} 個 RAW 檔案"
    if [ "$SKIPPED_PRE_RAW_COUNT" -gt 0 ]; then
        echo "已跳過 ${SKIPPED_PRE_RAW_COUNT} 個同時已有 .xmp 與 .acr 的 RAW 檔案"
    fi

    DENOISE_TARGET_FILES=("${FILES_TO_OPEN[@]}")
    while [ ${#FILES_TO_OPEN[@]} -gt 0 ]; do
        batch_count=${#FILES_TO_OPEN[@]}
        echo "正在用 $PHOTOSHOP_APP_DISPLAY 開啟 RAW 檔案..."
        if ! open_raw_files_in_photoshop "${FILES_TO_OPEN[@]}"; then
            echo "✗ 無法開啟 RAW 檔案"
            exit 1
        fi

        echo "✓ 已送出 RAW 開啟指令"
        if ! wait_for_camera_raw_window; then
            exit 1
        fi
        if ! select_all_camera_raw_files "$batch_count"; then
            exit 1
        fi
        sleep 1
        enable_camera_raw_denoise "$batch_count"
        if ! close_camera_raw_with_done; then
            echo "✗ 按「完成」關閉 Camera Raw 失敗"
            exit 1
        fi

        INCOMPLETE_DENOISE_FILES=()
        for file in "${FILES_TO_OPEN[@]}"; do
            if [ ! -f "${file%.*}.acr" ]; then
                INCOMPLETE_DENOISE_FILES+=("$file")
            fi
        done
        if [ ${#INCOMPLETE_DENOISE_FILES[@]} -eq 0 ]; then
            break
        fi
        if [ ${#INCOMPLETE_DENOISE_FILES[@]} -eq "$batch_count" ]; then
            echo "✗ 本輪沒有任何 RAW 產生去除雜色結果，程序停止"
            exit 1
        fi

        echo "本輪完成 $((batch_count - ${#INCOMPLETE_DENOISE_FILES[@]})) 張；自動繼續處理剩餘 ${#INCOMPLETE_DENOISE_FILES[@]} 張"
        FILES_TO_OPEN=("${INCOMPLETE_DENOISE_FILES[@]}")
    done
    FILES_TO_OPEN=("${DENOISE_TARGET_FILES[@]}")
    DENOISE_BATCH_CONFIRMED=1
    if ! apply_camera_raw_manual_noise_after_denoise; then
        exit 1
    fi
    if ! reload_raw_files_in_photoshop; then
        echo "✗ 重新載入 RAW 失敗"
        exit 1
    fi
    report_denoise_unconfirmed_files
    if ! write_current_photo_edit_dir; then
        exit 1
    fi

    if [ "${DENOISE_BATCH_CONFIRMED:-0}" -eq 1 ]; then
        echo "前置作業完成（已按「完成」並重新載入 RAW；.xmp 雜訊 20 應已反映）。請在 Camera Raw 內繼續人工修圖。"
    else
        echo "前置作業完成（已重新載入 RAW）。請確認上方所列檔案是否已完成「去除雜色」，並在 Camera Raw 內繼續人工修圖。"
    fi
    exit 0
fi

# 後置輸出只處理已完成人工 Camera Raw 操作並有 sidecar 的檔案
for file in "${RAW_FILES_FOUND[@]}"; do
    base_name="${file%.*}"
    acr_file="${base_name}.acr"
    xmp_file="${base_name}.xmp"

    if [ -f "$acr_file" ] && [ -f "$xmp_file" ]; then
        FILES_TO_OPEN+=("$file")
        echo "找到符合後置輸出條件的檔案：$(basename "$file")"
    else
        echo "⊘ 跳過後置輸出（缺少 .acr 或 .xmp）：$(basename "$file")"
    fi
done

if [ ${#FILES_TO_OPEN[@]} -eq 0 ]; then
    echo "沒有找到符合後置輸出條件的檔案（同時存在 .acr 與 .xmp 的 .ARW 或 .RAW 檔）"
    exit 0
fi

echo ""
echo "共找到 ${#FILES_TO_OPEN[@]} 個符合後置輸出條件的檔案"

# 定義模板檔案路徑
TEMPLATE_FILE="/Users/robbie/Dropbox/__攝影/__IG 底版.psd"

# 檢查模板檔案是否存在
if [ ! -f "$TEMPLATE_FILE" ]; then
    echo "錯誤：找不到模板檔案「__IG 底版.psd」"
    echo "路徑：$TEMPLATE_FILE"
    exit 1
fi

echo "找到模板檔案：__IG 底版.psd"
if ! make_available_offline "$TEMPLATE_FILE"; then
    exit 1
fi

OUTPUT_SOURCE_FILES=("${RAW_FILES_FOUND[@]}")
OUTPUT_SOURCE_LABEL="RAW"

prepare_output_dirs || exit 1
cleanup_orphan_outputs || exit 1

echo ""
echo "開始準備 PSD 中介檔..."

# 儲存 RAW 檔案和對應的 PSD 檔案配對
JOB_PSD_FILES=()
JOB_RAW_FILES=()

# 對每個找到的檔案，複製模板並重新命名
for file in "${FILES_TO_OPEN[@]}"; do
    base_name=$(basename "$file")
    file_name="${base_name%.*}"
    new_psd_file="$PSD_DIR/${file_name}.psd"

    psd_already_exists=false
    if [ -f "$new_psd_file" ]; then
        psd_already_exists=true
    fi

    if cp -f "$TEMPLATE_FILE" "$new_psd_file"; then
        if [ "$psd_already_exists" = true ]; then
            echo "✓ 已存在，已覆蓋：${file_name}.psd"
        else
            echo "✓ 已複製：${file_name}.psd"
        fi
        JOB_PSD_FILES+=("$new_psd_file")
        JOB_RAW_FILES+=("$file")
    else
        if [ "$psd_already_exists" = true ]; then
            echo "✗ 已存在但覆蓋失敗：${file_name}.psd"
        else
            echo "✗ 複製失敗：${file_name}.psd"
        fi
    fi
done

echo ""
echo "共準備了 ${#JOB_PSD_FILES[@]} 個 PSD 檔案"

if [ ${#JOB_PSD_FILES[@]} -gt 0 ]; then
    run_photoshop_outputs
fi

echo "完成！"
