import os
import sys

def extract_codebase_content(root_dir):
    codebase_content = []
    
    for dirpath, _, filenames in os.walk(root_dir):
        for filename in filenames:
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


# Check for directory path input
if len(sys.argv) < 2:
    print("Usage: python script.py <directory-path>")
    sys.exit(1)

# Get the directory path from the command line argument
root_directory = sys.argv[1]

output = extract_codebase_content(root_directory)

# Save the output to a file or print it directly
with open("codebase_content.txt", "w") as output_file:
    output_file.write(output)

print("Codebase content has been extracted and saved to codebase_content.txt.")
