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
