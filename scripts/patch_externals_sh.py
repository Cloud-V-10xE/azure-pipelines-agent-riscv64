import sys, re

path = sys.argv[1]
with open(path) as f:
    content = f.read()

if 'linux-riscv64' in content:
    print("ℹ️  externals.sh already patched")
    sys.exit(0)

# We insert an elif block for linux-riscv64 just before the closing else block.
# For riscv64 we skip node6/10/16 (no builds exist) and use unofficial node20/node24.
# The acquireExternalTool call signature is: url, dest_dir, [extract_fn], [dont_uncompress], [rename]
# We use the same pattern as the else block but with unofficial URLs.
# Since unofficial-builds uses a different tarball name format we handle manually via a
# simple wget+tar inside the elif — bypassing acquireExternalTool entirely.

riscv64_block = '''    elif [[ "$PACKAGERUNTIME" == "linux-riscv64" ]]; then
        echo "Using unofficial Node.js builds for linux-riscv64"

        # Hardcoded to versions that actually have RISC-V unofficial builds
        NODE20_RISCV_VERSION="20.9.0"
        NODE24_RISCV_VERSION="24.7.0"
        NODE20_RISCV_URL="https://unofficial-builds.nodejs.org/download/release/v${NODE20_RISCV_VERSION}/node-v${NODE20_RISCV_VERSION}-linux-riscv64.tar.gz"
        NODE24_RISCV_URL="https://github.com/alitariq4589/nodejs-riscv/releases/download/v${NODE24_RISCV_VERSION}/nodejs-${NODE24_RISCV_VERSION}-riscv64-linux.tar.gz"

        mkdir -p "$LAYOUT_DIR/externals/node20_1/bin"
        echo "Downloading Node.js ${NODE20_RISCV_VERSION} for riscv64..."
        wget -qO- "$NODE20_RISCV_URL" | tar -xz -C "$LAYOUT_DIR/externals/node20_1" --strip-components=1

        mkdir -p "$LAYOUT_DIR/externals/node24/bin"
        echo "Downloading Node.js ${NODE24_RISCV_VERSION} for riscv64..."
        wget -qO- "$NODE24_RISCV_URL" | tar -xz -C "$LAYOUT_DIR/externals/node24" --strip-components=1

        chmod +x "$LAYOUT_DIR/externals/node20_1/bin/node" || true
        chmod +x "$LAYOUT_DIR/externals/node24/bin/node" || true
        echo "✅ Node.js externals set up for linux-riscv64"
'''

# Insert before the else block
old = '    else\n        case $PACKAGERUNTIME in'
new = riscv64_block + '    else\n        case $PACKAGERUNTIME in'

if old not in content:
    print("ERROR: Could not find insertion point in externals.sh")
    print("Looking for:")
    print(repr(old))
    sys.exit(1)

content = content.replace(old, new, 1)

with open(path, 'w') as f:
    f.write(content)

print("✅ Patched externals.sh for linux-riscv64")
