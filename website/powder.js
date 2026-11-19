const slope = document.querySelector(".slope");
const video = slope.querySelector("video");
const motion = matchMedia("(prefers-reduced-motion: no-preference)");
const connection = navigator.connection;
const portrait = matchMedia("(max-aspect-ratio: 7/10)");
let inView = false;
let pageActive = true;

function updatePlayback() {
  const allowMotion = motion.matches && !connection?.saveData;
  if (!allowMotion) video.classList.remove("playing");

  if (!allowMotion || !inView || document.hidden || !pageActive) {
    video.pause();
    return;
  }

  const source = portrait.matches ? video.dataset.portraitSrc : video.dataset.src;
  if (video.getAttribute("src") !== source) {
    const time = video.currentTime;
    video.src = source;
    if (time > 0) video.currentTime = time;
  }
  video.play().catch(() => {});
}

video.addEventListener("playing", () => video.classList.add("playing"));
video.addEventListener("error", () => video.classList.remove("playing"));
new IntersectionObserver(([entry]) => {
  inView = entry.isIntersecting;
  updatePlayback();
}).observe(slope);
portrait.addEventListener("change", updatePlayback);
motion.addEventListener("change", updatePlayback);
connection?.addEventListener("change", updatePlayback);
document.addEventListener("visibilitychange", updatePlayback);
window.addEventListener("pagehide", () => {
  pageActive = false;
  updatePlayback();
});
window.addEventListener("pageshow", () => {
  pageActive = true;
  updatePlayback();
});
