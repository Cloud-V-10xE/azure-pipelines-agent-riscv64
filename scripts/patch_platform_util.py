import sys, re

path = sys.argv[1]
with open(path) as f:
    content = f.read()

pattern = r'(public static bool IsArm64 => PlatformUtil\.HostArchitecture == Architecture\.Arm64;)'
replacement = r'\1\n\n        public static bool IsRiscV64 => PlatformUtil.HostArchitecture == Architecture.RiscV64;'

new_content, n = re.subn(pattern, replacement, content, count=1)
if n == 0:
    print("WARNING: Could not find IsArm64 property - skipping")
    sys.exit(0)

with open(path, 'w') as f:
    f.write(new_content)

print("✅ Patched PlatformUtil.cs")