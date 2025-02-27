#!/bin/bash

###############################################################################
# project.sh
#
# Generates a simple directory tree and file contents, sorted by modification
# time ascending (oldest first => newest last). By default, it writes to
# "prompt_script.txt", but if you pass `--stdout`, it writes to stdout instead.
#
# Usage:
#   ./project.sh               # ignores "test"/"mock", writes to prompt_script.txt
#   ./project.sh -t            # includes test/mock files, writes to prompt_script.txt
#   ./project.sh build         # add extra ignore pattern "build", writes to prompt_script.txt
#   ./project.sh --stdout      # prints everything to stdout
#   ./project.sh --stdout -t   # prints everything to stdout, including test/mock
###############################################################################

# Default ignore items (folder or partial path names, no wildcard yet)
IGNORE_ITEMS=("build" "install" "cmake" "deps" ".vscode" "tests" ".git" ".venv_poetry" ".venv" ".cache_poetry" ".cache_pip" "__pycache__" ".cache")

# By default, we also skip 'test'/'mock' patterns unless `-t` is provided
INCLUDE_TEST=false

# Whether to write to file or stdout
WRITE_TO_STDOUT=false

# ------------------------------------------------------------------------------
# Parse command line arguments
#   - If `-t`, set INCLUDE_TEST=true
#   - If `--stdout`, set WRITE_TO_STDOUT=true
#   - Otherwise, treat argument as an additional ignore pattern
# ------------------------------------------------------------------------------
while [[ $# -gt 0 ]]; do
  case "$1" in
    -t)
      INCLUDE_TEST=true
      shift
      ;;
    --stdout)
      WRITE_TO_STDOUT=true
      shift
      ;;
    *)
      IGNORE_ITEMS+=("$1")
      shift
      ;;
  esac
done

# If not including tests, skip 'test' + 'mock'
if [ "$INCLUDE_TEST" = false ]; then
  IGNORE_ITEMS+=("test")
  IGNORE_ITEMS+=("mock")
fi

# Our output destination
OUTPUT_FILE="prompt_script.txt"

###############################################################################
# Decide which 'stat' format to use based on OS (macOS vs. Linux).
###############################################################################
if [ "$(uname)" = "Darwin" ]; then
  # macOS/BSD
  STAT_CMD='stat -f "%m %N"'
else
  # Linux (and possibly other *nix that supports this)
  STAT_CMD='stat -c "%Y %n"'
fi

###############################################################################
# Helper: Print directory structure
###############################################################################
print_directory_structure() {
  echo "Project Folder Structure:"
  echo "========================"

  # Convert IGNORE_ITEMS -> find prune patterns
  PRUNE_PATTERNS=()
  for item in "${IGNORE_ITEMS[@]}"; do
    PRUNE_PATTERNS+=( -path "*/$item*" -o )
  done
  # Remove trailing "-o"
  unset 'PRUNE_PATTERNS[${#PRUNE_PATTERNS[@]}-1]'

  find . \( \( "${PRUNE_PATTERNS[@]}" \) -prune \) -o \( -type d -print \) \
    | sed -e 's|[^/]*/|  |g'
}

###############################################################################
# Helper: Print file contents in ascending modification time order
###############################################################################
print_file_contents() {
  echo
  echo "Files with Contents:"
  echo "===================="

  # 1) Build find prune patterns from IGNORE_ITEMS
  PRUNE_PATTERNS=()
  for item in "${IGNORE_ITEMS[@]}"; do
    PRUNE_PATTERNS+=( -path "*/$item*" -o )
  done
  unset 'PRUNE_PATTERNS[${#PRUNE_PATTERNS[@]}-1]'

  # 2) Find only files with certain extensions
  #    (like your original script: *.py, *.c, *.cpp, etc.)
  #    We'll store them in an array to process next.
  readarray -t FOUND_FILES < <(
    find . \( \( "${PRUNE_PATTERNS[@]}" \) -prune \) -o \
      \( -type f \
         \( -name "*.py" \
         -o -name "*.h" \
         -o -name "*.hpp" \
         -o -name "*.c" \
         -o -name "*.cpp" \
         -o -name "*.yaml" \
         -o -name "*.yml" \
         -o -name "*.json" \
         -o -name "*.toml" \
         -o -name "Dockerfile*" \
         -o -name "*.sh" \
         -o -name "*.go" \
         -o -name "Makefile" \
         -o -name "*.mk" \
         -o -name "*.env" \
         -o -name "*.bat" \
         -o -name "*.lua" \
         -o -name "*.sql" \
         -o -name "*.dart" \) \
       -print \)
  )

  # If none found, just exit
  if [ ${#FOUND_FILES[@]} -eq 0 ]; then
    return
  fi

  # 3) For each file, collect "modTime filePath" using $STAT_CMD, e.g. "123456789 .somefile"
  #    Then we sort ascending by modTime.
  MOD_LIST=()
  for file in "${FOUND_FILES[@]}"; do
    # Evaluate STAT_CMD, ignoring errors
    # e.g. stat -c "%Y %n"  or  stat -f "%m %N"
    LINE=$(eval "$STAT_CMD \"$file\" 2>/dev/null")
    # E.g. "1675021230 ./somefile"
    # We'll store it as is. We'll handle spaces in filename carefully => assume no spaces
    MOD_LIST+=( "$LINE" )
  done

  # 4) Sort numerically by modTime (the first field).
  #    Then strip off the modTime field before printing.
  #    We'll gather the sorted lines into an array, then parse out the path.
  #    'sort -k1,1n' sorts by the first column numeric ascending => oldest first, newest last
  SORTED_LINES=$(printf "%s\n" "${MOD_LIST[@]}" | sort -k1,1n)

  # 5) Now read them in order, parse out the path, cat them
  while IFS= read -r line; do
    # The first space-delimited chunk is the modTime, the rest is the path
    modTime="${line%% *}"
    path="${line#* }"

    # Print a small divider
    echo
    echo
    echo "==== $path ===="
    echo
    cat "$path"
  done <<< "$SORTED_LINES"
}

###############################################################################
# Write or print (depending on --stdout)
###############################################################################
if [ "$WRITE_TO_STDOUT" = true ]; then
  print_directory_structure
  print_file_contents
else
  {
    print_directory_structure
    print_file_contents
  } > "$OUTPUT_FILE"

  echo "Project structure and file contents written to $OUTPUT_FILE"
fi

