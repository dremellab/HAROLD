#!/usr/bin/env python3
# filepath: /project/dremel_lab/workflows/pipelines/CHAPLIN/dev_cud2td/find_singularity_bind_paths.py

import os
import re
import sys

def find_linux_paths(file_content):
    """
    Extract Linux paths from the given file content.
    """
    # Regex to match Linux paths (e.g., /path/to/something)
    path_pattern = re.compile(r'(/(?:[a-zA-Z0-9_\-\.]+/)*[a-zA-Z0-9_\-\.]+)')
    return path_pattern.findall(file_content)

def filter_existing_paths(paths):
    """
    Filter out paths that do not exist on the filesystem.
    """
    return [path for path in paths if os.path.exists(path)]

def get_n_deep_prefix(path, n=4):
    """
    Truncate the path to the first 'n' directory levels.
    """
    parts = path.strip("/").split("/")
    if len(parts) >= n:
        return "/" + "/".join(parts[:n])
    return None

def main():
    if len(sys.argv) < 2:
        print("Usage: python3 find_singularity_bind_paths.py <file1> <file2> ...")
        sys.exit(1)

    input_files = sys.argv[1:]
    all_paths = set()

    for file_path in input_files:
        if not os.path.isfile(file_path):
            print(f"Warning: {file_path} is not a valid file. Skipping.")
            continue

        with open(file_path, 'r') as file:
            content = file.read()
            paths = find_linux_paths(content)
            all_paths.update(paths)

    # Filter paths that exist
    valid_paths = filter_existing_paths(all_paths)

    # Keep only paths at least 4 directories deep
    four_deep = filter(None, (get_n_deep_prefix(path, n=4) for path in valid_paths))

    # Get unique common 4-deep prefixes
    unique_base_paths = sorted(set(four_deep))

    # Print them as comma-separated list
    print(",".join(unique_base_paths))


if __name__ == "__main__":
    main()