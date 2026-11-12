// The header (fixed at the top) gets a shadow once content reaches it: the top of the big logo on the
// overview, the first thing on other pages
(() => {
  const header = document.querySelector(".top");
  const first = document.querySelector(".hero-mark, main > section > :first-child");
  if (!header || !first) return;
  const update = () => {
    const edge = first.getBoundingClientRect().top;
    header.classList.toggle("covering", edge < header.offsetHeight);
  };
  // The header is fixed: keep the page's top space the same as its height
  const fit = () => { document.body.style.paddingTop = header.offsetHeight + "px"; update(); };
  addEventListener("scroll", update, { passive: true });
  addEventListener("resize", fit);
  fit();
})();

// Clips: only the ones on screen play, so phones aren't decoding all of them at once; small
// screens get the lighter version. Without this script, each shows its poster.
(() => {
  const videos = document.querySelectorAll("video[data-src]");
  if (!videos.length) return;
  const small = matchMedia("(max-width: 900px)").matches;
  const still = matchMedia("(prefers-reduced-motion: reduce)").matches;
  const load = v => {
    if (v.getAttribute("src")) return;
    v.src = small && v.dataset.small ? v.dataset.small : v.dataset.src;
  };
  if (still || !("IntersectionObserver" in window)) {
    if (!still) videos.forEach(v => { load(v); v.play().catch(() => {}); });
    return;
  }
  const seen = new IntersectionObserver(entries => {
    for (const e of entries) {
      const v = e.target;
      if (e.isIntersecting) { load(v); v.play().catch(() => {}); }
      else if (!v.paused) v.pause();
    }
  }, { rootMargin: "120px 0px", threshold: 0.2 });
  videos.forEach(v => seen.observe(v));
})();

// The changelog's release picker: built from the releases on the page (so a new release needs
// nothing more), filtered as you type; arrows move, Enter goes there, Esc closes
(() => {
  const box = document.getElementById("cl-pick");
  if (!box) return;
  const input = box.querySelector("input"), list = box.querySelector("ul");
  const releases = [...document.querySelectorAll("section.cl-release[id]")].map(s => {
    const t = s.querySelector("h2 time");
    return { id: s.id, date: t ? t.textContent.trim() : "" };
  });
  if (!releases.length) return;
  box.hidden = false;
  let shown = [], hot = 0, current = location.hash.slice(1);

  const render = () => {
    const q = input.value.trim().toLowerCase().replace(/^v/, "");
    shown = releases.filter(r => !q || r.id.slice(1).includes(q) || r.date.toLowerCase().includes(q));
    hot = Math.max(0, Math.min(hot, shown.length - 1));
    list.innerHTML = "";
    if (!shown.length) {
      const li = document.createElement("li");
      li.className = "empty";
      li.textContent = "No release matches that yet";
      list.append(li);
      return;
    }
    shown.forEach((r, i) => {
      const li = document.createElement("li");
      li.id = "cl-opt-" + r.id.replace(/\./g, "-");
      li.setAttribute("role", "option");
      li.setAttribute("aria-selected", i === hot);
      li.className = (i === hot ? "hot " : "") + (r.id === current ? "here" : "");
      li.innerHTML = `<span>${r.id}</span><time>${r.date}</time>`;
      li.addEventListener("mousemove", () => { if (hot !== i) { hot = i; mark(); } });
      li.addEventListener("mousedown", e => { e.preventDefault(); go(r); });
      list.append(li);
    });
    mark();
  };
  const mark = () => {
    [...list.children].forEach((li, i) => {
      li.classList.toggle("hot", i === hot);
      li.setAttribute("aria-selected", i === hot);
    });
    const li = list.children[hot];
    if (li && li.id) { input.setAttribute("aria-activedescendant", li.id); li.scrollIntoView({ block: "nearest" }); }
  };
  const open = () => {
    if (!list.hidden) return;
    list.hidden = false; box.classList.add("open"); input.setAttribute("aria-expanded", "true");
    hot = Math.max(0, releases.findIndex(r => r.id === current));
    render();
  };
  const close = () => {
    list.hidden = true; box.classList.remove("open"); input.setAttribute("aria-expanded", "false");
    input.removeAttribute("aria-activedescendant");
  };
  const go = r => {
    current = r.id;
    input.value = "";
    close();
    input.blur();
    history.replaceState(null, "", "#" + r.id);
    document.getElementById(r.id).scrollIntoView({ behavior: matchMedia("(prefers-reduced-motion: reduce)").matches ? "auto" : "smooth" });
  };

  input.addEventListener("focus", open);
  input.addEventListener("click", open);
  input.addEventListener("input", () => { hot = 0; open(); render(); });
  input.addEventListener("blur", close);
  input.addEventListener("keydown", e => {
    if (e.key === "ArrowDown" || e.key === "ArrowUp") {
      e.preventDefault();
      if (list.hidden) { open(); return; }
      if (!shown.length) return;
      hot = (hot + (e.key === "ArrowDown" ? 1 : -1) + shown.length) % shown.length;
      mark();
    } else if (e.key === "Home" && !list.hidden && !input.value) { e.preventDefault(); hot = 0; mark(); }
    else if (e.key === "End" && !list.hidden && !input.value) { e.preventDefault(); hot = shown.length - 1; mark(); }
    else if (e.key === "Enter") { e.preventDefault(); if (shown[hot]) go(shown[hot]); }
    else if (e.key === "Escape") { if (input.value) { input.value = ""; render(); } else { close(); input.blur(); } }
  });
  addEventListener("hashchange", () => { current = location.hash.slice(1); });
})();
