# Little Lifts

Build a small ski resort across Village Hill, the wooded Saddle, and Summit Ridge. A vintage single chair is already turning when the valley opens. The longest lift spans about four times the length of the first one.

## Play on Mac

Open `build/Little Lifts.app`. To play from source, import `project.godot` in Godot 4.7.2 and press F5.

1. Choose **Cut a run**. Start at the upper ring, draw downhill through a stand of pines, and release at the lower ring. Use the Gentle arc, S turns, or Tree weave survey as a guide. Draw your own bends around stands of trees to leave islands of pines. The marks beside your stroke show the clearing width.
2. Watch a skier or snowboarder use the new trail. When the first rider reaches the lower station, **Build a lift** offers the Saddle double chair. Drag uphill between the survey rings or find another clear lift line on the accessible mountain.
3. Cut and ski a run served by the double chair to unlock the high-speed summit tram. Earlier lifts and trails keep running. Use the selector in **Cut a run** to return to an earlier lift.
4. Open **Village** to choose a building and click a marked plot. The first completed cut opens the waffle hut. Building the double chair opens the ski school, and the tram opens the day lodge. Ski racks, benches, and lamps appear as the resort grows.

5. Choose **Terrain** and select **Terrain park**. Click a marked site on a cut run to shape a pair of big kickers. The survey checks the approach, space between landings, slope and clearance. For **Summit extremes**, build the tram and cut a line that reaches a natural ridge ledge. Click the survey ring above an eligible lip to open that descent.

Clouds gather and snowfall drifts across the slopes over several minutes. Each resort opens in clear light with a view of the full ski area and its surrounding range.

Construction, terrain features, trail clearings, completed runs, and building placements save automatically on this Mac. Riders start a fresh lap when the resort reopens.

## Camera and controls

- Click a downhill rider, choose **Follow a rider**, or press **F** to follow a descent. The camera returns to the valley when the rider finishes.
- In **Explore**, left-drag to rotate and tilt the view. Right-drag to pan in any tool, or hold **Shift** and left-drag in Explore. Scroll or pinch to zoom at the pointer. **Space** toggles slow motion. **R** opens the mountain overview.
- Click **Mute** in the left sidebar or press **M** to toggle game sound. Little Lifts remembers your choice when you reopen it.
- **1–5** select Explore, Cut a run, Build a lift, Village, and Terrain. **Escape** cancels a stroke or returns to the overview.

## Interface

The left sidebar uses ski-area wayfinding signs. Explore and Cut a run show the trail key. A green circle means easy, a blue square means intermediate, and a black diamond means advanced. While cutting a trail, the key shows the grade of its steepest sustained stretch. Terrain parks have orange ovals and summit extremes have double black diamonds. Lift, village, and camera tools have their own pictograms and text labels.

## Verify and export

Run `godot --headless --path . --script res://checks/demo_check.gd` for the interactive progression and save/reopen checks. Run `godot --headless --path . --script res://skiing/check_runs.gd` for downhill routing, terrain clearance and snow tests.

Install matching Godot 4.7.2 macOS export templates, create a build directory, and run `godot --headless --export-release macOS "build/Little Lifts.app"`.

### Browser build

With the matching Godot Web templates installed, run the following from the project root.

```sh
mkdir -p build/web
godot --headless --path . --import
godot --headless --path . --export-release Web build/web/index.html
python3 web/package_static.py build/web build/site/play
```

Serve `build/site` with a static HTTP server and open `/play/`. The package includes a compressed, single-threaded WebAssembly runtime and the WebGL 2 game. Construction and sound settings are saved in browser storage for that site.

## Browser build

Export the **Web** preset with matching Godot 4.7.2 Web templates, then run `python3 web/package_static.py build/web website/play`. Serve the `website` directory over HTTP to play. The title screen and lift viewer are plain HTML, CSS and JavaScript. Web saves stay in the browser profile for the site's origin.
