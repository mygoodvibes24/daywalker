extends RefCounted
## The controls list shown on the Controls screen (main menu and pause menu).
## Data only: add a row here when a binding is added in main.gd `_setup_input()`
## (or by another system). Rows are [action, keyboard / mouse, controller].
## A row whose first element starts with "#" is a section heading.

const ROWS := [
	["# Movement", "", ""],
	["Move", "W A S D / arrows", "Left stick / D-pad"],
	["Camera", "Mouse", "Right stick"],
	["Sprint", "Shift", "LT (hold)"],
	["Jump (double jump)", "Space", "A / Cross"],
	["# Combat", "", ""],
	["Blade combo (3 hits)", "Left mouse / J", "X / Square  or  RT"],
	["Charged slash (hold attack)", "Hold left mouse / J", "Hold X / Square  or  RT"],
	["Thrust (attack out of a Blood Dash)", "Dash, then attack", "Dash, then attack"],
	["Running slash (attack while sprinting)", "Shift + attack", "LT + attack"],
	["Execute a staggered enemy", "Attack next to it", "Attack next to it"],
	["Parry (during an enemy's eye-flare)", "C / middle mouse", "L3"],
	["Blood Dash (3 charges)", "Right mouse / Q", "B / Circle"],
	["Weapon Art (each weapon type its own)", "V / mouse thumb button", "RB"],
	["# Special combos", "", ""],
	["Chain finisher", "Attack, attack, HOLD attack", "X, X, hold X"],
	["Blood Chain (spends 12 blood)", "Weapon Art right after the 3rd hit", "RB right after the 3rd hit"],
	["Heavy after a dodge", "Dash, then hold attack", "B, then hold X"],
	["Sprint heavy", "Sprint + hold attack", "LT + hold X"],
	["Jump cut / Plunge", "Attack in the air / hold it", "X in the air / hold it"],
	["Riposte", "Attack right after a parry", "X right after a parry"],
	["Bite a staggered enemy", "E", "Y / Triangle"],
	["# System", "", ""],
	["Pause menu", "Esc", "Back (inside the Coat)"],
	["Restart after death", "R", "Start / Options"],
	["# World", "", ""],
	["Interact / take loot", "E", "Y / Triangle"],
	["Drink bagged blood (Undercroft)", "F", "LB"],
	["Quick-use slots 1 / 2", "1 / 2", "LB / R3"],
	["Rain on / off", "T", "Back / Share (outside a Hunt)"],
	["# The Hunt", "", ""],
	["Map (doesn't pause)", "M", "Back / Share or touchpad"],
	["Keep vigil / trade / pry a coffin", "E", "Y / Triangle"],
	["Skip the Descent", "Space / left mouse", "A or X"],
	["# The Coat (inventory)", "", ""],
	["Open / close the Coat", "Tab / I", "Start / Options"],
	["Equip", "Enter / click", "A / Cross"],
	["Use", "U", "Y / Triangle"],
	["Drop", "X / Delete", "X / Square"],
]

const NOTES := "Interact and Bite share a button: next to a staggered enemy, Bite wins.\nLB drinks bagged blood when you are at the Undercroft, otherwise it quick-uses slot 1.\nControllers: Xbox, PlayStation and Switch Pro. Press any button to wake one in a browser."
