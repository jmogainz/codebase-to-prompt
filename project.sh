#!/usr/bin/env bash

###############################################################################
# project.sh
#
# Generates a simple directory tree and file contents, sorted by modification
# time ascending (oldest first => newest last). By default, it writes to
# "prompt_script.txt", but if you pass `--stdout`, it writes to stdout instead.
#
# Includes additional -a flag for "additional" patterns.
###############################################################################

# Default ignore items (by name or partial path)
IGNORE_ITEMS=("build" "install" "cmake" "deps" ".vscode" "tests" ".git" ".venv_poetry" ".venv" ".cache_poetry" ".cache_pip" "__pycache__" ".cache" "vendor")

# By default, we skip 'test'/'mock' patterns unless -t is provided
INCLUDE_TEST=false

# Whether to write to file or stdout
WRITE_TO_STDOUT=false

# We collect any -O patterns, then split them into folder/file patterns
ONLY_PATTERNS=()

# We collect any -a (“additional”) patterns, then split them as well
ADD_PATTERNS=()

print_usage() {
  cat <<EOF
Usage: $0 [options]

Options:
  -t               Include 'test'/'mock' files in output (otherwise they're ignored)
  -i <pattern>     Add an ignore pattern (can be repeated multiple times).
                   Glob/wildcard patterns are supported (e.g. -i build*).
  -O <pattern>     Include pattern(s). If the pattern ends with '/', it is
                   treated as a FOLDER pattern (keeping default file extensions).
                   If it does not end with '/', it is treated as a FILE pattern
                   (overriding the default file extensions).
                   This flag can be specified multiple times and supports globs.
  -a <pattern>     Add an *additional* pattern. If it ends with '/', it is treated
                   as a folder pattern (just like -O). Otherwise it's a file
                   pattern. These do *not* override defaults or -O patterns, but
                   are merged with them.
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
    -a)
      if [[ -z "$2" ]]; then
        echo "Error: '-a' requires a pattern argument."
        exit 1
      fi
      ADD_PATTERNS+=("$2")
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
  STAT_CMD='stat -f "%m %N"'
else
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

###############################################################################
# Build an array for the `find` command's `-name` checks.
# (Used if we haven't overridden with -O file patterns.)
###############################################################################
DEFAULT_FILE_PATTERN_ARGS=()
for glob in "${DEFAULT_FILE_GLOBS[@]}"; do
  DEFAULT_FILE_PATTERN_ARGS+=( -name "$glob" -o )
done
unset 'DEFAULT_FILE_PATTERN_ARGS[${#DEFAULT_FILE_PATTERN_ARGS[@]}-1]'

###############################################################################
# Separate ONLY_PATTERNS into folder vs. file
###############################################################################
ONLY_FOLDER_PATTERNS=()
ONLY_FILE_PATTERNS=()

for pat in "${ONLY_PATTERNS[@]}"; do
  if [[ "$pat" == */ ]]; then
    folder="${pat%/}"
    ONLY_FOLDER_PATTERNS+=("$folder")
  else
    ONLY_FILE_PATTERNS+=("$pat")
  fi
done

###############################################################################
# Separate ADD_PATTERNS into folder vs. file
###############################################################################
ADD_FOLDER_PATTERNS=()
ADD_FILE_PATTERNS=()

for pat in "${ADD_PATTERNS[@]}"; do
  if [[ "$pat" == */ ]]; then
    folder="${pat%/}"
    ADD_FOLDER_PATTERNS+=("$folder")
  else
    ADD_FILE_PATTERNS+=("$pat")
  fi
done

###############################################################################
# Expand folder patterns (which may contain wildcards) into actual directories
###############################################################################
expand_folder_patterns() {
  local input_array=("$@")
  local expanded=()

  shopt -s nullglob globstar 2>/dev/null
  for folder_pat in "${input_array[@]}"; do
    matches=( $folder_pat ) # expands if possible
    if [ ${#matches[@]} -eq 0 ]; then
      echo "Warning: folder pattern '$folder_pat' did not match anything."
      continue
    fi
    for m in "${matches[@]}"; do
      if [ -d "$m" ]; then
        expanded+=("$m")
      else
        echo "Warning: '$m' is not a directory (from pattern '$folder_pat')."
      fi
    done
  done
  shopt -u nullglob globstar 2>/dev/null

  echo "${expanded[@]}"
}

# Expand the folder patterns from -O
EXPANDED_FOLDER_PATHS=()
if [ ${#ONLY_FOLDER_PATTERNS[@]} -gt 0 ]; then
  mapfile -t expanded_1 < <( expand_folder_patterns "${ONLY_FOLDER_PATTERNS[@]}" )
  EXPANDED_FOLDER_PATHS+=( "${expanded_1[@]}" )
fi

# Expand the folder patterns from -a
EXPANDED_ADDITIONAL_PATHS=()
if [ ${#ADD_FOLDER_PATTERNS[@]} -gt 0 ]; then
  mapfile -t expanded_2 < <( expand_folder_patterns "${ADD_FOLDER_PATTERNS[@]}" )
  EXPANDED_ADDITIONAL_PATHS+=( "${expanded_2[@]}" )
fi

###############################################################################
# build_prune_patterns(): Build a PRUNE_PATTERNS array from IGNORE_ITEMS.
###############################################################################
build_prune_patterns() {
  PRUNE_PATTERNS=()
  for item in "${IGNORE_ITEMS[@]}"; do
    clean_item="${item%/}"

    if [[ "$clean_item" == *"*"* || "$clean_item" == *"?"* || "$clean_item" == *"["* ]]; then
      # wildcarded ignore
      PRUNE_PATTERNS+=( -path "*${clean_item}" -o -path "*${clean_item}/*" -o )
    else
      # literal
      PRUNE_PATTERNS+=( -path "*/${clean_item}" -o -path "*/${clean_item}/*" -o )
    fi
  done

  if [ ${#PRUNE_PATTERNS[@]} -gt 0 ]; then
    unset 'PRUNE_PATTERNS[${#PRUNE_PATTERNS[@]}-1]'
  fi
}

###############################################################################
# Print the directory structure
###############################################################################
print_directory_structure() {
  echo "Project Folder Structure:"
  echo "========================"

  build_prune_patterns

  indent_sed='s|[^/]*/|  |g'

  # Combine the two sets of expanded paths
  ALL_FOLDERS_TO_DISPLAY=("${EXPANDED_FOLDER_PATHS[@]}" "${EXPANDED_ADDITIONAL_PATHS[@]}")

  if [ ${#ALL_FOLDERS_TO_DISPLAY[@]} -eq 0 ]; then
    # No specific folders => print from .
    find . \( \( "${PRUNE_PATTERNS[@]}" \) -prune \) -o -type d -print \
      | sed -e "$indent_sed"
    return
  fi

  # Print each subtree
  declare -A seen
  for folder in "${ALL_FOLDERS_TO_DISPLAY[@]}"; do
    if [[ -n "${seen[$folder]}" ]]; then
      continue
    fi
    seen[$folder]=1

    echo
    echo "Directory subtree for: $folder"
    echo "--------------------------------"
    find "$folder" \( \( "${PRUNE_PATTERNS[@]}" \) -prune \) -o -type d -print \
      | sed -e "$indent_sed"
  done
}

###############################################################################
# Make a find expression array (properly spaced) for a list of file patterns.
# We'll return them line-by-line so the caller can read them into an array.
###############################################################################
make_find_expr() {
  local patterns=("$@")

  # Start with: -type f (
  # Then for each pattern => either "-path <pat>" or "-name <pat>"
  # Finally ) -print
  # We'll print each token on its own line for safe array reassembly.
  echo "-type"
  echo "f"
  echo "("

  local first=true
  for pat in "${patterns[@]}"; do
    if [ "$first" = true ]; then
      first=false
    else
      echo "-o"
    fi

    if [[ "$pat" == *"/"* ]]; then
      [[ "$pat" != ./* ]] && pat="./$pat"
      echo "-path"
      echo "$pat"
    else
      echo "-name"
      echo "$pat"
    fi
  done

  echo ")"
  echo "-print"
}

###############################################################################
# Print file contents (sorted by modification time ascending)
###############################################################################
print_file_contents() {
  echo
  echo "Files with Contents:"
  echo "===================="

  build_prune_patterns

  # Decide final set of file patterns
  FINAL_FILE_PATTERNS=()
  if [ ${#ONLY_FILE_PATTERNS[@]} -gt 0 ]; then
    # -O file patterns override defaults
    FINAL_FILE_PATTERNS+=( "${ONLY_FILE_PATTERNS[@]}" )
  else
    # use defaults
    FINAL_FILE_PATTERNS+=( "${DEFAULT_FILE_GLOBS[@]}" )
  fi

  # Then add the additional patterns
  if [ ${#ADD_FILE_PATTERNS[@]} -gt 0 ]; then
    FINAL_FILE_PATTERNS+=( "${ADD_FILE_PATTERNS[@]}" )
  fi

  # Decide which folders to search
  ALL_FOLDERS_TO_SEARCH=( "${EXPANDED_FOLDER_PATHS[@]}" "${EXPANDED_ADDITIONAL_PATHS[@]}" )
  if [ ${#ALL_FOLDERS_TO_SEARCH[@]} -eq 0 ]; then
    ALL_FOLDERS_TO_SEARCH=( "." )
  fi

  # Prepare the find expression in an array
  FIND_EXPR=()
  while IFS= read -r token; do
    FIND_EXPR+=( "$token" )
  done < <( make_find_expr "${FINAL_FILE_PATTERNS[@]}" )

  FOUND_FILES=()

  # Run find on each folder
  declare -A seenFolder
  for folder in "${ALL_FOLDERS_TO_SEARCH[@]}"; do
    # Avoid duplicates
    if [[ -n "${seenFolder[$folder]}" ]]; then
      continue
    fi
    seenFolder[$folder]=1

    readarray -t tmp_found < <(
      find "$folder" \
        \( \( "${PRUNE_PATTERNS[@]}" \) -prune \) -o \
        "${FIND_EXPR[@]}"
    )
    FOUND_FILES+=( "${tmp_found[@]}" )
  done

  if [ ${#FOUND_FILES[@]} -eq 0 ]; then
    return
  fi

  # Sort by modification time
  MOD_LIST=()
  for file in "${FOUND_FILES[@]}"; do
    LINE=$(eval "$STAT_CMD \"$file\" 2>/dev/null")
    [[ -n "$LINE" ]] && MOD_LIST+=( "$LINE" )
  done

  SORTED_LINES=$(printf "%s\n" "${MOD_LIST[@]}" | sort -k1,1n)

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
# Output the results (to stdout or to prompt_script.txt)
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

