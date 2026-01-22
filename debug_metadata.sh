#!/usr/bin/env bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
METADATA_SCRIPT="${SCRIPT_DIR}/.metadata_extractor.py"

# Create metadata script
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

# Test extract_metadata on a file
test_file="/Users/johnnyclem/Desktop/Music/LPs/MkGee - Dream Police/01 Mk.gee - Breakthespell (Official Audio).flac"
echo "Testing metadata extraction:"
metadata=$(python3 "$METADATA_SCRIPT" "$test_file" 2>/dev/null)
echo "Raw metadata: $metadata"
echo ""

# Test parsing
IFS=$'\x00' read -ra metadata_array <<< "$metadata"
echo "Parsed into ${#metadata_array[@]} elements:"
for i in "${!metadata_array[@]}"; do
    echo "  [$i]: ${metadata_array[i]}"
done
echo ""

# Test regex matching
for line in "${metadata_array[@]}"; do
    if [[ "$line" =~ ^([^=]+)=(.*)$ ]]; then
        key="${BASH_REMATCH[1]}"
        value="${BASH_REMATCH[2]}"
        echo "  Parsed: key='$key', value='$value'"
    else
        echo "  Failed to parse: '$line'"
    fi
done