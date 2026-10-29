<p align="center">
  <img src="Resources/icon/icon.svg" alt="Ogle logo: a round eye with a lime iris glancing down at a page reading md" width="160">
</p>

<h1 align="center">Ogle</h1>

<p align="center"><b>Ogle at your Markdown files... with vim.</b></p>

- Markdown with Mermaid diagrams, syntax highlighting and alerts
- Neovim built in, with your own config, beside the preview
- Linked panes: the editor and the preview scroll and zoom together, or apart
- Reloads on save and highlights what changed
- Find with match counts, an outline sidebar, and Open Quickly for recent files
- Native macOS, light and dark

## Installation

### Download

Download `Ogle.zip` from the [latest release](https://github.com/hafenr/ogle/releases/latest) (Apple Silicon, macOS 15 or later), unzip it, and move `Ogle.app` to `~/Applications`. The app is not notarized by Apple, so macOS refuses to open the downloaded copy until you remove the quarantine flag:

```sh
xattr -dr com.apple.quarantine ~/Applications/Ogle.app
```

### Build from source

Requirements: macOS 15 or later, the Swift toolchain (Xcode, or the Command Line Tools via `xcode-select --install`), Node.js with npm, and curl (`build.sh` downloads the Neovim release it bundles).

1. Build the app from the project directory:

   ```sh
   ./build.sh          # produces build/Ogle.app
   ```

2. Install it and open it once, so macOS registers it for Finder's "Open With" and the command-line launcher:

   ```sh
   cp -R build/Ogle.app ~/Applications/
   open ~/Applications/Ogle.app
   ```

   Use `/Applications` instead to install it for all users.

3. Optionally, install the `ogle` command:

   ```sh
   mkdir -p ~/.local/bin
   ln -s "$PWD/bin/ogle" ~/.local/bin/ogle
   ```

   `~/.local/bin` must be on your `PATH` (e.g. add `export PATH="$HOME/.local/bin:$PATH"` to `~/.zshrc`). The command is a link into this checkout, so keep the checkout where it is.

4. Optionally, make Ogle the default app for Markdown files: select a `.md` file in Finder, choose File › Get Info (⌘I), pick Ogle under "Open with", and click Change All….

### Updating

Quit Ogle, then rebuild and replace the installed app:

```sh
./build.sh && rm -rf ~/Applications/Ogle.app && cp -R build/Ogle.app ~/Applications/
```

### Uninstalling

```sh
rm -rf ~/Applications/Ogle.app ~/.local/bin/ogle
defaults delete dev.ogle    # recent files and window layout
```

### Releasing

Push a version tag. The Package workflow builds the app with that version and publishes a GitHub release with `Ogle.zip`:

```sh
git tag -a v0.3.0 -m "Ogle v0.3.0" && git push origin v0.3.0
```

## Usage

```sh
ogle README.md
```

Or use File › Open… (⌘O), drop a file on the Dock icon, or pick Ogle from Finder's "Open With". Zoom with ⌘+ / ⌘- / ⌘0 or pinch; pinching magnifies the preview only, and never changes the editor's text size, which follows ⌘+ / ⌘- / ⌘0 alone. Links to other Markdown files open in Ogle; other links open in the default app.

## Keyboard shortcuts

| Shortcut | Action |
| --- | --- |
| ⌘O / ⇧⌘O | Open… / Open Quickly… |
| ⌘F, ⌘G / ⇧⌘G | Find, next / previous match |
| ⌃⌘E | Show or hide the editor |
| ⌃⌘S | Show or hide the sidebar |
| ⌘+ / ⌘− / ⌘0 | Zoom in / out / actual size |
| ⌥⌘O | Open in the default editor |
| ⇧⌘E / ⌘P | Export as PDF / Print |
