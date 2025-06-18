# Codebase-to-Prompt Generator

A Bash script that generates a comprehensive overview of your project structure and file contents, optimized for sharing with AI coding assistants.

## Features

- **Directory Tree**: Generates a clean directory structure view
- **File Contents**: Includes source code with modification time sorting (oldest first)
- **Smart Filtering**: Built-in ignore patterns for common build artifacts, dependencies, and cache directories
- **Flexible Output**: Write to file or stdout
- **Pattern Control**: Include/exclude specific files and folders with glob support
- **Test File Handling**: Optional inclusion of test and mock files

## Usage

```bash
./project.sh [options]
```

### Options

- `-t` - Include test/mock files (otherwise ignored)
- `-i <pattern>` - Add ignore pattern (supports globs, can repeat)
- `-O <pattern>` - Include only specific patterns (folder/ or file patterns)
- `-a <pattern>` - Add additional patterns without overriding defaults
- `-o <file>` - Custom output file (default: `prompt_script.txt`)
- `--stdout` - Print to stdout instead of file
- `-h, --help` - Show help

### Examples

```bash
# Basic usage - generates prompt_script.txt
./project.sh

# Include test files and output to stdout
./project.sh -t --stdout

# Only include Go files from specific directories
./project.sh -O "src/" -O "*.go"

# Add TypeScript files to default patterns
./project.sh -a "*.ts" -a "*.tsx"

# Custom ignore patterns
./project.sh -i "temp*" -i "*.log"
```

## Default File Types

Automatically includes: Python, C/C++, Go, Shell, Lua, SQL, Dart, JavaScript, HTML, CSS, Makefiles, Dockerfiles, TOML, and environment files.

## Output Format

1. **Directory Structure** - Hierarchical view of folders
2. **File Contents** - Each file with header and full content, sorted by modification time

Perfect for providing context to AI coding assistants while keeping output focused and relevant.
