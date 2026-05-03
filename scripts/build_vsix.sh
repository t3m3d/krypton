#!/usr/bin/env bash
# Build a VS Code extension (.vsix) for Krypton syntax highlighting.
# A vsix is just a ZIP with a specific layout — no `vsce` / Node toolchain needed.
#
# Layout:
#   [Content_Types].xml
#   extension.vsixmanifest
#   extension/package.json
#   extension/language-configuration.json
#   extension/syntaxes/krypton.tmLanguage.json
#   extension/README.md
#
# Output: extensions/krypton-language-<version>.vsix
set -euo pipefail

cd "$(dirname "$0")/.."
SRC="krypton-lang"
[[ -f "$SRC/package.json" ]] || { echo "missing $SRC/package.json"; exit 1; }
[[ -f "$SRC/syntaxes/krypton.tmLanguage.json" ]] || { echo "missing tmLanguage submodule (run: git submodule update --init)"; exit 1; }

VERSION=$(grep -E '^\s*"version":' "$SRC/package.json" | head -1 | sed -E 's/.*"version":\s*"([^"]+)".*/\1/')
[[ -n "$VERSION" ]] || { echo "could not extract version from $SRC/package.json"; exit 1; }

OUT="extensions/krypton-language-${VERSION}.vsix"
WORK=$(mktemp -d)
trap "rm -rf $WORK" EXIT

mkdir -p "$WORK/extension/syntaxes"

# Manifest files at archive root
cat > "$WORK/[Content_Types].xml" <<'EOF'
<?xml version="1.0" encoding="utf-8"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
  <Default Extension=".vsixmanifest" ContentType="text/xml" />
  <Default Extension=".json" ContentType="application/json" />
  <Default Extension=".md" ContentType="text/markdown" />
</Types>
EOF

cat > "$WORK/extension.vsixmanifest" <<EOF
<?xml version="1.0" encoding="utf-8"?>
<PackageManifest Version="2.0.0" xmlns="http://schemas.microsoft.com/developer/vsx-schema/2011" xmlns:d="http://schemas.microsoft.com/developer/vsx-schema-design/2011">
  <Metadata>
    <Identity Language="en-US" Id="krypton-lang" Version="${VERSION}" Publisher="krypton-lang" />
    <DisplayName>Krypton</DisplayName>
    <Description xml:space="preserve">Syntax highlighting for the Krypton programming language (.k files)</Description>
    <Tags>krypton,language,syntax</Tags>
    <Categories>Programming Languages</Categories>
    <GalleryFlags>Public</GalleryFlags>
  </Metadata>
  <Installation>
    <InstallationTarget Id="Microsoft.VisualStudio.Code" Version="[1.75.0,)" />
  </Installation>
  <Dependencies />
  <Assets>
    <Asset Type="Microsoft.VisualStudio.Code.Manifest" Path="extension/package.json" Addressable="true" />
  </Assets>
</PackageManifest>
EOF

# Extension payload
cp "$SRC/package.json"                        "$WORK/extension/package.json"
cp "$SRC/language-configuration.json"         "$WORK/extension/language-configuration.json"
cp "$SRC/syntaxes/krypton.tmLanguage.json"    "$WORK/extension/syntaxes/krypton.tmLanguage.json"
[[ -f "$SRC/README.md" ]] && cp "$SRC/README.md" "$WORK/extension/README.md"

mkdir -p extensions
rm -f "$OUT"

# Use Python for portability (no zip binary needed in git-bash / WSL).
PY=$(command -v python3 || command -v python)
[[ -n "$PY" ]] || { echo "need python or python3 in PATH"; exit 1; }
"$PY" - "$WORK" "$OUT" <<'PY'
import os, sys, zipfile
src, out = sys.argv[1], sys.argv[2]
with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as z:
    for root, _, files in os.walk(src):
        for fn in files:
            p = os.path.join(root, fn)
            arc = os.path.relpath(p, src).replace(os.sep, "/")
            z.write(p, arc)
PY

echo "wrote $OUT ($(stat -c%s "$OUT" 2>/dev/null || stat -f%z "$OUT") bytes)"
