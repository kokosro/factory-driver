class_name MissionSchema
extends RefCounted
## JSON episodes, in world metres. Sequence is contiguous and zero based.
## Catalog validation is a second pass: missing, invalid and cyclic prerequisites
## exclude their dependents too. No production episodes are supplied by ML-1.
## ECON-1: reward_credits (a whole number above zero) marks a paid job and
## job_kind names what kind; absent from every ladder mission.
const RANKS := ["junior", "test_driver", "chief", "ace"]
const TYPES := ["waypoint_gate", "zone", "cone_slalom", "flag", "delivery_pickup", "delivery_return", "timed_finish", "lap"]
const FAILURES := ["skipped_gate", "cone_hit"]

static func number(v: Variant) -> bool:
	return (v is float or v is int) and is_finite(v)

static func position(v: Variant) -> bool:
	return v is Array and v.size() == 3 and number(v[0]) and number(v[1]) and number(v[2])

static func validate(data: Variant) -> PackedStringArray:
	var errors := PackedStringArray()
	if not data is Dictionary:
		return PackedStringArray(["mission must be an object"])
	for key in ["id", "title", "briefing"]:
		if not data.get(key) is String or data[key].strip_edges().is_empty():
			errors.append(key + " must be nonempty text")
	if not data.get("rank") in RANKS:
		errors.append("unknown rank")
	if not data.get("environment") in ["pad", "ring"]:
		errors.append("unknown environment")
	if data.has("cold_tyres") and not data.cold_tyres is bool:
		errors.append("cold_tyres must be boolean")
	# ECON-1: a paid mission is a job. Both fields are optional; the ladder
	# carries neither. The kind is free vocabulary (courier, testdrive,
	# scouting ...) and describes nothing without a reward.
	if data.has("reward_credits"):
		var reward: Variant = data.reward_credits
		if not number(reward) or reward <= 0 or reward != floor(reward):
			errors.append("reward_credits must be a whole number above zero")
	if data.has("job_kind"):
		if not data.job_kind is String or data.job_kind.strip_edges().is_empty():
			errors.append("job_kind must be nonempty text")
		if not data.has("reward_credits"):
			errors.append("job_kind needs reward_credits")
	if data.has("surface_override"):
		var surface: Variant = data.surface_override
		if not surface is Dictionary:
			errors.append("surface_override must be an object")
		else:
			for key in surface:
				if key not in ["grip", "rolling_drag", "bump", "ground_tint"]:
					errors.append("unknown surface_override field: " + str(key))
			for key in ["grip", "rolling_drag", "bump"]:
				if not number(surface.get(key)):
					errors.append("surface_override.%s must be a finite number" % key)
				elif key == "grip":
					if surface[key] < Surfaces.GRIP_MIN or surface[key] > Surfaces.GRIP_MAX:
						errors.append("surface_override.grip outside surface bounds")
				elif surface[key] < 0:
					errors.append("surface_override.%s must be non-negative" % key)
			# SNOW-2: the venue ground's colour for the episode, optional beside
			# the three required keys: display-space RGB, each channel in [0, 1].
			if surface.has("ground_tint"):
				var tint: Variant = surface.ground_tint
				if not tint is Array or tint.size() != 3:
					errors.append("surface_override.ground_tint must be three numbers")
				else:
					for channel in tint:
						if not number(channel):
							errors.append("surface_override.ground_tint must be three finite numbers")
						elif channel < 0 or channel > 1:
							errors.append("surface_override.ground_tint outside [0, 1]")
	var steps: Variant = data.get("episode")
	if not steps is Array or steps.is_empty():
		errors.append("episode must contain steps")
	else:
		var picked := false
		for i in steps.size():
			var s: Variant = steps[i]
			if not s is Dictionary:
				errors.append("step must be an object")
				continue
			if not s.get("type") in TYPES or not number(s.get("sequence")) or s.sequence != i:
				errors.append("step type/sequence invalid")
			if not s.get("type") is String:
				continue
			if not position(s.get("position")) or not number(s.get("radius")) or s.radius <= 0:
				errors.append("step position/radius invalid")
			if s.get("type") == "delivery_pickup":
				picked = true
			if s.get("type") == "delivery_return" and not picked:
				errors.append("return needs an earlier pickup")
			if s.get("type") in ["cone_slalom", "flag"]:
				if not s.get("cones") is Array or s.cones.is_empty():
					errors.append(s.type + " needs cones")
				else:
					for cone in s.cones:
						if not position(cone):
							errors.append("invalid cone position")
				if not number(s.get("cone_radius")) or s.cone_radius <= 0:
					errors.append("invalid cone radius")
		if not steps[-1] is Dictionary or not steps[-1].get("type") is String or steps[-1].type != "timed_finish":
			errors.append("episode must end at a timed finish")
	var scoring: Variant = data.get("scoring")
	if not scoring is Dictionary:
		errors.append("scoring must be an object")
	else:
		var limit: Variant = scoring.get("time_limit_s")
		if not number(limit) or limit <= 0:
			errors.append("invalid time limit")
		var medals: Variant = scoring.get("medal_times")
		if not medals is Dictionary:
			errors.append("medal_times must be an object")
		else:
			var previous := 0.0
			for medal in ["gold", "silver", "bronze"]:
				var t: Variant = medals.get(medal)
				if not number(t) or t <= previous or not number(limit) or t > limit:
					errors.append("invalid medal band " + medal)
				else:
					previous = t
		if not scoring.get("failure_conditions") is Array:
			errors.append("failure_conditions must be an array")
		else:
			for condition in scoring.failure_conditions:
				if not condition in FAILURES:
					errors.append("unsupported failure condition")
	var unlock: Variant = data.get("unlock")
	if not unlock is Dictionary:
		errors.append("unlock must be an object")
	else:
		if not unlock.get("required_rank") in RANKS or not data.get("rank") is String or unlock.get("required_rank") != data.get("rank"):
			errors.append("required_rank must match rank")
		if not unlock.get("required_missions") is Array:
			errors.append("required_missions must be an array")
		else:
			for id in unlock.required_missions:
				if not id is String or id.is_empty() or (data.get("id") is String and id == data.id):
					errors.append("invalid prerequisite")
	if data.has("input_script"):
		var driver: Variant = data.input_script
		if not driver is Dictionary or not driver.get("steps") is Array:
			errors.append("input_script needs steps")
		else:
			if driver.has("hold_speed") and (not number(driver.hold_speed) or driver.hold_speed <= 0):
				errors.append("invalid hold_speed")
			for step in driver.steps:
				if not step is Dictionary:
					errors.append("input step must be an object")
					continue
				for key in step:
					if not key in ["when", "press", "release", "steer_deg", "steer_free", "mark"]:
						errors.append("unknown input step field")
				for key in ["press", "release"]:
					if step.has(key):
						if not step[key] is Array:
							errors.append("input actions must be an array")
						else:
							for action in step[key]:
								if not action in ["accelerate", "brake", "steer_left", "steer_right", "handbrake"]:
									errors.append("unknown input action")
				if step.has("steer_deg") and not number(step.steer_deg):
					errors.append("invalid steer_deg")
				for key in ["steer_free", "mark"]:
					if step.has(key) and not step[key] is bool:
						errors.append("input flag must be boolean")
				if step.has("when"):
					if not step.when is Dictionary:
						errors.append("input conditions must be an object")
					else:
						for key in step.when:
							if not key in ["after", "speed_above", "speed_below", "travelled"] or not number(step.when[key]) or step.when[key] < 0:
								errors.append("invalid input condition")
	return errors

static func catalog_errors(entries: Array) -> Dictionary:
	var errors := {}
	var catalog := {}
	for i in entries.size():
		var e: Variant = entries[i]
		var id := str(e.get("id", "entry-%d" % i)) if e is Dictionary else "entry-%d" % i
		var faults := validate(e)
		if catalog.has(id):
			faults.append("duplicate id")
		catalog[id] = e
		if not faults.is_empty():
			errors[id] = faults
	for id: String in catalog:
		if not errors.has(id) and _broken(id, catalog, errors, []):
			errors[id] = PackedStringArray(["unknown, invalid or cyclic prerequisite"])
	return errors

static func _broken(id: String, catalog: Dictionary, errors: Dictionary, visiting: Array) -> bool:
	if errors.has(id) or not catalog.has(id) or visiting.has(id):
		return true
	var path := visiting.duplicate()
	path.append(id)
	for predecessor: String in catalog[id].unlock.required_missions:
		if _broken(predecessor, catalog, errors, path):
			return true
	return false

static func medal(scoring: Dictionary, seconds: float) -> String:
	if not is_finite(seconds) or seconds < 0 or seconds > scoring.time_limit_s:
		return ""
	for band in ["gold", "silver", "bronze"]:
		if seconds <= scoring.medal_times[band]:
			return band
	return "complete"
