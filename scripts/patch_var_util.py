import sys, re

path = sys.argv[1]
with open(path) as f:
    content = f.read()

pattern = r'(case Architecture\.Arm64:\s*\n\s*return "ARM64";)'
replacement = r'\1\n                case (Architecture)9:\n                    return "RISCV64";'

new_content, n = re.subn(pattern, replacement, content, count=1)
if n == 0:
    print("ERROR: Could not find Arm64 case in VarUtil.cs")
    sys.exit(1)

with open(path, 'w') as f:
    f.write(new_content)

print("✅ Patched VarUtil.cs")