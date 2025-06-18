#!/usr/bin/env bash

###############################################################################
# project.sh
#
# Generates a simple directory tree and file contents, sorted by modification
# time ascending (oldest first => newest last). By default, it writes to
# "prompt_script.txt", but if you pass `--stdout`, it writes to stdout instead.
#
# Includes additional -a flag for "additional" patterns that override ignores.
###############################################################################

# Default ignore items (by name or partial path)
IGNORE_ITEMS=("build" "install" "cmake" ".vscode" ".git" ".venv_poetry" ".venv" ".cache_poetry" ".cache_pip" "__pycache__" ".cache" "vendor" "node_modules" "dist" ".dart_tool" ".cxx" ".null*" "generated")

# By default, we skip 'test'/'mock' patterns unless -t is provided
INCLUDE_TEST=false

# Whether to write to file or stdout
WRITE_TO_STDOUT=false

# Default output file (can be overridden with -o)
OUTPUT_FILE="prompt_script.txt"

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
  -o <file>        Write output to <file> instead of the default prompt_script.txt
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
    -o)
      if [[ -z "$2" ]]; then
        echo "Error: '-o' requires a file path argument."
        exit 1
      fi
      OUTPUT_FILE="$2"
      WRITE_TO_STDOUT=false   # ensure we don’t also write to stdout
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
  IGNORE_ITEMS+=("tests")
  IGNORE_ITEMS+=("test")
  IGNORE_ITEMS+=("*_test.*")
  IGNORE_ITEMS+=("mock")
fi

# Add the (possibly overridden) output file to ignore list
IGNORE_ITEMS+=("$OUTPUT_FILE")

###############################################################################
# Decide which 'stat' command to use based on OS (macOS vs. Linux)
###############################################################################
STAT_CMD='stat -c "%Y %n"'

###############################################################################
# Define the default file extensions in ONE place
###############################################################################
DEFAULT_FILE_GLOBS=(
  "*.py"
  "*.h"
  "*.hpp"
  "*.c"
  "*.cpp"
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
  "*.dart"
  "*.js"
  "*.html"
  "*.css"
)

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

# ---------------------------------------------------------------------------
# Treat any -a *file* patterns as global additions.
# By appending them to DEFAULT_FILE_GLOBS, they’re picked up by every search
# that relies on the default glob list (without altering the existing logic
# for -O or per-folder overrides).
# ---------------------------------------------------------------------------
if [ ${#ADD_FILE_PATTERNS[@]} -gt 0 ]; then
  DEFAULT_FILE_GLOBS+=( "${ADD_FILE_PATTERNS[@]}" )
fi

###############################################################################
# Expand folder patterns (which may contain wildcards) into actual directories
###############################################################################
expand_folder_patterns() {
  local input_array=("$@")
  local expanded=()

  shopt -s nullglob globstar 2>/dev/null
  for folder_pat in "${input_array[@]}"; do
    matches=( $folder_pat )
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

  # IMPORTANT: Print each path on its own line
  for e in "${expanded[@]}"; do
    echo "$e"
  done
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

# -------------------------------------------------------------------
# If the user supplied -a <file> but *no* -a <folder> **and** there are
# still no folder scopes from -O, fall back to scanning project root (".").
# Otherwise, rely on the folder scopes that already exist.
# -------------------------------------------------------------------
if [[ ${#ADD_FILE_PATTERNS[@]} -gt 0 \
   && ${#EXPANDED_ADDITIONAL_PATHS[@]} -eq 0 \
   && ${#EXPANDED_FOLDER_PATHS[@]}    -eq 0 ]]; then
  EXPANDED_ADDITIONAL_PATHS+=( "." )
fi

for pat in "${ADD_FILE_PATTERNS[@]}"; do
  if [[ "$pat" == */* ]]; then
    dir="${pat%/*}"
    if [ -d "$dir" ]; then
      EXPANDED_ADDITIONAL_PATHS+=( "$dir" )
    else
      echo "Warning: directory '$dir' for additional pattern '$pat' not found."
    fi
  fi
done

# We’ll collect all forcibly included directories here (from -a), so we
# can skip ignoring them in our prune logic.
FORCED_INCLUDES=("${EXPANDED_ADDITIONAL_PATHS[@]}")

###############################################################################
# build_prune_patterns(): build PRUNE_PATTERNS from IGNORE_ITEMS,
# making sure a pattern matches at any depth (GNU/BSD find) and never
# prunes paths that were explicitly forced in with -a.
###############################################################################
build_prune_patterns() {
  PRUNE_PATTERNS=()

  # ------------------------------------------------------------------
  # 1.  Add one “prune”-test for every ignore token
  #     • leading "*/" lets the match occur no matter how deep it sits
  #     • second test with trailing "/*" also skips everything beneath
  # ------------------------------------------------------------------
  for item in "${IGNORE_ITEMS[@]}"; do
    clean_item="${item%/}"                  # strip trailing “/” if present
    PRUNE_PATTERNS+=(
      -path "*/${clean_item}"  -o           # ignore the file/dir itself
      -path "*/${clean_item}/*" -o          # …and anything inside it
    )
  done

  # drop the final “-o” so the expression is syntactically correct
  if [ ${#PRUNE_PATTERNS[@]} -gt 0 ]; then
    unset 'PRUNE_PATTERNS[${#PRUNE_PATTERNS[@]}-1]'
  fi

  # ------------------------------------------------------------------
  # 2.  If the user forced directories in via -a, make sure we *don’t*
  #     prune those (or anything under them)
  # ------------------------------------------------------------------
  if [ ${#FORCED_INCLUDES[@]} -gt 0 ]; then
    local forced_expr=()
    for f in "${FORCED_INCLUDES[@]}"; do
      f="${f#./}"                           # drop leading “./” if any
      [[ -z "$f" || "$f" == "." ]] && continue
      forced_expr+=(
        -path "*/${f}"    -o
        -path "*/${f}/*"  -o
      )
    done
    # trim trailing “-o”
    if [ ${#forced_expr[@]} -gt 0 ]; then
      unset 'forced_expr[${#forced_expr[@]}-1]'
      # keep: (ignore rules) AND NOT (forced-include rules)
      PRUNE_PATTERNS=( "(" "${PRUNE_PATTERNS[@]}" ")" -a -not "(" "${forced_expr[@]}" ")" )
    fi
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

  # If no -O folder patterns were given, we just show the entire project
  # from ".", ignoring prunes (but forced includes remain).
  if [ ${#EXPANDED_FOLDER_PATHS[@]} -eq 0 ]; then
    find . \( \( "${PRUNE_PATTERNS[@]}" \) -prune \) -o -type d -print | sed -e "$indent_sed"
    return
  fi

  # Otherwise, we unify the -O folder paths with any -a folder paths, and list each.
  declare -A seen
  ALL_FOLDERS_TO_DISPLAY=()

  for f in "${EXPANDED_FOLDER_PATHS[@]}" "${EXPANDED_ADDITIONAL_PATHS[@]}"; do
    if [[ -n "$f" && -z "${seen[$f]}" ]]; then
      seen[$f]=1
      ALL_FOLDERS_TO_DISPLAY+=( "$f" )
    fi
  done

  for folder in "${ALL_FOLDERS_TO_DISPLAY[@]}"; do
    echo
    echo "Directory subtree for: $folder"
    echo "--------------------------------"
    find "$folder" \( \( "${PRUNE_PATTERNS[@]}" \) -prune \) -o -type d -print \
      | sed -e "$indent_sed"
  done
}

###############################################################################
# Make a find expression array (properly spaced) for a list of file patterns.
###############################################################################
make_find_expr() {
  local patterns=("$@")
  # We'll output lines so the caller can read into an array

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

  FOUND_FILES=()

  # 1) If we have -O folders, use them (with only-file-patterns or defaults)
  if [ ${#EXPANDED_FOLDER_PATHS[@]} -gt 0 ]; then
    if [ ${#ONLY_FILE_PATTERNS[@]} -gt 0 ]; then
      search_patterns=( "${ONLY_FILE_PATTERNS[@]}" )
    else
      search_patterns=( "${DEFAULT_FILE_GLOBS[@]}" )
    fi

    FIND_EXPR_ONLY=()
    while IFS= read -r token; do
      FIND_EXPR_ONLY+=( "$token" )
    done < <( make_find_expr "${search_patterns[@]}" )

    for folder in "${EXPANDED_FOLDER_PATHS[@]}"; do
      readarray -t tmp < <(
        find "$folder" \
          \( \( "${PRUNE_PATTERNS[@]}" \) -prune \) -o \
          "${FIND_EXPR_ONLY[@]}"
      )
      FOUND_FILES+=( "${tmp[@]}" )
    done
  fi

  # 2) Process the -a folders (if any), using -a file patterns or defaults
  if [ ${#EXPANDED_ADDITIONAL_PATHS[@]} -gt 0 ]; then

    # Only add '.' if we *still* have nothing to search.  This prevents the
    # project root from being scanned a second time and producing duplicates.
    if [ ${#EXPANDED_ADDITIONAL_PATHS[@]} -eq 0 ]; then
      EXPANDED_ADDITIONAL_PATHS+=( "." )
    fi

    if [ ${#ADD_FILE_PATTERNS[@]} -gt 0 ]; then
      search_patterns=( "${ADD_FILE_PATTERNS[@]}" )
    else
      search_patterns=( "${DEFAULT_FILE_GLOBS[@]}" )
    fi

    FIND_EXPR_ADD=()
    while IFS= read -r token; do
      FIND_EXPR_ADD+=( "$token" )
    done < <( make_find_expr "${search_patterns[@]}" )

    for folder in "${EXPANDED_ADDITIONAL_PATHS[@]}"; do
      readarray -t tmp < <(
        find "$folder" \
          \( \( "${PRUNE_PATTERNS[@]}" \) -prune \) -o \
          "${FIND_EXPR_ADD[@]}"
      )
      FOUND_FILES+=( "${tmp[@]}" )
    done
  fi

  # 3) If no -O folders were given, fall back to searching "." with default globs
  if [ ${#EXPANDED_FOLDER_PATHS[@]} -eq 0 ]; then
    FIND_EXPR_DEFAULT=()
    while IFS= read -r token; do
      FIND_EXPR_DEFAULT+=( "$token" )
    done < <( make_find_expr "${DEFAULT_FILE_GLOBS[@]}" )

    readarray -t tmp < <(
      find . \
        \( \( "${PRUNE_PATTERNS[@]}" \) -prune \) -o \
        "${FIND_EXPR_DEFAULT[@]}"
    )
    FOUND_FILES+=( "${tmp[@]}" )
  fi

  [ ${#FOUND_FILES[@]} -eq 0 ] && return

  # -----------------------------------------------------------------
  # Deduplicate paths that can appear with and without a leading "./"
  # (e.g., "./worker-app/…" vs "worker-app/…").
  # -----------------------------------------------------------------
  if [ ${#FOUND_FILES[@]} -gt 1 ]; then
    declare -A _seen
    _uniq=()
    for _f in "${FOUND_FILES[@]}"; do
      _norm="${_f#./}"                # remove leading "./" if present
      [[ -n "${_seen["$_norm"]}" ]] && continue
      _uniq+=( "$_f" )
      _seen["$_norm"]=1
    done
    FOUND_FILES=( "${_uniq[@]}" )
  fi

  # Sort by mtime ascending, then print
  MOD_LIST=()
  for file in "${FOUND_FILES[@]}"; do
    LINE=$(eval "$STAT_CMD \"$file\"" 2>/dev/null)
    [[ -n "$LINE" ]] && MOD_LIST+=( "$LINE" )
  done

  sort_lines=$(printf "%s\n" "${MOD_LIST[@]}" | sort -k1,1nr)
  while IFS= read -r line; do
    path="${line#* }"
    echo
    echo "==== $path ===="
    echo
    cat "$path"
  done <<< "$sort_lines"
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

