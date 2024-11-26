import os
import sys
import argparse

def extract_codebase_content(root_dir, include_tests=False):
    codebase_content = []
    
    for dirpath, dirnames, filenames in os.walk(root_dir):
        # Exclude specific directories
        dirnames[:] = [d for d in dirnames if d not in ['.git', '.cache', 'build', 'install']]
        
        # If not including tests, ignore directories with "test" or "mock" in the name
        if not include_tests:
            dirnames[:] = [d for d in dirnames if 'test' not in d.lower() and 'mock' not in d.lower()]
        
        for filename in filenames:
            # Ignore files with "test" or "mock" in the name if not including tests
            # and ignore "codebase_content.txt"
            if (not include_tests and ('test' in filename.lower() or 'mock' in filename.lower())) or filename == "codebase_content.txt":
                continue
            
            # Construct the file's relative path
            relative_path = os.path.relpath(os.path.join(dirpath, filename), root_dir)
            file_path = os.path.join(dirpath, filename)
            
            # Read the file's content
            try:
                with open(file_path, 'r') as file:
                    file_content = file.read()
                
                # Append labeled content to the list
                codebase_content.append(f"## {relative_path}\n\n{file_content}\n")
            except Exception as e:
                print(f"Error reading {file_path}: {e}")

    # Join all labeled contents into a single string
    return "\n".join(codebase_content)


# Set up argument parser
parser = argparse.ArgumentParser(description="Extract codebase content from a directory.")
parser.add_argument("directory", help="Path to the root directory of the codebase")
parser.add_argument("-t", "--include-tests", action="store_true", 
                    help="Include files and folders with 'test' or 'mock' in the name")

# Parse arguments
args = parser.parse_args()

# Get the directory path and include_tests flag from arguments
root_directory = args.directory
include_tests = args.include_tests

output = extract_codebase_content(root_directory, include_tests=include_tests)

# Save the output to a file
with open("codebase_content.txt", "w") as output_file:
    output_file.write(output)

# Print the output to the console
print(output)

