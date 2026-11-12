// Slate's docs: the list of every page, in order, by section, and what builds the sidebar, the
// "On this page" list and the previous / next links from it. A new page goes in PAGES, and
// everything else follows. Each page's `covers` names the Settings pages it documents (their
// ids in shell/SettingsIndex.qml): tests/static/test_docs.py makes sure every Settings page is
// covered by one, and that every page here has its file.
const SECTIONS = [
  { title: "Getting started", pages: [
    { id: "introduction", title: "Introduction", icon: 0xEAC5, about: "What Slate is, and what makes it different" },
    { id: "install", title: "Installing Slate", icon: 0xEA96, about: "Getting it on your computer, distro by distro" },
    { id: "first-steps", title: "Your first login", icon: 0xEF4C, about: "The Welcome window, the Super key, and finding your way" },
    { id: "updating", title: "Updates", icon: 0xEB13, about: "New versions: what's new, updating, and going back", covers: ["updates"] },
  ]},
  { title: "The desktop", pages: [
    { id: "menu-bar", title: "The menu bar", icon: 0xEAD7, about: "What's on it, its panels, and arranging it your way", covers: ["bar"] },
    { id: "control-centre", title: "Control centre and panels", icon: 0xEB3F, about: "Quick switches, media, the weather and the bar's panels", covers: ["control"] },
    { id: "dock", title: "The dock", icon: 0xEAD3, about: "Pinned and running apps, Downloads and the waste basket", covers: ["dock"] },
    { id: "launcher", title: "The launcher", icon: 0xEB1C, about: "Finding apps, settings, files, sums and more", covers: ["launcher"] },
    { id: "notifications", title: "Notifications and indicators", icon: 0xEA35, about: "Pop-ups, history, Do Not Disturb and on-screen indicators", covers: ["notifications"] },
    { id: "menus", title: "Right-click menus", icon: 0xEF4F, about: "On the desktop, the menu bar and the dock" },
    { id: "nova", title: "Nova, the assistant", icon: 0xF014, about: "Asking an AI agent you already use to do things for you", covers: ["assistant"] },
  ]},
  { title: "Windows and workspaces", pages: [
    { id: "windows", title: "Windows", icon: 0xEFE6, about: "Tiling, side stack, scrolling, floating, title bars", covers: ["windows"] },
    { id: "switcher", title: "Switching windows", icon: 0xEB31, about: "Super+Tab, with live previews" },
    { id: "workspaces", title: "Workspaces and the overview", icon: 0xEDBA, about: "Moving between them, naming them, the secret workspace", covers: ["workspaces"] },
    { id: "spaces", title: "Spaces", icon: 0xEEF6, about: "Saving a set of workspaces and bringing it back", covers: ["spaces"] },
    { id: "hot-corners", title: "Hot corners", icon: 0xF7A0, about: "Actions for the corners of the screen", covers: ["hotcorners"] },
  ]},
  { title: "Look and feel", pages: [
    { id: "appearance", title: "Appearance", icon: 0xEB01, about: "Theme, colours, glass, shadows, fonts, size and motion", covers: ["appearance"] },
    { id: "wallpaper", title: "Wallpaper", icon: 0xEF56, about: "Your pictures, Slate's own, and changing by itself", covers: ["wallpaper"] },
    { id: "icons-and-pointers", title: "Icons and pointers", icon: 0xF1D4, about: "Icon themes, folder colours, app icons and pointer styles", covers: ["icons"] },
    { id: "app-theming", title: "App theming", icon: 0xEBB8, about: "Your other apps in Slate's colours", covers: ["apptheming"] },
  ]},
  { title: "Your computer", pages: [
    { id: "displays", title: "Displays", icon: 0xEA89, about: "Arranging screens, resolution, scale and Slate's size", covers: ["displays"] },
    { id: "input", title: "Keyboard, mouse and touchpad", icon: 0xEBD6, about: "Layouts, key repeat, pointer speed and gestures", covers: ["input"] },
    { id: "sound", title: "Sound", icon: 0xEB51, about: "Speakers, microphones, volume and Slate's sounds", covers: ["sound"] },
    { id: "power", title: "Power and battery", icon: 0xEA38, about: "Power modes, the charging limit, the lid and the power button", covers: ["power"] },
    { id: "network", title: "Network and Bluetooth", icon: 0xF09F, about: "Wi-Fi, wired connections, Airplane Mode and Bluetooth devices", covers: ["wifi", "bluetooth"] },
    { id: "printers-webcam", title: "Printers and the webcam", icon: 0xEB0E, about: "Adding printers, scanning, and your camera's picture", covers: ["printers", "webcam"] },
    { id: "security", title: "Locking and login", icon: 0xEAE2, about: "The lock screen, the login screen and the screensaver", covers: ["lock", "screensaver"] },
    { id: "privacy", title: "Private Mode and the camera", icon: 0xF227, about: "Turning off the mic, camera, assistants and screen capture", },
  ]},
  { title: "Apps and tools", pages: [
    { id: "apps", title: "Default and startup apps", icon: 0xEBB6, about: "Which apps open things, and what opens at login", covers: ["apps", "startup"] },
    { id: "screenshots", title: "Screenshots", icon: 0xF201, about: "Areas, windows and screens, saved and marked up", covers: ["screenshots"] },
    { id: "clipboard", title: "Clipboard and emoji", icon: 0xEA6F, about: "Clipboard history and the emoji picker" },
    { id: "night-light", title: "Night light, game mode and caffeine", icon: 0xEAF8, about: "Warmer evenings, smoother games, and staying awake", covers: ["general"] },
    { id: "region", title: "Region and time", icon: 0xEA70, about: "Time zone, the clock, dates and the weather's units", covers: ["datetime"] },
  ]},
  { title: "Reference", pages: [
    { id: "shortcuts", title: "Keyboard shortcuts", icon: 0xEA78, about: "Every shortcut, and choosing Slate's set or Hyprland's", covers: ["shortcuts"] },
    { id: "settings", title: "The Settings app", icon: 0xEB20, about: "Finding settings, search, restoring defaults", covers: ["overview"] },
    { id: "command-line", title: "The slate command", icon: 0xEBEF, about: "Restarting, logs, and controlling Slate from scripts" },
    { id: "customising", title: "Your own config", icon: 0xEA77, about: "Hyprland and QML tweaks of your own, kept safe", covers: ["about"] },
    { id: "assistant-server", title: "Slate for AI agents", icon: 0xF00A, about: "The MCP server, what it allows and what it refuses" },
    { id: "troubleshooting", title: "Troubleshooting", icon: 0xEADD, about: "When something's not right: the Debug page, logs and resetting", covers: ["debug"] },
  ]},
];

(() => {
  const all = [];
  for (const s of SECTIONS) for (const p of s.pages) all.push(Object.assign({ section: s.title }, p));
  const here = document.body.dataset.page || "";
  const glyph = c => "&#x" + c.toString(16).toUpperCase() + ";";

  // ---- The sidebar: every section and page, with a filter at the top ----------------------
  const nav = document.getElementById("docs-nav");
  if (nav) {
    const list = q => {
      const words = q.toLowerCase().split(/\s+/).filter(Boolean);
      const hit = p => words.every(w => (p.title + " " + p.about + " " + p.section).toLowerCase().includes(w));
      let html = "";
      for (const s of SECTIONS) {
        const pages = s.pages.filter(hit);
        if (!pages.length) continue;
        html += `<h4>${s.title}</h4><ul>` + pages.map(p =>
          `<li><a href="${p.id}.html"${p.id === here ? ' class="current" aria-current="page"' : ""}>` +
          `<i class="ti">${glyph(p.icon)}</i>${p.title}</a></li>`).join("") + "</ul>";
      }
      return html || `<p class="none">Nothing matches "${q.replace(/</g, "&lt;")}". Try fewer words.</p>`;
    };
    nav.innerHTML = `<div class="docs-search"><i class="ti">&#xEB1C;</i>` +
      `<input type="search" placeholder="Find a page" aria-label="Find a page"></div><div class="docs-list">${list("")}</div>`;
    const input = nav.querySelector("input"), out = nav.querySelector(".docs-list");
    input.addEventListener("input", () => { out.innerHTML = list(input.value); });
    input.addEventListener("keydown", e => {
      if (e.key === "Enter") { const a = out.querySelector("a"); if (a) location.href = a.href; }
    });
    // (narrow screens: a button shows and hides it)
    const button = document.querySelector(".docs-menu");
    if (button) button.addEventListener("click", () => nav.classList.toggle("open"));
    // (the current page in view in the sidebar: the sidebar scrolled, not the page)
    const cur = nav.querySelector("a.current");
    if (cur) nav.scrollTop = Math.max(0, cur.offsetTop - nav.clientHeight / 2);
  }

  // ---- The docs' front page: a card for each section's first page --------------------------
  const home = document.getElementById("docs-sections");
  if (home) {
    home.innerHTML = all.map(p =>
      `<a href="${p.id}.html"><i class="ti">${glyph(p.icon)}</i><strong>${p.title}</strong><span>${p.about}</span></a>`).join("");
  }

  // ---- Previous and next, and a link to suggest an edit -----------------------------------
  const pager = document.getElementById("docs-pager");
  const i = all.findIndex(p => p.id === here);
  if (pager && i >= 0) {
    const prev = all[i - 1], next = all[i + 1];
    pager.innerHTML =
      (prev ? `<a class="prev" href="${prev.id}.html"><small>Previous</small>${prev.title}</a>` : "") +
      (next ? `<a class="next" href="${next.id}.html"><small>Next</small>${next.title}</a>` : "") +
      `<a class="edit" href="https://github.com/daylerees/slate/edit/master/site/docs/${here}.html">` +
      `<i class="ti">&#xEB04;</i> Suggest a change to this page</a>`;
  }

  // ---- On this page: the page's headings, the one you're reading lit -----------------------
  const toc = document.getElementById("docs-toc");
  const heads = [...document.querySelectorAll(".doc h2, .doc h3")];
  if (toc && heads.length > 1) {
    const slug = t => t.toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/^-|-$/g, "");
    for (const h of heads) if (!h.id) h.id = slug(h.textContent);
    toc.innerHTML = "<h4>On this page</h4><ul>" + heads.map(h =>
      `<li class="${h.tagName === "H3" ? "sub" : ""}"><a href="#${h.id}">${h.textContent}</a></li>`).join("") + "</ul>";
    const links = [...toc.querySelectorAll("a")];
    const light = () => {
      let cur = 0;
      heads.forEach((h, k) => { if (h.getBoundingClientRect().top < 120) cur = k; });
      links.forEach((a, k) => a.classList.toggle("here", k === cur));
    };
    addEventListener("scroll", light, { passive: true });
    light();
  }
})();
