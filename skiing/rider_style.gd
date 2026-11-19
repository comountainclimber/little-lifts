extends RefCounted

const REGULAR_BOARDER := 6
const GOOFY_BOARDER := 7
const GUEST_COUNT := 8

# Equipment follows the guest through the queue, chair and every lap.
static func is_boarder(guest_id: int) -> bool:
	return guest_id == REGULAR_BOARDER or guest_id == GOOFY_BOARDER


# With a board pointing along local -Z, regular riders face +X and goofy riders face -X.
static func toe_side(guest_id: int) -> float:
	return -1.0 if guest_id == GOOFY_BOARDER else 1.0
