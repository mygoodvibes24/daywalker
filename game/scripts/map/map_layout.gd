extends RefCounted
## Port Vesper's large map, as data: bounds, districts, landmarks, the Hunt's deployment
## points and boss arenas. city.gd builds the geometry from this, the Hunt (hunt_config.gd,
## poi_spawner.gd, the Curfew), the map screen, loot and the navmesh bake read it.
##
## Layout (north is -Z, as on the compass), following docs/concept_art/10_city_overview.jpg:
##
##        x: -240        -70           125          240
##   z -240 +-------------+-------------+------------+
##          |             | HOLLOW      |   BAYOU    |
##          |   THE       | PINES       |  (corner)  |
##      -70 |   DOCKS     +-------------+---+--------+ -60
##          |  (river     |  OLD QUARTER    | VELVET |
##          |   quay on   |  (cathedral     | MILE   |
##          |   the west) |   plaza hub)    |        |
##       95 |             +-----------------+        |
##          |             |  ST. ROCH CEMETERY       |
##      240 +-------------+--------------------------+
##                  the river bends round the south and west edges

const HALF := 240.0
## Everything that exists, water and backdrops included.
const BOUNDS := Rect2(-HALF, -HALF, 2.0 * HALF, 2.0 * HALF)
## Where Sol can actually walk (inside the invisible walls).
const PLAY := Rect2(-205.0, -226.0, 431.0, 448.0)
const QUAY_X := -205.0 # the docks' quay edge; black water beyond
const RIVER_Z := 222.0 # the south waterfront; black water beyond
const GRID := 20.0 # street grid of the Old Quarter and the Velvet Mile

## Street-grid block cells (cell i covers x i*20..i*20+20, likewise j on z).
const OQ_I := [-3, 3] # Old Quarter: x -60..60
const OQ_J := [-3, 4] # z -60..80
const VM_I := [4, 11] # Velvet Mile: x 80..220 (cell 7 is the Mile itself)
const VM_J := [-3, 10] # z -60..200
const VM_MILE_I := 7 # x 140..160: the boulevard, streetcar line down the middle
const VM_SQUARE := Rect2i(6, 5, 3, 2) # cells left open for the Palm Square (x 120..180, z 100..140)
const VM_OPERA := Rect2i(8, 2, 2, 2) # Le Velours opera house (x 160..200, z 40..80)

const DISTRICTS := [
	{"id": "quarter", "name": "THE OLD QUARTER", "color": Color(0.78, 0.6, 0.36), "label": Vector2(-30, 48),
		"poly": [Vector2(-70, -70), Vector2(70, -70), Vector2(70, 95), Vector2(-70, 95)]},
	{"id": "velvet", "name": "THE VELVET MILE", "color": Color(0.92, 0.2, 0.5), "label": Vector2(150, 160),
		"poly": [Vector2(70, -70), Vector2(125, -70), Vector2(125, -60), Vector2(240, -60), Vector2(240, 240), Vector2(70, 240), Vector2(70, 95)]},
	{"id": "docks", "name": "THE DOCKS", "color": Color(0.95, 0.5, 0.15), "label": Vector2(-150, -10),
		"poly": [Vector2(-240, -240), Vector2(-70, -240), Vector2(-70, 240), Vector2(-240, 240)]},
	{"id": "pines", "name": "HOLLOW PINES", "color": Color(0.4, 0.62, 0.95), "label": Vector2(20, -205),
		"poly": [Vector2(-70, -240), Vector2(125, -240), Vector2(125, -70), Vector2(-70, -70)]},
	{"id": "bayou", "name": "THE BAYOU", "color": Color(0.35, 0.85, 0.45), "label": Vector2(182, -205),
		"poly": [Vector2(125, -240), Vector2(240, -240), Vector2(240, -60), Vector2(125, -60)]},
	{"id": "cemetery", "name": "ST. ROCH CEMETERY", "color": Color(0.7, 0.7, 0.78), "label": Vector2(0, 160),
		"poly": [Vector2(-70, 95), Vector2(70, 95), Vector2(70, 240), Vector2(-70, 240)]},
]

## Landmarks you navigate by (silhouettes visible over the roofs). icon: map glyph.
const LANDMARKS := [
	{"id": "cathedral", "name": "St. Jerome Cathedral", "pos": Vector3(0, 0, -30), "icon": "spire", "height": 48.0},
	{"id": "cranes", "name": "The Gantry Cranes", "pos": Vector3(-192, 0, -10), "icon": "crane", "height": 44.0},
	{"id": "tower", "name": "Hollow Pines Water Tower", "pos": Vector3(25, 0, -185), "icon": "tower", "height": 30.0},
	{"id": "plantation", "name": "Belle Rive Plantation", "pos": Vector3(185, 0, -168), "icon": "ruin", "height": 16.0},
	{"id": "opera", "name": "Le Velours Opera", "pos": Vector3(180, 0, 60), "icon": "dome", "height": 34.0},
]

# ---------------------------------------------------------------- the Hunt
## The Descent: around the map edge, across the districts. type: subway | manhole |
## rooftop | ladder (up a quay ladder out of the river) | trail (out of the trees) | boat.
const DEPLOY_POINTS := [
	{"name": "Pier Six Ladder", "type": "ladder", "pos": Vector3(-202, 0, -60), "face": Vector3(1, 0, 0)},
	{"name": "Tank Farm Drain", "type": "manhole", "pos": Vector3(-130, 0, -200), "face": Vector3(0, 0, 1)},
	{"name": "Hollow Pines Trail", "type": "trail", "pos": Vector3(-40, 0, -212), "face": Vector3(0, 0, 1)},
	{"name": "Bayou Landing", "type": "boat", "pos": Vector3(210, 0, -112), "face": Vector3(-1, 0, 0)},
	{"name": "Velvet Mile Station", "type": "subway", "pos": Vector3(150, 0, -50), "face": Vector3(0, 0, 1)},
	{"name": "Promenade Rooftops", "type": "rooftop", "pos": Vector3(120, 0, 210), "face": Vector3(0, 0, -1)},
	{"name": "Riverside Drain", "type": "manhole", "pos": Vector3(-20, 0, 214), "face": Vector3(0, 0, -1)},
	{"name": "Cannery Station", "type": "subway", "pos": Vector3(-130, 0, 200), "face": Vector3(0, 0, -1)},
]

## One boss arena per district; nights 1 and 2 draw two of them, the Final Night is FINAL_ARENA.
const ARENAS := [
	{"id": "cathedral", "name": "the Cathedral Steps", "pos": Vector3(0, 0, -20), "radius": 15.0, "district": "quarter"},
	{"id": "pier", "name": "Pier Nine", "pos": Vector3(-172, 0, 172), "radius": 15.0, "district": "docks"},
	{"id": "velvet", "name": "the Palm Square", "pos": Vector3(150, 0, 120), "radius": 15.0, "district": "velvet"},
	{"id": "hollow", "name": "the Hollow", "pos": Vector3(10, 0, -122), "radius": 15.0, "district": "pines"},
	{"id": "lawn", "name": "the Drowned Lawn", "pos": Vector3(185, 0, -132), "radius": 15.0, "district": "bayou"},
]
const FINAL_ARENA := {"id": "plaza", "name": "the Undercroft Plaza", "pos": Vector3(0, 0, 6), "radius": 16.0, "district": "quarter"}


static func district_at(x: float, z: float) -> String:
	if x < -70.0:
		return "docks"
	if x > 125.0 and z < -60.0:
		return "bayou"
	if z < -70.0:
		return "pines"
	if x > 70.0:
		return "velvet"
	if z > 95.0:
		return "cemetery"
	return "quarter"


static func district_def(id: String) -> Dictionary:
	for d in DISTRICTS:
		if d.id == id:
			return d
	return {}


## The four corners of the walkable area (for the Curfew's opening radius).
static func corners() -> Array:
	return [PLAY.position, Vector2(PLAY.end.x, PLAY.position.y), Vector2(PLAY.position.x, PLAY.end.y), PLAY.end]
