# Ogle redesign mockups

Static HTML mockups of the Ogle window, light mode only, drawn at 1280×800. Open them in a
browser. The values in them (colors, sizes, spacing) are the intended ones; the window chrome
(traffic lights, toolbar background) only stands in for AppKit and is not to be rebuilt in HTML.

- `01-today-reading.html`: the app as built at v0.2.3, for comparison.
- `02-proposed-reading-find.html`: Outline/Files sidebar, slim toolbar (Find, editor toggle,
  More menu), inline find bar with match count, zoom in the status bar.
- `03-proposed-reading-reload.html`: the same view after a reload: changed block tinted lime,
  toast "Reloaded · 1 block changed" with Show.
- `04-proposed-writing.html`: Neovim beside the preview, "— Edited" subtitle, "Showing last save"
  pill, cursor band around the block holding Neovim's cursor, and the chain-link "Linked" toggle
  next to the zoom control in the status bar (links scroll and zoom).
- `05-proposed-start-open-quickly.html`: start page with the drop zone and an Open Quickly
  card (⇧⌘O) listing recent files.

Colors: ink #23262B, lime #C6F05A, paper #FAFAF7 (from the app icon). Lime is used only as a
fill or highlight, never as text color. The recent file names and the Mermaid diagram in the
writing view are sample content.
