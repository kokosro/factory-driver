extends SceneTree
## Headless buildings test: the Ring's focus table
## (data/regions/eifel_ring/focus.json, the region's put-in-stone table of
## typed buildings, docs/design/4b/ring-region-decisions.md §4 as data) is
## read the way Buildings reads it and has to pass its validation, then is
## held to what the plan asks (implementation-plan.md §4B-5): exactly nine
## E2 gas stations, and exactly the nine amenity=fuel OSM ids the stone
## table names; exactly one social station by the library's arithmetic
## round(0.1 × 9) = 1, the pick the stone table's node 1711333738, and the
## derivation run twice yielding the same id; every E1 workshop holding
## build_cars; no E1 holding sell_fuel unless the file says so; the E11
## office within 50 m of way 26543901's first node, both sides in region
## metres (the record's lat/lon through SkeletonLoader.wgs84_to_local, the
## node from the checked-in skeleton's segment of that way); every
## record's shell a B entry of the catalogue, the element's own, with its
## placeholder footprint from the library; and can() refusing a privilege
## name outside the vocabulary with the reason. The provenance header is
## held to the files it cites: the query text (verbatim here) hashes to
## the header's query sha; the fetched answer, where the snapshot store is
## on this machine, hashes to the header's answer sha, and with the
## serving database's own timestamp written as at the 4B-2 pull hashes to
## the attic sha the 4B-2 manifest recorded (the honesty chain: the same
## attic data, one header field apart). Then validate() on fixtures
## broken in code (never on disk) names the record and the field. No
## network: the fetch is never run here. Seconds, right after the world
## profile test in run_tests.sh: static data that fails first. Writes
## nothing. Exits 0 on success, 1 on any fault.

## The pinned snapshot (ring-region-decisions.md §1), its own literal.
const PINNED_OSM_BASE := "2026-09-22T08:45:51Z"

## The nine amenity=fuel OSM ids put in stone (ring-region-decisions.md §4,
## the "Petrol stations" row): exactly these, no station invented.
const STONE_FUEL_IDS := [12023011572, 1711333738, 1497869198, 114676264, 483724476, 483724477, 732711989, 1335615680, 1023567856]

## The social pick (the same row): Döttinger Höhe, at the Ring's gate.
const SOCIAL_PICK := 1711333738

## The nine shop=car_repair OSM ids (the "Workshops" row: eight named and
## "one unnamed in Boos", node 1346072157 in the answer).
const STONE_REPAIR_IDS := [304343082, 2573632801, 533640757, 533642836, 948590128, 12047929770, 410078995, 1182024168, 1346072157]

## The dealerships, the test centre, the office's way (the rows below it).
const PORSCHE_WAY := 1182024168
const GENERAL_WAY := 831174023
const TEST_CENTRE_WAY := 667524970
const OFFICE_WAY := 26543901
const OFFICE_TOLERANCE_M := 50.0

## The records the Ring file holds: 9 E2 + 9 E1 + E3 + E4 + E8 + E11.
const EXPECTED_RECORDS := 22

## q3_economy.ql verbatim (tools/world/extract_osm.py's QUERIES entry,
## data-pipeline.md §2.1 with the attic date): what the header's
## query_sha256 has to be the sha256 of.
const Q3_QUERY := '[out:json][timeout:300][bbox:50.30,6.80,50.45,7.10][date:"2026-09-22T08:45:51Z"];\n(\n  nwr["amenity"~"^(fuel|driving_school|animal_shelter|parking|place_of_worship)$"];\n  nwr["shop"~"^(car|car_repair|car_parts|tyres)$"];\n  nwr["historic"="castle"];\n  nwr["building"~"^(grandstand|industrial|warehouse|garage|garages|barn|farm|church)$"];\n  nwr["man_made"="storage_tank"];\n  nwr["landuse"="industrial"];\n);\nout geom;\n'

## The 4B-2 manifest's recorded sha256 of q3_economy.json and the serving
## timestamp it carried (fd-4B2-osm/manifest.json, 2026-09-23T00:58:32Z):
## the attic identity the header's chain has to end on.
const ATTIC_SHA256 := "edd99baba9ed09b02b8a19f4e3eb496a5146ef49d9290f5b024026450c703ec0"
const ATTIC_SERVED := "2026-09-23T00:58:32Z"

var _failures := 0


func _initialize() -> void:
	var data: Variant = Buildings.read_file()
	_check_file(data)
	if not data is Dictionary:
		print("BUILDINGS TEST FAILED: %d fault(s)" % _failures)
		quit(1)
		return
	_check_provenance(data)
	_check_stations()
	_check_social()
	_check_workshops()
	_check_dealerships_and_centre()
	_check_office()
	_check_shells()
	_check_positions()
	_check_can()
	_check_lookups()
	_check_broken_fixtures(data)
	print("BUILDINGS TEST PASSED" if _failures == 0 else "BUILDINGS TEST FAILED: %d fault(s)" % _failures)
	quit(0 if _failures == 0 else 1)


## An ok line or a FAIL line, counted.
func _ok(condition: bool, what: String, reason: String = "") -> void:
	if condition:
		print("  ok    ", what)
	else:
		_failures += 1
		printerr("  FAIL  ", reason if reason != "" else what)


## The file is there, is JSON, parses twice to the same bytes, and passes
## validate() with nothing to say.
func _check_file(data: Variant) -> void:
	var reparsed: Variant = Buildings.read_file()
	_ok(data is Dictionary and var_to_bytes(data) == var_to_bytes(reparsed), "%s parses, and parsed twice it comes out the same" % Buildings.PATH, "%s: %s" % [Buildings.PATH, "not a JSON object" if not data is Dictionary else "parsed twice, it does not come out the same"])
	var errors := Buildings.validate(data)
	for error: String in errors:
		printerr("  FAIL  ", error)
	_failures += errors.size()
	_ok(errors.is_empty(), "the focus table passes Buildings.validate() with nothing to say")
	if data is Dictionary:
		var keys: Array = data.keys()
		keys.sort()
		_ok(keys == ["provenance", "records", "region", "social"] and data.region == Buildings.REGION, "the schema's four top keys, region %s" % data.get("region"), "top keys %s, region %s" % [keys, data.get("region")])


## The provenance header: the pinned snapshot and bbox; the query's sha the
## sha256 of the query text; the answer's sha the file's where the store is
## on this machine; the attic chain to the 4B-2 manifest's sha.
func _check_provenance(data: Dictionary) -> void:
	var provenance: Dictionary = data.provenance
	var fetch: Dictionary = provenance.fetch
	_ok(provenance.osm_base == PINNED_OSM_BASE and provenance.bbox == SkeletonLoader.BBOX, "provenance: osm_base the pinned %s, bbox the Ring's %s" % [PINNED_OSM_BASE, provenance.bbox], "provenance: osm_base %s, bbox %s" % [provenance.osm_base, provenance.bbox])
	_ok(fetch.date == "2026-09-24" and fetch.endpoint.begins_with("https://") and fetch.tool.contains("extract_osm.py") and fetch.tool.contains("q3_economy"), "provenance.fetch: %s on %s by %s" % [fetch.endpoint, fetch.date, fetch.tool.get_slice(" (", 0)], "provenance.fetch: %s" % [fetch])
	var query_sha := _sha256_of(Q3_QUERY.to_utf8_buffer())
	_ok(fetch.query_file == "q3_economy.ql" and fetch.query_sha256 == query_sha, "provenance.fetch.query_sha256 %s is the sha256 of q3_economy.ql's text (verbatim here, %d bytes)" % [fetch.query_sha256, Q3_QUERY.to_utf8_buffer().size()], "query_sha256 %s, the query text hashes to %s" % [fetch.query_sha256, query_sha])
	_ok(fetch.answer_file == "q3_economy.json" and fetch.answer_elements == 1049 and fetch.answer_bytes == 867778 and fetch.served_timestamp_osm_base >= PINNED_OSM_BASE, "provenance.fetch: q3_economy.json, %d elements, %d bytes, served by a database of %s (at or past the attic date)" % [fetch.answer_elements, fetch.answer_bytes, fetch.served_timestamp_osm_base], "answer: %s elements, %s bytes, served %s" % [fetch.answer_elements, fetch.answer_bytes, fetch.served_timestamp_osm_base])
	_ok(fetch.attic_sha256 == ATTIC_SHA256 and fetch.attic_note.contains(ATTIC_SERVED), "provenance.fetch.attic_sha256 is the 4B-2 manifest's recorded %s and the note names the 4B-2 serving timestamp %s" % [ATTIC_SHA256, ATTIC_SERVED], "attic_sha256 %s" % fetch.attic_sha256)
	var folder: String = fetch.folder.get_slice(" (", 0)
	var answer_path := folder.path_join(fetch.answer_file)
	var query_path := folder.path_join(fetch.query_file)
	if FileAccess.file_exists(answer_path) and FileAccess.file_exists(query_path):
		var bytes := FileAccess.get_file_as_bytes(answer_path)
		var answer_sha := _sha256_of(bytes)
		var query_on_disk := _sha256_of(FileAccess.get_file_as_bytes(query_path))
		_ok(answer_sha == fetch.answer_sha256 and query_on_disk == fetch.query_sha256 and bytes.size() == fetch.answer_bytes, "the snapshot store is on this machine: %s hashes to the header's answer_sha256 %s (%d bytes) and the .ql to its query_sha256" % [answer_path, answer_sha, bytes.size()], "on disk: answer %s (%d bytes), query %s; the header says %s / %s" % [answer_sha, bytes.size(), query_on_disk, fetch.answer_sha256, fetch.query_sha256])
		var text := bytes.get_string_from_utf8()
		var served: String = fetch.served_timestamp_osm_base
		var attic_sha := _sha256_of(text.replace(served, ATTIC_SERVED).to_utf8_buffer())
		_ok(text.count(served) == 1 and attic_sha == ATTIC_SHA256, "the attic chain holds on this machine: with the serving timestamp %s written as at the 4B-2 pull (%s), the same bytes hash to attic_sha256 %s: the data is the pinned attic's, one header field apart" % [served, ATTIC_SERVED, ATTIC_SHA256], "the substituted file hashes to %s (served timestamp found %d times)" % [attic_sha, text.count(served)])
	else:
		_ok(true, "the snapshot store %s is not on this machine: answer_sha256 %s stands as the header records it (the store's manifest.json says the same)" % [folder, fetch.answer_sha256])
		_ok(true, "the attic chain is the header's word here: attic_sha256 %s, verified on the machine that holds the store" % ATTIC_SHA256)
	var e11: Dictionary = fetch.e11_source
	_ok(e11.way == OFFICE_WAY and e11.query_file == "q1_skeleton.ql" and _is_sha(e11.answer_sha256), "provenance.fetch.e11_source: way %d's first node %d from the 4B-2 q1 pull, sha256 %s" % [e11.way, e11.first_node, e11.answer_sha256], "e11_source: %s" % [e11])
	var lines: Dictionary = provenance.decisions.lines
	_ok(provenance.decisions.doc == "docs/design/4b/ring-region-decisions.md" and lines.petrol_stations == 114 and lines.workshops == 115 and lines.porsche_dealership == 116 and lines.general_dealership == 117 and lines.test_centre == 118 and lines.proving_ground_office == 119, "provenance.decisions: %s §4, the rows at lines 114-119" % provenance.decisions.doc, "decisions: %s" % [provenance.decisions])


## Exactly nine E2, exactly the stone table's nine OSM ids, each selling
## fuel in a B6 canopy.
func _check_stations() -> void:
	var stations := Buildings.stations()
	_ok(stations.size() == 9, "exactly 9 E2 gas stations in the Ring file (\"gas stations are RARE\": the nine tagged, none invented)", "%d E2 records" % stations.size())
	var ids: Array[int] = []
	for station: Buildings.Record in stations:
		ids.append(station.osm_id)
		_ok(station.can("sell_fuel") and station.shell == "B6" and station.osm_id in STONE_FUEL_IDS, "%s: %s/%d%s sells fuel in a B6 canopy%s" % [station.id, station.osm_type, station.osm_id, " (%s)" % station.osm_name if station.osm_name != "" else " (unnamed)", ", social" if station.social else ""], "%s: %s/%d, shell %s, privileges %s" % [station.id, station.osm_type, station.osm_id, station.shell, station.privileges])
	var sorted_ids := ids.duplicate()
	sorted_ids.sort()
	var stone := STONE_FUEL_IDS.duplicate()
	stone.sort()
	_ok(sorted_ids == stone, "the nine are exactly the stone table's amenity=fuel ids: %s" % [STONE_FUEL_IDS], "the file's E2 ids %s, the stone table's %s" % [ids, STONE_FUEL_IDS])


## Exactly one social station by the arithmetic, the stone table's pick,
## the same id on a second derivation.
func _check_social() -> void:
	var n := Buildings.stations().size()
	var count := Buildings.social_count(n)
	var social: Dictionary = Buildings.social()
	_ok(count == 1 and social.count == 1 and social.n == n and social.share == Buildings.social_share() and social.arithmetic == "round(0.1 x 9) = 1", "social count: round(%s × %d) = %d, the library's arithmetic (E2's social_share from the catalogue), the header's %s" % [Buildings.social_share(), n, count, social.arithmetic], "social: count %d, header %s" % [count, social])
	var first := Buildings.social_stations()
	var second := Buildings.social_stations()
	_ok(first.size() == 1 and first[0].osm_id == SOCIAL_PICK and social.picks.size() == 1 and int(social.picks[0]) == SOCIAL_PICK, "exactly 1 social station, the stone table's pick: node %d (%s), the header's picks %s" % [SOCIAL_PICK, first[0].osm_name if first.size() == 1 else "-", social.picks], "social stations %d, picks %s" % [first.size(), social.picks])
	_ok(second.size() == first.size() and second[0].osm_id == first[0].osm_id and second[0].id == first[0].id, "a second run of the derivation yields the same id: %s, node %d" % [second[0].id if second.size() == 1 else "-", second[0].osm_id if second.size() == 1 else 0], "second derivation: %d stations" % second.size())
	_ok(first.size() == 1 and first[0].can("sell_tuna") and first[0].extra_privileges != "", "the social station holds sell_tuna beyond E2's sell_fuel, and the file says why: %s" % _short(first[0].extra_privileges if first.size() == 1 else ""), "the social station's privileges %s" % [first[0].privileges if first.size() == 1 else []])
	var others_tuna := 0
	for station: Buildings.Record in Buildings.stations():
		if not station.social and station.can("sell_tuna"):
			others_tuna += 1
	_ok(others_tuna == 0, "no other station sells tuna (the others are cat-required, not social)", "%d non-social stations sell tuna" % others_tuna)


## Nine E1 from the nine shop=car_repair places, every one building cars,
## none selling fuel (the file says so for none).
func _check_workshops() -> void:
	var workshops := Buildings.by_element("E1")
	_ok(workshops.size() == 9, "exactly 9 E1 workshops in the Ring file (\"all nine exist as startups\")", "%d E1 records" % workshops.size())
	var ids: Array[int] = []
	for workshop: Buildings.Record in workshops:
		ids.append(workshop.osm_id)
		_ok(workshop.can("build_cars") and workshop.can("build_components") and workshop.can("repair") and workshop.shell == "B7", "%s has build_cars (and build_components, repair) in a B7 hall: %s/%d%s" % [workshop.id, workshop.osm_type, workshop.osm_id, " (%s)" % workshop.osm_name if workshop.osm_name != "" else " (unnamed, Boos)"], "%s: privileges %s, shell %s" % [workshop.id, workshop.privileges, workshop.shell])
	var sorted_ids := ids.duplicate()
	sorted_ids.sort()
	var stone := STONE_REPAIR_IDS.duplicate()
	stone.sort()
	_ok(sorted_ids == stone, "the nine are exactly the stone table's shop=car_repair ids: %s" % [STONE_REPAIR_IDS], "the file's E1 ids %s, the stone table's %s" % [ids, STONE_REPAIR_IDS])
	var fuel_sellers := []
	var said_so := true
	for workshop: Buildings.Record in workshops:
		if workshop.can("sell_fuel"):
			fuel_sellers.append(workshop.id)
			said_so = said_so and workshop.extra_privileges != ""
	_ok(fuel_sellers.is_empty() and said_so, "no E1 has sell_fuel (the file says so for none: an E1 selling fuel needs extra_privileges saying why)", "E1 selling fuel: %s, said so: %s" % [fuel_sellers, said_so])


## The two dealerships and the test centre at their ways.
func _check_dealerships_and_centre() -> void:
	var porsche := Buildings.by_element("E3")
	var general := Buildings.by_element("E4")
	var centre := Buildings.by_element("E8")
	_ok(porsche.size() == 1 and porsche[0].osm_type == "way" and porsche[0].osm_id == PORSCHE_WAY and porsche[0].shell == "B8" and porsche[0].can("sell_cars") and porsche[0].can("buy_cars") and porsche[0].can("rent_car"), "E3 the Porsche dealership: way %d promoted from E1 (the E1 record stands at the same way), B8, sell_cars buy_cars rent_car" % PORSCHE_WAY, "E3: %d record(s) %s" % [porsche.size(), porsche[0].osm_id if porsche.size() == 1 else 0])
	_ok(general.size() == 1 and general[0].osm_type == "way" and general[0].osm_id == GENERAL_WAY and general[0].shell == "B8" and general[0].can("rent_car"), "E4 the general dealership: way %d (Autohaus Rausch, unbranded in-game), B8, rent_car for the first-run rental" % GENERAL_WAY, "E4: %d record(s)" % general.size())
	_ok(centre.size() == 1 and centre[0].osm_type == "way" and centre[0].osm_id == TEST_CENTRE_WAY and centre[0].shell == "B9" and centre[0].can("exam"), "E8 the test centre: way %d (Fahrschule Hecken), B9, exam" % TEST_CENTRE_WAY, "E8: %d record(s)" % centre.size())
	var same_way := 0
	for workshop: Buildings.Record in Buildings.by_element("E1"):
		if workshop.osm_id == PORSCHE_WAY:
			same_way += 1
	_ok(same_way == 1, "the Porsche site holds two records (E1 startup and E3 house) at one way: distinct elements, one OSM id (validate() allows an id per element once)", "%d E1 at the Porsche way" % same_way)


## The E11 within 50 m of way 26543901's first node: the record through
## the loader's projection, the node from the checked-in skeleton.
func _check_office() -> void:
	var offices := Buildings.by_element("E11")
	_ok(offices.size() == 1 and offices[0].shell == "B9" and offices[0].can("ring_booking") and offices[0].can("telemetry_desk"), "E11 the proving-ground office: one, B9, ring_booking telemetry_desk", "E11: %d record(s)" % offices.size())
	if offices.size() != 1:
		return
	var office := offices[0]
	var first: SkeletonLoader.Segment = null
	for segment: SkeletonLoader.Segment in SkeletonLoader.segments():
		if segment.osm_way == OFFICE_WAY and (first == null or segment.id < first.id):
			first = segment
	if first == null:
		_ok(false, "", "way %d is not in the skeleton" % OFFICE_WAY)
		return
	var node := first.first()
	var at := office.position()
	var distance := at.distance_to(node)
	_ok(distance <= OFFICE_TOLERANCE_M, "the E11 sits %.3f m from way %d's first node: the record (%.7f, %.7f) projects to (%.3f, %.3f) region metres, the skeleton's %s starts at (%.3f, %.3f) (%s; within %.0f m)" % [distance, OFFICE_WAY, office.lat, office.lon, at.x, at.y, first.id, node.x, node.y, first.tags.get("name", "unnamed"), OFFICE_TOLERANCE_M], "the E11 is %.3f m from way %d's first node (%.3f, %.3f), the record at (%.3f, %.3f)" % [distance, OFFICE_WAY, node.x, node.y, at.x, at.y])
	var source: Dictionary = Buildings.provenance().fetch.e11_source
	_ok(office.osm_type == "node" and office.osm_id == source.first_node and office.osm_id > 0, "the E11's OSM id is the way's first node, %d, as the header's e11_source records" % office.osm_id, "the E11 is %s/%d, the header's first node %s" % [office.osm_type, office.osm_id, source.get("first_node")])


## Every record's shell a B entry of the catalogue and its element's own;
## the placeholder footprint the library's default where it states one.
func _check_shells() -> void:
	var records := Buildings.records()
	_ok(records.size() == EXPECTED_RECORDS, "%d records in the Ring file: 9 E2 + 9 E1 + E3 + E4 + E8 + E11" % EXPECTED_RECORDS, "%d records" % records.size())
	for record: Buildings.Record in records:
		var entry := ElementCatalogue.entry(record.shell)
		var element := ElementCatalogue.entry(record.element)
		var is_b: bool = not entry.is_empty() and entry.get("family") == "B"
		var own: bool = not element.is_empty() and element.get("shell") == record.shell
		var footprint := record.footprint_m()
		var stated := footprint != Vector2.ZERO
		_ok(is_b and own and (stated or record.shell == "B9"), "%s shell %s (%s) is a B entry of the catalogue and %s's own; placeholder footprint %s" % [record.id, record.shell, entry.get("title", "?"), record.element, "%.0f × %.0f m (the library's default)" % [footprint.x, footprint.y] if stated else "none stated (B9 is B0's recipe, from the OSM footprint at 4B-8)"], "%s: shell %s is %s, %s's is %s; footprint %s" % [record.id, record.shell, "a B entry" if is_b else "no B entry", record.element, element.get("shell"), footprint])
	_ok(Buildings.shell_footprint("B6") == Vector2(12, 8) and Buildings.shell_footprint("B7") == Vector2(15, 10) and Buildings.shell_footprint("B8") == Vector2(20, 12) and Buildings.shell_footprint("B9") == Vector2.ZERO and Buildings.shell_footprint("R1") == Vector2.ZERO, "the shell footprints read from the catalogue's stone parameters: B6 12 × 8, B7 15 × 10, B8 20 × 12 m; B9 none stated; a non-B id none", "footprints B6 %s B7 %s B8 %s B9 %s" % [Buildings.shell_footprint("B6"), Buildings.shell_footprint("B7"), Buildings.shell_footprint("B8"), Buildings.shell_footprint("B9")])


## Positions: WGS84 inside the bbox, a way's the centre of its bounds as
## served, and the projection landing inside the region (no metres baked).
func _check_positions() -> void:
	var data: Dictionary = Buildings.read_file()
	var ways := 0
	var centred := 0
	var inside := 0
	var x_min := INF
	var x_max := -INF
	var z_min := INF
	var z_max := -INF
	for raw: Dictionary in data.records:
		if raw.has("bounds"):
			ways += 1
			var bounds: Dictionary = raw.bounds
			if absf(raw.position.lat - (bounds.minlat + bounds.maxlat) / 2.0) < 1e-8 and absf(raw.position.lon - (bounds.minlon + bounds.maxlon) / 2.0) < 1e-8:
				centred += 1
		elif raw.osm.type == "node":
			inside += 1
	for record: Buildings.Record in Buildings.records():
		var at := record.position()
		x_min = minf(x_min, at.x)
		x_max = maxf(x_max, at.x)
		z_min = minf(z_min, at.y)
		z_max = maxf(z_max, at.y)
	_ok(ways == centred and ways + inside == EXPECTED_RECORDS, "%d way records carry the bounds Overpass served and their position is the bounds' centre; %d node records carry the node's own lat/lon" % [ways, inside], "%d ways, %d centred, %d nodes" % [ways, centred, inside])
	var bbox: Array = SkeletonLoader.BBOX
	var corners := [SkeletonLoader.wgs84_to_local(bbox[0], bbox[1]), SkeletonLoader.wgs84_to_local(bbox[0], bbox[3]), SkeletonLoader.wgs84_to_local(bbox[2], bbox[1]), SkeletonLoader.wgs84_to_local(bbox[2], bbox[3])]
	var box := Rect2(corners[0], Vector2.ZERO)
	for corner: Vector2 in corners:
		box = box.expand(corner)
	_ok(x_min >= box.position.x and x_max <= box.end.x and z_min >= box.position.y and z_max <= box.end.y, "the %d records project to x %.0f..%.0f, z %.0f..%.0f region metres, inside the bbox's four projected corners (x %.0f..%.0f, z %.0f..%.0f; the origin E0/N0 lies inside the bbox, the grid converges)" % [EXPECTED_RECORDS, x_min, x_max, z_min, z_max, box.position.x, box.end.x, box.position.y, box.end.y], "positions x %.0f..%.0f z %.0f..%.0f, the bbox's corners x %.0f..%.0f z %.0f..%.0f" % [x_min, x_max, z_min, z_max, box.position.x, box.end.x, box.position.y, box.end.y])


## can(): a privilege held, a privilege not held (with what is held), a
## name outside the vocabulary refused with the reason, the vocabulary
## ElementCatalogue's.
func _check_can() -> void:
	var station: Buildings.Record = Buildings.record("E2.1")
	var workshop: Buildings.Record = Buildings.record("E1.1")
	if station == null or workshop == null:
		_ok(false, "", "E2.1 or E1.1 is not in the file")
		return
	_ok(station.can("sell_fuel") and station.refusal("sell_fuel") == "", "E2.1.can(\"sell_fuel\") is true, no refusal")
	_ok(not workshop.can("sell_fuel") and workshop.refusal("sell_fuel") == "E1.1 does not hold sell_fuel (its privileges: build_cars, build_components, repair)", "E1.1.can(\"sell_fuel\") is false, the refusal names what it holds: \"%s\"" % workshop.refusal("sell_fuel"), "refusal: %s" % workshop.refusal("sell_fuel"))
	var refusal := station.refusal("sell_beer")
	_ok(not station.can("sell_beer") and refusal.begins_with("sell_beer is not in the privilege vocabulary (the 17 names of ElementCatalogue.PRIVILEGES: ") and refusal.contains("sell_fuel") and refusal.contains("rent_car"), "an unknown privilege name is refused with the reason: \"%s\"" % _short(refusal), "refusal for sell_beer: %s" % refusal)
	_ok(not workshop.can("") and workshop.refusal("").begins_with("\"\" is not in the privilege vocabulary"), "an empty name is refused the same way")
	_ok(not Buildings.is_privilege("free_fuel") and Buildings.is_privilege("sell_tuna") and ElementCatalogue.PRIVILEGES.size() == 17, "the vocabulary is ElementCatalogue.PRIVILEGES, 17 names, referenced not copied (Buildings holds no list of its own)")
	var listed := true
	for name: String in ElementCatalogue.PRIVILEGES:
		listed = listed and Buildings.privilege_refusal(name) == ""
	_ok(listed, "every one of the 17 names passes privilege_refusal() with nothing to say")


## The lookups answer from the file.
func _check_lookups() -> void:
	_ok(Buildings.record("E11.1") != null and Buildings.record("E11.1").element == "E11" and Buildings.record("E99.1") == null, "record(\"E11.1\") is the office; record() of an id that is not there is null")
	_ok(Buildings.by_element("E9").is_empty() and Buildings.by_element("E2").size() == 9, "by_element(\"E9\") is empty (the sanctuary is by rule, not placed yet); by_element(\"E2\") is the nine")
	var owners := {}
	var demands := 0
	for record: Buildings.Record in Buildings.records():
		owners[record.owner] = owners.get(record.owner, 0) + 1
		demands += record.demand.size()
	_ok(owners == {"npc": EXPECTED_RECORDS} and demands == 0, "every record's owner is npc (nothing is the driver's before the first run) and every demand set is empty (the jobs iteration fills them)", "owners %s, demands %d" % [owners, demands])
	var lines := {}
	for record: Buildings.Record in Buildings.records():
		lines[record.stone_line] = lines.get(record.stone_line, 0) + 1
	_ok(lines == {114: 9, 115: 9, 116: 1, 117: 1, 118: 1, 119: 1}, "every record cites its stone line: 114 × 9 (stations), 115 × 9 (workshops), 116, 117, 118, 119", "stone lines %s" % [lines])


## validate() on fixtures broken in code, one per fault kind, has to name
## the record and the field. Nothing is written to disk.
func _check_broken_fixtures(data: Dictionary) -> void:
	_expect_fault(_broken(data, "E1.1", "privileges", ["build_cars", "build_components", "repair", "sell_beer"]), "record E1.1.privileges has sell_beer: sell_beer is not in the privilege vocabulary", "a privilege outside the vocabulary")
	_expect_fault(_broken(data, "E1.1", "privileges", ["build_components", "repair"]), "record E1.1.privileges lacks build_cars, which every E1 holds", "an E1 without build_cars")
	_expect_fault(_broken(data, "E1.1", "privileges", ["build_cars", "build_components", "repair", "sell_fuel"]), "record E1.1.privileges holds sell_fuel beyond E1's, and the file does not say so", "an E1 selling fuel without the file saying so")
	_expect_no_fault(_broken(_broken(data, "E1.1", "privileges", ["build_cars", "build_components", "repair", "sell_fuel"]), "E1.1", "extra_privileges", "by troc: the startup took the pumps over"), "an E1 selling fuel WITH the file saying so (extra_privileges)")
	_expect_fault(_broken(data, "E1.1", "privileges", ["build_cars", "build_components", "repair", "repair"]), "record E1.1.privileges has repair twice", "a privilege twice")
	_expect_fault(_broken(data, "E1.1", "shell", "B99"), "record E1.1.shell is B99, no such B entry", "a shell naming no B entry")
	_expect_fault(_broken(data, "E1.1", "shell", "B6"), "record E1.1.shell is B6, E1's shell is B7", "a shell that is not the element's")
	_expect_fault(_broken(data, "E1.1", "shell", "R1"), "record E1.1.shell is R1, not a B id", "a shell that is no B id")
	_expect_fault(_broken(data, "E1.1", "element", "E99"), "record E1.1.element is E99, no such entry", "an element the catalogue lacks")
	_expect_fault(_broken(data, "E1.1", "owner", "bank"), "record E1.1.owner is bank, not one of none, driver, npc", "an owner outside none|driver|npc")
	_expect_fault(_broken(data, "E1.1", "position", {"lat": 51.0, "lon": 6.9}), "record E1.1.position (51.0, 6.9) is outside the Ring bbox", "a position outside the bbox")
	_expect_fault(_broken(data, "E1.1", "social", true), "record E1.1 is social, only a gas station (E2) is", "a social flag on a workshop")
	_expect_fault(_broken(data, "E2.1", "social", true), "2 station(s) flagged social, round(0.1 × 9) is 1", "two social stations among nine")
	_expect_fault(_broken(data, "E2.2", "social", false), "0 station(s) flagged social, round(0.1 × 9) is 1", "no social station among nine")
	_expect_fault(_broken(data, "E1.1", "id", "E1.2"), "record E1.2 is there twice, ids are unique", "a duplicate id")
	_expect_fault(_broken(data, "E1.2", "osm", {"type": "way", "id": 304343082}), "record E1.2 places E1 at way/304343082, which E1.1 already does", "one element placed twice from one OSM id")
	_expect_fault(_broken(data, "E1.1", "colour", "blue"), "record E1.1.colour is not in the schema", "a key the schema does not know")
	_expect_fault(_broken(data, "E1.1", "stone", {"doc": "x"}), "record E1.1.stone is", "a record without its stone citation")
	var unpinned: Dictionary = data.duplicate(true)
	unpinned.provenance.osm_base = "2026-09-23T00:00:00Z"
	_expect_fault(unpinned, "provenance.osm_base is 2026-09-23T00:00:00Z, the pinned snapshot is", "an unpinned snapshot")
	var bad_sha: Dictionary = data.duplicate(true)
	bad_sha.provenance.fetch.answer_sha256 = "not-a-sha"
	_expect_fault(bad_sha, "provenance.fetch.answer_sha256 is not-a-sha, not a sha256 hex", "a sha field that is no sha256")
	_expect_fault(null, "not a JSON object", "a file that is not JSON")


## `data` with the record `id` changed: `key` set to `value`. A deep copy:
## the real file stays what it is.
func _broken(data: Dictionary, id: String, key: String, value: Variant) -> Dictionary:
	var copy: Dictionary = data.duplicate(true)
	for record: Dictionary in copy.records:
		if record.id == id:
			record[key] = value
			break
	return copy


## One broken fixture: validate() has to say something with `expected` in it.
func _expect_fault(fixture: Variant, expected: String, what: String) -> void:
	var errors := Buildings.validate(fixture)
	var named := false
	for error: String in errors:
		if error.contains(expected):
			named = true
	_ok(named, "validate() names %s: \"%s\"" % [what, expected], "validate() on %s says %s, not \"%s\"" % [what, errors, expected])


## A fixture that is valid: validate() has nothing to say.
func _expect_no_fault(fixture: Variant, what: String) -> void:
	var errors := Buildings.validate(fixture)
	_ok(errors.is_empty(), "validate() accepts %s" % what, "validate() on %s says %s" % [what, errors])


## The sha256 hex of bytes.
func _sha256_of(bytes: PackedByteArray) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(bytes)
	return context.finish().hex_encode()


func _is_sha(value: Variant) -> bool:
	return value is String and RegEx.create_from_string("^[0-9a-f]{64}$").search(value) != null


## The first words of a line, for an ok line.
func _short(line: String) -> String:
	return line if line.length() <= 96 else line.substr(0, 93) + "..."
