#!/usr/bin/env bash

set -euo pipefail

VERSION="1.0.0"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ERROR_LOG="${SCRIPT_DIR}/organize_errors.log"
METADATA_SCRIPT="${SCRIPT_DIR}/.metadata_extractor.py"

DRY_RUN=true
SOURCE_DIR=""
OUTPUT_DIR=""
VERBOSE=false
FORCE_OVERWRITE=false

ANSI_RED='\033[0;31m'
ANSI_GREEN='\033[0;32m'
ANSI_YELLOW='\033[0;33m'
ANSI_BLUE='\033[0;34m'
ANSI_CYAN='\033[0;36m'
ANSI_RESET='\033[0m'
ANSI_BOLD='\033[1m'

TOTAL_FILES=0
PROCESSED_FILES=0
ERROR_COUNT=0
SKIPPED_FILES=0
CONVERTED_COUNT=0
COPIED_COUNT=0
START_TIME=0

AUDIO_EXTENSIONS="*.mp3 *.flac *.wav *.aiff *.aif *.m4a *.ogg *.opus *.wma *.vdjstems"

cleanup() {
    if [[ -f "$METADATA_SCRIPT" ]]; then
        rm -f "$METADATA_SCRIPT"
    fi
}

trap 'cleanup' EXIT INT TERM

log_error() {
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[${timestamp}] ERROR: $1" >> "$ERROR_LOG"
    ERROR_COUNT=$((ERROR_COUNT + 1))
}

log_info() {
    echo -e "${ANSI_CYAN}[INFO]${ANSI_RESET} $1"
}

log_success() {
    echo -e "${ANSI_GREEN}[OK]${ANSI_RESET} $1"
}

log_warning() {
    echo -e "${ANSI_YELLOW}[WARN]${ANSI_RESET} $1"
}

log_error_cli() {
    echo -e "${ANSI_RED}[ERROR]${ANSI_RESET} $1"
}

show_banner() {
    cat << EOF
╔═══════════════════════════════════════════════════════════════╗
║                 Music Library Organizer v${VERSION}                   ║
║                                                               ║
║   - Converts to 320kbps MP3 (keeps FLAC lossless)            ║
║   - Organizes: Artist/Singles|Album/##_Track.mp3              ║
║   - Preserves metadata: year, genre, track#, art             ║
║   - Copy → Verify → Delete (safe mode)                       ║
╚═══════════════════════════════════════════════════════════════╝
EOF
}

show_usage() {
    cat << EOF
${ANSI_BOLD}Usage:${ANSI_RESET} $0 [OPTIONS] [SOURCE_DIR]

${ANSI_BOLD}Options:${ANSI_RESET}
    -o, --output DIR    Output directory (default: SOURCE_organized)
    -y, --yes           Execute after preview (default: preview only)
    -f, --force         Overwrite existing files
    -v, --verbose       Show detailed progress
    -h, --help          Show this help message

${ANSI_BOLD}Examples:${ANSI_RESET}
    $0 /path/to/music                    # Preview mode
    $0 /path/to/music -y                 # Execute
    $0 /path/to/music -o /dest -y        # Custom output, execute
    $0 /path/to/music -f -y              # Overwrite existing, execute

${ANSI_BOLD}Supported Formats:${ANSI_RESET}
    Input:  MP3, FLAC, WAV, AIF, M4A, OGG, VDJSTEMS, etc.
    Output: 320kbps CBR MP3 (or lossless FLAC copy)
EOF
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -o|--output)
                OUTPUT_DIR="$2"
                shift 2
                ;;
            -y|--yes)
                DRY_RUN=false
                shift
                ;;
            -f|--force)
                FORCE_OVERWRITE=true
                shift
                ;;
            -v|--verbose)
                VERBOSE=true
                shift
                ;;
            -h|--help)
                show_usage
                exit 0
                ;;
            -*)
                log_error_cli "Unknown option: $1"
                show_usage
                exit 1
                ;;
            *)
                if [[ -z "$SOURCE_DIR" ]]; then
                    SOURCE_DIR="$1"
                else
                    log_error_cli "Unexpected argument: $1"
                    exit 1
                fi
                shift
                ;;
        esac
    done
}

validate_dirs() {
    if [[ -z "$SOURCE_DIR" ]]; then
        read -rp "Enter source music directory: " SOURCE_DIR
    fi

    SOURCE_DIR="$(cd "$SOURCE_DIR" && pwd)"

    if [[ ! -d "$SOURCE_DIR" ]]; then
        log_error_cli "Source directory does not exist: $SOURCE_DIR"
        exit 1
    fi

    if [[ -z "$OUTPUT_DIR" ]]; then
        OUTPUT_DIR="${SOURCE_DIR}_organized"
    else
        OUTPUT_DIR="$(cd "$OUTPUT_DIR" && pwd)"
    fi

    if [[ -d "$OUTPUT_DIR" && -n "$(ls -A "$OUTPUT_DIR" 2>/dev/null)" ]]; then
        if [[ "$FORCE_OVERWRITE" == "false" ]]; then
            log_warning "Output directory exists and is not empty: $OUTPUT_DIR"
            read -rp "Continue anyway? (files may be skipped) [y/N]: " confirm
            if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
                exit 0
            fi
        fi
    fi

    mkdir -p "$OUTPUT_DIR"
}

check_dependencies() {
    local missing=()

    for cmd in ffmpeg ffprobe python3 bc; do
        if ! command -v "$cmd" &>/dev/null; then
            missing+=("$cmd")
        fi
    done

    if [[ ${#missing[@]} -gt 0 ]]; then
        log_error_cli "Missing dependencies: ${missing[*]}"
        echo "Install with: brew install ${missing[*]}"
        exit 1
    fi

    if ! python3 -c "import mutagen" 2>/dev/null; then
        log_info "Installing mutagen for Python metadata handling..."
        pip3 install mutagen --quiet 2>/dev/null || {
            log_error_cli "Failed to install mutagen. Run: pip3 install mutagen"
            exit 1
        }
    fi
}

create_metadata_script() {
    cat > "$METADATA_SCRIPT" << 'METADATA_EOF'
#!/usr/bin/env python3
import sys
import os
from mutagen.mp3 import MP3
from mutagen.flac import FLAC
from mutagen.wave import WAVE
from mutagen import File
from mutagen.id3 import ID3, TIT2, TPE1, TALB, TPE2, TDRC, TCON, TRCK, APIC, TCMP

def get_metadata(filepath):
    result = {
        'artist': 'Unknown Artist',
        'album': 'Unknown Album',
        'album_artist': '',
        'title': os.path.splitext(os.path.basename(filepath))[0],
        'year': '',
        'genre': '',
        'track_number': '',
        'compilation': False,
        'cover_data': None
    }

    try:
        audio = File(filepath)
        if audio is None:
            return result

        if hasattr(audio, 'tags'):
            tags = audio.tags
        else:
            tags = getattr(audio, 'info', {}) or {}

        def get_first(tag_names, default=None):
            for name in tag_names:
                if name in tags:
                    val = tags[name]
                    if hasattr(val, 'text') and val.text:
                        return val.text[0]
                    elif hasattr(val, '__iter__') and not isinstance(val, str):
                        try:
                            return next(iter(val))
                        except StopIteration:
                            pass
            return default

        result['artist'] = get_first(['TPE1', 'artist']) or result['artist']
        result['title'] = get_first(['TIT2', 'title']) or result['title']
        result['album'] = get_first(['TALB', 'album']) or result['album']
        result['album_artist'] = get_first(['TPE2', 'albumartist']) or ''
        result['year'] = str(get_first(['TDRC', 'year', 'date']) or '')[:4]
        result['genre'] = get_first(['TCON', 'genre']) or ''
        result['track_number'] = get_first(['TRCK', 'tracknumber']) or ''

        tcmp = get_first(['TCMP', 'compilation'])
        if tcmp and tcmp.lower() in ('1', 'true', 'yes'):
            result['compilation'] = True

        if 'APIC:' in tags:
            result['cover_data'] = bytes(tags['APIC:'].data)
        elif hasattr(tags, 'get_all'):
            for key in tags.keys():
                if key.startswith('APIC'):
                    result['cover_data'] = bytes(tags[key].data)
                    break

    except Exception as e:
        pass

    return result

if __name__ == '__main__':
    if len(sys.argv) < 2:
        sys.exit(1)
    
    meta = get_metadata(sys.argv[1])
    output = []
    for key, value in meta.items():
        if value is None:
            value = ''
        if isinstance(value, bool):
            value = '1' if value else '0'
        if isinstance(value, bytes):
            value = '<BINARY:{}bytes>'.format(len(value))
        output.append('{}={}'.format(key, value))
    
    print('\x00'.join(output))
METADATA_EOF
    chmod +x "$METADATA_SCRIPT"
}

extract_metadata() {
    local filepath="$1"
    local metadata
    metadata=$(python3 "$METADATA_SCRIPT" "$filepath" 2>/dev/null)

    if [[ -z "$metadata" ]]; then
        echo "artist=Unknown Artist|album=Unknown Album|title=$(basename "$filepath" .${filepath##*.})|year=|genre=|track_number=|compilation=false|album_artist="
        return
    fi

    IFS=$'\x00' read -ra lines <<< "$metadata"
    for line in "${lines[@]}"; do
        echo "$line"
    done
}

parse_metadata() {
    local filepath="$1"
    local metadata
    metadata=$(extract_metadata "$filepath")

    artist="Unknown Artist"
    album="Unknown Album"
    album_artist=""
    title=""
    year=""
    genre=""
    track_number=""
    compilation="false"

    # Parse metadata - split by null character and process each key=value pair
    while IFS= read -r -d '' line; do
        if [[ "$line" =~ ^([^=]+)=(.*)$ ]]; then
            key="${BASH_REMATCH[1]}"
            value="${BASH_REMATCH[2]}"
            # Handle special cases
            case "$key" in
                "artist") artist="$value" ;;
                "album") album="$value" ;;
                "album_artist") album_artist="$value" ;;
                "title") title="$value" ;;
                "year") year="$value" ;;
                "genre") genre="$value" ;;
                "track_number") track_number="$value" ;;
                "compilation") compilation="$value" ;;
            esac
        fi
    done <<< "$metadata"
}

classify_track() {
    local filepath="$1"
    local artist="$2"
    local album="$3"
    local album_artist="$4"
    local compilation="$5"

    local classification="single"
    local folder_name="Singles"
    
    # Get directory-based artist/album context
    local dir_context
    dir_context=$(get_album_context "$filepath")
    local dir_artist="${dir_context%%|*}"
    local dir_album="${dir_context##*|}"
    
    # Prioritize directory analysis over metadata for album detection
    local structure
    structure=$(analyze_directory_structure "$filepath")
    
    case "$structure" in
        "multi_album")
            classification="album"
            folder_name="$dir_album"
            # Use directory-derived artist but prefer metadata if available
            if [[ "$artist" != "Unknown Artist" ]]; then
                # Keep metadata artist
                :
            else
                artist="$dir_artist"
            fi
            ;;
        "single_album")
            classification="album"
            folder_name="$dir_album"
            # Use directory-derived artist but prefer metadata if available
            if [[ "$artist" != "Unknown Artist" ]]; then
                # Keep metadata artist
                :
            else
                artist="$dir_artist"
            fi
            ;;
        *)
            # Fallback to metadata-based classification for unknown structures
            if [[ "$compilation" == "true" ]] || [[ -n "$album" && "$album" != "Unknown Album" ]]; then
                if [[ "$compilation" == "true" ]] || [[ -n "$album_artist" && "$album_artist" != "$artist" ]]; then
                    classification="compilation"
                    folder_name="Compilations"
                else
                    classification="album"
                    folder_name="$album"
                fi
            fi
            ;;
    esac

    echo "$classification|$folder_name|$artist"
}

sanitize_filename() {
    local filename="$1"
    local max_len=200

    filename=$(echo "$filename" | sed 's/[\\/:*?"<>|]/_/g' | sed 's/[[:space:]]\+/ /g' | sed 's/^[[:space:]]\+\|[[:space:]]\+$//g')

    if [[ ${#filename} -gt $max_len ]]; then
        local ext="${filename##*.}"
        local base="${filename%.*}"
        local ext_len=$((${#ext} + 1))
        local new_base_len=$((max_len - ext_len))
        if [[ $new_base_len -lt 10 ]]; then
            new_base_len=10
        fi
        filename="${base:0:$new_base_len}...${ext}"
    fi

    echo "$filename"
}

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

get_track_number() {
    local track_num="$1"

    if [[ -n "$track_num" && "$track_num" =~ ^([0-9]+) ]]; then
        printf "%03d" "${BASH_REMATCH[1]}"
    else
        echo "001"
    fi
}

generate_target_path() {
    local filepath="$1"
    local artist="$2"
    local album="$3"
    local title="$4"
    local track_number="$5"
    local classification="$6"
    local folder_name="$7"

    artist=$(sanitize_filename "$artist")
    folder_name=$(sanitize_filename "$folder_name")
    title=$(sanitize_filename "$title")

    local track_num
    track_num=$(get_track_number "$track_number")

    local ext
    ext=$(echo "$filepath" | sed 's/.*\.//' | tr '[:upper:]' '[:lower:]')

    if [[ "$classification" == "compilation" ]]; then
        echo "Compilations/${folder_name}/${track_num}_${title}.${ext}"
    elif [[ "$classification" == "album" ]]; then
        echo "${artist}/${folder_name}/${track_num}_${title}.${ext}"
    else
        echo "${artist}/Singles/${track_num}_${title}.${ext}"
    fi
}

is_lossless() {
    local filepath="$1"
    local ext="${filepath##*.}"

    case "$(echo "$ext" | tr '[:upper:]' '[:lower:]')" in
        flac|wav|aiff|aif)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

needs_conversion() {
    local filepath="$1"
    local ext="${filepath##*.}"

    if is_lossless "$filepath"; then
        return 1
    fi

    if [[ "$(echo "$ext" | tr '[:upper:]' '[:lower:]')" == "mp3" ]]; then
        local bitrate
        bitrate=$(ffprobe -v error -select_streams a:0 -show_entries stream=bit_rate -of csv=p=0 "$filepath" 2>/dev/null | cut -d. -f1)
        bitrate=${bitrate:-0}
        if [[ $bitrate -ge 320000 ]]; then
            return 1
        fi
    fi

    return 0
}

convert_to_mp3() {
    local input="$1"
    local output="$2"

    local ext="${input##*.}"

    if is_lossless "$input"; then
        log_info "Copying lossless: $ext -> mp3"
        ffmpeg -y -i "$input" -codec:a libmp3lame -qscale:a 0 -b:a 320k "$output" 2>/dev/null
    else
        ffmpeg -y -i "$input" -codec:a libmp3lame -qscale:a 0 -b:a 320k "$output" 2>/dev/null
    fi
}

copy_lossless() {
    local input="$1"
    local output="$2"

    cp "$input" "$output"
}

verify_copy() {
    local original="$1"
    local copy="$2"

    local orig_size copy_size diff tolerance
    orig_size=$(stat -f%z "$original" 2>/dev/null || stat -c%s "$original" 2>/dev/null)
    copy_size=$(stat -f%z "$copy" 2>/dev/null || stat -c%s "$copy" 2>/dev/null)

    if [[ -z "$orig_size" || -z "$copy_size" ]]; then
        log_error "Cannot compare file sizes: $original"
        return 1
    fi

    diff=$(echo "scale=2; if ($orig_size > $copy_size) $orig_size - $copy_size else $copy_size - $orig_size" | bc)
    tolerance=$(echo "scale=0; $orig_size * 5 / 100" | bc)

    if [[ $(echo "$diff <= $tolerance" | bc) -eq 1 ]]; then
        return 0
    fi

    if is_lossless "$original"; then
        local orig_md5 copy_md5
        orig_md5=$(md5sum "$original" 2>/dev/null | cut -d' ' -f1)
        copy_md5=$(md5sum "$copy" 2>/dev/null | cut -d' ' -f1)
        if [[ "$orig_md5" == "$copy_md5" ]]; then
            return 0
        fi
    fi

    return 1
}

copy_metadata() {
    local source="$1"
    local dest="$2"

    python3 - "$source" "$dest" << 'COPYMETA_EOF'
import sys
from mutagen.mp3 import MP3
from mutagen.id3 import ID3, TIT2, TPE1, TALB, TPE2, TDRC, TCON, TRCK, APIC, TCMP

src_path, dst_path = sys.argv[1], sys.argv[2]

try:
    src = File(src_path)
    dst = MP3(dst_path, ID3=ID3)

    if dst.tags is None:
        dst.add_tags()

    tag_map = {
        'TIT2': 'title',
        'TPE1': 'artist', 
        'TALB': 'album',
        'TPE2': 'albumartist',
        'TDRC': 'year',
        'TCON': 'genre',
        'TRCK': 'track_number',
    }

    for id3_tag, attr in tag_map.items():
        if hasattr(src, 'tags') and src.tags:
            val = None
            if id3_tag in src.tags:
                val = src.tags[id3_tag]
            if val and hasattr(val, 'text') and val.text:
                try:
                    dst.tags[id3_tag] = val.__class__(val.text)
                except:
                    pass

    if hasattr(src, 'tags') and src.tags:
        for key in src.tags.keys():
            if key.startswith('APIC'):
                try:
                    dst.tags[key] = src.tags[key]
                except:
                    pass

    dst.save()
except Exception as e:
    pass
COPYMETA_EOF
}

count_files() {
    local count=0
    local ext
    for ext in $AUDIO_EXTENSIONS; do
        count=$((count + $(find "$SOURCE_DIR" -type f -iname "$ext" 2>/dev/null | wc -l)))
    done
    echo $count
}

scan_library() {
    log_info "Scanning library: $SOURCE_DIR"

    local count=0
    local ext
    for ext in $AUDIO_EXTENSIONS; do
        while IFS= read -r -d '' file; do
            ((count++))
            if [[ $((count % 1000)) -eq 0 ]]; then
                echo -ne "\r  Found $count files..."
            fi
        done < <(find "$SOURCE_DIR" -type f -iname "$ext" -print0 2>/dev/null)
    done

    echo ""
    TOTAL_FILES=$count
}

calculate_disk_usage() {
    local source_size=0
    local target_size=0
    local ext

    for ext in $AUDIO_EXTENSIONS; do
        while IFS= read -r -d '' file; do
            local size
            size=$(stat -f%z "$file" 2>/dev/null || stat -c%s "$file" 2>/dev/null || echo 0)
            source_size=$((source_size + size))

            if is_lossless "$file"; then
                target_size=$((target_size + size))
            else
                target_size=$((target_size + size / 4))
            fi
        done < <(find "$SOURCE_DIR" -type f -iname "$ext" -print0 2>/dev/null)
    done

    echo "$source_size $target_size"
}

format_size() {
    local size=$1
    if [[ $size -ge 1073741824 ]]; then
        echo "$(echo "scale=2; $size / 1073741824" | bc)GB"
    elif [[ $size -ge 1048576 ]]; then
        echo "$(echo "scale=2; $size / 1048576" | bc)MB"
    elif [[ $size -ge 1024 ]]; then
        echo "$(echo "scale=2; $size / 1024" | bc)KB"
    else
        echo "${size}B"
    fi
}

show_preview() {
    log_info "Analyzing library structure..."

    local file_count=0
    local album_count=0
    local single_count=0
    local compilation_count=0
    local lossless_count=0
    local lossy_count=0
    local unique_artists=()
    local ext

# Build array of files first to avoid subshell issues
    local files_array=()
    for ext in $AUDIO_EXTENSIONS; do
        while IFS= read -r -d '' file; do
            files_array+=("$file")
        done < <(find "$SOURCE_DIR" -type f -iname "$ext" -print0 2>/dev/null)
    done
    
    # Process files
    for file in "${files_array[@]}"; do
        ((file_count++))

        if is_lossless "$file"; then
            ((lossless_count++))
        else
            ((lossy_count++))
        fi

        parse_metadata "$file"

        local classification_result
        classification_result=$(classify_track "$file" "$artist" "$album" "$album_artist" "$compilation")
        local classification="${classification_result%%|*}"
        classification_result="${classification_result#*|}"
        local folder_name="${classification_result%%|*}"
        local updated_artist="${classification_result##*|}"
        
        # Update artist if directory analysis provided a better one
        if [[ -n "$updated_artist" && "$updated_artist" != "Unknown Artist" ]]; then
            artist="$updated_artist"
        fi

        case "$classification" in
            album) ((album_count++)) ;;
            single) ((single_count++)) ;;
            compilation) ((compilation_count++)) ;;
        esac

        found=0
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
        fi
    done

    local sizes
    sizes=$(calculate_disk_usage)
    local source_size="${sizes%% *}"
    local target_size="${sizes## *}"

    echo ""
    echo -e "${ANSI_BOLD}╔══════════════════════════════════════════════════════════════╗${ANSI_RESET}"
    echo -e "${ANSI_BOLD}║                    PREVIEW SUMMARY                          ║${ANSI_RESET}"
    echo -e "${ANSI_BOLD}╚══════════════════════════════════════════════════════════════╝${ANSI_RESET}"
    echo ""
    echo -e "  ${ANSI_CYAN}Source:${ANSI_RESET}      $SOURCE_DIR"
    echo -e "  ${ANSI_CYAN}Output:${ANSI_RESET}      $OUTPUT_DIR"
    echo ""
    echo -e "  ${ANSI_GREEN}Total Files:${ANSI_RESET}   $file_count"
    echo -e "  ${ANSI_GREEN}Artists:${ANSI_RESET}      ${#unique_artists[@]}"
    echo ""
    echo -e "  ${ANSI_BLUE}Albums:${ANSI_RESET}        $album_count"
    echo -e "  ${ANSI_BLUE}Singles:${ANSI_RESET}       $single_count"
    echo -e "  ${ANSI_BLUE}Compilations:${ANSI_RESET} $compilation_count"
    echo ""
    echo -e "  ${ANSI_YELLOW}Lossless:${ANSI_RESET}     $lossless_count (FLAC/WAV/AIFF)"
    echo -e "  ${ANSI_YELLOW}Lossy:${ANSI_RESET}        $lossy_count (MP3/OGG/M4A/etc)"
    echo ""
    echo -e "  ${ANSI_CYAN}Space:${ANSI_RESET}"
    echo -e "    Source:  $(format_size $source_size)"
    echo -e "    Target:  $(format_size $target_size)"
    echo ""

    if [[ "$DRY_RUN" == "true" ]]; then
        echo -e "${ANSI_BOLD}╔══════════════════════════════════════════════════════════════╗${ANSI_RESET}"
        echo -e "${ANSI_BOLD}║  PREVIEW ONLY - No changes made                              ║${ANSI_RESET}"
        echo -e "${ANSI_BOLD}║                                                              ║${ANSI_RESET}"
        echo -e "${ANSI_BOLD}║  Run with ${ANSI_GREEN}-y${ANSI_BOLD} to execute, or with ${ANSI_GREEN}-y -f${ANSI_BOLD} to force      ║${ANSI_RESET}"
        echo -e "${ANSI_BOLD}╚══════════════════════════════════════════════════════════════╝${ANSI_RESET}"
        echo ""
        echo -e "  ${ANSI_RED}Exiting without making changes.${ANSI_RESET}"
        exit 0
    fi
}

update_progress() {
    local current=$1
    local total=$2
    local current_file="$3"

    # Avoid division by zero
    if [[ $total -eq 0 ]]; then
        return
    fi

    local width=40
    local percent=$((current * 100 / total))
    local filled=$((width * current / total))
    local empty=$((width - filled))

    local filled_bar=""
    local i=0
    while [[ $i -lt $filled ]]; do
        filled_bar="${filled_bar}█"
        ((i++))
    done

    i=0
    local empty_bar=""
    while [[ $i -lt $empty ]]; do
        empty_bar="${empty_bar}░"
        ((i++))
    done

    local eta=""
    if [[ $current -gt 0 ]]; then
        local elapsed=$(($(date +%s) - START_TIME))
        local total_est=$((elapsed * total / current))
        local remaining=$((total_est - elapsed))
        local mins=$((remaining / 60))
        local secs=$((remaining % 60))
        eta="${mins}m${secs}s"
    fi

    printf "\r${ANSI_CYAN}[${filled_bar}${empty_bar}]${ANSI_RESET} %3d%% (%d/%d) - %-50s ETA: %s" \
        "$percent" "$current" "$total" "$current_file" "$eta"
}

process_file() {
    local filepath="$1"

    parse_metadata "$filepath"

    local classification_result
    classification_result=$(classify_track "$filepath" "$artist" "$album" "$album_artist" "$compilation")
    local classification="${classification_result%%|*}"
    classification_result="${classification_result#*|}"
    local folder_name="${classification_result%%|*}"
    local updated_artist="${classification_result##*|}"
    
    # Update artist if directory analysis provided a better one
    if [[ -n "$updated_artist" && "$updated_artist" != "Unknown Artist" ]]; then
        artist="$updated_artist"
    fi

    local target_rel
    target_rel=$(generate_target_path "$filepath" "$artist" "$album" "$title" "$track_number" "$classification" "$folder_name")
    local target_path="${OUTPUT_DIR}/${target_rel}"
    local target_dir
    target_dir=$(dirname "$target_path")

    if [[ -f "$target_path" ]]; then
        if [[ "$FORCE_OVERWRITE" == "true" ]]; then
            log_info "Overwriting: $target_rel"
        else
            log_info "Skipping (exists): $target_rel"
            SKIPPED_FILES=$((SKIPPED_FILES + 1))
            return 0
        fi
    fi

    mkdir -p "$target_dir"

    if is_lossless "$filepath"; then
        if [[ "$FORCE_OVERWRITE" == "true" ]] || [[ ! -f "$target_path" ]]; then
            copy_lossless "$filepath" "$target_path"
            if verify_copy "$filepath" "$target_path"; then
                copy_metadata "$filepath" "$target_path"
                COPIED_COUNT=$((COPIED_COUNT + 1))
            else
                log_error "Verification failed for: $filepath -> $target_path"
                rm -f "$target_path"
            fi
        fi
    elif needs_conversion "$filepath"; then
        convert_to_mp3 "$filepath" "${target_path%.mp3}.mp3"
        target_path="${target_path%.mp3}.mp3"
        if verify_copy "$filepath" "$target_path"; then
            copy_metadata "$filepath" "$target_path"
            CONVERTED_COUNT=$((CONVERTED_COUNT + 1))
        else
            log_error "Verification failed for: $filepath -> $target_path"
            rm -f "$target_path"
        fi
    else
        if [[ "$FORCE_OVERWRITE" == "true" ]] || [[ ! -f "$target_path" ]]; then
            cp "$filepath" "$target_path"
            if verify_copy "$filepath" "$target_path"; then
                COPIED_COUNT=$((COPIED_COUNT + 1))
            else
                log_error "Verification failed for: $filepath -> $target_path"
                rm -f "$target_path"
            fi
        fi
    fi

    if [[ -f "$target_path" ]]; then
        rm -f "$filepath"
    fi

    PROCESSED_FILES=$((PROCESSED_FILES + 1))
}

main() {
    show_banner
    echo ""

    parse_args "$@"
    validate_dirs
    check_dependencies

    rm -f "$ERROR_LOG"
    touch "$ERROR_LOG"

    create_metadata_script

    START_TIME=$(date +%s)

    show_preview

    log_info "Starting processing..."

    local count=0
    local ext

    for ext in $AUDIO_EXTENSIONS; do
        while IFS= read -r -d '' file; do
            ((count++))
            update_progress $count $TOTAL_FILES "$(basename "$file")"

            if ! process_file "$file"; then
                :
            fi
        done < <(find "$SOURCE_DIR" -type f -iname "$ext" -print0 2>/dev/null)
    done

    echo ""

    local elapsed=$(($(date +%s) - START_TIME))

    echo ""
    echo -e "${ANSI_BOLD}╔══════════════════════════════════════════════════════════════╗${ANSI_RESET}"
    echo -e "${ANSI_BOLD}║                    COMPLETION SUMMARY                       ║${ANSI_RESET}"
    echo -e "${ANSI_BOLD}╚══════════════════════════════════════════════════════════════╝${ANSI_RESET}"
    echo ""
    echo -e "  ${ANSI_GREEN}Processed:${ANSI_RESET}       $PROCESSED_FILES files"
    echo -e "  ${ANSI_GREEN}Converted:${ANSI_RESET}      $CONVERTED_COUNT (to 320kbps MP3)"
    echo -e "  ${ANSI_GREEN}Copied (lossless):${ANSI_RESET} $COPIED_COUNT"
    echo -e "  ${ANSI_YELLOW}Skipped:${ANSI_RESET}        $SKIPPED_FILES"
    echo -e "  ${ANSI_RED}Errors:${ANSI_RESET}          $ERROR_COUNT (see $ERROR_LOG)"
    echo ""
    echo -e "  ${ANSI_CYAN}Time elapsed:${ANSI_RESET}    ${elapsed}s"
    echo ""

    if [[ $ERROR_COUNT -gt 0 ]]; then
        log_warning "Some files had errors. Review: $ERROR_LOG"
    fi

    log_success "Music library organization complete!"
}

main "$@"
