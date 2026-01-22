#!/usr/bin/env bash

AUDIO_EXTENSIONS="*.mp3 *.flac *.wav *.aiff *.aif *.m4a *.ogg *.opus *.wma *.vdjstems"
SOURCE_DIR="/Users/johnnyclem/Desktop/Music/LPs"

# Use a temporary file to avoid subshell issues
temp_files_list=$(mktemp)

find "$SOURCE_DIR" -type f -iname "*.flac" -print0 2>/dev/null | head -n 5 | tr '\n' '\0' > "$temp_files_list"

echo "Testing with temp file approach:"
unique_artists=()
file_count=0

while IFS= read -r -d '' file; do
    ((file_count++))
    echo "File $file_count: $(basename "$file")"
    
    # Simulate artist extraction logic
    artist=$(basename "$(dirname "$(dirname "$file")")")
    if [[ "$artist" == "$(basename "$SOURCE_DIR")" ]]; then
        artist=$(basename "$(dirname "$file")")
    fi
    
    echo "  Artist: '$artist'"
    
    # Check if artist is already in unique_artists array
    local found=0
    if [[ ${#unique_artists[@]} -gt 0 ]]; then
        for ua in "${unique_artists[@]}"; do
            if [[ "$ua" == "$artist" ]]; then
                found=1
                break
            fi
        done
    fi
    if [[ $found -eq 0 ]]; then
        unique_artists+=("$artist")
        echo "  Added to unique artists"
    else
        echo "  Artist already exists"
    fi
    echo "  Current unique artists count: ${#unique_artists[@]}"
    echo ""
done < "$temp_files_list"

rm -f "$temp_files_list"

echo "Final unique artists count: ${#unique_artists[@]}"
printf 'Artists: %s\n' "${unique_artists[@]}"