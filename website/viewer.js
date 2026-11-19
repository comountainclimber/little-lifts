import {
  Scene, Group, PerspectiveCamera, WebGLRenderer, HemisphereLight,
  DirectionalLight, Box3, Vector3, SRGBColorSpace, GLTFLoader
} from "./vendor/three-gltf.js";

export function createViewer(canvas, stage, hangWire) {
  const renderer = new WebGLRenderer({canvas, alpha:true, antialias:true, powerPreference:"low-power"});
  renderer.setClearColor(0x000000, 0);
  renderer.outputColorSpace = SRGBColorSpace;
  const scene = new Scene();
  const pivot = new Group();
  const camera = new PerspectiveCamera(26, 1, .05, 50);
  scene.add(pivot);
  scene.add(new HemisphereLight(0xfff9f2, 0xb5c8db, 1.8));
  const sun = new DirectionalLight(0xffeed7, 2.6);
  sun.position.set(-3, 5, 4);
  scene.add(sun);
  const rim = new DirectionalLight(0xecf5ff, .8);
  rim.position.set(2, 2, -3);
  scene.add(rim);

  const loader = new GLTFLoader();
  const cache = new Map();
  const hook = new Vector3();
  const projected = new Vector3();
  const swungGrip = new Vector3();
  const reducedMotion = matchMedia("(prefers-reduced-motion: reduce)");
  let animation = 0;
  let lastFrame = 0;
  let model;
  let version = 0;
  let yaw = -.62, pitch = .16, radius = 1;

  function draw() {
    if (!model) return;
    const distance = radius / (Math.sin(camera.fov * Math.PI / 360) * Math.min(1, camera.aspect));
    camera.position.set(distance * Math.sin(yaw) * Math.cos(pitch), distance * Math.sin(pitch), distance * Math.cos(yaw) * Math.cos(pitch));
    camera.lookAt(0, 0, 0);
    renderer.render(scene,camera);
    projected.copy(hook).project(camera);
    hangWire((projected.x + 1) * .5, (1 - projected.y) * .5);
  }
  function resize() {
    if (!stage.clientWidth || !stage.clientHeight) return;
    renderer.setPixelRatio(Math.min(window.devicePixelRatio || 1, 2));
    renderer.setSize(stage.clientWidth,stage.clientHeight,false);
    camera.aspect = stage.clientWidth / stage.clientHeight;
    camera.updateProjectionMatrix();
    draw();
  }
  new ResizeObserver(resize).observe(stage);

  // Tiny wind movement pivots about the cable grip, not the middle of the cabin.
  function sway(time) {
    animation = 0;
    if (!model || document.hidden || reducedMotion.matches || canvas.hidden) return;
    if (time - lastFrame >= 36) {
      pivot.rotation.set(.006 * Math.sin(time * .00093),0,.019 * Math.sin(time * .00076));
      swungGrip.copy(hook).applyQuaternion(pivot.quaternion);
      pivot.position.copy(hook).sub(swungGrip);
      lastFrame = time;
      draw();
    }
    animation = requestAnimationFrame(sway);
  }
  function wake() {
    if (animation) cancelAnimationFrame(animation);
    animation = 0;
    if (document.hidden) return;
    if (reducedMotion.matches) {
      pivot.rotation.set(0,0,0);
      pivot.position.set(0,0,0);
      draw();
    } else {
      animation = requestAnimationFrame(sway);
    }
  }
  document.addEventListener("visibilitychange",wake);
  reducedMotion.addEventListener("change",wake);

  function findGrip(bbox) {
    // The clamp atop each in-game carrier is in a different place.
    const vertex = new Vector3();
    const top = new Box3();
    model.traverse(part => {
      const positions = part.geometry?.attributes?.position;
      if (!positions) return;
      for (let i = 0; i < positions.count; i++) {
        vertex.fromBufferAttribute(positions,i).applyMatrix4(part.matrixWorld);
        if (vertex.y >= bbox.max.y - .008) top.expandByPoint(vertex);
      }
    });
    top.getCenter(hook);
  }
  async function show(key) {
    const id = ++version;
    if (!cache.has(key)) {
      cache.set(key,loader.loadAsync("art/" + key + ".glb").catch(error => {
        cache.delete(key);
        throw error;
      }));
    }
    const {scene: loaded} = await cache.get(key);
    if (id !== version) return false;
    if (model) pivot.remove(model);
    model = loaded;
    pivot.rotation.set(0,0,0);
    pivot.position.set(0,0,0);
    pivot.updateMatrixWorld(true);
    pivot.add(model);
    model.position.set(0,0,0);
    const bounds = new Box3().setFromObject(model);
    const size = bounds.getSize(new Vector3());
    model.position.copy(bounds.getCenter(new Vector3())).multiplyScalar(-1);
    model.updateMatrixWorld(true);
    bounds.setFromObject(model);
    findGrip(bounds);
    radius = Math.max(size.y * .68, Math.hypot(size.x,size.z) * .47);
    yaw = -.67;
    pitch = .18;
    resize();
    wake();
    return true;
  }

  let pointer;
  canvas.addEventListener("pointerdown", event => {
    if (!event.isPrimary || (event.pointerType === "mouse" && event.button !== 0)) return;
    pointer = {id:event.pointerId,x:event.clientX,y:event.clientY};
    canvas.setPointerCapture(event.pointerId);
  });
  canvas.addEventListener("pointermove", event => {
    if (!pointer || event.pointerId !== pointer.id) return;
    yaw -= (event.clientX - pointer.x) * .011;
    pitch = Math.max(-.34,Math.min(.80,pitch + (event.clientY-pointer.y) * .007));
    pointer.x = event.clientX;
    pointer.y = event.clientY;
    draw();
  });
  for (const name of ["pointerup","pointercancel","lostpointercapture"]) {
    canvas.addEventListener(name,event => {if (pointer?.id === event.pointerId) pointer = null;});
  }
  canvas.addEventListener("keydown",event => {
    if (event.key === "ArrowLeft" || event.key === "ArrowRight") {
      event.preventDefault();
      yaw += event.key === "ArrowLeft" ? -.18 : .18;
      draw();
    }
  });
  return {show,resize};
}
