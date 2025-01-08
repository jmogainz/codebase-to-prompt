import ast

def remove_comments_docstrings_and_bodies(source):
    """
    Removes comments, docstrings, and function bodies from the given Python source code.
    """
    class FunctionBodyRemover(ast.NodeTransformer):
        def visit_FunctionDef(self, node):
            # Remove the function body, keep the signature and docstring placeholder
            node.body = [ast.Pass()]  # Replace the function body with a `pass` statement
            return node

        def visit_AsyncFunctionDef(self, node):
            # Handle async functions as well
            node.body = [ast.Pass()]
            return node

        def visit_ClassDef(self, node):
            # Recursively remove function bodies inside classes
            node.body = [self.visit(child) if isinstance(child, (ast.FunctionDef, ast.AsyncFunctionDef)) else child for child in node.body]
            return node

    # Parse source to AST
    parsed_ast = ast.parse(source)

    # Remove docstrings
    def remove_docstrings(node):
        if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef, ast.ClassDef, ast.Module)):
            if node.body and isinstance(node.body[0], ast.Expr) and isinstance(node.body[0].value, ast.Str):
                node.body.pop(0)  # Remove the first expression if it's a docstring
        for child in ast.iter_child_nodes(node):
            remove_docstrings(child)

    remove_docstrings(parsed_ast)

    # Remove function bodies
    FunctionBodyRemover().visit(parsed_ast)

    # Convert back to source code
    cleaned_code = ast.unparse(parsed_ast)

    return cleaned_code

def process_file(file_path):
    with open(file_path, "r") as f:
        source_code = f.read()

    cleaned_code = remove_comments_docstrings_and_bodies(source_code)

    with open(file_path, "w") as f:
        f.write(cleaned_code)
    print(f"Comments, docstrings, and function bodies removed from {file_path}")

# Usage:
file_path = "temp.py"  # Replace with the path to your Python file
process_file(file_path)
