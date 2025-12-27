#!/bin/bash

# ------------------------------
# unpack.sh — Exam‑style solution
# ------------------------------
# Supports:
#   - gzip (.gz)
#   - bzip2 (.bz2)
#   - compress (.Z)
#   - zip (.zip)
#
# Requirements:
#   - Keep original archives intact
#   - Overwrite extracted files automatically
#   - Verbose mode (-v)
#   - Recursive mode (-r)
#   - Exit code = number of NOT‑decompressed files
#
# Notes:
#   - Uses `file` to detect archive type (never trust extensions)
#   - Uses streaming decompressors (gzip -dc, bzip2 -dc, uncompress -c)
#   - Uses getopts (standard POSIX flag parser)
# ------------------------------

# Flags
VERBOSE=false
RECURSIVE=false

# Counters
decompressed_count=0
not_decompressed_count=0

# ------------------------------
# Parse flags using getopts
# ------------------------------
# getopts handles combined flags (-rv, -vr, -r -v)
while getopts "rv" opt; do
    case "$opt" in
        r) RECURSIVE=true ;;
        v) VERBOSE=true ;;
    esac
done

# Remove parsed flags from "$@"
shift $((OPTIND - 1))

# ------------------------------
# Utility: print verbose messages
# ------------------------------
vmsg() {
    if "$VERBOSE"; then
        echo "$1"
    fi
}

# ------------------------------
# Process a single file
# ------------------------------
process_file() {
    local file_path="$1"

    # Use `file -b` to detect type (never rely on extension)
    local file_type
    file_type=$(file -b "$file_path")
    vmsg "Detected type: $file_type"

    local status=0

    # ------------------------------
    # GZIP
    # ------------------------------
    if [[ "$file_type" == *"gzip compressed data"* ]]; then
        local out="${file_path%.gz}"
        gzip -dc "$file_path" > "$out" 2>/dev/null
        status=$?

    # ------------------------------
    # BZIP2
    # ------------------------------
    elif [[ "$file_type" == *"bzip2 compressed data"* ]]; then
        local out="${file_path%.bz2}"
        [[ "$out" == "$file_path" ]] && out="${file_path}.out"
        bzip2 -dc "$file_path" > "$out" 2>/dev/null
        status=$?

    # ------------------------------
    # ZIP
    # ------------------------------
    elif [[ "$file_type" == *"Zip archive data"* ]]; then
        unzip -o "$file_path" >/dev/null 2>&1
        status=$?

    # ------------------------------
    # COMPRESS (.Z)
    # ------------------------------
    elif [[ "$file_type" == *"compress'd data"* ]]; then
        local out="${file_path%.Z}"
        [[ "$out" == "$file_path" ]] && out="${file_path}.out"
        uncompress -c "$file_path" > "$out" 2>/dev/null
        status=$?

    # ------------------------------
    # NOT an archive
    # ------------------------------
    else
        vmsg "Ignoring $(basename "$file_path")"
        not_decompressed_count=$((not_decompressed_count + 1))
        return
    fi

    # ------------------------------
    # Check decompressor exit status
    # ------------------------------
    if [ $status -eq 0 ]; then
        vmsg "Unpacking $(basename "$file_path") ..."
        decompressed_count=$((decompressed_count + 1))
    else
        vmsg "Ignoring $(basename "$file_path")"
        not_decompressed_count=$((not_decompressed_count + 1))
    fi
}

# ------------------------------
# Process directory (non‑recursive)
# ------------------------------
process_directory_non_recursive() {
    local dir="$1"
    local entry

    for entry in "$dir"/*; do
        [ -e "$entry" ] || continue
        if [ -f "$entry" ]; then
            process_file "$entry"
        fi
    done
}

# ------------------------------
# Process directory (recursive)
# ------------------------------
process_directory_recursive() {
    local dir="$1"
    local entry

    for entry in "$dir"/*; do
        [ -e "$entry" ] || continue

        if [ -d "$entry" ]; then
            process_directory_recursive "$entry"
        elif [ -f "$entry" ]; then
            process_file "$entry"
        fi
    done
}

# ------------------------------
# Route paths to correct handler
# ------------------------------
process_path() {
    local path="$1"

    if [ -d "$path" ]; then
        if "$RECURSIVE"; then
            process_directory_recursive "$path"
        else
            process_directory_non_recursive "$path"
        fi
    elif [ -f "$path" ]; then
        process_file "$path"
    else
        vmsg "Ignoring $path"
        not_decompressed_count=$((not_decompressed_count + 1))
    fi
}

# ------------------------------
# Main loop — process all arguments
# ------------------------------
for item in "$@"; do
    process_path "$item"
done

# ------------------------------
# Final summary
# ------------------------------
echo "Decompressed $decompressed_count archive(s)"

# Exit code = number of NOT‑decompressed files
exit $not_decompressed_count
