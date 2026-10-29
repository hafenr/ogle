"use strict";

window.mdpeek = (() => {
  const content = document.getElementById("content");
  const darkMode = matchMedia("(prefers-color-scheme: dark)");

  // Octicons (MIT, github.com/primer/octicons), as used by GitHub.
  const octicon = (name, path) =>
    `<svg class="octicon octicon-${name}" viewBox="0 0 16 16" width="16" height="16" aria-hidden="true"><path d="${path}"></path></svg>`;
  const LINK_ICON = octicon("link", "m7.775 3.275 1.25-1.25a3.5 3.5 0 1 1 4.95 4.95l-2.5 2.5a3.5 3.5 0 0 1-4.95 0 .751.751 0 0 1 .018-1.042.751.751 0 0 1 1.042-.018 1.998 1.998 0 0 0 2.83 0l2.5-2.5a2.002 2.002 0 0 0-2.83-2.83l-1.25 1.25a.751.751 0 0 1-1.042-.018.751.751 0 0 1-.018-1.042Zm-4.69 9.64a1.998 1.998 0 0 0 2.83 0l1.25-1.25a.751.751 0 0 1 1.042.018.751.751 0 0 1 .018 1.042l-1.25 1.25a3.5 3.5 0 1 1-4.95-4.95l2.5-2.5a3.5 3.5 0 0 1 4.95 0 .751.751 0 0 1-.018 1.042.751.751 0 0 1-1.042.018 1.998 1.998 0 0 0-2.83 0l-2.5 2.5a1.998 1.998 0 0 0 0 2.83Z");
  const ALERTS = {
    note: ["Note", octicon("info", "M0 8a8 8 0 1 1 16 0A8 8 0 0 1 0 8Zm8-6.5a6.5 6.5 0 1 0 0 13 6.5 6.5 0 0 0 0-13ZM6.5 7.75A.75.75 0 0 1 7.25 7h1a.75.75 0 0 1 .75.75v2.75h.25a.75.75 0 0 1 0 1.5h-2a.75.75 0 0 1 0-1.5h.25v-2h-.25a.75.75 0 0 1-.75-.75ZM8 6a1 1 0 1 1 0-2 1 1 0 0 1 0 2Z")],
    tip: ["Tip", octicon("light-bulb", "M8 1.5c-2.363 0-4 1.69-4 3.75 0 .984.424 1.625.984 2.304l.214.253c.223.264.47.556.673.848.284.411.537.896.621 1.49a.75.75 0 0 1-1.484.211c-.04-.282-.163-.547-.37-.847a8.456 8.456 0 0 0-.542-.68c-.084-.1-.173-.205-.268-.32C3.201 7.75 2.5 6.766 2.5 5.25 2.5 2.31 4.863 0 8 0s5.5 2.31 5.5 5.25c0 1.516-.701 2.5-1.328 3.259-.095.115-.184.22-.268.319-.207.245-.383.453-.541.681-.208.3-.33.565-.37.847a.751.751 0 0 1-1.485-.212c.084-.593.337-1.078.621-1.489.203-.292.45-.584.673-.848.075-.088.147-.173.213-.253.561-.679.985-1.32.985-2.304 0-2.06-1.637-3.75-4-3.75ZM5.75 12h4.5a.75.75 0 0 1 0 1.5h-4.5a.75.75 0 0 1 0-1.5ZM6 15.25a.75.75 0 0 1 .75-.75h2.5a.75.75 0 0 1 0 1.5h-2.5a.75.75 0 0 1-.75-.75Z")],
    important: ["Important", octicon("report", "M0 1.75C0 .784.784 0 1.75 0h12.5C15.216 0 16 .784 16 1.75v9.5A1.75 1.75 0 0 1 14.25 13H8.06l-2.573 2.573A1.458 1.458 0 0 1 3 14.543V13H1.75A1.75 1.75 0 0 1 0 11.25Zm1.75-.25a.25.25 0 0 0-.25.25v9.5c0 .138.112.25.25.25h2a.75.75 0 0 1 .75.75v2.19l2.72-2.72a.749.749 0 0 1 .53-.22h6.5a.25.25 0 0 0 .25-.25v-9.5a.25.25 0 0 0-.25-.25Zm7 2.25v2.5a.75.75 0 0 1-1.5 0v-2.5a.75.75 0 0 1 1.5 0ZM9 9a1 1 0 1 1-2 0 1 1 0 0 1 2 0Z")],
    warning: ["Warning", octicon("alert", "M6.457 1.047c.659-1.234 2.427-1.234 3.086 0l6.082 11.378A1.75 1.75 0 0 1 14.082 15H1.918a1.75 1.75 0 0 1-1.543-2.575Zm1.763.707a.25.25 0 0 0-.44 0L1.698 13.132a.25.25 0 0 0 .22.368h12.164a.25.25 0 0 0 .22-.368Zm.53 3.996v2.5a.75.75 0 0 1-1.5 0v-2.5a.75.75 0 0 1 1.5 0ZM9 11a1 1 0 1 1-2 0 1 1 0 0 1 2 0Z")],
    caution: ["Caution", octicon("stop", "M4.47.22A.749.749 0 0 1 5 0h6c.199 0 .389.079.53.22l4.25 4.25c.141.14.22.331.22.53v6a.749.749 0 0 1-.22.53l-4.25 4.25A.749.749 0 0 1 11 16H5a.749.749 0 0 1-.53-.22L.22 11.53A.749.749 0 0 1 0 11V5c0-.199.079-.389.22-.53Zm.84 1.28L1.5 5.31v5.38l3.81 3.81h5.38l3.81-3.81V5.31L10.69 1.5ZM8 4a.75.75 0 0 1 .75.75v3.5a.75.75 0 0 1-1.5 0v-3.5A.75.75 0 0 1 8 4Zm0 8a1 1 0 1 1 0-2 1 1 0 0 1 0 2Z")],
  };

  const COPY_ICON = octicon("copy", "M0 6.75C0 5.784.784 5 1.75 5h1.5a.75.75 0 0 1 0 1.5h-1.5a.25.25 0 0 0-.25.25v7.5c0 .138.112.25.25.25h7.5a.25.25 0 0 0 .25-.25v-1.5a.75.75 0 0 1 1.5 0v1.5A1.75 1.75 0 0 1 9.25 16h-7.5A1.75 1.75 0 0 1 0 14.25Z M5 1.75C5 .784 5.784 0 6.75 0h7.5C15.216 0 16 .784 16 1.75v7.5A1.75 1.75 0 0 1 14.25 11h-7.5A1.75 1.75 0 0 1 5 9.25Zm1.75-.25a.25.25 0 0 0-.25.25v7.5c0 .138.112.25.25.25h7.5a.25.25 0 0 0 .25-.25v-7.5a.25.25 0 0 0-.25-.25Z");
  const CHECK_ICON = octicon("check", "M13.78 4.22a.75.75 0 0 1 0 1.06l-7.25 7.25a.75.75 0 0 1-1.06 0L2.22 9.28a.751.751 0 0 1 .018-1.042.751.751 0 0 1 1.042-.018L6 10.94l6.72-6.72a.75.75 0 0 1 1.06 0Z");
  const CODE_ICON = octicon("code", "m11.28 3.22 4.25 4.25a.75.75 0 0 1 0 1.06l-4.25 4.25a.749.749 0 0 1-1.275-.326.749.749 0 0 1 .215-.734L13.94 8l-3.72-3.72a.749.749 0 0 1 .326-1.275.749.749 0 0 1 .734.215Zm-6.56 0a.751.751 0 0 1 1.042.018.751.751 0 0 1 .018 1.042L2.06 8l3.72 3.72a.749.749 0 0 1-.326 1.275.749.749 0 0 1-.734-.215L.47 8.53a.75.75 0 0 1 0-1.06Z");
  const EXPAND_ICON = octicon("screen-full", "M1.75 10a.75.75 0 0 1 .75.75v2.5c0 .138.112.25.25.25h2.5a.75.75 0 0 1 0 1.5h-2.5A1.75 1.75 0 0 1 1 13.25v-2.5a.75.75 0 0 1 .75-.75Zm12.5 0a.75.75 0 0 1 .75.75v2.5A1.75 1.75 0 0 1 13.25 15h-2.5a.75.75 0 0 1 0-1.5h2.5a.25.25 0 0 0 .25-.25v-2.5a.75.75 0 0 1 .75-.75ZM2.75 2.5a.25.25 0 0 0-.25.25v2.5a.75.75 0 0 1-1.5 0v-2.5C1 1.784 1.784 1 2.75 1h2.5a.75.75 0 0 1 0 1.5ZM10 1.75a.75.75 0 0 1 .75-.75h2.5c.966 0 1.75.784 1.75 1.75v2.5a.75.75 0 0 1-1.5 0v-2.5a.25.25 0 0 0-.25-.25h-2.5a.75.75 0 0 1-.75-.75Z");
  const CLOSE_ICON = octicon("x", "M3.72 3.72a.75.75 0 0 1 1.06 0L8 6.94l3.22-3.22a.749.749 0 0 1 1.275.326.749.749 0 0 1-.215.734L9.06 8l3.22 3.22a.749.749 0 0 1-.326 1.275.749.749 0 0 1-.734-.215L8 9.06l-3.22 3.22a.751.751 0 0 1-1.042-.018.751.751 0 0 1-.018-1.042L6.94 8 3.72 4.78a.75.75 0 0 1 0-1.06Z");

  const button = (action, label, icon, text = "") =>
    `<button type="button" class="md-button" data-action="${action}" aria-label="${label}" title="${label}">${icon}${text ? `<span>${text}</span>` : ""}</button>`;

  // Messages to the app (outline, current section, clipboard, open requests).
  const native = (message) => window.webkit?.messageHandlers?.mdpeek?.postMessage(message);

  // Rendered diagrams by theme, occurrence and source, so unchanged diagrams are reused
  // as-is on reload and keep the layout stable.
  let diagramCache = new Map();
  let diagramCount = 0;
  let generation = 0;
  let baseURL = null;
  let last = null;
  let currentSection;

  // Diagrams follow the page: neutral outlines in the document's colors instead of
  // Mermaid's default lavender.
  const FONT = "-apple-system, BlinkMacSystemFont, 'Segoe UI', 'Noto Sans', Helvetica, Arial, sans-serif";
  const MERMAID_THEMES = {
    light: {
      fontFamily: FONT, background: "#ffffff", textColor: "#1f2328",
      primaryColor: "#ffffff", primaryTextColor: "#1f2328", primaryBorderColor: "#23262b",
      secondaryColor: "#f3f3ee", secondaryTextColor: "#1f2328", secondaryBorderColor: "#59636e",
      tertiaryColor: "#fafaf7", tertiaryTextColor: "#1f2328", tertiaryBorderColor: "#d1d9e0",
      lineColor: "#59636e", noteBkgColor: "#f1fbd6", noteTextColor: "#1f2328", noteBorderColor: "#8fb22a",
      clusterBkg: "#f6f8fa", clusterBorder: "#d1d9e0", edgeLabelBackground: "#ffffff",
    },
    dark: {
      darkMode: true, fontFamily: FONT, background: "#0d1117", textColor: "#e6edf3",
      primaryColor: "#161b22", primaryTextColor: "#e6edf3", primaryBorderColor: "#c9d1d9",
      secondaryColor: "#21262d", secondaryTextColor: "#e6edf3", secondaryBorderColor: "#8b949e",
      tertiaryColor: "#0d1117", tertiaryTextColor: "#e6edf3", tertiaryBorderColor: "#3d444d",
      lineColor: "#8b949e", noteBkgColor: "#2a3214", noteTextColor: "#e6edf3", noteBorderColor: "#c6f05a",
      clusterBkg: "#151b23", clusterBorder: "#3d444d", edgeLabelBackground: "#0d1117",
    },
  };
  const mermaidTheme = () => (darkMode.matches ? "dark" : "light");
  const configureMermaid = () =>
    mermaid.initialize({
      startOnLoad: false, securityLevel: "strict", suppressErrorRendering: true,
      theme: "base", themeVariables: MERMAID_THEMES[mermaidTheme()],
      themeCSS: ".node rect, .node circle, .node ellipse, .node polygon, .node path { filter: none !important; }",
    });
  configureMermaid();
  darkMode.addEventListener("change", () => {
    configureMermaid();
    if (last) render(last.html, last.baseURL, true, { quiet: true });
  });

  DOMPurify.addHook("afterSanitizeAttributes", (node) => {
    for (const name of ["src", "href"]) {
      const value = node.getAttribute(name);
      const resolved = value && !value.startsWith("#") && URL.parse(value, baseURL);
      if (resolved) node.setAttribute(name, resolved.href);
    }
    const srcset = node.getAttribute("srcset");
    if (srcset) {
      node.setAttribute("srcset", srcset.split(",").map((candidate) => {
        const [url, ...descriptors] = candidate.trim().split(/\s+/);
        return [URL.parse(url, baseURL)?.href ?? url, ...descriptors].join(" ");
      }).join(", "));
    }
  });

  // `preserveScroll` is set for reloads of the same file; those show a short notice
  // unless `quiet` (re-renders for an appearance change).
  async function render(html, documentBaseURL, preserveScroll, { quiet = false } = {}) {
    const current = ++generation;
    last = { html, baseURL: documentBaseURL };
    baseURL = documentBaseURL;
    const container = document.createElement("div");
    container.append(DOMPurify.sanitize(html, { RETURN_DOM_FRAGMENT: true }));
    addHeadingAnchors(container);
    addAlerts(container);
    addTaskListClasses(container);
    highlightCode(container);
    if (!(await renderDiagrams(container, current))) return;
    addCodeBlockHeaders(container);
    await imagesLoaded(container);
    if (current !== generation) return;

    welcome.hidden = true;
    content.hidden = false;
    const anchor = preserveScroll ? scrollAnchor() : null;
    const before = preserveScroll ? [...content.children].map(signature) : null;
    markOwnScroll();
    content.replaceChildren(...container.childNodes);
    if (sourceLine) scrollToSourceLine(sourceLine);
    else if (anchor) restoreScrollAnchor(anchor);
    else window.scrollTo(0, 0);
    reflowAnchor = scrollAnchor();
    centerAnchor = viewCenterAnchor();
    postOutline();
    updateSection(true);
    refreshFind();
    markCursorBlock();
    if (preserveScroll && !quiet) showChanges(before);
  }

  // The start page, shown while no file is open.
  const welcome = document.getElementById("welcome");
  function showWelcome() {
    generation++;
    last = null;
    content.replaceChildren();
    content.hidden = true;
    welcome.hidden = false;
    native({ type: "outline", headings: [], words: 0 });
  }
  welcome.addEventListener("click", (event) => {
    if (event.target.closest("[data-action=open]")) native({ type: "open" });
  });
  // Highlights the drop zone while a file is dragged over the window; the drop itself
  // is handled by the app.
  let dragDepth = 0;
  addEventListener("dragenter", () => document.body.classList.toggle("dragging", ++dragDepth > 0));
  addEventListener("dragleave", () => document.body.classList.toggle("dragging", --dragDepth > 0));

  // MARK: Outline

  const headingElements = () => content.querySelectorAll("h1, h2, h3, h4");

  function postOutline() {
    const headings = [...headingElements()].map((heading) => ({
      id: heading.id, level: Number(heading.tagName[1]), title: heading.textContent.trim(),
    }));
    const text = [...content.children].filter((block) => !block.matches(".mermaid-figure, .code-block"))
      .map((block) => block.innerText).join(" ");
    native({ type: "outline", headings, words: (text.match(/[\p{L}\p{N}][\p{L}\p{N}'’-]*/gu) ?? []).length });
  }

  // The current section is the last heading above the top of the window (or the last one
  // visible once scrolled to the bottom).
  function updateSection(force) {
    const headings = [...headingElements()];
    const scroller = document.scrollingElement;
    const atBottom = scroller.scrollTop > 0 && scroller.scrollTop + innerHeight >= scroller.scrollHeight - 2;
    let id = headings[0]?.id ?? null;
    for (const heading of headings) {
      const top = heading.getBoundingClientRect().top;
      if (top <= 80 || (atBottom && top < innerHeight)) id = heading.id;
      else if (!atBottom) break;
    }
    if (force || id !== currentSection) {
      currentSection = id;
      native({ type: "section", id });
    }
  }
  let sectionUpdateScheduled = false;
  addEventListener("scroll", () => {
    if (sectionUpdateScheduled) return;
    sectionUpdateScheduled = true;
    requestAnimationFrame(() => {
      sectionUpdateScheduled = false;
      updateSection(false);
    });
  }, { passive: true });

  function scrollToHeading(id) {
    const heading = document.getElementById(id);
    if (heading) window.scrollTo({ top: heading.getBoundingClientRect().top + scrollY - 16, behavior: "smooth" });
  }

  // MARK: Notices

  // A short notice at the top of the window, with an optional button ({ label, run }). It
  // stays while the pointer is over it.
  let toastTimer;
  function showToast(text, action) {
    let toast = document.getElementById("toast");
    if (!toast) {
      toast = document.createElement("div");
      toast.id = "toast";
      toast.setAttribute("role", "status");
      toast.addEventListener("mouseenter", () => clearTimeout(toastTimer));
      toast.addEventListener("mouseleave", () => hideToastLater(1500));
      document.body.append(toast);
    }
    const label = document.createElement("span");
    label.textContent = text;
    toast.replaceChildren(label);
    if (action) {
      const button = document.createElement("button");
      button.type = "button";
      button.textContent = action.label;
      button.addEventListener("click", () => {
        action.run();
        toast.classList.remove("visible");
      });
      toast.append(button);
    }
    toast.classList.toggle("has-action", Boolean(action));
    toast.classList.add("visible");
    hideToastLater(action ? 4000 : 1800);
  }

  function hideToastLater(delay) {
    clearTimeout(toastTimer);
    toastTimer = setTimeout(() => document.getElementById("toast")?.classList.remove("visible"), delay);
  }

  // A pill at the top right while the editor has unsaved changes, which the page does not show.
  function showUnsavedNotice(shown) {
    let notice = document.getElementById("unsaved");
    if (!shown) {
      notice?.remove();
      return;
    }
    if (notice) return;
    notice = document.createElement("div");
    notice.id = "unsaved";
    notice.setAttribute("role", "status");
    notice.innerHTML = "Showing last save · <kbd>:w</kbd> to update";
    document.body.append(notice);
  }

  // After a reload, tints the top-level blocks that are new or changed (fading out) and says
  // how many there are, with a button that scrolls to the first.
  function showChanges(before) {
    const blocks = [...content.children];
    const { indexes, removed } = changedIndexes(before, blocks.map(signature));
    const changed = indexes.map((index) => blocks[index]);
    changed.forEach(tintChanged);
    const count = (n, what) => `${n} ${n === 1 ? "block" : "blocks"} ${what}`;
    if (changed.length) {
      showToast(`Reloaded · ${count(changed.length, "changed")}`, {
        label: "Show",
        run: () => {
          const block = changed.find((element) => element.isConnected);
          if (!block) return;
          window.scrollTo({ top: block.getBoundingClientRect().top + scrollY - 24, behavior: "smooth" });
          tintChanged(block);
        },
      });
    } else {
      showToast(removed ? `Reloaded · ${count(removed, "removed")}` : "Reloaded");
    }
  }

  // The indexes of the blocks in `after` that are new or changed since `before` (lists of
  // block signatures), and how many blocks were removed.
  function changedIndexes(before, after) {
    const indexes = [];
    let newIndex = 0;
    let removed = 0;
    for (const change of Diff.diffArrays(before, after)) {
      if (change.added) {
        for (let i = 0; i < change.count; i++) indexes.push(newIndex + i);
      } else if (change.removed) {
        removed += change.count;
        continue;
      }
      newIndex += change.count;
    }
    return { indexes, removed: Math.max(removed - indexes.length, 0) };
  }

  function tintChanged(block) {
    block.classList.remove("mdpeek-changed");
    void block.offsetWidth; // Restarts the animation.
    block.classList.add("mdpeek-changed");
    block.addEventListener("animationend", () => block.classList.remove("mdpeek-changed"), { once: true });
  }

  // MARK: Find

  // Matches are painted with the CSS Custom Highlight API, which leaves the DOM as it is, so
  // the scroll anchoring (which compares the blocks' text) is unaffected.
  const findMatches = new Highlight();
  const findCurrent = new Highlight();
  CSS.highlights.set("find-match", findMatches);
  CSS.highlights.set("find-current", findCurrent);
  let findState = null;

  // Text that is not shown, or is part of the page's own controls, is not searched.
  const UNSEARCHED = "[hidden], .anchor, .md-button, .code-block-header, style, script";

  function findRanges(query, caseSensitive) {
    const pattern = new RegExp(query.replace(/[.*+?^${}()|[\]\\]/g, "\\$&"), caseSensitive ? "gu" : "giu");
    const ranges = [];
    const walker = document.createTreeWalker(content, NodeFilter.SHOW_TEXT, {
      acceptNode: (node) => (node.parentElement?.closest(UNSEARCHED) ? NodeFilter.FILTER_REJECT : NodeFilter.FILTER_ACCEPT),
    });
    for (let node = walker.nextNode(); node; node = walker.nextNode()) {
      for (const match of node.data.matchAll(pattern)) {
        if (!match[0]) continue;
        const range = new Range();
        range.setStart(node, match.index);
        range.setEnd(node, match.index + match[0].length);
        ranges.push(range);
      }
    }
    return ranges;
  }

  function paintFind() {
    findMatches.clear();
    findCurrent.clear();
    findState?.ranges.forEach((range, index) => (index === findState.index ? findCurrent : findMatches).add(range));
  }

  // `index` counts from 1; 0 without matches.
  const findResult = () => ({ index: findState?.ranges.length ? findState.index + 1 : 0, count: findState?.ranges.length ?? 0 });

  // Scrolls the current match into view, a third of the way down, if it is not in view.
  function revealMatch() {
    const range = findState?.ranges[findState.index];
    if (!range) return;
    const rect = range.getBoundingClientRect();
    if (rect.top >= 16 && rect.bottom <= innerHeight - 16) return;
    window.scrollTo({ top: scrollY + rect.top - innerHeight / 3 });
  }

  // Finds `query` and makes the first match at or below the top of the window the current one.
  function find(query, caseSensitive) {
    if (!query) {
      clearFind();
      return findResult();
    }
    const ranges = findRanges(query, caseSensitive);
    const visible = ranges.findIndex((range) => range.getBoundingClientRect().bottom > 0);
    findState = { query, caseSensitive, ranges, index: Math.max(visible, 0) };
    paintFind();
    revealMatch();
    return findResult();
  }

  function findNext(backwards) {
    const count = findState?.ranges.length;
    if (!count) return findResult();
    findState.index = (findState.index + (backwards ? count - 1 : 1)) % count;
    paintFind();
    revealMatch();
    return findResult();
  }

  function clearFind() {
    findState = null;
    paintFind();
  }

  // After a render, finds the matches in the new content again, without scrolling, and
  // reports the new count.
  function refreshFind() {
    if (!findState) return;
    const ranges = findRanges(findState.query, findState.caseSensitive);
    findState = { ...findState, ranges, index: Math.min(findState.index, Math.max(ranges.length - 1, 0)) };
    paintFind();
    native({ type: "find", ...findResult() });
  }

  // Esc on the page closes the find bar (unless it closes a full-window diagram).
  addEventListener("keydown", (event) => {
    if (event.key === "Escape" && !document.querySelector(".lightbox")) native({ type: "escape" });
  });

  // MARK: Code blocks and diagram controls

  function addCodeBlockHeaders(root) {
    for (const pre of root.querySelectorAll("pre")) {
      if (pre.closest(".mermaid-figure, .mermaid-error")) continue;
      const language = pre.querySelector(":scope > code")?.className.match(/language-(\S+)/)?.[1] ?? "";
      const block = document.createElement("div");
      block.className = "code-block";
      const header = document.createElement("div");
      header.className = "code-block-header";
      const label = document.createElement("span");
      label.textContent = language;
      header.append(label);
      header.insertAdjacentHTML("beforeend", button("copy-code", "Copy code", COPY_ICON, "Copy"));
      pre.replaceWith(block);
      block.append(header, pre);
    }
  }

  function copy(text, kind = "text") {
    if (window.webkit?.messageHandlers?.mdpeek) native({ type: "copy", kind, text });
    else navigator.clipboard?.writeText(text);
  }

  // Briefly shows a check mark (and "Copied") on a copy button.
  function confirmCopy(target) {
    const icon = target.querySelector("svg");
    const label = target.querySelector("span");
    const [iconHTML, labelText] = [icon.outerHTML, label?.textContent];
    icon.outerHTML = CHECK_ICON;
    if (label) label.textContent = "Copied";
    target.classList.add("done");
    setTimeout(() => {
      target.querySelector("svg").outerHTML = iconHTML;
      if (label) label.textContent = labelText;
      target.classList.remove("done");
    }, 1200);
  }

  content.addEventListener("click", (event) => {
    const target = event.target.closest("button[data-action]");
    if (!target || target.classList.contains("done")) return;
    const figure = target.closest(".mermaid-figure");
    switch (target.dataset.action) {
      case "copy-code":
        copy(target.closest(".code-block").querySelector("pre").innerText.replace(/\n$/, ""));
        confirmCopy(target);
        break;
      case "copy-svg":
        copy(figure.querySelector(".mermaid-diagram svg").outerHTML, "svg");
        confirmCopy(target);
        break;
      case "toggle-source": {
        const source = figure.querySelector(".mermaid-source");
        source.hidden = !source.hidden;
        target.setAttribute("aria-pressed", String(!source.hidden));
        break;
      }
      case "expand":
        openLightbox(figure.querySelector(".mermaid-diagram svg"));
        break;
    }
  });

  // Shows a diagram on its own, scaled to fill the window.
  function openLightbox(svg) {
    const overlay = document.createElement("div");
    overlay.className = "lightbox";
    overlay.setAttribute("role", "dialog");
    overlay.setAttribute("aria-label", "Diagram");
    const diagram = svg.cloneNode(true);
    diagram.removeAttribute("style");
    diagram.setAttribute("width", "100%");
    diagram.setAttribute("height", "100%");
    overlay.append(diagram);
    overlay.insertAdjacentHTML("beforeend", button("close", "Close", CLOSE_ICON));
    const close = () => {
      overlay.remove();
      removeEventListener("keydown", onKey);
    };
    const onKey = (event) => {
      if (event.key === "Escape") close();
    };
    overlay.addEventListener("click", close);
    addEventListener("keydown", onKey);
    document.body.append(overlay);
    overlay.querySelector("button").focus();
  }

  // Heading ids and permalinks as GitHub generates them.
  function addHeadingAnchors(root) {
    const counts = new Map();
    for (const heading of root.querySelectorAll("h1, h2, h3, h4, h5, h6")) {
      const slug = heading.textContent.trim().toLowerCase()
        .replace(/[^\p{L}\p{M}\p{N}\p{Pc} -]/gu, "").replace(/ /g, "-");
      const count = counts.get(slug) ?? 0;
      counts.set(slug, count + 1);
      heading.id ||= count ? `${slug}-${count}` : slug;
      heading.insertAdjacentHTML("afterbegin", `<a class="anchor" aria-hidden="true" href="#${encodeURIComponent(heading.id)}">${LINK_ICON}</a>`);
    }
  }

  // GitHub alerts: a blockquote starting with a line like "[!NOTE]".
  function addAlerts(root) {
    for (const quote of root.querySelectorAll("blockquote")) {
      const paragraph = quote.firstElementChild;
      const text = paragraph?.tagName === "P" ? paragraph.firstChild : null;
      const match = text?.nodeType === Node.TEXT_NODE && text.data.match(/^\[!(note|tip|important|warning|caution)\][ \t]*(\n|$)/i);
      if (!match) continue;
      const type = match[1].toLowerCase();
      text.data = text.data.slice(match[0].length);
      if (!paragraph.textContent.trim() && !paragraph.querySelector("img")) paragraph.remove();
      const alert = document.createElement("div");
      alert.className = `markdown-alert markdown-alert-${type}`;
      const [title, icon] = ALERTS[type];
      alert.innerHTML = `<p class="markdown-alert-title">${icon.replace("octicon ", "octicon mr-2 ")}${title}</p>`;
      alert.append(...quote.childNodes);
      alert.dataset.sourcepos = quote.dataset.sourcepos;
      quote.replaceWith(alert);
    }
  }

  // cmark-gfm emits plain checkboxes; GitHub's stylesheet expects these classes.
  function addTaskListClasses(root) {
    for (const checkbox of root.querySelectorAll("li > input[type=checkbox]:first-child")) {
      checkbox.classList.add("task-list-item-checkbox");
      checkbox.parentElement.classList.add("task-list-item");
      checkbox.parentElement.parentElement.classList.add("contains-task-list");
    }
  }

  function highlightCode(root) {
    for (const code of root.querySelectorAll("pre > code[class*='language-']")) {
      const language = code.className.match(/language-(\S+)/)[1];
      if (language !== "mermaid" && hljs.getLanguage(language)) hljs.highlightElement(code);
    }
  }

  // Returns false if a newer render started in the meantime.
  async function renderDiagrams(root, current) {
    const cache = new Map();
    const occurrences = new Map();
    for (const code of root.querySelectorAll("pre > code.language-mermaid")) {
      const source = code.textContent;
      const occurrence = occurrences.get(source) ?? 0;
      occurrences.set(source, occurrence + 1);
      const key = `${mermaidTheme()}\n${occurrence}\n${source}`;
      let diagram = diagramCache.get(key);
      if (!diagram) {
        diagram = await renderDiagram(source);
        if (current !== generation) return false;
        diagramCache.set(key, diagram);
      }
      cache.set(key, diagram);
      const figure = diagram.cloneNode(true);
      figure.dataset.sourcepos = code.parentElement.dataset.sourcepos;
      code.parentElement.replaceWith(figure);
    }
    diagramCache = cache;
    return true;
  }

  async function renderDiagram(source) {
    const element = document.createElement("div");
    try {
      const { svg } = await mermaid.render(`mermaid-${++diagramCount}`, source);
      element.className = "mermaid-figure";
      element.innerHTML = `<div class="mermaid-toolbar">${[
        button("copy-svg", "Copy as SVG", COPY_ICON),
        button("toggle-source", "Show source", CODE_ICON),
        button("expand", "Open full window", EXPAND_ICON),
      ].join("")}</div><div class="mermaid-diagram">${svg}</div>`;
      const pre = document.createElement("pre");
      pre.className = "mermaid-source";
      pre.hidden = true;
      const code = document.createElement("code");
      code.textContent = source;
      pre.append(code);
      element.append(pre);
    } catch (error) {
      element.className = "mermaid-error";
      showDiagramError(element, source, error);
    }
    return element;
  }

  function showDiagramError(element, source, error) {
    const location = errorLocation(source, error);
    const message = document.createElement("div");
    message.className = "mermaid-error-message";
    message.textContent = error?.message ?? String(error);
    // Mermaid counts lines without front matter and comments; refer to the lines shown instead.
    if (location) message.textContent = message.textContent.replace(/line \d+/i, `line ${location.line + 1}`);
    const code = document.createElement("code");
    const lines = source.replace(/\n$/, "").split("\n");
    lines.forEach((line, index) => {
      const row = document.createElement("span");
      row.className = "line";
      if (location?.line === index) {
        row.classList.add("error-line");
        const start = Math.min(Math.max(location.start ?? 0, line.search(/\S|$/)), line.length);
        const end = Math.max(location.end ?? line.length, start + 1);
        const mark = document.createElement("mark");
        mark.textContent = line.slice(start, end);
        row.append(line.slice(0, start), mark, line.slice(end));
      } else {
        row.textContent = line;
      }
      code.append(row);
    });
    const pre = document.createElement("pre");
    pre.append(code);
    element.append(message, pre);
    if (location) {
      requestAnimationFrame(() => element.querySelector(".error-line")?.scrollIntoView({ block: "nearest", inline: "nearest" }));
    }
  }

  // Maps the position mermaid reports to a line (0-based) and column range in the source.
  function errorLocation(source, error) {
    let line, start, end;
    const loc = error?.hash?.loc;
    if (loc) {
      // Jison parsers: 1-based lines, 0-based columns.
      line = loc.first_line;
      if (loc.last_line === loc.first_line) [start, end] = [loc.first_column, loc.last_column];
    } else {
      // Langium parsers report "line N, column M" (both 1-based); others only "line N".
      const match = error?.message?.match(/line (\d+)(?:, column (\d+))?/i);
      if (!match) return null;
      line = Number(match[1]);
      if (match[2]) start = Number(match[2]) - 1;
    }
    const lines = parsedLines(source);
    const index = lines[Math.min(line, lines.length) - 1];
    return index === undefined ? null : { line: index, start, end };
  }

  // Mermaid parses the diagram without its front matter, directives, comment lines and
  // leading blank lines. Returns, for each parsed line, the index of the source line.
  function parsedLines(source) {
    const lines = source.split("\n");
    let index = 0;
    if (/^\s*---\s*$/.test(lines[0])) {
      const end = lines.findIndex((line, i) => i > 0 && /^\s*---\s*$/.test(line));
      if (end > 0) index = end + 1;
    }
    const kept = [];
    for (; index < lines.length; index++) {
      const line = lines[index].trim();
      const isComment = line.startsWith("%%") && !line.startsWith("%%{");
      const isBlankOrDirective = line === "" || /^%%\{.*\}%%$/.test(line);
      if (isComment || (kept.length === 0 && isBlankOrDirective)) continue;
      kept.push(index);
    }
    return kept;
  }

  // Waits (briefly) for images so the layout is final before the scroll position is restored.
  function imagesLoaded(root) {
    const images = [...root.querySelectorAll("img")].map((image) => image.decode().catch(() => {}));
    return Promise.race([Promise.all(images), new Promise((resolve) => setTimeout(resolve, 1000))]);
  }

  // The scroll position is remembered relative to the top-level block at the top of the
  // viewport, so that it survives edits elsewhere in the document.
  function scrollAnchor() {
    const scroller = document.scrollingElement;
    if (scroller.scrollTop > 0 && scroller.scrollTop + window.innerHeight >= scroller.scrollHeight - 2) {
      return { atBottom: true };
    }
    const blocks = [...content.children];
    const index = blocks.findIndex((block) => block.getBoundingClientRect().bottom > 0);
    if (index < 0) return null;
    const rect = blocks[index].getBoundingClientRect();
    return { index, signatures: blocks.map(signature), offset: -rect.top, height: rect.height };
  }

  function restoreScrollAnchor(anchor) {
    const scroller = document.scrollingElement;
    if (anchor.atBottom) {
      scroller.scrollTop = scroller.scrollHeight;
      return;
    }
    const blocks = [...content.children];
    if (!blocks.length) return;
    const block = blocks[matchingIndex(anchor.signatures, blocks.map(signature), anchor.index)];
    const rect = block.getBoundingClientRect();
    // Within a changed block, keep the same relative position.
    const offset = anchor.offset > 0 && anchor.height > 0 ? (anchor.offset / anchor.height) * rect.height : anchor.offset;
    scroller.scrollTop += rect.top + offset;
  }

  // Finds where the old block at `index` ended up; a changed block maps to its replacement.
  function matchingIndex(before, after, index) {
    let oldIndex = 0;
    let newIndex = 0;
    for (const change of Diff.diffArrays(before, after)) {
      if (change.added) {
        newIndex += change.count;
        continue;
      }
      if (index < oldIndex + change.count) {
        return Math.min(change.removed ? newIndex : newIndex + index - oldIndex, after.length - 1);
      }
      oldIndex += change.count;
      if (!change.removed) newIndex += change.count;
    }
    return after.length - 1;
  }

  const signature = (block) => `${block.tagName}:${block.textContent}`;

  // Keeps the text at the top of the window in place when the window's width changes (resized,
  // or the sidebar or editor toggled) and the text reflows. While the page is magnified (pinch
  // to zoom), only part of it shows: the point at the center of the window stays there instead,
  // since the page's centered layout moves sideways as it widens.
  let reflowAnchor = null;
  let centerAnchor = null;
  let reflowAnchorScheduled = false;
  addEventListener("scroll", () => {
    if (reflowAnchorScheduled) return;
    reflowAnchorScheduled = true;
    requestAnimationFrame(() => {
      reflowAnchorScheduled = false;
      reflowAnchor = scrollAnchor();
      centerAnchor = viewCenterAnchor();
    });
  }, { passive: true });
  addEventListener("resize", () => {
    markOwnScroll();
    if (centerAnchor) restoreViewCenter(centerAnchor);
    else if (sourceLine) scrollToSourceLine(sourceLine);
    else if (reflowAnchor) restoreScrollAnchor(reflowAnchor);
  });

  // The element at the center of the window and where in it the center is, while magnified.
  function viewCenterAnchor() {
    if (visualViewport.scale <= 1) return null;
    const element = document.elementFromPoint(innerWidth / 2, innerHeight / 2);
    if (!element) return null;
    const rect = element.getBoundingClientRect();
    return { element, x: (innerWidth / 2 - rect.left) / rect.width, y: (innerHeight / 2 - rect.top) / rect.height };
  }

  function restoreViewCenter(anchor) {
    const rect = anchor.element.getBoundingClientRect();
    window.scrollTo(
      scrollX + rect.left + anchor.x * rect.width - innerWidth / 2,
      scrollY + rect.top + anchor.y * rect.height - innerHeight / 2);
  }

  // MARK: Scrolling with the editor

  // The Markdown source line kept at the top of the window while the page follows the
  // editor, or null once the user scrolls the page. Renders in progress apply it when they
  // finish.
  let sourceLine = null;
  function followSourceLine(line) {
    sourceLine = line;
    if (line) {
      markOwnScroll();
      scrollToSourceLine(line);
    }
  }

  // Scrolling done by the page itself (following the editor, rendering, reflowing) is not
  // reported to the editor. Its scroll events arrive before the next animation frame.
  let ownScroll = false;
  let reportedLine = null;
  function markOwnScroll() {
    ownScroll = true;
    reportedLine = null;
    requestAnimationFrame(() => {
      ownScroll = false;
    });
  }

  // Reports the source line at the top of the window as the user scrolls, at most once a
  // frame, so the editor can follow.
  let lineReportScheduled = false;
  addEventListener("scroll", () => {
    if (ownScroll) return;
    sourceLine = null;
    if (lineReportScheduled) return;
    lineReportScheduled = true;
    requestAnimationFrame(() => {
      lineReportScheduled = false;
      const line = sourceLineAtTop();
      if (line !== reportedLine) {
        reportedLine = line;
        native({ type: "scroll", line });
      }
    });
  }, { passive: true });

  // Source lines map to positions proportionally within the innermost block that contains
  // them. A diagram stands for the lines between its fences: its top is the first line of
  // its source and halfway down is halfway through the source. Elements with source
  // positions come in document order, which is also the order of their first lines and of
  // their tops.
  function sourceLines(element) {
    const [start, end] = element.dataset.sourcepos.match(/^(\d+):\d+-(\d+)/).slice(1).map(Number);
    const isDiagram = element.matches(".mermaid-figure, .mermaid-error") && end - start >= 2;
    return isDiagram ? [start + 1, end - 1] : [start, end];
  }

  // The source line of the editor's cursor: the innermost block holding it is outlined. A block
  // holds the lines of its source, a diagram those of its fenced block.
  let cursorLine = null;
  function setCursorLine(line) {
    cursorLine = line;
    markCursorBlock();
  }

  function markCursorBlock() {
    let block = null;
    if (cursorLine) {
      for (const element of content.querySelectorAll("[data-sourcepos]")) {
        const [start, end] = element.dataset.sourcepos.match(/^(\d+):\d+-(\d+)/).slice(1).map(Number);
        if (start > cursorLine) break;
        if (cursorLine <= end) block = element;
      }
    }
    for (const element of content.querySelectorAll(".mdpeek-cursor")) {
      if (element !== block) element.classList.remove("mdpeek-cursor");
    }
    block?.classList.add("mdpeek-cursor");
  }

  // Scrolls so that Markdown source line `line` is at the top of the window.
  function scrollToSourceLine(line) {
    let top = 0;
    for (const element of content.querySelectorAll("[data-sourcepos]")) {
      const [start, end] = sourceLines(element);
      if (start > line) break;
      const rect = element.getBoundingClientRect();
      if (!rect.height) continue;
      top = rect.top + scrollY + Math.min((line - start) / (end - start + 1), 1) * rect.height;
    }
    window.scrollTo({ top: line > 1 ? top : 0 });
  }

  // The Markdown source line at the top of the window: the inverse of scrollToSourceLine.
  function sourceLineAtTop() {
    let line = 1;
    for (const element of content.querySelectorAll("[data-sourcepos]")) {
      const rect = element.getBoundingClientRect();
      if (rect.top > 0) break;
      if (!rect.height) continue;
      const [start, end] = sourceLines(element);
      line = start + Math.min(-rect.top / rect.height, 1) * (end - start + 1);
    }
    return Math.floor(line);
  }

  return { render, showWelcome, scrollToHeading, followSourceLine, sourceLineAtTop, find, findNext, clearFind, showUnsavedNotice, setCursorLine };
})();
