import sys
import os
import re

def merge_config(new_cfg_path, backup_cfg_path):
    if not os.path.exists(backup_cfg_path):
        return

    with open(backup_cfg_path, 'r') as f:
        backup_content = f.read()

    with open(new_cfg_path, 'r') as f:
        new_content = f.read()

    keys = [
        "gemini_api_key", "chatgpt_api_key", "deepseek_api_key", "claude_api_key",
        "custom1_api_key", "custom1_endpoint", "custom1_model", "custom1_format", "custom1_headers",
        "custom2_api_key", "custom2_endpoint", "custom2_model", "custom2_format", "custom2_headers"
    ]

    for key in keys:
        # Extract value from backup
        # Pattern matches the assignment of the key
        pattern = rf'[^\w]{key}\s*=\s*"([^"]*)"'
        match = re.search(pattern, backup_content)
        
        if match:
            val = match.group(1)
            if val:
                # Inject into new content only if the target is currently an empty string ""
                target_pattern = rf'({key}\s*=\s*)"([^"]*)"'
                
                def replace_func(m):
                    prefix = m.group(1)
                    current_val = m.group(2)
                    if not current_val:
                        return f'{prefix}"{val}"'
                    return m.group(0)
                
                new_content = re.sub(target_pattern, replace_func, new_content)

    with open(new_cfg_path, 'w') as f:
        f.write(new_content)

if __name__ == "__main__":
    if len(sys.argv) < 3:
        sys.exit(1)
    merge_config(sys.argv[1], sys.argv[2])
