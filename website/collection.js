const canvas = document.querySelector("#model");
const rig = document.querySelector("#rig");
const scene = document.querySelector("#scene");
const poster = document.querySelector("#poster");
const wire = document.querySelector("#wire");
const rim = document.querySelector("#wire-rim");
const options = [...document.querySelectorAll("[data-lift]")];
const labels = Object.fromEntries(options.map(button => [button.dataset.lift,button.textContent]));
let selected = "tram";
let viewer;

function hangWire(u, v) {
  const frame = scene.getBoundingClientRect();
  const bounds = rig.getBoundingClientRect();
  const x = bounds.left - frame.left + u * bounds.width;
  const y = bounds.top - frame.top + v * bounds.height;
  const slope = frame.width < 700 ? -.17 : -.105;
  const path = "M 0 " + (y - slope * x).toFixed(2) + " L " + frame.width + " " + (y + slope * (frame.width - x)).toFixed(2);
  wire.setAttribute("d", path);
  rim.setAttribute("d", path);
}

function hangPoster() {
  if (poster.hidden) return;
  const w = rig.clientWidth, h = rig.clientHeight;
  if (!w || !h) return;
  const ratio = poster.naturalWidth && poster.naturalHeight ? poster.naturalWidth / poster.naturalHeight : 840 / 650;
  const height = Math.min(w / ratio, h);
  const y = (h - height) * .5 + height * (selected === "tram" ? .13 : .08);
  hangWire(.50, y / h);
}

function showPoster() {
  canvas.hidden = true;
  canvas.tabIndex = -1;
  poster.hidden = false;
  poster.alt = labels[selected];
  poster.src = "art/" + selected + "-cutout.webp";
  hangPoster();
}

async function showModel(key) {
  if (!viewer) return;
  try {
    if (!await viewer.show(key) || key !== selected) return;
    canvas.hidden = false;
    canvas.tabIndex = 0;
    canvas.setAttribute("aria-label", labels[key] + ". Drag or use the left and right arrow keys to rotate the lift.");
    poster.hidden = true;
    viewer.resize();
  } catch {
    if (key === selected) showPoster();
  }
}

for (const option of options) {
  option.addEventListener("click", () => {
    const key = option.dataset.lift;
    if (selected === key) return;
    selected = key;
    for (const button of options) button.setAttribute("aria-pressed", String(button === option));
    showPoster();
    showModel(key);
  });
}
poster.addEventListener("load", hangPoster);
window.addEventListener("resize", hangPoster);
hangPoster();

try {
  const {createViewer} = await import("./viewer.js");
  viewer = createViewer(canvas, rig, hangWire);
  canvas.addEventListener("webglcontextlost", () => showPoster());
  canvas.addEventListener("webglcontextrestored", () => showModel(selected));
  await showModel(selected);
} catch {
  showPoster();
}
