import sys
import re
import subprocess
from pathlib import Path

def run_cmd(cmd):
    print(f"Running: {' '.join(cmd)}")
    subprocess.run(cmd, check=True)

def main():
    if len(sys.argv) != 2:
        print("Usage: python release.py <new_version>")
        sys.exit(1)

    new_version = sys.argv[1]
    
    # Path to _meta.lua relative to this script's location
    meta_path = Path(__file__).parent.parent / "xray.koplugin" / "_meta.lua"
    
    if not meta_path.exists():
        print(f"Error: Could not find {meta_path}")
        sys.exit(1)
        
    print(f"Updating version to {new_version} in {meta_path.name}")
    content = meta_path.read_text(encoding="utf-8")
    
    # Find and replace the version string
    new_content, count = re.subn(r'version\s*=\s*"[^"]+"', f'version = "{new_version}"', content)
    
    if count == 0:
        print("Error: Could not find version string in _meta.lua")
        sys.exit(1)
        
    meta_path.write_text(new_content, encoding="utf-8")
    print("Version updated successfully.")
    
    # Git operations
    print("Executing git commands...")
    try:
        run_cmd(["git", "add", str(meta_path.resolve())])
        run_cmd(["git", "commit", "-m", f"Release {new_version}"])
        run_cmd(["git", "push"])
        run_cmd(["git", "tag", new_version])
        run_cmd(["git", "push", "origin", new_version])
        print(f"\n✅ Release {new_version} completed and pushed successfully!")
    except subprocess.CalledProcessError as e:
        print(f"Error during git operations: {e}")
        sys.exit(1)

if __name__ == "__main__":
    main()
