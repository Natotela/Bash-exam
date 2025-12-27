#!/usr/bin/env bash
# unpack.sh — universal extractor (exam-polished)
# Usage: unpack.sh [-v] [-V] [-r] path1 [path2 ...]
#
# Behavior summary:
#  - Default: prints "Decompressed N archive(s)" (always)
#  - -v: per-file messages ("Unpacking ..." / "Ignoring ...")
#  - -V: extra final summary (counts and recursion note)
#  - -r: recursive directory processing
#  - Exit code: number of non-archive files encountered (capped at 254)
#  - Prefers GNU keep/name flags when available (gunzip -N -k, bunzip2 -k, xz -k)
#  - Forces overwrite when using destructive tools (-f) to avoid prompts
#  - Uses `file -b` to detect archive type (not file extension)
#  - Suppresses internal stderr so only intended stdout appears
set -o errexit
set -o nounset
set -o pipefail

VERBOSE=false   # -v per-file messages
EXTRA=false     # -V extra final summary
RECURSIVE=false # -r recursive

vmsg() { $VERBOSE && printf '%s\n' "$1"; }

# -------------------------
# Feature detection (portable)
# -------------------------
# We capture both stdout and stderr (2>&1) when probing --help because some
# builds print help to stderr. This makes detection robust across systems.
gzip_supports_name_and_keep=false
if command -v gzip >/dev/null 2>&1; then
  if gzip --help 2>&1 | grep -q -- '--name' && gzip --help 2>&1 | grep -q -- '--keep'; then
    gzip_supports_name_and_keep=true
  fi
fi

bzip2_supports_keep=false
if command -v bunzip2 >/dev/null 2>&1; then
  if bunzip2 --help 2>&1 | grep -q -- '--keep\| -k'; then
    bzip2_supports_keep=true
  fi
fi

xz_supports_keep=false
if command -v xz >/dev/null 2>&1; then
  if xz --help 2>&1 | grep -q -- '--keep\| -k'; then
    xz_supports_keep=true
  fi
fi

# -------------------------
# Counters
# -------------------------
total_inputs=0
total_processed=0
archives_extracted=0
non_archives=0

# -------------------------
# extract_file function
# - returns 0 when the file was handled as an archive
# - returns 1 when the file is not an archive
# Notes:
#  - All tool stderr is redirected to /dev/null to avoid extra output.
#  - When using destructive tools in keep mode we add -f to force overwrite
#    and avoid interactive prompts (this is required for repeated runs).
# -------------------------
extract_file() {
  local file="$1"
  local base dir type out orig
  base=$(basename -- "$file")
  dir=$(dirname -- "$file")
  type=$(file -b -- "$file" 2>/dev/null || printf '')

  # per-file verbose message (only printed when -v)
  case "$type" in
    *"Zip archive data"*) vmsg "Unpacking $base..." ;;
    *"gzip compressed data"*) vmsg "Unpacking $base..." ;;
    *"bzip2 compressed data"*) vmsg "Unpacking $base..." ;;
    *"compress'd data"*) vmsg "Unpacking $base..." ;;
    *) vmsg "Ignoring $base" ;;
  esac

  # -------------------------
  # ZIP (active)
  # unzip preserves internal filenames and directory tree.
  # -o forces overwrite (no prompts)
  # -------------------------
  if [[ "$type" == *"Zip archive data"* ]]; then
    (cd "$dir" && unzip -o -- "$base" >/dev/null 2>&1) || true
    return 0
  fi

  # -------------------------
  # TAR-like (COMMENTED OUT)
  # If you want tar support, uncomment this block.
  # tar archives contain full file trees and names; tar -xf extracts them.
  # We keep the code here commented for the exam requirement to limit formats.
  # -------------------------
  #: <<'TAR_BLOCK'
  #if [[ "$type" == *"tar archive"* ]] || [[ "$type" == *"ustar"* ]] || [[ "$type" == *"pax archive"* ]] || [[ "$type" == *"POSIX tar"* ]]; then
  #  (cd "$dir" && tar --overwrite -xf -- "$base" >/dev/null 2>&1) 2>/dev/null || (cd "$dir" && tar -xf -- "$base" >/dev/null 2>&1) || true
  #  return 0
  #fi
  #TAR_BLOCK

  # -------------------------
  # GZIP (active)
  # - Prefer gunzip -N -k -f when available:
  #   - -N restores original filename if stored in gzip header
  #   - -k keeps the .gz archive (non-destructive)
  #   - -f forces overwrite to avoid interactive prompts
  # - Fallback: gzip -dc > out (portable, keeps archive)
  # - We use gzip -l + awk 'NR==2 {print $4}' to try to read the internal name
  #   when -N is not available. awk 'NR==2 {print $4}' means:
  #     NR==2  -> operate on the second line of gzip -l output
  #     print $4 -> print the 4th whitespace-separated field (the stored name)
  # -------------------------
  if [[ "$type" == *"gzip compressed data"* ]]; then
    if $gzip_supports_name_and_keep; then
      (cd "$dir" && gunzip -N -k -f -- "$base" >/dev/null 2>&1) || true
      return 0
    else
      orig=$(gzip -l -- "$file" 2>/dev/null | awk 'NR==2 {print $4}' 2>/dev/null || printf '')
      if [ -n "$orig" ] && [ "$orig" != "-" ]; then
        gzip -dc -- "$file" > "$dir/$orig" 2>/dev/null || true
      else
        out="${file%.gz}"
        [ "$out" = "$file" ] && out="${file}.out"
        gzip -dc -- "$file" > "$out" 2>/dev/null || true
      fi
      return 0
    fi
  fi

  # -------------------------
  # BZIP2 (active)
  # - Prefer bunzip2 -k -f when available (keep archive, force overwrite)
  # - Fallback: bzip2 -dc > out (portable)
  # -------------------------
  if [[ "$type" == *"bzip2 compressed data"* ]]; then
    if $bzip2_supports_keep; then
      (cd "$dir" && bunzip2 -k -f -- "$base" >/dev/null 2>&1) || true
      return 0
    else
      out="${file%.bz2}"
      [ "$out" = "$file" ] && out="${file}.out"
      bzip2 -dc -- "$file" > "$out" 2>/dev/null || true
      return 0
    fi
  fi

  # -------------------------
  # XZ (COMMENTED OUT)
  # If you want XZ support, uncomment this block.
  # xz archives can be handled with xz -k -f -d (keep + force) or xz -dc > out.
  # -------------------------
  #: <<'XZ_BLOCK'
  #if [[ "$type" == *"XZ compressed data"* ]] || [[ "$type" == *"XZ compressed"* ]]; then
  #  if $xz_supports_keep; then
  #    (cd "$dir" && xz -k -f -d -- "$base" >/dev/null 2>&1) || true
  #    return 0
  #  else
  #    out="${file%.xz}"
  #    [ "$out" = "$file" ] && out="${file}.out"
  #    xz -dc -- "$file" > "$out" 2>/dev/null || true
  #    return 0
  #  fi
  #fi
  #XZ_BLOCK

  # -------------------------
  # COMPRESS (.Z) (active)
  # - uncompress -c > out (keeps archive)
  # -------------------------
  if [[ "$type" == *"compress'd data"* ]]; then
    out="${file%.Z}"
    [ "$out" = "$file" ] && out="${file}.out"
    uncompress -c -- "$file" > "$out" 2>/dev/null || true
    return 0
  fi

  # Not a supported archive
  return 1
}

# -------------------------
# Directory processing (shallow)
# -------------------------
process_dir_shallow() {
  local dir="$1" entry
  for entry in "$dir"/*; do
    [ -e "$entry" ] || continue
    if [ -f "$entry" ]; then
      total_processed=$((total_processed+1))
      if extract_file "$entry"; then
        archives_extracted=$((archives_extracted+1))
      else
        non_archives=$((non_archives+1))
      fi
    fi
  done
}

# -------------------------
# Directory processing (recursive)
# -------------------------
process_dir_recursive() {
  local dir="$1" entry
  for entry in "$dir"/*; do
    [ -e "$entry" ] || continue
    if [ -d "$entry" ]; then
      process_dir_recursive "$entry"
    elif [ -f "$entry" ]; then
      total_processed=$((total_processed+1))
      if extract_file "$entry"; then
        archives_extracted=$((archives_extracted+1))
      else
        non_archives=$((non_archives+1))
      fi
    fi
  done
}

# -------------------------
# Parse options
# -------------------------
while getopts "vVr" opt; do
  case "$opt" in
    v) VERBOSE=true ;;
    V) EXTRA=true ;;
    r) RECURSIVE=true ;;
    *) ;;
  esac
done
shift $((OPTIND - 1))

if [ $# -eq 0 ]; then
  printf 'Usage: %s [-v] [-V] [-r] path1 [path2 ...]\n' "$0"
  exit 2
fi

# -------------------------
# Main loop over inputs
# -------------------------
for p in "$@"; do
  total_inputs=$((total_inputs+1))
  if [ -f "$p" ]; then
    total_processed=$((total_processed+1))
    if extract_file "$p"; then
      archives_extracted=$((archives_extracted+1))
    else
      non_archives=$((non_archives+1))
    fi
  elif [ -d "$p" ]; then
    if $RECURSIVE; then
      process_dir_recursive "$p"
    else
      process_dir_shallow "$p"
    fi
  else
    # non-existent or other path counts as non-archive
    non_archives=$((non_archives+1))
  fi
done

# -------------------------
# Default output (always printed)
# -------------------------
printf 'Decompressed %d archive(s)\n' "$archives_extracted"

# -------------------------
# Extra final summary (only when -V)
# -------------------------
if $EXTRA; then
  printf '● Processed %d inputs: %d files processed, %d archives extracted, %d non-archives\n' \
    "$total_inputs" "$total_processed" "$archives_extracted" "$non_archives"
  if [ "$RECURSIVE" = true ]; then
    printf '● Recursive mode: subfolders were processed\n'
  else
    printf '● Non-recursive mode: subfolders were ignored\n'
  fi
fi

# -------------------------
# Exit code equals number of non-archive files (cap at 254)
# -------------------------
if [ "$non_archives" -gt 254 ]; then
  exit 254
else
  exit "$non_archives"
fi
