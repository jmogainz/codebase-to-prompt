#!/bin/bash

###############################################################################
# project.sh
#
# Generates a simple directory tree and file contents, sorted by modification
# time ascending (oldest first => newest last). By default, it writes to
# "prompt_script.txt", but if you pass `--stdout`, it writes to stdout instead.
#
# Usage:
#   ./project.sh                          # ignores "test"/"mock", writes to prompt_script.txt
#   ./project.sh -t                       # includes test/mock files, writes to prompt_script.txt
#   ./project.sh -i build -i install ...  # add extra ignore patterns, writes to prompt_script.txt
#   ./project.sh -O '*.txt'               # only files matching '*.txt', ignoring default patterns
#   ./project.sh --stdout                 # prints everything to stdout
#   ./project.sh --stdout -t -i build     # prints everything to stdout, includes test, ignores 'build'
###############################################################################

# Default ignore items (folder or partial path names, no wildcard yet)
IGNORE_ITEMS=("build" "install" "cmake" "deps" ".vscode" "tests" ".git" ".venv_poetry" ".venv" ".cache_poetry" ".cache_pip" "__pycache__" ".cache" "vendor")

# By default, we skip 'test'/'mock' patterns unless `-t` is provided
INCLUDE_TEST=false

# Whether to write to file or stdout
WRITE_TO_STDOUT=false

# If set, only include files matching this pattern
ONLY_PATTERN=""

print_usage() {
  cat <<EOF
Usage: $0 [options]

Options:
  -t               Include 'test'/'mock' files in output (otherwise they're ignored)
  -i <pattern>     Add an ignore pattern (can be repeated multiple times)
  -O <pattern>     Only include files matching this pattern (e.g. '*.txt', CMakeLists.txt, etc.)
  --stdout         Print to stdout instead of writing to prompt_script.txt
  -h, --help       Show this help message
EOF
}

# ------------------------------------------------------------------------------
# Parse command line arguments
# ------------------------------------------------------------------------------
while [[ $# -gt 0 ]]; do
  case "$1" in
    -t)
      INCLUDE_TEST=true
      shift
      ;;
    -i)
      # Require an argument after -i
      if [[ -z "$2" ]]; then
        echo "Error: '-i' requires a pattern argument."
        exit 1
      fi
      IGNORE_ITEMS+=("$2")
      shift 2
      ;;
    -O)
      # Require an argument after -O
      if [[ -z "$2" ]]; then
        echo "Error: '-O' requires a pattern argument."
        exit 1
      fi
      ONLY_PATTERN="$2"
      shift 2
      ;;
    --stdout)
      WRITE_TO_STDOUT=true
      shift
      ;;
    -h|--help)
      print_usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1"
      echo
      print_usage
      exit 1
      ;;
  esac
done

# If not including tests, skip 'test' + 'mock'
if [ "$INCLUDE_TEST" = false ]; then
  IGNORE_ITEMS+=("test")
  IGNORE_ITEMS+=("*_test.*")
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
  # Remove the trailing "-o"
  unset 'PRUNE_PATTERNS[${#PRUNE_PATTERNS[@]}-1]'

  # 2) If ONLY_PATTERN is set, use that. Otherwise, use default file patterns.
  if [ -n "$ONLY_PATTERN" ]; then
    readarray -t FOUND_FILES < <(
      find . \( \( "${PRUNE_PATTERNS[@]}" \) -prune \) -o \
        \( -type f -name "$ONLY_PATTERN" -print \)
    )
  else
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
           -o -name "*Dockerfile*" \
           -o -name "*.sh" \
           -o -name "*.go" \
           -o -name "Makefile" \
           -o -name "*.mk" \
           -o -name "*.env" \
           -o -name "*.bat" \
           -o -name "*.lua" \
           -o -name "*.sql" \
           -o -name "*.gradle" \
           -o -name "*.properties" \
           -o -name "*.xml" \
           -o -name "*.dart" \) \
         -print \)
    )
  fi

  # If none found, just exit
  if [ ${#FOUND_FILES[@]} -eq 0 ]; then
    return
  fi

  # 3) For each file, collect "modTime filePath" using $STAT_CMD
  MOD_LIST=()
  for file in "${FOUND_FILES[@]}"; do
    LINE=$(eval "$STAT_CMD \"$file\" 2>/dev/null")
    MOD_LIST+=( "$LINE" )
  done

  # 4) Sort numerically by modTime (the first field)
  SORTED_LINES=$(printf "%s\n" "${MOD_LIST[@]}" | sort -k1,1n)

  # 5) Now read them in order, parse out the path, cat them
  while IFS= read -r line; do
    modTime="${line%% *}"
    path="${line#* }"

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

