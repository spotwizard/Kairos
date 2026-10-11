#!/bin/bash

SOURCE_DIR="/Users/robbie/Pictures/Transfer"

DATE_PREFIX=$(date +"%Y%m%d")
TARGET_DIR=""

find "$SOURCE_DIR" -type d | while read -r subdir; do
    subdir_name=$(basename "$subdir")
    
    if [[ $subdir_name =~ ^(.+)-([0-9]{8})$ ]]; then
        store_name="${BASH_REMATCH[1]}"
        date_prefix="${BASH_REMATCH[2]}_"
        
        arw_count=$(find "$subdir" -maxdepth 1 -name "*.ARW" -print | awk 'END { print NR + 0 }')
        dng_count=$(find "$subdir" -maxdepth 1 -name "*.dng" -print | awk 'END { print NR + 0 }')
        cr2_count=$(find "$subdir" -maxdepth 1 -name "*.CR2" -print | awk 'END { print NR + 0 }')
        total_files=$((arw_count + dng_count + cr2_count))
        
        if [ $total_files -eq 0 ]; then
            continue
        fi
        
        echo "轉移 RAW 檔案：$subdir 找到 $total_files 個 RAW 檔案（ARW: $arw_count, DNG: $dng_count, CR2: $cr2_count），開始轉移..."
        
        TARGET_DIR="/Users/robbie/Dropbox/__攝影/${store_name}"
        mkdir -p "$TARGET_DIR/RAW"
        mkdir -p "$TARGET_DIR/PSD"
        mkdir -p "$TARGET_DIR/IG"
        mkdir -p "$TARGET_DIR/FB"
        
        for file in "$subdir"/*.ARW; do
            if [ -f "$file" ]; then
                filename=$(basename "$file")
                if [[ $filename =~ ^[0-9]{8} ]]; then
                    new_filename="${filename%.*}"
                else
                    new_filename="${date_prefix}${filename%.*}"
                fi
                
                mv "$file" "$TARGET_DIR/RAW/$new_filename.${filename##*.}"
                echo "已搬移：$filename -> RAW/$new_filename.${filename##*.}"
            fi
        done

        for file in "$subdir"/*.dng; do
            if [ -f "$file" ]; then
                filename=$(basename "$file")
                if [[ $filename =~ ^[0-9]{8} ]]; then
                    new_filename="${filename%.*}"
                else
                    new_filename="${date_prefix}${filename%.*}"
                fi

                mv "$file" "$TARGET_DIR/RAW/$new_filename.${filename##*.}"
                echo "已搬移：$filename -> RAW/$new_filename.${filename##*.}"

            fi
        done

        for file in "$subdir"/*.CR2; do
            if [ -f "$file" ]; then
                filename=$(basename "$file")
                if [[ $filename =~ ^[0-9]{8} ]]; then
                    new_filename="${filename%.*}"
                else
                    new_filename="${date_prefix}${filename%.*}"
                fi

                mv "$file" "$TARGET_DIR/RAW/$new_filename.${filename##*.}"
                echo "已搬移：$filename -> RAW/$new_filename.${filename##*.}"

            fi
        done
    fi
done

echo "轉移 RAW 檔案完成。"
