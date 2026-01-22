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

analyze_directory_structure() {
    local filepath="$1"
    local dir
    dir=$(dirname "$filepath")
    local parent_dir
    parent_dir=$(dirname "$dir")
    
    if [[ "$parent_dir" != "$SOURCE_DIR" ]] && has_audio_subdirectories "$parent_dir"; then
        echo "multi_album"
    elif has_audio_files "$dir"; then
        echo "single_album"
    else
        echo "unknown"
    fi
}

get_album_context() {
    local filepath="$1"
    local dir
    dir=$(dirname "$filepath")
    local structure
    structure=$(analyze_directory_structure "$filepath")
    
    case "$structure" in
        "multi_album")
            local parent_dir artist album
            parent_dir=$(dirname "$dir")
            album_context=$(extract_artist_album_from_folder "$parent_dir")
            artist="${album_context%%|*}"
            album=$(basename "$dir")
            ;;
        "single_album")
            album_context=$(extract_artist_album_from_folder "$dir")
            artist="${album_context%%|*}"
            album="${album_context##*|}"
            ;;
        *)
            artist="Unknown Artist"
            album="Unknown Album"
            ;;
    esac
    
    echo "$artist|$album"
}

# Test unique artist counting like in the main script
unique_artists=()
file_count=0

# Get first few files to test
find "$SOURCE_DIR" -type f -iname "*.flac" -print0 | while IFS= read -r -d '' file; do
    ((file_count++))
    if [[ $file_count -gt 5 ]]; then
        break
    fi
    
    echo "File $file_count: $file"
    context=$(get_album_context "$file")
    artist="${context%%|*}"
    echo "  Extracted artist: '$artist'"
    
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
        echo "  Added to unique artists: '$artist'"
    else
        echo "  Artist already exists: '$artist'"
    fi
    echo "  Current unique artists count: ${#unique_artists[@]}"
    echo ""
done

echo "Total unique artists found: ${#unique_artists[@]}"
printf 'Artists: %s\n' "${unique_artists[@]}"