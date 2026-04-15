import sys, re

path = sys.argv[1]
with open(path) as f:
    content = f.read()

# 1. Add linux-riscv64 to valid RIDs
if 'linux-riscv64' not in content.split('_VALID_RIDS=')[1].split('\n')[0]:
    content = re.sub(
        r"(_VALID_RIDS='[^']+)(win-arm64')",
        r"\1win-arm64:linux-riscv64'",
        content,
        count=1
    )
    print("✅ Added linux-riscv64 to _VALID_RIDS")
else:
    print("ℹ️  _VALID_RIDS already contains linux-riscv64")

# 2. Add riscv64 uname detection
if 'riscv64) RUNTIME_ID="linux-riscv64"' not in content:
    content = content.replace(
        'aarch64) RUNTIME_ID="linux-arm64";;',
        'aarch64) RUNTIME_ID="linux-arm64";;\n            riscv64) RUNTIME_ID="linux-riscv64";;'
    )
    print("✅ Added riscv64 uname detection")
else:
    print("ℹ️  riscv64 uname detection already present")

# 3. Stub out restore_sdk_and_runtime to prevent downloading non-existent RISC-V net8 SDK
if 'RISCV_SDK_SKIP' not in content:
    content = re.sub(
        r'(function restore_sdk_and_runtime\(\) \{)',
        r'\1\n    # RISCV_SDK_SKIP: use pre-installed SDK from DOTNET_ROOT\n    echo "Using pre-installed SDK at: ${DOTNET_ROOT}"\n    return 0',
        content,
        count=1
    )
    print("✅ Stubbed out restore_sdk_and_runtime")
else:
    print("ℹ️  restore_sdk_and_runtime already stubbed")

# 4. Fix the PATH setup block to use DOTNET_ROOT instead of DOTNET_DIR/sdk/VERSION
# After restore_sdk_and_runtime, dev.sh does:
#   export PATH=${DOTNET_DIR}/sdk/${DOTNET_SDK_VERSION}:${DOTNET_DIR}:$PATH
# We need it to use DOTNET_ROOT
if 'DOTNET_DIR}/sdk/${DOTNET_SDK_VERSION}' in content:
    content = content.replace(
        'export PATH=${DOTNET_DIR}/sdk/${DOTNET_SDK_VERSION}:${DOTNET_DIR}:$PATH',
        'export PATH=${DOTNET_ROOT}:$PATH'
    )
    print("✅ Fixed PATH to use DOTNET_ROOT")
else:
    print("ℹ️  PATH already patched or not found")

with open(path, 'w') as f:
    f.write(content)
