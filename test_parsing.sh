#!/usr/bin/env bash

# Test IFS parsing with null characters
metadata="artist=John\x00album=Album Name\x00title=Song Title\x00"

echo "Original metadata: $metadata"
echo ""

# Test parsing method 1: IFS assignment
local IFS=$'\x00'
echo "Method 1 - IFS assignment:"
count=0
for line in $metadata; do
    ((count++))
    echo "  $count: '$line'"
    if [[ "$line" =~ ^([^=]+)=(.*)$ ]]; then
        key="${BASH_REMATCH[1]}"
        value="${BASH_REMATCH[2]}"
        echo "    Parsed: key='$key', value='$value'"
    fi
done

echo ""

# Test parsing method 2: read with -d
echo "Method 2 - read with -d:"
count=0
while IFS= read -r -d '' line; do
    ((count++))
    echo "  $count: '$line'"
    if [[ "$line" =~ ^([^=]+)=(.*)$ ]]; then
        key="${BASH_REMATCH[1]}"
        value="${BASH_REMATCH[2]}"
        echo "    Parsed: key='$key', value='$value'"
    fi
done <<< "$metadata"