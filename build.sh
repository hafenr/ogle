#!/bin/bash
# Builds build/Ogle.app. Requires the Swift toolchain, npm and curl.
set -euo pipefail
cd "$(dirname "$0")"

# The Neovim bundled for the editor pane: an official release, downloaded once.
nvim_version=v0.12.6
nvim_sha256=1dbd148222b051ba6c307c4d17a318ed083df018a4f6a5a0ce46955ffc9ab87b
nvim="build/nvim-$nvim_version"
if [[ ! -d "$nvim" ]]; then
  mkdir -p build
  curl -fsSL "https://github.com/neovim/neovim/releases/download/$nvim_version/nvim-macos-arm64.tar.gz" -o build/nvim.tar.gz
  echo "$nvim_sha256  build/nvim.tar.gz" | shasum -a 256 -c --quiet -
  rm -rf "$nvim.partial"
  mkdir "$nvim.partial"
  tar -xzf build/nvim.tar.gz -C "$nvim.partial" --strip-components 1
  rm build/nvim.tar.gz
  mv "$nvim.partial" "$nvim"
fi

npm ci --no-audit --no-fund --loglevel=error
swift build -c release

app=build/Ogle.app
web="$app/Contents/Resources/web"
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$web/vendor"
cp "$(swift build -c release --show-bin-path)/Ogle" "$app/Contents/MacOS/"
cp Resources/Info.plist "$app/Contents/"
cp Resources/AppIcon.icns Resources/ogle.lua "$app/Contents/Resources/"
mkdir -p "$app/Contents/Resources/neovim/share"
cp -R "$nvim/bin" "$nvim/lib" "$app/Contents/Resources/neovim/"
cp -R "$nvim/share/nvim" "$app/Contents/Resources/neovim/share/"
cp Resources/web/* "$web/"
cp node_modules/mermaid/dist/mermaid.min.js \
   node_modules/dompurify/dist/purify.min.js \
   node_modules/diff/dist/diff.min.js \
   node_modules/@highlightjs/cdn-assets/highlight.min.js \
   node_modules/github-markdown-css/github-markdown.css \
   "$web/vendor/"
cp node_modules/@highlightjs/cdn-assets/styles/github.min.css "$web/vendor/highlight-github.css"
cp node_modules/@highlightjs/cdn-assets/styles/github-dark.min.css "$web/vendor/highlight-github-dark.css"
codesign --force --sign - "$app"
echo "Built $app"
