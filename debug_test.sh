#!/usr/bin/env bash

AUDIO_EXTENSIONS="*.mp3 *.flac *.wav *.aiff *.aif *.m4a *.ogg *.opus *.wma *.vdjstems"

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

analyze_directory_structure() {
    local filepath="$1"
    local dir
    dir=$(dirname "$filepath")
    local parent_dir
    parent_dir=$(dirname "$dir")
    
    # Check if parent directory has subdirectories with audio files AND we're at least 2 levels deep from source
    if [[ "$parent_dir" != "$SOURCE_DIR" ]] && has_audio_subdirectories "$parent_dir"; then
        echo "multi_album"
    # Check if current directory has audio files but no subdirectories with audio (single album structure)
    elif has_audio_files "$dir"; then
        echo "single_album"
    else
        echo "unknown"
    fi
}

SOURCE_DIR="/Users/johnnyclem/Desktop/Music/LPs"

# Test with Chromeo
test_file="/Users/johnnyclem/Desktop/Music/LPs/Chromeo/Business Casual/Don't Turn the Lights On.flac"
echo "Testing file: $test_file"
dir=$(dirname "$test_file")
parent_dir=$(dirname "$dir")
echo "Directory: $dir"
echo "Parent dir: $parent_dir"
echo "SOURCE_DIR: $SOURCE_DIR"
echo "Parent != SOURCE_DIR: $([[ "$parent_dir" != "$SOURCE_DIR" ]] && echo "TRUE" || echo "FALSE")"
echo "Parent has audio subdirs: $(has_audio_subdirectories "$parent_dir" && echo "YES" || echo "NO")"
echo "Current has audio files: $(has_audio_files "$dir" && echo "YES" || echo "NO")"
echo "Current has audio subdirs: $(has_audio_subdirectories "$dir" && echo "YES" || echo "NO")"
echo "Structure: $(analyze_directory_structure "$test_file")"
echo ""

# Test with flat folder
test_file2="/Users/johnnyclem/Desktop/Music/LPs/Bon Iver/22 (OVER S∞∞N).flac"
echo "Testing file: $test_file2"
dir2=$(dirname "$test_file2")
parent_dir2=$(dirname "$dir2")
echo "Directory: $dir2"
echo "Parent dir: $parent_dir2"
echo "SOURCE_DIR: $SOURCE_DIR"
echo "Parent != SOURCE_DIR: $([[ "$parent_dir2" != "$SOURCE_DIR" ]] && echo "TRUE" || echo "FALSE")"
echo "Parent has audio subdirs: $(has_audio_subdirectories "$parent_dir2" && echo "YES" || echo "NO")"
echo "Current has audio files: $(has_audio_files "$dir2" && echo "YES" || echo "NO")"
echo "Current has audio subdirs: $(has_audio_subdirectories "$dir2" && echo "YES" || echo "NO")"
echo "Structure: $(analyze_directory_structure "$test_file2")"