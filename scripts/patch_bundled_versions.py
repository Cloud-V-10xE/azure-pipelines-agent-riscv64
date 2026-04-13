import sys

path = sys.argv[1]
with open(path) as f:
    lines = f.readlines()

result = []
i = 0
in_net8_block = False

while i < len(lines):
    line = lines[i]

    # Detect entering a net8.0 KnownAppHostPack or KnownRuntimePack block
    if ('KnownAppHostPack' in line or 'KnownRuntimePack' in line) and '"8.0"' in line:
        in_net8_block = True

    if in_net8_block:
        if 'AppHostRuntimeIdentifiers=' in line and 'linux-riscv64' not in line:
            line = line.replace('freebsd-arm64"', 'freebsd-arm64;linux-riscv64"')
        if 'RuntimePackRuntimeIdentifiers=' in line and 'linux-riscv64' not in line:
            line = line.replace('freebsd-arm64"', 'freebsd-arm64;linux-riscv64"')
        if '/>' in line:
            in_net8_block = False

    result.append(line)
    i += 1

with open(path, 'w') as f:
    f.writelines(result)

print("✅ Patched BundledVersions.props (net8.0 block only)")
