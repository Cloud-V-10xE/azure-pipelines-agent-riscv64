#!/usr/bin/env python3
"""
Patches all *.runtimeconfig.json files in the agent layout bin directory.
Converts self-contained (includedFrameworks) configs to framework-dependent,
targeting Microsoft.NETCore.App 10.0.2 with LatestMinor roll-forward.

Usage: python3 patch_runtimeconfig.py <layout_bin_dir>
"""

import sys
import json
from pathlib import Path

def patch_runtimeconfig(path: Path):
    with open(path) as f:
        cfg = json.load(f)

    opts = cfg.get('runtimeOptions', {})

    # Convert from self-contained (includedFrameworks) to framework-dependent
    if 'includedFrameworks' in opts:
        del opts['includedFrameworks']

    opts['framework'] = {'name': 'Microsoft.NETCore.App', 'version': '10.0.2'}
    opts['rollForward'] = 'LatestMinor'

    with open(path, 'w') as f:
        json.dump(cfg, f, indent=2)

    print(f'  Patched {path}')

def main():
    if len(sys.argv) < 2:
        print(f"Usage: {sys.argv[0]} <layout_bin_dir>", file=sys.stderr)
        sys.exit(1)

    bin_dir = Path(sys.argv[1])
    if not bin_dir.is_dir():
        print(f"Error: directory not found: {bin_dir}", file=sys.stderr)
        sys.exit(1)

    configs = list(bin_dir.rglob('*.runtimeconfig.json'))
    if not configs:
        print("  No *.runtimeconfig.json files found, nothing to patch.")
        sys.exit(0)

    for config_path in configs:
        patch_runtimeconfig(config_path)

    print(f'✅ Patched {len(configs)} runtimeconfig file(s)')

if __name__ == '__main__':
    main()
