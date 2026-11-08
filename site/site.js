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
