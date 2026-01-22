#!/usr/bin/env bash

AUDIO_EXTENSIONS="*.mp3 *.flac *.wav *.aiff *.aif *.m4a *.ogg *.opus *.wma *.vdjstems"
SOURCE_DIR="/Users/johnnyclem/Desktop/Music/LPs"

has_audio_files() {
    local dir="$1"
    local ext
    for ext in $AUDIO_EXTENSIONS; do
        if find "$dir" -maxdepth 1 -type f -iname "$ext" -quit 2>/dev/null; then
            return 0
        fi
    done
    return 1
}

has_audio_subdirectories() {
    local dir="$1"
    local subdir
    while IFS= read -r -d '' subdir; do
        if has_audio_files "$subdir"; then
            return 0
        fi
    done < <(find "$dir" -mindepth 1 -maxdepth 1 -type d -print0 2>/dev/null)
    return 1
}

extract_artist_album_from_folder() {
    local folder_path="$1"
    local folder_name
    folder_name=$(basename "$folder_path")
    
    local artist="Unknown Artist"
    local album="$folder_name"
    
    if [[ "$folder_name" =~ ^(.+)[[:space:]]*-[[:space:]]*(.+)$ ]]; then
        artist="${BASH_REMATCH[1]}"
        album="${BASH_REMATCH[2]}"
    else
        artist="$folder_name"
    fi
    
    echo "$artist|$album"
}

get_album_context() {
    local filepath="$1"
    local dir
    dir=$(dirname "$filepath")
    local parent_dir
    parent_dir=$(dirname "$dir")
    
    if [[ "$parent_dir" != "$SOURCE_DIR" ]] && has_audio_subdirectories "$parent_dir"; then
        local artist album
        album_context=$(extract_artist_album_from_folder "$parent_dir")
        artist="${album_context%%|*}"
        album=$(basename "$dir")
    elif has_audio_files "$dir"; then
        album_context=$(extract_artist_album_from_folder "$dir")
        artist="${album_context%%|*}"
        album="${album_context##*|}"
    else
        artist="Unknown Artist"
        album="Unknown Album"
    fi
    
    echo "$artist|$album"
}

# Test artist extraction from a few files
echo "Testing artist extraction:"
files=(
    "/Users/johnnyclem/Desktop/Music/LPs/Bon Iver/22 (OVER S∞∞N).flac"
    "/Users/johnnyclem/Desktop/Music/LPs/Chromeo/Business Casual/Don't Turn the Lights On.flac"
    "/Users/johnnyclem/Desktop/Music/LPs/D'Angelo - Voodoo/Playa Playa.flac"
)

for file in "${files[@]}"; do
    echo "File: $file"
    context=$(get_album_context "$file")
    artist="${context%%|*}"
    album="${context##*|}"
    echo "  Artist: $artist"
    echo "  Album: $album"
    echo ""
done