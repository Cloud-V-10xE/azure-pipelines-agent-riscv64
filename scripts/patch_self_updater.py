import sys, re

path = sys.argv[1]
with open(path) as f:
    content = f.read()

pattern = r'(private async Task<bool> UpdateNeeded\([^)]*\)\s*\{)'
replacement = (
    r'\1\n'
    '            // Auto-update disabled: no linux-riscv64 package exists on releases\n'
    '            Trace.Info($"Auto-update disabled for RISC-V build. Skipping update check.");\n'
    '            return false;\n'
    '#pragma warning disable CS0162'
)

new_content, n = re.subn(pattern, replacement, content, count=1)
if n == 0:
    print("ERROR: Could not find UpdateNeeded() method")
    sys.exit(1)

with open(path, 'w') as f:
    f.write(new_content)

print("✅ Patched SelfUpdater.cs")