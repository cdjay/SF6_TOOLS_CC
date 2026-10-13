"use strict";
const poster = document.querySelector(".poster"), stage = document.querySelector(".stage");
function fit() {
    const exporting = new URLSearchParams(location.search).has("export");
    document.body.classList.toggle("export", exporting);
    const scale = exporting ? 1 : Math.min(1, Math.max(0.2, (innerWidth - 32) / 1080));
    poster.style.transform = `scale(${scale})`;
    stage.style.width = `${1080 * scale}px`;
    stage.style.height = `${poster.offsetHeight * scale}px`;
}
document.querySelector("#fighter").addEventListener("change", event => { location.href = event.target.value; });
document.querySelector("#clean").addEventListener("click", () => {
    document.body.classList.toggle("clean"); fit();
});
document.addEventListener("keydown", event => {
    if (event.key === "Escape") { document.body.classList.remove("clean"); fit(); }
});
addEventListener("resize", fit);
addEventListener("load", fit);
new ResizeObserver(fit).observe(poster);
fit();
