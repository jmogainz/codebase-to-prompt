#!/bin/bash

###############################################################################
# project.sh
#
# Generates a simple directory tree and file contents, sorted by modification
# time ascending (oldest first => newest last). By default, it writes to
# "prompt_script.txt", but if you pass `--stdout`, it writes to stdout instead.
#
# Usage examples:
#   ./project.sh
#       - Ignores test/mock files, writes to prompt_script.txt
#
#   ./project.sh -t
#       - Includes test/mock files, writes to prompt_script.txt
#
#   ./project.sh -i build -i install ...
#       - Adds extra ignore patterns, writes to prompt_script.txt
#
#   ./project.sh -O '*.txt'
#       - Only includes files or directories matching '*.txt'
#
#   ./project.sh -O worker-app/lib/features/worker/ -O worker-app/lib/features/auth/ -O flutter-auth/
#       - Only includes items whose path contains one or more of these patterns.
#
#   ./project.sh --stdout
#       - Prints everything to stdout instead of writing to prompt_script.txt
###############################################################################

# Default ignore items (folder or partial path names; no wildcard yet)
IGNORE_ITEMS=("build" "install" "cmake" "deps" ".vscode" "tests" ".git" ".venv_poetry" ".venv" ".cache_poetry" ".cache_pip" "__pycache__" ".cache" "vendor")

# By default, we skip 'test'/'mock' patterns unless -t is provided
INCLUDE_TEST=false

# Whether to write to file or stdout
WRITE_TO_STDOUT=false

# Array to store patterns provided by -O flags (only include files/directories matching these patterns)
ONLY_PATTERNS=()

print_usage() {
  cat <<EOF
Usage: $0 [options]

Options:
  -t               Include 'test'/'mock' files in output (otherwise they're ignored)
  -i <pattern>     Add an ignore pattern (can be repeated multiple times)
  -O <pattern>     Only include files or directories whose full path matches this pattern.
                   This flag can be specified multiple times.
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
      if [[ -z "$2" ]]; then
        echo "Error: '-i' requires a pattern argument."
        exit 1
      fi
      IGNORE_ITEMS+=("$2")
      shift 2
      ;;
    -O)
      if [[ -z "$2" ]]; then
        echo "Error: '-O' requires a pattern argument."
        exit 1
      fi
      ONLY_PATTERNS+=("$2")
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

# If not including tests, add default test and mock ignore patterns
if [ "$INCLUDE_TEST" = false ]; then
  IGNORE_ITEMS+=("test")
  IGNORE_ITEMS+=("*_test.*")
  IGNORE_ITEMS+=("mock")
fi

# Output file (if not using stdout)
OUTPUT_FILE="prompt_script.txt"

###############################################################################
# Decide which 'stat' command to use based on OS (macOS vs. Linux)
###############################################################################
if [ "$(uname)" = "Darwin" ]; then
  # macOS/BSD
  STAT_CMD='stat -f "%m %N"'
else
  # Linux (and possibly other *nix)
  STAT_CMD='stat -c "%Y %n"'
fi

###############################################################################
# Helper: Print directory structure (filtered by -O patterns if provided)
###############################################################################
print_directory_structure() {
  echo "Project Folder Structure:"
  echo "========================"

  # Build prune patterns from IGNORE_ITEMS
  PRUNE_PATTERNS=()
  for item in "${IGNORE_ITEMS[@]}"; do
    PRUNE_PATTERNS+=( -path "*/$item*" -o )
  done
  unset 'PRUNE_PATTERNS[${#PRUNE_PATTERNS[@]}-1]'

  # If ONLY_PATTERNS is provided, include only directories whose full path contains one of them.
  if [ ${#ONLY_PATTERNS[@]} -gt 0 ]; then
    # Build a predicate for directories matching any ONLY_PATTERN using -path
    DIR_EXPR=( \( -path "*${ONLY_PATTERNS[0]}*" )
    for pattern in "${ONLY_PATTERNS[@]:1}"; do
      DIR_EXPR+=( -o -path "*$pattern*" )
    done
    DIR_EXPR+=( \) )
    find . \( \( "${PRUNE_PATTERNS[@]}" \) -prune \) -o \( -type d "${DIR_EXPR[@]}" -print \) \
      | sed -e 's|[^/]*/|  |g'
  else
    find . \( \( "${PRUNE_PATTERNS[@]}" \) -prune \) -o \( -type d -print \) \
      | sed -e 's|[^/]*/|  |g'
  fi
}

###############################################################################
# Helper: Print file contents (filtered by -O patterns if provided)
###############################################################################
print_file_contents() {
  echo
  echo "Files with Contents:"
  echo "===================="

  # Build prune patterns from IGNORE_ITEMS
  PRUNE_PATTERNS=()
  for item in "${IGNORE_ITEMS[@]}"; do
    PRUNE_PATTERNS+=( -path "*/$item*" -o )
  done
  unset 'PRUNE_PATTERNS[${#PRUNE_PATTERNS[@]}-1]'

  # Determine file selection criteria
  if [ ${#ONLY_PATTERNS[@]} -gt 0 ]; then
    # Build a find expression using -path so that any file whose full path contains one
    # of the ONLY_PATTERNS is selected.
    find_expr=( -type f \( -path "*${ONLY_PATTERNS[0]}*" )
    for pattern in "${ONLY_PATTERNS[@]:1}"; do
      find_expr+=( -o -path "*$pattern*" )
    done
    find_expr+=( \) -print )
    readarray -t FOUND_FILES < <(
      find . \( \( "${PRUNE_PATTERNS[@]}" \) -prune \) -o "${find_expr[@]}"
    )
  else
    # Default: select files with certain extensions
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

  # If no files are found, exit this section
  if [ ${#FOUND_FILES[@]} -eq 0 ]; then
    return
  fi

  # For each found file, collect "modTime filePath" using the appropriate stat command
  MOD_LIST=()
  for file in "${FOUND_FILES[@]}"; do
    LINE=$(eval "$STAT_CMD \"$file\" 2>/dev/null")
    MOD_LIST+=( "$LINE" )
  done

  # Sort by modification time (numerically, using the first field)
  SORTED_LINES=$(printf "%s\n" "${MOD_LIST[@]}" | sort -k1,1n)

  # Read each sorted line, extract the path, and output the file's content
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
# Output the results (to stdout or file)
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

