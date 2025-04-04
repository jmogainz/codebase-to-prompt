#!/usr/bin/env bash

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
#   ./project.sh -O "*.txt"
#       - Only includes files whose path matches '*.txt', overriding default
#         file patterns (the directory tree is still shown for the entire
#         project if no folder patterns are given, subject to ignore rules).
#
#   ./project.sh -O worker-app/lib/features/worker/
#       - Only includes files matching the default file patterns *inside*
#         'worker-app/lib/features/worker' (subject to ignore rules),
#         and shows the directory tree only for that folder path.
#
#   ./project.sh -O worker-app/lib/features/worker/ -O "*.txt"
#       - Because a file pattern (`*.txt`) is present, it overrides the
#         default file patterns. Only files matching `*.txt` anywhere are shown.
#         Meanwhile, the folder pattern restricts the directory tree to that
#         folder path for display.
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

# Collect all -O patterns; we'll separate them into folder patterns vs file patterns
ONLY_PATTERNS=()

print_usage() {
  cat <<EOF
Usage: $0 [options]

Options:
  -t               Include 'test'/'mock' files in output (otherwise they're ignored)
  -i <pattern>     Add an ignore pattern (can be repeated multiple times).
                   Example: -i worker-app  (will ignore worker-app and all subfolders)
  -O <pattern>     Include pattern(s). If the pattern ends with '/', it is
                   treated as a FOLDER pattern (keeping default file extensions).
                   If it does not end with '/', it is treated as a FILE pattern
                   (overriding the default file extensions).
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
IGNORE_ITEMS+=("$OUTPUT_FILE")

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
# Define the default file extensions in ONE place
###############################################################################
DEFAULT_FILE_GLOBS=(
  "*.py"
  "*.h"
  "*.hpp"
  "*.c"
  "*.cpp"
  "*.yaml"
  "*.yml"
  "*.json"
  "*.toml"
  "*Dockerfile*"
  "*.sh"
  "*.go"
  "Makefile"
  "*.mk"
  "*.env"
  "*.bat"
  "*.lua"
  "*.sql"
  "*.gradle"
  "*.properties"
  "*.xml"
  "*.txt"
  "*.dart"
)

# Build an array for the `find` command's `-name` checks. We'll insert "-o" between them.
DEFAULT_FILE_PATTERN_ARGS=()
for glob in "${DEFAULT_FILE_GLOBS[@]}"; do
  DEFAULT_FILE_PATTERN_ARGS+=( -name "$glob" -o )
done
# Remove the trailing '-o'
unset 'DEFAULT_FILE_PATTERN_ARGS[${#DEFAULT_FILE_PATTERN_ARGS[@]}-1]'

###############################################################################
# Separate ONLY_PATTERNS into folder patterns vs file patterns
# ------------------------------------------------------------------------------
# - If a pattern ends with '/', treat it as a folder pattern (keeping default
#   file extensions).
# - Otherwise, treat it as a file pattern (overrides default file extensions).
###############################################################################
ONLY_FOLDER_PATTERNS=()
ONLY_FILE_PATTERNS=()

for pat in "${ONLY_PATTERNS[@]}"; do
  if [[ "$pat" == */ ]]; then
    # Folder pattern
    folder="${pat%/}"  # remove trailing slash
    ONLY_FOLDER_PATTERNS+=("$folder")
  else
    # File pattern
    ONLY_FILE_PATTERNS+=("$pat")
  fi
done

###############################################################################
# Build prune patterns from IGNORE_ITEMS
#
# This function:
# 1) Strips trailing slashes from the ignore pattern
# 2) Creates two rules:
#       -path "*/ITEM"     (the directory/file itself)
#       -path "*/ITEM/*"   (anything inside that directory)
#    for each ignore item
###############################################################################
build_prune_patterns() {
  PRUNE_PATTERNS=()
  for item in "${IGNORE_ITEMS[@]}"; do
    # Remove trailing slash if present, for consistency
    clean_item="${item%/}"

    # If we want to ignore 'clean_item', we should ignore:
    #  - the path that ends with ".../clean_item" 
    #  - anything that starts with ".../clean_item/"
    #
    # This covers ignoring an entire directory and its subcontents,
    # as well as ignoring a single file with that exact name.
    PRUNE_PATTERNS+=( -path "*/${clean_item}" -o -path "*/${clean_item}/*" -o )
  done

  # Remove trailing '-o' if any
  if [ ${#PRUNE_PATTERNS[@]} -gt 0 ]; then
    unset 'PRUNE_PATTERNS[${#PRUNE_PATTERNS[@]}-1]'
  fi
}

###############################################################################
# Helper: Print directory structure
#
# - If there are no folder-only patterns, print the entire tree (minus ignored).
# - If there are folder-only patterns, print a separate section for each.
###############################################################################
print_directory_structure() {
  echo "Project Folder Structure:"
  echo "========================"

  # Build the PRUNE_PATTERNS array now
  build_prune_patterns

  indent_sed='s|[^/]*/|  |g'

  # Case: No folder-only patterns => entire tree
  if [ ${#ONLY_FOLDER_PATTERNS[@]} -eq 0 ]; then
    find . \( \( "${PRUNE_PATTERNS[@]}" \) -prune \) -o -type d -print \
      | sed -e "$indent_sed"
    return
  fi

  # Case: One or more folder-only patterns => separate sections
  for folder in "${ONLY_FOLDER_PATTERNS[@]}"; do
    if [ -d "$folder" ]; then
      echo
      echo "Directory subtree for: $folder"
      echo "--------------------------------"
      find "$folder" \
        \( \( "${PRUNE_PATTERNS[@]}" \) -prune \) -o -type d -print \
        | sed -e "$indent_sed"
    else
      echo
      echo "Warning: '$folder' does not exist or is not a directory."
    fi
  done
}

###############################################################################
# Helper: Print file contents
###############################################################################
print_file_contents() {
  echo
  echo "Files with Contents:"
  echo "===================="

  # Build the PRUNE_PATTERNS array now
  build_prune_patterns

  FOUND_FILES=()

  # ---------------------------------------------------------
  # CASE 1: We have at least one FILE pattern => override defaults
  # ---------------------------------------------------------
  if [ ${#ONLY_FILE_PATTERNS[@]} -gt 0 ]; then

    # Build a single find expression that matches any of these FILE patterns (OR logic).
    find_expr=( -type f \( )
    first=true
    for pat in "${ONLY_FILE_PATTERNS[@]}"; do
      if [ "$first" = true ]; then
        first=false
      else
        find_expr+=( -o )
      fi

      # If pattern has wildcard
      if [[ "$pat" == *"*"* || "$pat" == *"?"* || "$pat" == *"["* ]]; then
        # If it includes '/', use -path
        if [[ "$pat" == */* ]]; then
          # Ensure it starts with './' if not already
          [[ "$pat" != ./* ]] && pat="./$pat"
          find_expr+=( -path "$pat" )
        else
          # No slash => use -name
          find_expr+=( -name "$pat" )
        fi
      else
        # No wildcards => exact match
        if [[ "$pat" == */* ]]; then
          [[ "$pat" != ./* ]] && pat="./$pat"
          find_expr+=( -path "$pat" )
        else
          find_expr+=( -name "$pat" )
        fi
      fi
    done
    find_expr+=( \) -print )

    readarray -t FOUND_FILES < <(
      find . \( \( "${PRUNE_PATTERNS[@]}" \) -prune \) -o "${find_expr[@]}"
    )

  # ---------------------------------------------------------
  # CASE 2: Only FOLDER patterns => keep default file patterns, but limit to those folders
  # ---------------------------------------------------------
  elif [ ${#ONLY_FOLDER_PATTERNS[@]} -gt 0 ]; then
    for folder in "${ONLY_FOLDER_PATTERNS[@]}"; do
      if [ -d "$folder" ]; then
        readarray -t tmp_found < <(
          find "$folder" \( \( "${PRUNE_PATTERNS[@]}" \) -prune \) -o \
            \( -type f \( "${DEFAULT_FILE_PATTERN_ARGS[@]}" \) -print \)
        )
        FOUND_FILES+=("${tmp_found[@]}")
      fi
    done

  # ---------------------------------------------------------
  # CASE 3: No patterns => default file extensions across entire project
  # ---------------------------------------------------------
  else
    readarray -t FOUND_FILES < <(
      find . \( \( "${PRUNE_PATTERNS[@]}" \) -prune \) -o \
        \( -type f \( "${DEFAULT_FILE_PATTERN_ARGS[@]}" \) -print \)
    )
  fi

  # If no files are found, just return
  if [ ${#FOUND_FILES[@]} -eq 0 ]; then
    return
  fi

  # Collect "modTime filePath" for sorting by modification time
  MOD_LIST=()
  for file in "${FOUND_FILES[@]}"; do
    LINE=$(eval "$STAT_CMD \"$file\" 2>/dev/null")
    [[ -n "$LINE" ]] && MOD_LIST+=( "$LINE" )
  done

  # Sort by modification time (numerically, using the first field)
  SORTED_LINES=$(printf "%s\n" "${MOD_LIST[@]}" | sort -k1,1n)

  # Read each sorted line, extract the path, and output file content
  while IFS= read -r line; do
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

