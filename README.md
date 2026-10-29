<p align="center">
  <img src="Resources/icon/icon.svg" alt="Ogle logo: a round eye with a lime iris glancing down at a page reading md" width="160">
</p>

<h1 align="center">Ogle</h1>

<p align="center"><b>Ogle at your Markdown files... with vim.</b></p>

- Renders Markdown the way GitHub does, Mermaid diagrams included
- Neovim built in, with your own config, beside the preview
- Scroll lock: the editor and the preview scroll and zoom together, or apart
- Reloads on save and highlights what changed
- Find with match counts, an outline sidebar, and Open Quickly for recent files
- Native macOS, light and dark

## Features

### Reading

- GitHub Flavored Markdown via [cmark-gfm](https://github.com/swiftlang/swift-cmark) (the parser GitHub uses): tables, task lists, footnotes, autolinks, alerts (`> [!NOTE]`), heading anchors, syntax highlighting, sanitized raw HTML.
- ```` ```mermaid ```` blocks are rendered as diagrams in colors matching the page. Hover a diagram to copy it as SVG, show its source, or open it full window. A diagram that fails to parse shows its source with line numbers, the error message, and the offending line/token highlighted; the rest of the document renders normally.
- Code blocks show their language and a Copy button.
- Reloads automatically when the file changes (including atomic saves by editors such as vim or VS Code), keeping the scroll position anchored to the content you were looking at, and the zoom level. Blocks that were added or changed flash lime and fade out, and a notice says how many changed ("Reloaded · 2 blocks changed"), with a Show button that scrolls to the first.
- Light and dark mode follow the system.

### Editing with Neovim

- The editor pane (⌃⌘E or the toolbar button) runs Neovim, bundled with the app, in a terminal next to the preview, with your own configuration (`~/.config/nvim`, plugins, keybindings, Vimscript or Lua). It starts through your login shell, so plugins find the same tools as in your terminal. Files you open in Ogle open in Neovim too, and the preview reloads when you save.
- Linked (the default), the editor and the preview scroll together, whichever you scroll, and the editor opens where you are reading; a diagram corresponds to the lines of its source. Zooming scales the editor's text along with the preview, and the block holding Neovim's cursor is marked with a lime bar on its left in the preview (View › Highlight Cursor in Preview turns this off).
- Click the chain-link button on the divider between them (or View › Link Editor and Preview) to unlink them: they then scroll independently, and zooming applies to whichever has focus. Linking them again brings the other one to the zoom level and position of the one you last scrolled or zoomed, which stays where it is.
- While Neovim has unsaved changes, the window shows them as edited ("— Edited" in the subtitle) and a pill on the preview says it shows the last save, until you `:w`. Quitting Neovim closes the pane, and Ogle asks before discarding unsaved changes.

### Finding your way

- Find bar (⌘F) between the toolbar and the preview: shows the number of matches ("2 of 8"), highlights all of them and the current one more strongly, and goes through them with Return / ⇧Return, ⌘G / ⇧⌘G or the arrow buttons. Aa matches case. Done or Esc closes it.
- Sidebar (⌃⌘S or the toolbar button) with an Outline | Files switch. Outline (the default once a document is open) lists its headings, marks the section you are reading with a lime dot, and jumps to a heading when you click it. Files lists recently opened files; right-click one to show it in Finder or remove it. The filter field filters whichever list is shown.
- Open Quickly (⇧⌘O): your recent files, searchable by name or folder. Return opens the selected file, ⌥Return opens it with the editor, ⌘⌫ removes it from the list. With no file open, the start page shows it as a card next to the drop zone; over a document it opens as a sheet.
- Status bar below the preview (and the editor) with word count, reading time and the current section, and the zoom control (− 100% +).
- A slim toolbar: Find, the editor toggle, and a More menu with Open in Editor (the default app for the file other than Ogle), Share, Export as PDF and Print.

### Keyboard shortcuts

| Shortcut | Action |
| --- | --- |
| ⌘O / ⇧⌘O | Open… / Open Quickly… |
| ⌘F, ⌘G / ⇧⌘G | Find, next / previous match |
| ⌃⌘E | Show or hide the editor |
| ⌃⌘S | Show or hide the sidebar |
| ⌘+ / ⌘− / ⌘0 | Zoom in / out / actual size |
| ⌥⌘O | Open in the default editor |
| ⇧⌘E / ⌘P | Export as PDF / Print |

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

### Upgrading from mdpeek

Ogle was called mdpeek up to v0.2.3. It brings over mdpeek's recent files, window layout and settings the first time it starts. Remove the old app and command:

```sh
rm -rf ~/Applications/mdpeek.app ~/.local/bin/mdpeek
defaults delete dev.mdpeek
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

## Layout

- `Sources/Ogle` – the AppKit app: window with sidebar, `WKWebView` preview, FSEvents file watcher, cmark-gfm rendering, and the editor pane ([SwiftTerm](https://github.com/migueldeicaza/SwiftTerm) running Neovim).
- `Resources/ogle.lua` – loaded into the editor's Neovim; reports its scroll position, cursor line, unsaved changes and background color to Ogle over a Unix socket, and opens and scrolls to what Ogle shows. The Neovim release is pinned in `build.sh`.
- `Resources/AppIcon.icns`, `Resources/icon/` – the app icon and its SVG sources; `scripts/make_icon.py` regenerates them. `icon.svg` (the logo, with the tile as a slab casting a shadow) is for the README and the start page; the app icon is built from `icon-app.svg` and `icon-small.svg`, which keep to the standard rounded square so macOS shows them full size.
- `Resources/web` – the page that displays the rendered HTML and the start page (`ogle.js` handles sanitizing, alerts, highlighting, Mermaid, scroll preservation, find, the reload and cursor highlights, and Open Quickly). Its third-party libraries are pinned in `package.json` and copied into the app bundle by `build.sh`.
- `docs/design` – the HTML mockups of the window's design, with its colors (ink #23262B, lime #C6F05A, paper #FAFAF7).
