#!/usr/bin/env bash
set -euo pipefail

# ============================================================

# Cleanup and clone the repository

rm -rf azure-pipelines-agent

git clone --branch main https://github.com/microsoft/azure-pipelines-agent.git 

# ============================================================

# ============================================================
# build.sh - Local test build for Azure Pipelines Agent RISC-V
# Mirrors the GitHub Actions workflow.
# Run from the directory containing build.sh, scripts/, and azure-pipelines-agent/
# ============================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AGENT_DIR="$SCRIPT_DIR/azure-pipelines-agent"
SCRIPTS_DIR="$SCRIPT_DIR/scripts"

log()  { echo ""; echo "▶ $*"; }
ok()   { echo "  ✅ $*"; }
fail() { echo "  ❌ $*"; exit 1; }

# ============================================================
# Sanity checks
# ============================================================
[ -d "$AGENT_DIR" ] || fail "azure-pipelines-agent directory not found at $AGENT_DIR"
[ -d "$SCRIPTS_DIR" ] || fail "scripts directory not found at $SCRIPTS_DIR"
for s in patch_self_updater.py patch_var_util.py patch_bundled_versions.py patch_platform_util.py patch_runtimeconfig.py; do
  [ -f "$SCRIPTS_DIR/$s" ] || fail "Missing script: $SCRIPTS_DIR/$s"
done

# ============================================================
# Step: Install dependencies
# ============================================================
log "Install dependencies"
sudo apt-get update
sudo apt-get install -y liblttng-ust-dev libkrb5-dev zlib1g-dev libicu-dev \
  libssl-dev libcurl4-openssl-dev libelf-dev libunwind-dev pkg-config wget tar libatomic1 \
  patchelf binutils file

# ============================================================
# Step: Download and setup .NET 10.0.102 SDK
# ============================================================
log "Download and setup .NET 10.0.102 SDK"
cd "$AGENT_DIR"

if [ ! -f "_dotnetsdk/10.0.102/dotnet" ]; then
  wget -q --show-progress -O dotnet.tar.gz \
    https://github.com/filipnavara/dotnet-riscv/releases/download/10.0.102/dotnet-sdk-10.0.102-linux-riscv64.tar.gz
  mkdir -p _dotnetsdk/10.0.102
  tar -xf dotnet.tar.gz -C _dotnetsdk/10.0.102
  echo "10.0.102" > _dotnetsdk/10.0.102/.10.0.102
  rm dotnet.tar.gz
  ok "SDK extracted"
else
  ok "SDK already present, skipping download"
fi

export DOTNET_ROOT="$AGENT_DIR/_dotnetsdk/10.0.102"
export PATH="$DOTNET_ROOT:$PATH"
dotnet --version || fail "dotnet not working"

# ============================================================
# Step: Create net8.0 runtime packs from net10.0
# ============================================================
log "Create net8.0 runtime packs from net10.0"
cd "$AGENT_DIR"

SDK_ROOT="_dotnetsdk/10.0.102"
PACKS_DIR="$SDK_ROOT/packs"

NET10_RUNTIME_VERSION=$(ls -1 "$PACKS_DIR/Microsoft.NETCore.App.Runtime.linux-riscv64/" | head -1)
NET10_HOST_VERSION=$(ls -1   "$PACKS_DIR/Microsoft.NETCore.App.Host.linux-riscv64/"    | head -1)
NET10_ASPNET_VERSION=$(ls -1 "$PACKS_DIR/Microsoft.AspNetCore.App.Runtime.linux-riscv64/" | head -1)

echo "  net10.0 runtime : $NET10_RUNTIME_VERSION"
echo "  net10.0 host    : $NET10_HOST_VERSION"
echo "  net10.0 aspnet  : $NET10_ASPNET_VERSION"

NET8_VERSION="8.0.23"

for pair in \
  "Microsoft.NETCore.App.Runtime.linux-riscv64:$NET10_RUNTIME_VERSION" \
  "Microsoft.NETCore.App.Host.linux-riscv64:$NET10_HOST_VERSION" \
  "Microsoft.AspNetCore.App.Runtime.linux-riscv64:$NET10_ASPNET_VERSION"
do
  PACK="${pair%%:*}"
  SRC="${pair##*:}"
  if [ ! -d "$PACKS_DIR/$PACK/$NET8_VERSION" ]; then
    echo "  Creating $PACK/$NET8_VERSION"
    cp -r "$PACKS_DIR/$PACK/$SRC" "$PACKS_DIR/$PACK/$NET8_VERSION"
  else
    echo "  $PACK/$NET8_VERSION already exists"
  fi
done
ok "net8.0 runtime packs ready"

# ============================================================
# Step: Check for global.json and update SDK version
# ============================================================
log "Check for global.json and update if needed"
cd "$AGENT_DIR"

find . -name "global.json" -type f | while read -r json_file; do
  echo "  Found: $json_file"
  if grep -q "sdk" "$json_file"; then
    sed -i 's/"version".*:.*"[0-9].*"/"version": "10.0.102"/g' "$json_file"
    echo "    → patched"
  fi
done

# ============================================================
# Step: Patch dev.sh for RISC-V and .NET 10
# ============================================================
log "Patch dev.sh for RISC-V and .NET 10"
python3 "$SCRIPTS_DIR/patch_dev_sh.py" "$AGENT_DIR/src/dev.sh"

grep '_VALID_RIDS' "$AGENT_DIR/src/dev.sh" | grep -q 'linux-riscv64' \
  || fail "_VALID_RIDS patch did not apply!"
ok "dev.sh patched"


# Make chmod calls non-fatal for missing apphost binaries
sed -i '/chmod.*bin\/Agent\./s/$/ 2>\/dev\/null || true/' "$AGENT_DIR/src/dev.sh"


# ============================================================
# Step: Patch externals.sh for RISC-V
# ============================================================
log "Patch externals.sh for RISC-V"
python3 "$SCRIPTS_DIR/patch_externals_sh.py" "$AGENT_DIR/src/Misc/externals.sh"

grep -q 'linux-riscv64' "$AGENT_DIR/src/Misc/externals.sh" \
  || fail "externals.sh patch did not apply!"
ok "externals.sh patched"

# ============================================================
# Step: Patch SelfUpdater to disable auto-update
# ============================================================
log "Patch SelfUpdater.cs"
python3 "$SCRIPTS_DIR/patch_self_updater.py" \
  "$AGENT_DIR/src/Agent.Listener/SelfUpdater.cs"

echo "  Verifying:"
grep -A 6 "private async Task<bool> UpdateNeeded" \
  "$AGENT_DIR/src/Agent.Listener/SelfUpdater.cs" | head -10

# ============================================================
# Step: Add linux-riscv64 to RuntimeIdentifiers in all csproj
# ============================================================
log "Add linux-riscv64 to RuntimeIdentifiers"
cd "$AGENT_DIR"

find src -name "*.csproj" -type f | while read -r csproj; do
  if grep -q "<RuntimeIdentifiers>" "$csproj"; then
    if ! grep "<RuntimeIdentifiers>" "$csproj" | grep -q "linux-riscv64"; then
      sed -i 's/<RuntimeIdentifiers>\(.*\)<\/RuntimeIdentifiers>/<RuntimeIdentifiers>\1;linux-riscv64<\/RuntimeIdentifiers>/' "$csproj"
      echo "  Patched: $csproj"
    fi
  fi
done
ok "csproj files patched"

# ============================================================
# Step: Patch VarUtil to detect RISC-V architecture
# ============================================================
log "Patch VarUtil.cs"
python3 "$SCRIPTS_DIR/patch_var_util.py" \
  "$AGENT_DIR/src/Microsoft.VisualStudio.Services.Agent/Util/VarUtil.cs"

echo "  Verifying:"
grep -n "RiscV64\|Arm64\|OSArchitecture" \
  "$AGENT_DIR/src/Microsoft.VisualStudio.Services.Agent/Util/VarUtil.cs"

# ============================================================
# Step: Register linux-riscv64 for net8.0 in BundledVersions.props
# ============================================================
log "Register linux-riscv64 for net8.0 (patch_bundled_versions.py)"
PROPS_FILE="$AGENT_DIR/_dotnetsdk/10.0.102/sdk/10.0.102/Microsoft.NETCoreSdk.BundledVersions.props"

echo "  Before patch (net8.0 AppHostRuntimeIdentifiers):"
grep 'AppHostRuntimeIdentifiers' "$PROPS_FILE" | grep -v 'linux-riscv64' | head -3 || true

python3 "$SCRIPTS_DIR/patch_bundled_versions.py" "$PROPS_FILE"

echo "  After patch:"
grep 'linux-riscv64' "$PROPS_FILE" | head -5 || fail "linux-riscv64 not found in props after patch"

# ============================================================
# Step: Patch PlatformUtil to add IsRiscV64
# ============================================================
log "Patch PlatformUtil.cs"
python3 "$SCRIPTS_DIR/patch_platform_util.py" \
  "$AGENT_DIR/src/Agent.Sdk/Util/PlatformUtil.cs"

# ============================================================
# Step: Write NuGet.config and pre-seed packages
# ============================================================
#
# FIX: The previous approach modified the existing NuGet.config by checking
# whether feed strings appeared anywhere in the file. The problem: both
# nuget.org and the PipelineTools feed were already present in the file but
# BEFORE the <clear /> tag - meaning NuGet wiped them on restore. The check
# found the strings and skipped re-adding them after <clear />, so only
# library-packs and nuget.org (the SDK default) remained active.
#
# Solution: write a completely fresh NuGet.config so we control exactly what
# appears after <clear />, and use a local directory feed for packages that
# live on the PipelineTools feed (avoids any auth / availability issues).
# ============================================================
log "Write NuGet.config and pre-seed packages"

# Local directory NuGet feed - drop .nupkg files here, NuGet picks them up
LOCAL_FEED_DIR="$AGENT_DIR/_local_nuget_feed"
mkdir -p "$LOCAL_FEED_DIR"

# Global packages cache (for ref packs from nuget.org)
NUGET_PACKAGES_DIR="$AGENT_DIR/_nuget_packages"
export NUGET_PACKAGES="$NUGET_PACKAGES_DIR"

# ---- Write a fresh NuGet.config ----
# We overwrite whatever the repo has. Feeds listed here are the only ones
# NuGet will use; <clear /> ensures nothing from user/machine config leaks in.
cat > "$AGENT_DIR/src/NuGet.config" <<EOF
<?xml version="1.0" encoding="utf-8"?>
<configuration>
  <packageSources>
    <clear />
    <add key="nugetvssprivate"  value="https://pkgs.dev.azure.com/mseng/PipelineTools/_packaging/nugetvssprivate/nuget/v3/index.json" protocolVersion="3" />
    <add key="nuget.org"      value="https://api.nuget.org/v3/index.json" protocolVersion="3" />
    <add key="PipelineTools"  value="https://pkgs.dev.azure.com/mseng/PipelineTools/_packaging/PipelineTools_PublicPackages/nuget/v3/index.json" protocolVersion="3" />
    <add key="local-feed"     value="${LOCAL_FEED_DIR}" />
  </packageSources>
  <disabledPackageSources />
</configuration>
EOF
ok "NuGet.config written (fresh, feeds positioned after <clear />)"

echo "  Active sources:"
grep '<add key=' "$AGENT_DIR/src/NuGet.config" | sed 's/^/    /'

# ---- Pre-seed nuget.org ref packs into global cache ----
# NuGet requires a .nupkg.sha512 file alongside the .nupkg to accept a cached
# entry as valid - without it NuGet ignores the cached copy and re-downloads.
for pkg in \
  "microsoft.netcore.app.ref/8.0.23" \
  "microsoft.aspnetcore.app.ref/8.0.23"
do
  PKG_NAME="${pkg%%/*}"
  PKG_VER="${pkg##*/}"
  DEST="$NUGET_PACKAGES_DIR/$pkg"
  NUPKG_FILE="$DEST/${PKG_NAME}.${PKG_VER}.nupkg"
  SHA_FILE="${NUPKG_FILE}.sha512"

  if [ ! -f "$NUPKG_FILE" ]; then
    echo "  Fetching $pkg from nuget.org..."
    mkdir -p "$DEST"
    wget -q -O "$NUPKG_FILE" \
      "https://api.nuget.org/v3-flatcontainer/${PKG_NAME}/${PKG_VER}/${PKG_NAME}.${PKG_VER}.nupkg"
    unzip -q -o "$NUPKG_FILE" -d "$DEST"
    # Generate the sha512 hash file NuGet needs to trust the cached entry
    openssl dgst -sha512 -binary "$NUPKG_FILE" | base64 -w 0 > "$SHA_FILE"
    ok "Fetched and cached $pkg"
  else
    # Regenerate sha512 if somehow missing
    [ -f "$SHA_FILE" ] || { openssl dgst -sha512 -binary "$NUPKG_FILE" | base64 -w 0 > "$SHA_FILE"; echo "  Regenerated sha512 for $pkg"; }
    ok "$pkg already in cache"
  fi
done


# ============================================================
# Step: Inject Directory.Build.targets to suppress apphost for riscv64
# ============================================================

log "Inject Directory.Build.targets for linux-riscv64"

cat > "$AGENT_DIR/src/Directory.Build.targets" <<'EOF'
<Project>
  <PropertyGroup Condition="'$(RuntimeIdentifier)' == 'linux-riscv64'">
    <UseAppHost>false</UseAppHost>
    <SelfContained>false</SelfContained>
  </PropertyGroup>
</Project>
EOF

ok "Directory.Build.targets written"

# ============================================================
# Step: Build
# ============================================================
log "Build (dev.sh layout Release linux-riscv64)"

export DOTNET_ROOT="$AGENT_DIR/_dotnetsdk/10.0.102"
export DOTNET_MULTILEVEL_LOOKUP=0
export DOTNET_SKIP_FIRST_TIME_EXPERIENCE=1
export NUGET_PACKAGES="$AGENT_DIR/_nuget_packages"
export PATH="$DOTNET_ROOT:$PATH"

dotnet --version || fail "dotnet not on PATH"

cd "$AGENT_DIR/src"
./dev.sh layout net8.0 Release linux-riscv64


# ============================================================
# Step: Copy native runtime files into layout (complete self-contained)
# ============================================================

log "Bundle .NET runtime into layout"
LAYOUT="$AGENT_DIR/_layout/linux-riscv64"
SDK_DIR="$AGENT_DIR/_dotnetsdk/10.0.102"

# Copy dotnet host
cp "$SDK_DIR/dotnet" "$LAYOUT/bin/"
chmod +x "$LAYOUT/bin/dotnet"

# Copy host resolver
mkdir -p "$LAYOUT/bin/host/fxr/10.0.2"
cp "$SDK_DIR/host/fxr/10.0.2/libhostfxr.so" "$LAYOUT/bin/host/fxr/10.0.2/"

# Copy shared framework (this is how real .NET installs work)
mkdir -p "$LAYOUT/bin/shared/Microsoft.NETCore.App/10.0.2"
cp "$SDK_DIR/shared/Microsoft.NETCore.App/10.0.2/"* "$LAYOUT/bin/shared/Microsoft.NETCore.App/10.0.2/" 2>/dev/null || true

# Patch all runtimeconfig.json to request framework 10.0.2
# (the app was compiled for net8.0 but .NET 10 can run it — forward compatible)

python3 "$SCRIPTS_DIR/patch_runtimeconfig.py" "$LAYOUT/bin"


ok "Runtime bundled and runtimeconfig patched"

# ============================================================
# Step: Verify Build Output
# ============================================================
log "Verify Build Output"
cd "$AGENT_DIR"

for app in "Agent.Listener" "Agent.Worker" "Agent.PluginHost"; do
  BIN_PATH="_layout/linux-riscv64/bin/$app"
  DLL_PATH="_layout/linux-riscv64/bin/${app}.dll"

  echo ""
  echo "  Checking $app..."

  if [ -f "$BIN_PATH" ]; then
    if file "$BIN_PATH" | grep -q "ELF.*RISC-V"; then
      echo "    ✅ Native RISC-V ELF binary"
      ls -lh "$BIN_PATH"
    else
      echo "    ⚠️  Binary exists but arch unclear:"
      file "$BIN_PATH"
    fi
  else
    echo "    ℹ️  No native binary (UseAppHost=false is expected)"
  fi

  [ -f "$DLL_PATH" ] && echo "    ✅ DLL exists" || fail "DLL missing: $DLL_PATH"
done

# ============================================================
# Step: Test Runner Execution
# ============================================================

log "Test Runner Execution"
LAYOUT="$AGENT_DIR/_layout/linux-riscv64/bin"
export DOTNET_ROOT="$LAYOUT"
cd "$LAYOUT"

./dotnet Agent.Listener.dll --version || fail "Execution failed"
ok "Executed successfully"

# ============================================================
# Step: Create wrapper scripts for framework-dependent deployment
# ============================================================
log "Create launcher wrapper scripts"
LAYOUT="$AGENT_DIR/_layout/linux-riscv64"

# Create a wrapper that run.sh/config.sh will call instead of the native binary


for app in Agent.Listener Agent.Worker Agent.PluginHost; do
  cat > "$LAYOUT/bin/$app" <<'WRAPPER'
#!/usr/bin/env bash
SOURCE="${BASH_SOURCE[0]}"
while [ -h "$SOURCE" ]; do
  DIR="$( cd -P "$( dirname "$SOURCE" )" && pwd )"
  SOURCE="$(readlink "$SOURCE")"
  [[ $SOURCE != /* ]] && SOURCE="$DIR/$SOURCE"
done
DIR="$( cd -P "$( dirname "$SOURCE" )" && pwd )"
export DOTNET_ROOT="$DIR"
exec "$DIR/dotnet" "$DIR/APPNAME.dll" "$@"
WRAPPER
  sed -i "s/APPNAME/$app/g" "$LAYOUT/bin/$app"
  chmod +x "$LAYOUT/bin/$app"
done

ok "Launcher wrappers created"


# ============================================================
# Step: Package
# ============================================================
log "Package"
cd "$AGENT_DIR/src"

export DOTNET_ROOT="$AGENT_DIR/_dotnetsdk/10.0.102"
export DOTNET_MULTILEVEL_LOOKUP=0
export PATH="$DOTNET_ROOT:$PATH"

./dev.sh package net8.0 Release linux-riscv64

ok "Build complete. Package at: $AGENT_DIR/_package/"
ls -lh "$AGENT_DIR/_package/" || true

