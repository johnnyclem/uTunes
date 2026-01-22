# Music Library Organizer

A powerful bash script that organizes, converts, and optimizes your music library with safety-first operations.

## Features

- **Smart Conversion**: Converts all audio to 320kbps CBR MP3 while preserving FLAC/WAV/AIFF files lossless
- **Intelligent Organization**: Automatically categorizes tracks by Artist → Singles/Album → Numbered Tracks
- **Compilation Support**: Detects and organizes VA/compilation albums separately
- **Metadata Preservation**: Keeps year, genre, track number, and cover art
- **Safety First**: Copy → Verify → Delete workflow (never destructively move files)
- **Error Logging**: Continues on errors and logs failures for review
- **Progress Tracking**: Real-time progress bar with ETA

## Requirements

### Dependencies
- `ffmpeg` - Audio conversion
- `ffprobe` - Audio format detection
- `python3` - Script runtime
- `bc` - Progress calculations
- `mutagen` - Python metadata library

### Installation

```bash
# macOS with Homebrew
brew install ffmpeg bc

# Install mutagen for Python
pip3 install mutagen

# Make script executable
chmod +x organize_music.sh
```

## Usage

```bash
# Preview mode (default - no changes made)
./organize_music.sh /path/to/music

# Execute after preview
./organize_music.sh /path/to/music -y

# Custom output directory
./organize_music.sh /path/to/music -o /dest/path -y

# Force overwrite existing files
./organize_music.sh /path/to/music -y -f

# Show help
./organize_music.sh --help
```

## Output Structure

```
music_organized/
├── Artist Name/
│   ├── Singles/
│   │   ├── 001_First_Single.mp3
│   │   └── 002_Second_Single.mp3
│   └── Album Name/
│       ├── 001_First_Track.mp3
│       └── 002_Second_Track.mp3
└── Compilations/
    └── Compilation Album/
        ├── 001_Artist_Track.mp3
        └── 002_Artist_Track.mp3
```

## Classification Logic

### Singles
- Tracks without album metadata
- Tracks in folders named "Singles"
- Detected as non-album tracks

### Albums
- Tracks with album metadata
- Album Artist matches primary Artist
- Organized by Album Name

### Compilations
- Tracks with compilation flag in metadata
- Album Artist differs from track Artist
- Organized in Compilations folder

## Supported Formats

### Input
| Format | Handling |
|--------|----------|
| FLAC | Copied lossless |
| WAV | Copied lossless |
| AIFF/AIF | Copied lossless |
| MP3 < 320kbps | Re-encoded to 320kbps |
| MP3 >= 320kbps | Copied as-is |
| M4A, OGG, Opus, WMA | Converted to 320kbps MP3 |
| VDJSTEMS | Converted to 320kbps MP3 |

### Output
- 320kbps CBR MP3
- Lossless FLAC (originals preserved)

## Safety Features

1. **Preview Mode**: Always shows planned actions before execution
2. **Copy Before Delete**: Files are copied, verified, then originals deleted
3. **Verification**: CRC/size checks after each copy operation
4. **Error Recovery**: Continues processing on errors, logs failures
5. **No Overwrite by Default**: Skips existing files unless `-f` used

## Error Handling

- Errors logged to `organize_errors.log` in script directory
- Failed files are skipped, not deleted
- Processing continues with remaining files
- Summary shows error count at completion

## File Naming

- Maximum 200 characters (filesystem safe)
- Invalid chars replaced with underscores
- Format: `###_Track_Title.ext`
- Track numbers zero-padded (001, 002, etc.)

## Command Line Options

| Option | Description |
|--------|-------------|
| `-o, --output DIR` | Output directory (default: `SOURCE_organized`) |
| `-y, --yes` | Execute after preview (default: preview only) |
| `-f, --force` | Overwrite existing files |
| `-v, --verbose` | Show detailed progress |
| `-h, --help` | Show help message |

## Progress Output

```
[██████████████░░░░░░░░░░] 45% (450/1000 files) - Artist - Track.mp3 ETA: 2m30s
```

## Troubleshooting

### Missing Dependencies
```bash
# Verify installations
which ffmpeg ffprobe python3 bc

# Install missing on macOS
brew install ffmpeg bc

# Install Python mutagen
pip3 install mutagen
```

### Permission Denied
```bash
chmod +x organize_music.sh
```

### No Files Found
- Check source directory path
- Verify audio files have supported extensions
- Run with `-v` for verbose output

## License

MIT License - Use freely, backup your music first.
