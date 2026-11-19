const video = document.querySelector(".slope video");
const motion = matchMedia("(prefers-reduced-motion: no-preference)");

// One short turn, then the page rests on the photograph. The static image is
// also the complete experience on slow connections and in reduced-motion mode.
let played = false;
function showTurn() {
  if (!motion.matches) {
    video.pause();
    video.classList.remove("playing");
    return;
  }
  if (played || navigator.connection?.saveData) return;
  played = true;
  video.src = "art/powder-turn.mp4";
  video.play().catch(() => video.classList.remove("playing"));
}
video.addEventListener("playing", () => video.classList.add("playing"));
video.addEventListener("timeupdate", () => {
  if (video.duration - video.currentTime < .32) video.classList.remove("playing");
});
video.addEventListener("ended", () => video.classList.remove("playing"));
motion.addEventListener("change", showTurn);
if (document.readyState === "complete") showTurn();
else window.addEventListener("load", showTurn, { once: true });
