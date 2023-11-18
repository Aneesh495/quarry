#!/usr/bin/env python3
import sys
import os

def check_file(filepath):
    errors = []
    try:
        with open(filepath, 'r', encoding='utf-8', errors='replace') as f:
            for line_no, line in enumerate(f, 1):
                if '\u2014' in line:
                    errors.append(f"{filepath}:{line_no}: Contains em dash (\\u2014): {line.strip()}")
                if '\u2013' in line:
                    errors.append(f"{filepath}:{line_no}: Contains en dash (\\u2013): {line.strip()}")
    except Exception as e:
        errors.append(f"{filepath}: Error reading: {e}")
    return errors

def main():
    root_dir = os.path.dirname(os.path.abspath(__file__))
    total_errors = []
    checked_count = 0
    
    for dirpath, dirnames, filenames in os.walk(root_dir):
        if '.git' in dirpath:
            continue
        for fname in filenames:
            ext = os.path.splitext(fname)[1].lower()
            if ext in ['.t', '.lua', '.md', '.txt', '.py', '.sh', '.c', '.h', '.html', '.css', '.js', '.json', '.yaml', '.yml']:
                filepath = os.path.join(dirpath, fname)
                checked_count += 1
                errors = check_file(filepath)
                if errors:
                    total_errors.extend(errors)
                    
    print(f"Checked {checked_count} files for em dashes and en dashes.")
    if total_errors:
        print(f"FAILED: Found {len(total_errors)} violations:")
        for err in total_errors:
            print("  " + err)
        sys.exit(1)
    else:
        print("PASSED: Zero em dashes or en dashes found across all files.")
        sys.exit(0)

if __name__ == '__main__':
    main()
