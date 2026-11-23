package main

import "core:fmt"
import "core:mem"
import "score"
import win "window"

TARGET_WIDTH  :: 800
TARGET_HEIGHT :: 900
MIN_WIDTH     :: 320
MIN_HEIGHT    :: 240

SCORE_PATH :: "demo.toml"
FONT_PATH  :: "Bravura.otf"

LAYER_PAGE    :: 0
LAYER_SCORE   :: 1
LAYER_OVERLAY :: 2
LAYER_UI      :: 3

// SMuFL codepoints (Bravura)
SMUFL_G_CLEF                  :: rune(0xE050)
SMUFL_C_CLEF                  :: rune(0xE05C)
SMUFL_F_CLEF                  :: rune(0xE062)
SMUFL_TIME_SIG_0              :: rune(0xE080)
SMUFL_NOTEHEAD_WHOLE          :: rune(0xE0A2)
SMUFL_NOTEHEAD_HALF           :: rune(0xE0A3)
SMUFL_NOTEHEAD_BLACK          :: rune(0xE0A4)
SMUFL_AUGMENTATION_DOT        :: rune(0xE1E7)
SMUFL_FLAG_8TH_UP             :: rune(0xE240)
SMUFL_FLAG_8TH_DOWN           :: rune(0xE241)
SMUFL_FLAG_16TH_UP            :: rune(0xE242)
SMUFL_FLAG_16TH_DOWN          :: rune(0xE243)
SMUFL_FLAG_32ND_UP            :: rune(0xE244)
SMUFL_FLAG_32ND_DOWN          :: rune(0xE245)
SMUFL_ACCIDENTAL_FLAT         :: rune(0xE260)
SMUFL_ACCIDENTAL_NATURAL      :: rune(0xE261)
SMUFL_ACCIDENTAL_SHARP        :: rune(0xE262)
SMUFL_ACCIDENTAL_DOUBLE_SHARP :: rune(0xE263)
SMUFL_ACCIDENTAL_DOUBLE_FLAT  :: rune(0xE264)
SMUFL_REST_WHOLE              :: rune(0xE4E3)
SMUFL_REST_HALF               :: rune(0xE4E4)
SMUFL_REST_QUARTER            :: rune(0xE4E5)
SMUFL_REST_8TH                :: rune(0xE4E6)
SMUFL_REST_16TH               :: rune(0xE4E7)
SMUFL_REST_32ND               :: rune(0xE4E8)

SMUFL_GLYPHS := [?]rune{
	SMUFL_G_CLEF,
	SMUFL_C_CLEF,
	SMUFL_F_CLEF,
	SMUFL_TIME_SIG_0 + 0,
	SMUFL_TIME_SIG_0 + 1,
	SMUFL_TIME_SIG_0 + 2,
	SMUFL_TIME_SIG_0 + 3,
	SMUFL_TIME_SIG_0 + 4,
	SMUFL_TIME_SIG_0 + 5,
	SMUFL_TIME_SIG_0 + 6,
	SMUFL_TIME_SIG_0 + 7,
	SMUFL_TIME_SIG_0 + 8,
	SMUFL_TIME_SIG_0 + 9,
	SMUFL_NOTEHEAD_WHOLE,
	SMUFL_NOTEHEAD_HALF,
	SMUFL_NOTEHEAD_BLACK,
	SMUFL_AUGMENTATION_DOT,
	SMUFL_FLAG_8TH_UP,
	SMUFL_FLAG_8TH_DOWN,
	SMUFL_FLAG_16TH_UP,
	SMUFL_FLAG_16TH_DOWN,
	SMUFL_FLAG_32ND_UP,
	SMUFL_FLAG_32ND_DOWN,
	SMUFL_ACCIDENTAL_FLAT,
	SMUFL_ACCIDENTAL_NATURAL,
	SMUFL_ACCIDENTAL_SHARP,
	SMUFL_ACCIDENTAL_DOUBLE_SHARP,
	SMUFL_ACCIDENTAL_DOUBLE_FLAT,
	SMUFL_REST_WHOLE,
	SMUFL_REST_HALF,
	SMUFL_REST_QUARTER,
	SMUFL_REST_8TH,
	SMUFL_REST_16TH,
	SMUFL_REST_32ND,
}

Note_Kind :: enum {
	Whole,
	Half,
	Quarter,
	Eighth,
	Sixteenth,
	Thirty_Second,
}

main :: proc() {
	when ODIN_DEBUG {
		track: mem.Tracking_Allocator
		mem.tracking_allocator_init(&track, context.allocator)
		context.allocator = mem.tracking_allocator(&track)
		defer {
			if len(track.allocation_map) > 0 {
				fmt.eprintfln("=== %v allocations not freed: ===", len(track.allocation_map))
				for _, entry in track.allocation_map {
					fmt.eprintfln("- %v bytes @ %v", entry.size, entry.location)
				}
			}
			if len(track.bad_free_array) > 0 {
				fmt.eprintfln("=== %v incorrect frees: ===", len(track.bad_free_array))
				for entry in track.bad_free_array {
					fmt.eprintfln("- %p @ %v", entry.memory, entry.location)
				}
			}
			mem.tracking_allocator_destroy(&track)
		}
	}

	s, loaded := score.load(SCORE_PATH)
	if !loaded {
		s = score.make_demo()
		if !score.save(&s, SCORE_PATH) {
			fmt.eprintfln("Failed to write %s", SCORE_PATH)
		}
	}
	defer score.destroy(&s)

	w, ok := win.create("Notation", TARGET_WIDTH, TARGET_HEIGHT, MIN_WIDTH, MIN_HEIGHT)
	if !ok {
		return
	}
	defer win.destroy(&w)

	atlas, font_ok := win.atlas_create(FONT_PATH, SMUFL_GLYPHS[:])
	if !font_ok {
		return
	}
	defer win.atlas_destroy(&atlas)

	scene := win.scene_init(&w, .World, .World, .World, .Screen)

	cam := win.Camera {
		pos  = {s.page.width_pt * 0.5, s.page.height_pt * 0.5},
		zoom = 0.95,
	}

	draw_scene(&scene, &s, &atlas, cam)

	panning := false
	running := true
	main_loop(&cam, &scene, &s, &atlas, &running, &panning)
}

main_loop :: proc(
	cam: ^win.Camera,
	scene: ^win.Scene,
	s: ^score.Score,
	atlas: ^win.Glyph_Atlas,
	running, panning: ^bool,
) {
	for running^ {
		events, wait_ok := win.wait_events(scene.window)
		if !wait_ok {
			break
		}
		needs_redraw := false
		for event in events {
			switch e in event {
			case win.Event_Quit:
				running^ = false
			case win.Event_Redraw:
				needs_redraw = true
			case win.Event_Key_Down:
				#partial switch e.key {
				case .Escape:
					running^ = false
				case .Num_0:
					cam.pos = {s.page.width_pt * 0.5, s.page.height_pt * 0.5}
					cam.zoom = 0.95
					needs_redraw = true
				}
			case win.Event_Mouse_Down:
				if e.button == .Left || e.button == .Middle {
					panning^ = true
				}
			case win.Event_Mouse_Up:
				if e.button == .Left || e.button == .Middle {
					panning^ = false
				}
			case win.Event_Mouse_Move:
				if panning^ {
					cam.pos.x -= f32(e.dx) / cam.zoom
					cam.pos.y -= f32(e.dy) / cam.zoom
					needs_redraw = true
				} else if win.ctrl_held() {
					needs_redraw = true
				}
			case win.Event_Mouse_Wheel:
				if e.dy != 0 {
					factor: f32 = e.dy > 0 ? 1.1 : (1.0 / 1.1)
					cam.zoom = clamp(cam.zoom * factor, 0.25, 8.0)
					needs_redraw = true
				}
			}
		}
		if running^ && needs_redraw {
			draw_scene(scene, s, atlas, cam^)
		}
	}
}

draw_scene :: proc(scene: ^win.Scene, s: ^score.Score, atlas: ^win.Glyph_Atlas, cam: win.Camera) {
	win.scene_begin(scene, {0.22, 0.23, 0.25, 1.0})

	draw_page(win.scene_layer(scene, LAYER_PAGE), s.page)
	draw_score(win.scene_layer(scene, LAYER_SCORE), s, atlas)
	draw_overlay(win.scene_layer(scene, LAYER_OVERLAY), s, atlas)
	draw_ui(win.scene_layer(scene, LAYER_UI), f32(scene.window.win_w), f32(scene.window.win_h))

	pushed_inspector := false
	if win.ctrl_held() {
		mouse := win.mouse_pos()
		hovered := win.scene_hit_test(scene, cam, mouse)
		win.scene_push(scene, .Screen)
		draw_layer_badge(
			win.scene_peek(scene),
			hovered,
			mouse,
			f32(scene.window.win_w),
			f32(scene.window.win_h),
		)
		pushed_inspector = true
	}

	win.scene_end(scene, cam)

	if pushed_inspector {
		win.scene_pop(scene)
	}
}

draw_layer_badge :: proc(l: ^win.Layer, layer_idx: int, mouse: [2]f32, win_w, win_h: f32) {
	pixel_size: f32 = 3.0
	pad_x: f32 = 8.0
	pad_y: f32 = 6.0

	num_w, num_h := win.measure_int(layer_idx, pixel_size)
	box_w := num_w + pad_x * 2.0
	box_h := num_h + pad_y * 2.0

	x := clamp(mouse.x + 14.0, 4.0, max(4.0, win_w - box_w - 4.0))
	y := clamp(mouse.y + 14.0, 4.0, max(4.0, win_h - box_h - 4.0))

	win.draw_rect(l, x - 1.0, y - 1.0, box_w + 2.0, box_h + 2.0, {0.35, 0.60, 1.0, 0.85})
	win.draw_rect(l, x, y, box_w, box_h, {0.10, 0.11, 0.14, 0.94})
	win.draw_int(l, layer_idx, x + pad_x, y + pad_y, pixel_size, {0.95, 0.96, 0.98, 1.0})
}

draw_page :: proc(l: ^win.Layer, page: score.Page_Setup) {
	win.draw_rect(l, 6, 8, page.width_pt, page.height_pt, {0.0, 0.0, 0.0, 0.28})
	win.draw_rect(l, 0, 0, page.width_pt, page.height_pt, {0.98, 0.97, 0.94, 1.0})
}

staff_header_width :: proc(s: ^score.Score, atlas: ^win.Glyph_Atlas) -> f32 {
	space := s.page.staff_space_pt
	em_size := space * 4.0

	w := space * 0.8 + win.glyph_advance(atlas, SMUFL_G_CLEF, em_size) + space * 0.9
	if len(s.measures) > 0 {
		fifths := abs(int(s.measures[0].key_sig))
		if fifths > 0 {
			w += f32(fifths) * space * 1.05 + space * 0.6
		}
		ts := s.measures[0].time_sig
		ts_w := max(measure_time_num(atlas, ts.num, em_size), measure_time_num(atlas, ts.den, em_size))
		w += ts_w + space * 1.4
	}
	return w
}

draw_score :: proc(l: ^win.Layer, s: ^score.Score, atlas: ^win.Glyph_Atlas) {
	page := s.page
	staff_w := page.width_pt - page.margin_left - page.margin_right
	space := page.staff_space_pt
	em_size := space * 4.0
	line_thick: f32 = max(0.6, space * 0.12)
	staff_h := 4.0 * space + line_thick
	measure_count := max(1, len(s.measures))

	header_w := staff_header_width(s, atlas)
	music_x0 := page.margin_left + header_w
	measure_w := max(space * 4.0, (staff_w - header_w) / f32(measure_count))

	ink := [4]f32{0.08, 0.08, 0.08, 1.0}
	staff_y := page.margin_top + 48.0

	for &part in s.parts {
		for &staff in part.staves {
			top_center_y := staff_y + line_thick * 0.5

			// 5 staff lines
			for i in 0 ..< 5 {
				y := staff_y + f32(i) * space
				win.draw_rect(l, page.margin_left, y, staff_w, line_thick, ink)
			}

			// Opening barline + measure barlines
			bar_thick := max(1.0, space * 0.18)
			win.draw_rect(l, page.margin_left, staff_y, bar_thick, staff_h, ink)
			for m in 1 ..= measure_count {
				x := music_x0 + f32(m) * measure_w
				if m == measure_count {
					x = page.margin_left + staff_w - bar_thick
				}
				win.draw_rect(l, x, staff_y, bar_thick, staff_h, ink)
			}

			// Clef, key signature, and time signature
			cursor_x := page.margin_left + space * 0.8
			draw_clef(l, atlas, staff.clef, cursor_x, top_center_y, space, em_size, ink)
			cursor_x += win.glyph_advance(atlas, clef_glyph(staff.clef), em_size) + space * 0.9

			if len(s.measures) > 0 {
				key_sig := s.measures[0].key_sig
				if key_sig != 0 {
					cursor_x = draw_key_sig(l, atlas, staff.clef, key_sig, cursor_x, top_center_y, space, em_size, ink)
					cursor_x += space * 0.6
				}
				draw_time_sig(l, atlas, s.measures[0].time_sig, cursor_x, top_center_y, space, em_size, ink)
			}

			// Notes and rests
			for m_idx in 0 ..< min(len(staff.measures), measure_count) {
				bar_x := music_x0 + f32(m_idx) * measure_w
				sm := &staff.measures[m_idx]
				for &voice in sm.voices {
					if len(voice.entries) == 0 {
						continue
					}
					slot_w := measure_w / f32(len(voice.entries))
					for &entry, e_idx in voice.entries {
						cx := bar_x + (f32(e_idx) + 0.5) * slot_w
						draw_entry(l, atlas, &entry, staff.clef, cx, top_center_y, space, line_thick, em_size, ink)
					}
				}
			}

			staff_y += staff_h + space * 9.0
		}
	}
}

clef_glyph :: proc(clef: score.Clef) -> rune {
	switch clef {
	case .Treble: return SMUFL_G_CLEF
	case .Bass:   return SMUFL_F_CLEF
	case .Alto:   return SMUFL_C_CLEF
	case .Tenor:  return SMUFL_C_CLEF
	}
	return SMUFL_G_CLEF
}

draw_clef :: proc(
	l: ^win.Layer,
	atlas: ^win.Glyph_Atlas,
	clef: score.Clef,
	x, top_center_y, space, em_size: f32,
	color: [4]f32,
) {
	y := top_center_y
	switch clef {
	case .Treble: y += 3.0 * space // G4 line (2nd from bottom)
	case .Bass:   y += 1.0 * space // F3 line (2nd from top)
	case .Alto:   y += 2.0 * space // Middle line
	case .Tenor:  y += 1.0 * space // 2nd line from top
	}
	win.draw_glyph(l, atlas, clef_glyph(clef), x, y, em_size, color)
}

draw_key_sig :: proc(
	l: ^win.Layer,
	atlas: ^win.Glyph_Atlas,
	clef: score.Clef,
	fifths: i8,
	start_x, top_center_y, space, em_size: f32,
	color: [4]f32,
) -> f32 {
	sharp_steps := [score.Clef][7]int{
		.Treble = {0, 3, -1, 2, 5, 1, 4},
		.Bass   = {2, 5, 1, 4, 7, 3, 6},
		.Alto   = {1, 4, 0, 3, 6, 2, 5},
		.Tenor  = {7, 3, 6, 2, 5, 1, 4},
	}
	flat_steps := [score.Clef][7]int{
		.Treble = {4, 1, 5, 2, 6, 3, 7},
		.Bass   = {6, 3, 7, 4, 8, 5, 9},
		.Alto   = {5, 2, 6, 3, 7, 4, 8},
		.Tenor  = {3, 0, 4, 1, 5, 2, 6},
	}

	x := start_x
	count := min(abs(int(fifths)), 7)
	cp := fifths > 0 ? SMUFL_ACCIDENTAL_SHARP : SMUFL_ACCIDENTAL_FLAT
	steps := fifths > 0 ? sharp_steps[clef] : flat_steps[clef]

	for i in 0 ..< count {
		y := top_center_y + f32(steps[i]) * (space * 0.5)
		win.draw_glyph(l, atlas, cp, x, y, em_size, color)
		x += space * 1.05
	}
	return x
}

measure_time_num :: proc(atlas: ^win.Glyph_Atlas, n: i32, em_size: f32) -> f32 {
	if n <= 0 {
		return win.glyph_advance(atlas, SMUFL_TIME_SIG_0, em_size)
	}
	w: f32 = 0
	v := n
	for v > 0 {
		d := v % 10
		w += win.glyph_advance(atlas, SMUFL_TIME_SIG_0 + rune(d), em_size)
		v /= 10
	}
	return w
}

draw_time_num :: proc(
	l: ^win.Layer,
	atlas: ^win.Glyph_Atlas,
	n: i32,
	cx, cy, em_size: f32,
	color: [4]f32,
) {
	digits: [8]i32
	count := 0
	v := n
	if v <= 0 {
		digits[0] = 0
		count = 1
	} else {
		for v > 0 && count < len(digits) {
			digits[count] = v % 10
			v /= 10
			count += 1
		}
	}

	total_w := measure_time_num(atlas, n, em_size)
	x := cx - total_w * 0.5
	for i := count - 1; i >= 0; i -= 1 {
		cp := SMUFL_TIME_SIG_0 + rune(digits[i])
		win.draw_glyph(l, atlas, cp, x, cy, em_size, color)
		x += win.glyph_advance(atlas, cp, em_size)
	}
}

draw_time_sig :: proc(
	l: ^win.Layer,
	atlas: ^win.Glyph_Atlas,
	ts: score.Rational,
	x, top_center_y, space, em_size: f32,
	color: [4]f32,
) {
	num_w := measure_time_num(atlas, ts.num, em_size)
	den_w := measure_time_num(atlas, ts.den, em_size)
	cx := x + max(num_w, den_w) * 0.5

	draw_time_num(l, atlas, ts.num, cx, top_center_y + 1.0 * space, em_size, color)
	draw_time_num(l, atlas, ts.den, cx, top_center_y + 3.0 * space, em_size, color)
}

draw_entry :: proc(
	l: ^win.Layer,
	atlas: ^win.Glyph_Atlas,
	entry: ^score.Entry,
	clef: score.Clef,
	cx, top_center_y, space, line_thick, em_size: f32,
	color: [4]f32,
) {
	kind, dots := classify_duration(entry.duration)

	if len(entry.notes) == 0 {
		draw_rest(l, atlas, kind, dots, cx, top_center_y, space, em_size, color)
		return
	}

	min_step := max(int)
	max_step := min(int)
	for note in entry.notes {
		st := pitch_to_staff_step(note.pitch, clef)
		if st < min_step { min_step = st }
		if st > max_step { max_step = st }
	}

	top_dist := 4 - min_step
	bot_dist := max_step - 4
	stem_up := bot_dist > top_dist

	head_cp := notehead_glyph(kind)
	head_w := win.glyph_advance(atlas, head_cp, em_size)
	head_x := cx - head_w * 0.5

	// Ledger lines above (<= -2) and below (>= 10)
	ledger_w := head_w + space * 0.75
	ledger_thick := line_thick * 1.15
	if min_step <= -2 {
		for st := -2; st >= min_step; st -= 2 {
			ly := top_center_y + f32(st) * (space * 0.5) - ledger_thick * 0.5
			win.draw_rect(l, cx - ledger_w * 0.5, ly, ledger_w, ledger_thick, color)
		}
	}
	if max_step >= 10 {
		for st := 10; st <= max_step; st += 2 {
			ly := top_center_y + f32(st) * (space * 0.5) - ledger_thick * 0.5
			win.draw_rect(l, cx - ledger_w * 0.5, ly, ledger_w, ledger_thick, color)
		}
	}

	// Noteheads, accidentals, and augmentation dots
	for note in entry.notes {
		st := pitch_to_staff_step(note.pitch, clef)
		cy := top_center_y + f32(st) * (space * 0.5)
		win.draw_glyph(l, atlas, head_cp, head_x, cy, em_size, color)

		if note.pitch.alter != 0 || note.pitch.accidental == .Force {
			acc_cp := accidental_glyph(note.pitch.alter)
			acc_w := win.glyph_advance(atlas, acc_cp, em_size)
			win.draw_glyph(l, atlas, acc_cp, head_x - acc_w - space * 0.25, cy, em_size, color)
		}

		if dots > 0 {
			dot_y := (st % 2 == 0) ? cy - space * 0.5 : cy
			for d in 0 ..< dots {
				dot_x := head_x + head_w + space * (0.35 + f32(d) * 0.55)
				win.draw_glyph(l, atlas, SMUFL_AUGMENTATION_DOT, dot_x, dot_y, em_size, color)
			}
		}
	}

	// Stem & SMuFL flag
	if kind != .Whole {
		stem_thick := max(0.7, space * 0.12)
		stem_len := space * 3.5
		mid_y := top_center_y + 2.0 * space
		high_y := top_center_y + f32(min_step) * (space * 0.5)
		low_y := top_center_y + f32(max_step) * (space * 0.5)

		stem_x: f32
		stem_top, stem_bot: f32
		if stem_up {
			stem_x = head_x + head_w - stem_thick
			stem_bot = low_y - space * 0.14
			stem_top = min(high_y - stem_len, mid_y)
		} else {
			stem_x = head_x
			stem_top = high_y + space * 0.14
			stem_bot = max(low_y + stem_len, mid_y)
		}
		win.draw_rect(l, stem_x, stem_top, stem_thick, stem_bot - stem_top, color)

		if flag_cp, has_flag := flag_glyph(kind, stem_up); has_flag {
			tip_y := stem_up ? stem_top : stem_bot
			win.draw_glyph(l, atlas, flag_cp, stem_x, tip_y, em_size, color)
		}
	}
}

notehead_glyph :: proc(kind: Note_Kind) -> rune {
	switch kind {
	case .Whole: return SMUFL_NOTEHEAD_WHOLE
	case .Half:  return SMUFL_NOTEHEAD_HALF
	case .Quarter, .Eighth, .Sixteenth, .Thirty_Second:
		return SMUFL_NOTEHEAD_BLACK
	}
	return SMUFL_NOTEHEAD_BLACK
}

flag_glyph :: proc(kind: Note_Kind, stem_up: bool) -> (rune, bool) {
	#partial switch kind {
	case .Eighth:        return stem_up ? SMUFL_FLAG_8TH_UP : SMUFL_FLAG_8TH_DOWN, true
	case .Sixteenth:     return stem_up ? SMUFL_FLAG_16TH_UP : SMUFL_FLAG_16TH_DOWN, true
	case .Thirty_Second: return stem_up ? SMUFL_FLAG_32ND_UP : SMUFL_FLAG_32ND_DOWN, true
	}
	return 0, false
}

accidental_glyph :: proc(alter: i8) -> rune {
	switch alter {
	case -2: return SMUFL_ACCIDENTAL_DOUBLE_FLAT
	case -1: return SMUFL_ACCIDENTAL_FLAT
	case 1:  return SMUFL_ACCIDENTAL_SHARP
	case 2:  return SMUFL_ACCIDENTAL_DOUBLE_SHARP
	case:    return SMUFL_ACCIDENTAL_NATURAL
	}
}

draw_rest :: proc(
	l: ^win.Layer,
	atlas: ^win.Glyph_Atlas,
	kind: Note_Kind,
	dots: int,
	cx, top_center_y, space, em_size: f32,
	color: [4]f32,
) {
	cp: rune
	ry := top_center_y + 2.0 * space
	switch kind {
	case .Whole:
		cp = SMUFL_REST_WHOLE
		ry = top_center_y + 1.0 * space
	case .Half:
		cp = SMUFL_REST_HALF
	case .Quarter:
		cp = SMUFL_REST_QUARTER
	case .Eighth:
		cp = SMUFL_REST_8TH
	case .Sixteenth:
		cp = SMUFL_REST_16TH
	case .Thirty_Second:
		cp = SMUFL_REST_32ND
	}

	rw := win.glyph_advance(atlas, cp, em_size)
	rx := cx - rw * 0.5
	win.draw_glyph(l, atlas, cp, rx, ry, em_size, color)

	if dots > 0 {
		dot_y := top_center_y + 1.5 * space
		for d in 0 ..< dots {
			dot_x := rx + rw + space * (0.35 + f32(d) * 0.55)
			win.draw_glyph(l, atlas, SMUFL_AUGMENTATION_DOT, dot_x, dot_y, em_size, color)
		}
	}
}

classify_duration :: proc(r: score.Rational) -> (kind: Note_Kind, dots: int) {
	if r.num <= 0 || r.den <= 0 {
		return .Quarter, 0
	}
	g := gcd_i32(r.num, r.den)
	num := r.num / g
	den := r.den / g

	base_den := den
	if num == 3 && den >= 2 {
		dots = 1
		base_den = den / 2
	} else if num == 7 && den >= 4 {
		dots = 2
		base_den = den / 4
	} else if num != 1 {
		val := f64(num) / f64(den)
		if val >= 0.75 { return .Whole, 0 }
		if val >= 0.375 { return .Half, 0 }
		if val >= 0.1875 { return .Quarter, 0 }
		if val >= 0.09375 { return .Eighth, 0 }
		if val >= 0.046875 { return .Sixteenth, 0 }
		return .Thirty_Second, 0
	}

	switch base_den {
	case 1:  return .Whole, dots
	case 2:  return .Half, dots
	case 4:  return .Quarter, dots
	case 8:  return .Eighth, dots
	case 16: return .Sixteenth, dots
	case:
		if base_den < 1 { return .Whole, dots }
		return .Thirty_Second, dots
	}
}

gcd_i32 :: proc(a, b: i32) -> i32 {
	x, y := a, b
	for y != 0 {
		x, y = y, x % y
	}
	return x
}

pitch_to_staff_step :: proc(p: score.Pitch, clef: score.Clef) -> int {
	top_line_diatonic: int
	switch clef {
	case .Treble: top_line_diatonic = 5 * 7 + int(score.Step.F)
	case .Bass:   top_line_diatonic = 3 * 7 + int(score.Step.A)
	case .Alto:   top_line_diatonic = 4 * 7 + int(score.Step.G)
	case .Tenor:  top_line_diatonic = 4 * 7 + int(score.Step.E)
	}
	note_diatonic := int(p.octave) * 7 + int(p.step)
	return top_line_diatonic - note_diatonic
}

draw_overlay :: proc(l: ^win.Layer, s: ^score.Score, atlas: ^win.Glyph_Atlas) {
	page := s.page
	staff_w := page.width_pt - page.margin_left - page.margin_right
	header_w := staff_header_width(s, atlas)
	measure_w := max(page.staff_space_pt * 4.0, (staff_w - header_w) / f32(max(1, len(s.measures))))
	staff_y := page.margin_top + 48.0
	staff_h := 4.0 * page.staff_space_pt + max(0.6, page.staff_space_pt * 0.12)

	win.draw_rect(
		l,
		page.margin_left + header_w,
		staff_y - 4.0,
		measure_w,
		staff_h + 8.0,
		{0.20, 0.50, 0.95, 0.22},
	)
}

draw_ui :: proc(l: ^win.Layer, win_w, win_h: f32) {
	toolbar_h: f32 = 36.0
	status_h: f32 = 24.0
	win.draw_rect(l, 0, 0, win_w, toolbar_h, {0.14, 0.15, 0.17, 0.96})
	win.draw_rect(l, 0, toolbar_h, win_w, 1.0, {0.08, 0.08, 0.10, 1.0})
	win.draw_rect(l, 0, win_h - status_h, win_w, status_h, {0.14, 0.15, 0.17, 0.96})
}
