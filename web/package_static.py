"""Package a Godot Web export as a standalone static site below the 25 MiB asset limit."""
import argparse
import gzip
import hashlib
from pathlib import Path
import shutil

LIMIT = 25 * 1024 * 1024
ROOT = Path(__file__).resolve().parents[1]


def package(source, target):
    if (source / "index.wasm").resolve() == (target / "index.wasm").resolve():
        raise ValueError("Choose a separate output directory for the packaged site.")
    source_js = (source / "index.js").read_text()
    raw = (source / "index.wasm").read_bytes()
    if raw[:4] != b"\0asm":
        raise ValueError("Invalid Godot WebAssembly export.")
    payload = gzip.compress(raw, compresslevel=9, mtime=0)
    if len(payload) >= LIMIT:
        raise ValueError("Compressed runtime exceeds the static-host asset limit.")
    digest = hashlib.sha256(payload).hexdigest()[:14]
    payload_name = f"engine-{digest}.gz.bin"
    target.mkdir(parents=True, exist_ok=True)
    # The engine's public startup API and audio worklet paths stay intact. Scope
    # response decoding to the loader's own fetch binding for its exact WASM URL.
    prefix = """(function (nativeFetch, wasmURL, payloadURL) {
  const fetch = function (input, init) {
    const url = new URL(typeof input === 'string' || input instanceof URL ? input : input.url, document.baseURI);
    if (url.href !== wasmURL.href) return nativeFetch(input, init);
    return nativeFetch(payloadURL, init).then(function (response) {
      if (!response.ok) return response;
      return new Response(response.body.pipeThrough(new DecompressionStream('gzip')), {
        headers: {'Content-Type': 'application/wasm', 'Content-Length': 'RAW_SIZE'}
      });
    });
  };
""".replace("RAW_SIZE", str(len(raw)))
    suffix = f"""
  globalThis.Engine = Engine;
}})(globalThis.fetch.bind(globalThis), new URL('index.wasm', document.baseURI), new URL('{payload_name}', document.baseURI));
"""
    output_js = prefix + source_js + suffix
    for name in ("index.html", "index.pck", "index.icon.png", "index.apple-touch-icon.png",
                 "index.audio.worklet.js", "index.audio.position.worklet.js"):
        item = source / name
        if item.stat().st_size >= LIMIT:
            raise ValueError(f"{name} exceeds the static-host asset limit.")
        shutil.copyfile(item, target / name)
    (target / payload_name).write_bytes(payload)
    (target / "index.js").write_text(output_js)
    licenses = (ROOT / "web" / "Godot-Notices.txt").read_text() + "\n\n" + (ROOT / "demo/browser_fonts/OFL.txt").read_text()
    (target / "licenses.txt").write_text(licenses)
    print(f"Standalone browser build: {target}. Runtime {len(raw):,} -> {len(payload):,} bytes.")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("export", type=Path, help="Godot Web export directory containing index.html")
    parser.add_argument("output", type=Path, help="Static site's play directory")
    args = parser.parse_args()
    package(args.export, args.output)
