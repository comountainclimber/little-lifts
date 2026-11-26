# Little Lifts

Build a small ski resort across Village Hill, the wooded Saddle, and Summit Ridge. A vintage single chair is already turning when the valley opens. The longest lift spans about four times the length of the first one.

## Play on Mac

Open `build/Little Lifts.app`. To play from source, import `project.godot` in Godot 4.7.2 and press F5.

1. Choose **Cut a run**. Click the snow to place bends between the lift stations. Drag a bend to move it, use **Undo bend** to remove the last one, and choose **Cut trail** to open the route. Drawing from ring to ring opens a freehand trail on release. Sketching only part of a trail leaves an editable draft with links to both stations. Gentle arc, S turns, and Tree weave give you survey lines to follow. Your route can cross open snow or clear a strip through the pines.
2. Watch a skier or snowboarder use the new trail. When the first rider reaches the lower station, **Build a lift** offers the Saddle double chair. Click the two terminal locations or drag between them. The survey rings suggest one route. You can put a lift elsewhere on accessible terrain, including through the woods. Construction clears the cable corridor and skiable return. Hold **Alt** for precise placement near a survey ring.
3. Cut and ski a run served by the double chair to unlock the high-speed summit tram. Earlier lifts and trails keep running. Use the selector in **Cut a run** to return to an earlier lift.
4. Open **Village** to choose a building and click a marked plot. The first completed cut opens the waffle hut. Building the double chair opens the ski school, and the tram opens the day lodge. Ski racks, benches, and lamps appear as the resort grows.

5. Choose **Terrain** and select **Terrain park**. Click a marked site on a cut run to shape a pair of big kickers. The survey checks the approach, space between landings, slope and clearance. Select **Summit extremes** to inspect the seven ridge ledges at any time. Build the tram and cut a line that reaches one to open it. Click the survey ring above an eligible lip to open that descent.

Clouds gather and snowfall drifts across the slopes over several minutes. Each resort opens in clear light with a view of the full ski area and its surrounding range.

Construction, terrain features, trail clearings, completed runs, and building placements save automatically on this Mac. Riders start a fresh lap when the resort reopens.

## Camera and controls

- Click a downhill rider, choose **Follow a rider**, or press **F** to follow a descent. The camera returns to the valley when the rider finishes.
- In **Explore**, left-drag to rotate and tilt the view. Right-drag to pan in any tool, or hold **Shift** and left-drag in Explore. Over the mountain, use the mouse wheel or a vertical two-finger scroll to zoom at the pointer. On a trackpad, spread two fingers to zoom in or pinch together to zoom out. **+** and **−** zoom at the center of the map. **Space** toggles slow motion. **R** opens the mountain overview.
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
python3 web/package_static.py build/web website/play
```

Serve `website` over HTTP. The title screen opens the game at `/play/`. Construction and sound settings are saved in browser storage for that site.
