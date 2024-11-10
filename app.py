import os
import sys
import argparse

def extract_codebase_content(root_dir, include_tests=False):
    codebase_content = []
    
    for dirpath, dirnames, filenames in os.walk(root_dir):
        # If not including tests, ignore directories with "test" in the name
        if not include_tests:
            dirnames[:] = [d for d in dirnames if 'test' not in d.lower()]
        
        for filename in filenames:
            # Ignore files with "test" in the name if not including tests
            if not include_tests and 'test' in filename.lower():
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
                    help="Include files and folders with 'test' in the name")

# Parse arguments
args = parser.parse_args()

# Get the directory path and include_tests flag from arguments
root_directory = args.directory
include_tests = args.include_tests

output = extract_codebase_content(root_directory, include_tests=include_tests)

# Save the output to a file
with open("codebase_content.txt", "w") as output_file:
    output_file.write(output)

print("Codebase content has been extracted and saved to codebase_content.txt.")
