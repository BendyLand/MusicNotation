package utils

import "../toml"
import "core:fmt"
import "core:os"
import "core:strconv"
import "core:strings"
import sdl "vendor:sdl2"
import stbtt "vendor:stb/truetype"

// ---------------------------------------------------------------------------
// Math, Geometry, & Bitmap Digit Helpers
// ---------------------------------------------------------------------------

gcd_i32 :: proc(a, b: i32) -> i32 {
	x, y := a, b
	for y != 0 {
		x, y = y, x % y
	}
	return x == 0 ? 1 : x
}

gcd_i64 :: proc(a, b: i64) -> i64 {
	x, y := a, b
	for y != 0 {
		x, y = y, x % y
	}
	return x == 0 ? 1 : x
}

screen_to_world :: proc(cam: Camera, win_w, win_h: f32, screen_pos: [2]f32) -> [2]f32 {
	return {
		cam.pos.x + (screen_pos.x - win_w * 0.5) / cam.zoom,
		cam.pos.y + (screen_pos.y - win_h * 0.5) / cam.zoom,
	}
}

point_in_triangle :: proc(p, a, b, c: [2]f32) -> bool {
	cross :: proc(o, u, v: [2]f32) -> f32 {
		return (u.x - o.x) * (v.y - o.y) - (u.y - o.y) * (v.x - o.x)
	}
	d1 := cross(p, a, b)
	d2 := cross(p, b, c)
	d3 := cross(p, c, a)
	has_neg := (d1 < 0) || (d2 < 0) || (d3 < 0)
	has_pos := (d1 > 0) || (d2 > 0) || (d3 > 0)
	return !(has_neg && has_pos)
}

format_int_glyphs :: proc(value: int, buf: ^[16]int) -> int {
	n := 0
	v := value
	if v == 0 {
		buf[0] = 0
		return 1
	}
	if v < 0 {
		buf[0] = 10 // '-'
		n = 1
		v = -v
	}
	start := n
	for v > 0 && n < len(buf) {
		buf[n] = v % 10
		v /= 10
		n += 1
	}
	for lo, hi := start, n - 1; lo < hi; lo, hi = lo + 1, hi - 1 {
		buf[lo], buf[hi] = buf[hi], buf[lo]
	}
	return n
}

measure_int :: proc(value: int, pixel_size: f32) -> (w, h: f32) {
	buf: [16]int
	count := format_int_glyphs(value, &buf)
	return f32(count * 4 - 1) * pixel_size, 5.0 * pixel_size
}

// ---------------------------------------------------------------------------
// Window & Editor Tool Helpers
// ---------------------------------------------------------------------------

compute_initial_size :: proc(target_w, target_h, min_w, min_h: i32) -> (w, h: i32) {
	usable: sdl.Rect
	if sdl.GetDisplayUsableBounds(0, &usable) != 0 {
		return target_w, target_h
	}
	max_h := max(i32(min_h), usable.h - 80)
	max_w := max(i32(min_w), usable.w - 80)
	scale := min(f32(1.0), f32(max_h) / f32(target_h), f32(max_w) / f32(target_w))
	return i32(f32(target_w) * scale), i32(f32(target_h) * scale)
}

translate_mouse_button :: proc(btn: u8) -> Mouse_Button {
	switch btn {
	case sdl.BUTTON_LEFT:
		return .Left
	case sdl.BUTTON_MIDDLE:
		return .Middle
	case sdl.BUTTON_RIGHT:
		return .Right
	case:
		return .Unknown
	}
}

toggle_accidental :: proc(tool: ^Editor_Tool, target: Accidental_Override) {
	if tool.mode == .Select {
		tool.mode = .Note_Entry
		tool.accidental = target
	}
	else if tool.accidental == target {
		tool.accidental = .None
	}
	else {
		tool.accidental = target
	}
}

// ---------------------------------------------------------------------------
// Rational & Duration Helpers
// ---------------------------------------------------------------------------

parse_rational :: proc(s: string) -> (r: Rational, ok: bool) {
	slash := strings.index_byte(s, '/')
	if slash < 0 {
		return {}, false
	}
	num, ok_n := strconv.parse_int(s[:slash])
	den, ok_d := strconv.parse_int(s[slash + 1:])
	if !ok_n || !ok_d || den == 0 {
		return {}, false
	}
	return Rational{i32(num), i32(den)}, true
}

rational_reduce :: proc(r: Rational) -> Rational {
	if r.den == 0 || r.num == 0 {
		return {0, 1}
	}
	num := r.num
	den := r.den
	if den < 0 {
		num = -num
		den = -den
	}
	g := gcd_i32(abs(num), den)
	return {num / g, den / g}
}

rational_add :: proc(a, b: Rational) -> Rational {
	a_norm := a.den == 0 ? Rational{0, 1} : a
	b_norm := b.den == 0 ? Rational{0, 1} : b
	num := i64(a_norm.num) * i64(b_norm.den) + i64(b_norm.num) * i64(a_norm.den)
	den := i64(a_norm.den) * i64(b_norm.den)
	if den == 0 || num == 0 {
		return {0, 1}
	}
	g := gcd_i64(abs(num), abs(den))
	return {i32(num / g), i32(den / g)}
}

rational_sub :: proc(a, b: Rational) -> Rational {
	return rational_add(a, {-b.num, b.den})
}

rational_cmp :: proc(a, b: Rational) -> int {
	a_norm := a.den == 0 ? Rational{0, 1} : a
	b_norm := b.den == 0 ? Rational{0, 1} : b
	lhs := i64(a_norm.num) * i64(b_norm.den)
	rhs := i64(b_norm.num) * i64(a_norm.den)
	if lhs < rhs {return -1}
	if lhs > rhs {return 1}
	return 0
}

rational_to_f32 :: proc(r: Rational) -> f32 {
	if r.den == 0 {
		return 0.0
	}
	return f32(r.num) / f32(r.den)
}

note_kind_to_rational :: proc(kind: Note_Kind) -> Rational {
	switch kind {
	case .Whole:
		return {1, 1}
	case .Half:
		return {1, 2}
	case .Quarter:
		return {1, 4}
	case .Eighth:
		return {1, 8}
	case .Sixteenth:
		return {1, 16}
	case .Thirty_Second:
		return {1, 32}
	}
	return {1, 4}
}

classify_duration :: proc(r: Rational) -> (kind: Note_Kind, dots: int) {
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
	}
	else if num == 7 && den >= 4 {
		dots = 2
		base_den = den / 4
	}
	else if num != 1 {
		val := f64(num) / f64(den)
		if val >= 0.75 {return .Whole, 0}
		if val >= 0.375 {return .Half, 0}
		if val >= 0.1875 {return .Quarter, 0}
		if val >= 0.09375 {return .Eighth, 0}
		if val >= 0.046875 {return .Sixteenth, 0}
		return .Thirty_Second, 0
	}

	switch base_den {
	case 1:
		return .Whole, dots
	case 2:
		return .Half, dots
	case 4:
		return .Quarter, dots
	case 8:
		return .Eighth, dots
	case 16:
		return .Sixteenth, dots
	case:
		if base_den < 1 {return .Whole, dots}
		return .Thirty_Second, dots
	}
}

largest_standard_dur_le :: proc(rem: Rational) -> (Rational, bool) {
	candidates := [6]Rational{{1, 1}, {1, 2}, {1, 4}, {1, 8}, {1, 16}, {1, 32}}
	for c in candidates {
		if rational_cmp(c, rem) <= 0 {
			return c, true
		}
	}
	if rem.num > 0 && rem.den > 0 {
		return rational_reduce(rem), true
	}
	return {}, false
}

measure_capacity :: proc(meta: Measure_Meta) -> Rational {
	if meta.time_sig.num <= 0 || meta.time_sig.den <= 0 {
		return {4, 4}
	}
	return meta.time_sig
}

voice_duration_sum :: proc(entries: []Entry) -> Rational {
	sum := Rational{0, 1}
	for &e in entries {
		sum = rational_add(sum, e.duration)
	}
	return sum
}

// ---------------------------------------------------------------------------
// Pitch, Accidental, & SMuFL Glyph Helpers
// ---------------------------------------------------------------------------

glyph_advance :: proc(atlas: ^Glyph_Atlas, cp: rune, em_size: f32) -> f32 {
	if g, ok := atlas.glyphs[cp]; ok {
		return g.advance * em_size
	}
	return 0
}

clef_glyph :: proc(clef: Clef) -> rune {
	switch clef {
	case .Treble:
		return SMUFL_G_CLEF
	case .Bass:
		return SMUFL_F_CLEF
	case .Alto:
		return SMUFL_C_CLEF
	case .Tenor:
		return SMUFL_C_CLEF
	}
	return SMUFL_G_CLEF
}

notehead_glyph :: proc(kind: Note_Kind) -> rune {
	switch kind {
	case .Whole:
		return SMUFL_NOTEHEAD_WHOLE
	case .Half:
		return SMUFL_NOTEHEAD_HALF
	case .Quarter, .Eighth, .Sixteenth, .Thirty_Second:
		return SMUFL_NOTEHEAD_BLACK
	}
	return SMUFL_NOTEHEAD_BLACK
}

flag_glyph :: proc(kind: Note_Kind, stem_up: bool) -> (rune, bool) {
	#partial switch kind {
	case .Eighth:
		return stem_up ? SMUFL_FLAG_8TH_UP : SMUFL_FLAG_8TH_DOWN, true
	case .Sixteenth:
		return stem_up ? SMUFL_FLAG_16TH_UP : SMUFL_FLAG_16TH_DOWN, true
	case .Thirty_Second:
		return stem_up ? SMUFL_FLAG_32ND_UP : SMUFL_FLAG_32ND_DOWN, true
	}
	return 0, false
}

accidental_glyph :: proc(alter: i8) -> rune {
	switch alter {
	case -2:
		return SMUFL_ACCIDENTAL_DOUBLE_FLAT
	case -1:
		return SMUFL_ACCIDENTAL_FLAT
	case 1:
		return SMUFL_ACCIDENTAL_SHARP
	case 2:
		return SMUFL_ACCIDENTAL_DOUBLE_SHARP
	case:
		return SMUFL_ACCIDENTAL_NATURAL
	}
}

measure_time_num :: proc(atlas: ^Glyph_Atlas, n: i32, em_size: f32) -> f32 {
	if n <= 0 {
		return glyph_advance(atlas, SMUFL_TIME_SIG_0, em_size)
	}
	w: f32 = 0
	v := n
	for v > 0 {
		d := v % 10
		w += glyph_advance(atlas, SMUFL_TIME_SIG_0 + rune(d), em_size)
		v /= 10
	}
	return w
}

pitch_to_staff_step :: proc(p: Pitch, clef: Clef) -> int {
	top_line_diatonic: int
	switch clef {
	case .Treble:
		top_line_diatonic = 5 * 7 + int(Step.F)
	case .Bass:
		top_line_diatonic = 3 * 7 + int(Step.A)
	case .Alto:
		top_line_diatonic = 4 * 7 + int(Step.G)
	case .Tenor:
		top_line_diatonic = 4 * 7 + int(Step.E)
	}
	note_diatonic := int(p.octave) * 7 + int(p.step)
	return top_line_diatonic - note_diatonic
}

staff_step_to_pitch :: proc(staff_step: int, clef: Clef, alter: i8) -> Pitch {
	top_line_diatonic: int
	switch clef {
	case .Treble:
		top_line_diatonic = 5 * 7 + int(Step.F)
	case .Bass:
		top_line_diatonic = 3 * 7 + int(Step.A)
	case .Alto:
		top_line_diatonic = 4 * 7 + int(Step.G)
	case .Tenor:
		top_line_diatonic = 4 * 7 + int(Step.E)
	}
	diatonic := clamp(top_line_diatonic - staff_step, 0, 10 * 7 + 6)
	return Pitch {
		step   = Step(diatonic %% 7),
		octave = i8(diatonic / 7),
		alter  = alter,
	}
}

bar_accidentals_init :: proc(key_sig: i8) -> Bar_Accidental_State {
	sharp_order := [7]Step{.F, .C, .G, .D, .A, .E, .B}
	flat_order := [7]Step{.B, .E, .A, .D, .G, .C, .F}
	key_alter: [Step]i8
	if key_sig > 0 {
		for i in 0 ..< min(int(key_sig), 7) {
			key_alter[sharp_order[i]] = 1
		}
	}
	else if key_sig < 0 {
		for i in 0 ..< min(int(-key_sig), 7) {
			key_alter[flat_order[i]] = -1
		}
	}
	state: Bar_Accidental_State
	for oct in 0 ..< len(state.active) {
		state.active[oct] = key_alter
	}
	return state
}

should_draw_accidental :: proc(state: ^Bar_Accidental_State, note: Note) -> bool {
	p := note.pitch
	oct := clamp(int(p.octave), 0, len(state.active) - 1)
	current := state.active[oct][p.step]
	state.active[oct][p.step] = p.alter
	if note.tie_end {
		return false
	}
	return p.alter != current
}

accidental_state_before :: proc(
	key_sig: i8,
	entries: []Entry,
	stop_idx: int,
) -> Bar_Accidental_State {
	state := bar_accidentals_init(key_sig)
	limit := clamp(stop_idx, 0, len(entries))
	for i in 0 ..< limit {
		for note in entries[i].notes {
			p := note.pitch
			oct := clamp(int(p.octave), 0, len(state.active) - 1)
			state.active[oct][p.step] = p.alter
		}
	}
	return state
}

sort_chord_notes :: proc(notes: []Note) {
	for i := 1; i < len(notes); i += 1 {
		cur := notes[i]
		cur_key := int(cur.pitch.octave) * 14 + int(cur.pitch.step) * 2 + int(cur.pitch.alter)
		j := i - 1
		for j >= 0 {
			prev := notes[j]
			prev_key := int(prev.pitch.octave) * 14 + int(prev.pitch.step) * 2 + int(prev.pitch.alter)
			if prev_key <= cur_key {
				break
			}
			notes[j + 1] = notes[j]
			j -= 1
		}
		notes[j + 1] = cur
	}
}

inject_remainder_rests :: proc(
	entries: ^[dynamic]Entry,
	insert_idx: int,
	rem: Rational,
) {
	norm := rational_reduce(rem)
	if norm.num <= 0 || norm.den <= 0 {
		return
	}
	idx := insert_idx
	if norm.den <= 32 && (32 % norm.den) == 0 {
		ticks := norm.num * (32 / norm.den)
		units := [6]i32{1, 2, 4, 8, 16, 32}
		for u in units {
			if (ticks & u) != 0 {
				dur := rational_reduce({u, 32})
				inject_at(entries, idx, Entry{duration = dur})
				idx += 1
				ticks -= u
			}
		}
		for ticks >= 32 {
			inject_at(entries, idx, Entry{duration = {1, 1}})
			idx += 1
			ticks -= 32
		}
	}
	else {
		inject_at(entries, idx, Entry{duration = norm})
	}
}

// ---------------------------------------------------------------------------
// Score Layout & Spatial Hit-Testing Helpers
// ---------------------------------------------------------------------------

default_page_setup :: proc() -> Page_Setup {
	return Page_Setup {
		width_pt       = 612.0,
		height_pt      = 792.0,
		margin_top     = 72.0,
		margin_bottom  = 72.0,
		margin_left    = 54.0,
		margin_right   = 54.0,
		staff_space_pt = 6.0,
	}
}

measure_count :: proc(s: ^Score) -> int {
	n := 0
	for &part in s.parts {
		for &staff in part.staves {
			n = max(n, len(staff.measures))
		}
	}
	return n
}

staff_header_width :: proc(s: ^Score, atlas: ^Glyph_Atlas) -> f32 {
	space := s.page.staff_space_pt
	em_size := space * 4.0
	fallback_w := space * 0.8 + glyph_advance(atlas, SMUFL_G_CLEF, em_size) + space * 0.9
	max_w: f32 = 0.0
	for &part in s.parts {
		for &staff in part.staves {
			w :=
				space * 0.8 +
				glyph_advance(atlas, clef_glyph(staff.clef), em_size) +
				space * 0.9
			if len(staff.measures) > 0 {
				meta := staff.measures[0].meta
				fifths := abs(int(meta.key_sig))
				if fifths > 0 {
					w += f32(fifths) * space * 1.05 + space * 0.6
				}
				ts := meta.time_sig
				ts_w := max(
					measure_time_num(atlas, ts.num, em_size),
					measure_time_num(atlas, ts.den, em_size),
				)
				w += ts_w + space * 1.4
			}
			max_w = max(max_w, w)
		}
	}
	return max_w > 0.0 ? max_w : fallback_w
}

compute_score_layout :: proc(s: ^Score, atlas: ^Glyph_Atlas) -> Score_Layout {
	page := s.page
	staff_w := page.width_pt - page.margin_left - page.margin_right
	space := page.staff_space_pt
	line_thick: f32 = max(0.6, space * 0.12)
	staff_h := 4.0 * space + line_thick
	total_measures := max(1, measure_count(s))
	header_w := staff_header_width(s, atlas)
	music_x0 := page.margin_left + header_w
	measure_w := max(space * 4.0, (staff_w - header_w) / f32(total_measures))
	return Score_Layout {
		staff_w        = staff_w,
		space          = space,
		line_thick     = line_thick,
		staff_h        = staff_h,
		staff_step_y   = staff_h + space * 9.0,
		first_staff_y  = page.margin_top + 48.0,
		total_measures = total_measures,
		header_w       = header_w,
		music_x0       = music_x0,
		measure_w      = measure_w,
	}
}

measure_notes_bounds :: proc(
	staff: ^Staff,
	m_idx: int,
	layout: Score_Layout,
	atlas: ^Glyph_Atlas,
) -> (
	notes_x0, usable_w: f32,
) {
	bar_x := layout.music_x0 + f32(m_idx) * layout.measure_w
	notes_x0 = bar_x
	space := layout.space
	em_size := space * 4.0

	if m_idx > 0 && m_idx < len(staff.measures) {
		sm := &staff.measures[m_idx]
		prev_meta := staff.measures[m_idx - 1].meta
		key_changed := sm.meta.key_sig != prev_meta.key_sig
		time_changed := sm.meta.time_sig != prev_meta.time_sig
		if key_changed || time_changed {
			sig_x := bar_x + space * 0.6
			if key_changed && sm.meta.key_sig != 0 {
				sig_x += f32(min(abs(int(sm.meta.key_sig)), 7)) * space * 1.05 + space * 0.5
			}
			if time_changed {
				ts := sm.meta.time_sig
				ts_w := max(
					measure_time_num(atlas, ts.num, em_size),
					measure_time_num(atlas, ts.den, em_size),
				)
				sig_x += ts_w + space * 0.6
			}
			notes_x0 = sig_x
		}
	}

	usable_w = max(space * 2.0, (bar_x + layout.measure_w) - notes_x0)
	return notes_x0, usable_w
}

beat_to_x :: proc(notes_x0, usable_w, space: f32, offset, cap: Rational) -> f32 {
	left_pad := min(space * 1.8, usable_w * 0.20)
	right_pad := min(space * 0.5, usable_w * 0.08)
	span := max(space * 1.0, usable_w - left_pad - right_pad)
	cap_f := max(f32(0.03125), rational_to_f32(cap))
	off_f := clamp(rational_to_f32(offset), 0.0, cap_f)
	return notes_x0 + left_pad + (off_f / cap_f) * span
}

hit_test_measure :: proc(
	s: ^Score,
	atlas: ^Glyph_Atlas,
	world_pos: [2]f32,
) -> Selection {
	layout := compute_score_layout(s, atlas)
	if world_pos.x < layout.music_x0 {
		return {}
	}
	m_idx := int((world_pos.x - layout.music_x0) / layout.measure_w)
	if m_idx < 0 || m_idx >= layout.total_measures {
		return {}
	}
	hit_pad_y := layout.space * 3.0
	staff_y := layout.first_staff_y
	for &part, p_idx in s.parts {
		for &staff, s_idx in part.staves {
			if m_idx < len(staff.measures) &&
			   world_pos.y >= staff_y - hit_pad_y &&
			   world_pos.y <= staff_y + layout.staff_h + hit_pad_y {
				return Selection {
					active      = true,
					part_idx    = p_idx,
					staff_idx   = s_idx,
					measure_idx = m_idx,
				}
			}
			staff_y += layout.staff_step_y
		}
	}
	return {}
}

resolve_note_target :: proc(
	s: ^Score,
	atlas: ^Glyph_Atlas,
	tool: Editor_Tool,
	world_pos: [2]f32,
) -> Note_Target {
	layout := compute_score_layout(s, atlas)
	if world_pos.x < layout.music_x0 || world_pos.x > s.page.margin_left + layout.staff_w {
		return {}
	}
	m_idx := int((world_pos.x - layout.music_x0) / layout.measure_w)
	if m_idx < 0 || m_idx >= layout.total_measures {
		return {}
	}

	band_pad := layout.space * 4.5
	staff_y := layout.first_staff_y
	found_part := -1
	found_staff := -1
	for &part, p_idx in s.parts {
		for &staff, s_idx in part.staves {
			if m_idx < len(staff.measures) &&
			   world_pos.y >= staff_y - band_pad &&
			   world_pos.y <= staff_y + layout.staff_h + band_pad {
				found_part = p_idx
				found_staff = s_idx
				break
			}
			staff_y += layout.staff_step_y
		}
		if found_part >= 0 {
			break
		}
	}
	if found_part < 0 {
		return {}
	}

	staff := &s.parts[found_part].staves[found_staff]
	sm := &staff.measures[m_idx]
	top_center_y := staff_y + layout.line_thick * 0.5
	half_space := layout.space * 0.5
	rel := (world_pos.y - top_center_y) / half_space
	staff_step := clamp(int(rel >= 0.0 ? rel + 0.5 : rel - 0.5), -10, 18)

	notes_x0, usable_w := measure_notes_bounds(staff, m_idx, layout, atlas)
	cap := measure_capacity(sm.meta)

	entries: []Entry
	if len(sm.voices) > 0 {
		entries = sm.voices[0].entries[:]
	}

	used := voice_duration_sum(entries)
	effective_cap := rational_cmp(used, cap) > 0 ? used : cap
	rem := rational_sub(cap, used)
	has_room := rational_cmp(rem, {0, 1}) > 0

	best_idx := -1
	best_cx: f32 = 0.0
	best_dist := max(f32)
	cur_off := Rational{0, 1}
	for &e, e_idx in entries {
		ecx := beat_to_x(notes_x0, usable_w, layout.space, cur_off, effective_cap)
		d := abs(world_pos.x - ecx)
		if d < best_dist {
			best_dist = d
			best_idx = e_idx
			best_cx = ecx
		}
		cur_off = rational_add(cur_off, e.duration)
	}

	target := Note_Target {
		part_idx     = found_part,
		staff_idx    = found_staff,
		measure_idx  = m_idx,
		top_center_y = top_center_y,
		staff_step   = staff_step,
		clef         = staff.clef,
	}

	req_dur := note_kind_to_rational(tool.duration)
	stop_idx := len(entries)

	if best_idx >= 0 && (!has_room || best_dist <= layout.space * 1.35) {
		target.kind = .Existing_Entry
		target.entry_idx = best_idx
		target.cx = best_cx
		entry_dur := entries[best_idx].duration
		if len(entries[best_idx].notes) == 0 && !tool.is_rest && rational_cmp(req_dur, entry_dur) < 0 {
			target.effective_dur = req_dur
		}
		else {
			target.effective_dur = entry_dur
		}
		stop_idx = best_idx
	}
	else if has_room {
		fit_dur, fit_ok := req_dur, true
		if rational_cmp(req_dur, rem) > 0 {
			fit_dur, fit_ok = largest_standard_dur_le(rem)
		}
		if !fit_ok {
			return {}
		}
		target.kind = .Append_Entry
		target.entry_idx = len(entries)
		target.cx = beat_to_x(notes_x0, usable_w, layout.space, used, effective_cap)
		target.effective_dur = fit_dur
		stop_idx = len(entries)
	}
	else {
		return {}
	}

	bar_acc := accidental_state_before(sm.meta.key_sig, entries, stop_idx)
	base_pitch := staff_step_to_pitch(staff_step, staff.clef, 0)
	oct := clamp(int(base_pitch.octave), 0, len(bar_acc.active) - 1)
	active_alter := bar_acc.active[oct][base_pitch.step]

	alter := active_alter
	switch tool.accidental {
	case .None:
		alter = active_alter
	case .Flat:
		alter = -1
	case .Natural:
		alter = 0
	case .Sharp:
		alter = 1
	}

	target.pitch = Pitch {
		step   = base_pitch.step,
		octave = base_pitch.octave,
		alter  = alter,
	}
	target.draw_acc = !tool.is_rest && (alter != active_alter)

	if target.kind == .Existing_Entry && !tool.is_rest {
		for n in entries[target.entry_idx].notes {
			if n.pitch.step == target.pitch.step && n.pitch.octave == target.pitch.octave {
				if tool.accidental == .None || n.pitch.alter == target.pitch.alter {
					target.will_delete = true
				}
				break
			}
		}
	}

	return target
}

// ---------------------------------------------------------------------------
// TOML & Notation Shorthand Helpers
// ---------------------------------------------------------------------------

get_string :: proc(t: ^toml.Table, key: string, default_val: string) -> string {
	val, ok := t.entries[key]
	if !ok {
		return default_val
	}
	s, is_str := val.(string)
	return is_str ? s : default_val
}

get_int :: proc(t: ^toml.Table, key: string, default_val: int) -> int {
	val, ok := t.entries[key]
	if !ok {
		return default_val
	}
	n, is_int := val.(i64)
	return is_int ? int(n) : default_val
}

get_f32 :: proc(t: ^toml.Table, key: string, default_val: f32) -> f32 {
	val, ok := t.entries[key]
	if !ok {
		return default_val
	}
	#partial switch v in val {
	case f64:
		return f32(v)
	case i64:
		return f32(v)
	}
	return default_val
}

get_table :: proc(t: ^toml.Table, key: string) -> (^toml.Table, bool) {
	val, ok := t.entries[key]
	if !ok {
		return nil, false
	}
	tbl, is_tbl := val.(^toml.Table)
	return tbl, is_tbl
}

get_array :: proc(t: ^toml.Table, key: string) -> (^toml.Array, bool) {
	val, ok := t.entries[key]
	if !ok {
		return nil, false
	}
	arr, is_arr := val.(^toml.Array)
	return arr, is_arr
}

write_toml_string :: proc(b: ^strings.Builder, s: string) {
	strings.write_byte(b, '"')
	for i in 0 ..< len(s) {
		ch := s[i]
		switch ch {
		case '"':
			strings.write_string(b, `\"`)
		case '\\':
			strings.write_string(b, `\\`)
		case '\n':
			strings.write_string(b, `\n`)
		case '\r':
			strings.write_string(b, `\r`)
		case '\t':
			strings.write_string(b, `\t`)
		case:
			strings.write_byte(b, ch)
		}
	}
	strings.write_byte(b, '"')
}

clef_to_string :: proc(c: Clef) -> string {
	switch c {
	case .Treble:
		return "treble"
	case .Bass:
		return "bass"
	case .Alto:
		return "alto"
	case .Tenor:
		return "tenor"
	}
	return "treble"
}

string_to_clef :: proc(s: string) -> Clef {
	switch s {
	case "bass":
		return .Bass
	case "alto":
		return .Alto
	case "tenor":
		return .Tenor
	case:
		return .Treble
	}
}

parse_voice_key :: proc(k: string) -> (int, bool) {
	s := k
	if len(s) > 0 && (s[0] == 'v' || s[0] == 'V') {
		s = s[1:]
	}
	num, ok := strconv.parse_int(s)
	if !ok || num < 1 {
		return 0, false
	}
	return num - 1, true
}

ensure_staff_measure :: proc(staff: ^Staff, bar_idx: int, ts: Rational, key: i8) {
	for len(staff.measures) <= bar_idx {
		append(&staff.measures, Staff_Measure{})
	}
	staff.measures[bar_idx].meta = Measure_Meta {
		time_sig = ts,
		key_sig  = key,
	}
}

write_meta_voice :: proc(b: ^strings.Builder, measures: []Staff_Measure) {
	strings.write_string(b, "meta = \"|")
	for &m, i in measures {
		cur := m.meta
		if i == 0 {
			fmt.sbprintf(
				b,
				" time:%d/%d key:%d |",
				cur.time_sig.num,
				cur.time_sig.den,
				cur.key_sig,
			)
			continue
		}
		prev := measures[i - 1].meta
		time_changed := cur.time_sig != prev.time_sig
		key_changed := cur.key_sig != prev.key_sig
		if time_changed {
			fmt.sbprintf(b, " time:%d/%d", cur.time_sig.num, cur.time_sig.den)
		}
		if key_changed {
			fmt.sbprintf(b, " key:%d", cur.key_sig)
		}
		strings.write_string(b, " |")
	}
	strings.write_byte(b, '"')
}

parse_meta_voice :: proc(text: string, staff: ^Staff) {
	cur_bar := 0
	cur_time := Rational{4, 4}
	cur_key: i8 = 0

	if len(text) > 0 {
		rest := text
		for raw_line in strings.split_lines_iterator(&rest) {
			line := strings.trim_space(raw_line)
			if len(line) == 0 || line[0] != '|' {
				continue
			}
			trimmed := strings.trim_suffix(strings.trim_prefix(line, "|"), "|")
			for bar_text in strings.split_iterator(&trimmed, "|") {
				seg := strings.trim_space(bar_text)

				if len(seg) > 0 {
					tokens := strings.fields(seg)
					defer delete(tokens)

					if len(tokens) == 1 &&
					   len(tokens[0]) >= 2 &&
					   (tokens[0][0] == 'x' || tokens[0][0] == 'X') {
						if skip, ok := strconv.parse_int(tokens[0][1:]); ok && skip > 0 {
							for _ in 0 ..< skip {
								ensure_staff_measure(staff, cur_bar, cur_time, cur_key)
								cur_bar += 1
							}
							continue
						}
					}

					for tok in tokens {
						colon := strings.index_byte(tok, ':')
						if colon < 0 {
							continue
						}
						k := tok[:colon]
						v := tok[colon + 1:]
						switch k {
						case "time":
							if ts, ok := parse_rational(v); ok {
								cur_time = ts
							}
						case "key":
							if fifths, ok := strconv.parse_int(v); ok {
								cur_key = i8(fifths)
							}
						}
					}
				}
				ensure_staff_measure(staff, cur_bar, cur_time, cur_key)
				cur_bar += 1
			}
		}
	}

	for i in cur_bar ..< len(staff.measures) {
		staff.measures[i].meta = Measure_Meta {
			time_sig = cur_time,
			key_sig  = cur_key,
		}
	}
}

write_entry :: proc(b: ^strings.Builder, entry: ^Entry, include_dur: bool) {
	if len(entry.notes) == 0 {
		strings.write_byte(b, 'r')
	}
	else {
		for note, i in entry.notes {
			if i > 0 {
				strings.write_byte(b, '+')
			}
			write_note(b, note)
		}
	}
	if include_dur {
		fmt.sbprintf(b, ":%d/%d", entry.duration.num, entry.duration.den)
	}
}

write_note :: proc(b: ^strings.Builder, n: Note) {
	if n.tie_end {
		strings.write_byte(b, '~')
	}
	step_chars := [Step]u8 {
		.C = 'C',
		.D = 'D',
		.E = 'E',
		.F = 'F',
		.G = 'G',
		.A = 'A',
		.B = 'B',
	}
	strings.write_byte(b, step_chars[n.pitch.step])
	switch n.pitch.alter {
	case -2:
		strings.write_string(b, "bb")
	case -1:
		strings.write_byte(b, 'b')
	case 1:
		strings.write_byte(b, '#')
	case 2:
		strings.write_string(b, "##")
	}
	fmt.sbprintf(b, "%d", n.pitch.octave)
	if n.tie_start {
		strings.write_byte(b, '~')
	}
}

parse_voice_text :: proc(text: string, staff: ^Staff, voice_idx: int) {
	cur_bar := 0
	rest := text
	for raw_line in strings.split_lines_iterator(&rest) {
		line := strings.trim_space(raw_line)
		if len(line) == 0 || line[0] != '|' {
			continue
		}
		trimmed := strings.trim_suffix(strings.trim_prefix(line, "|"), "|")
		for bar_text in strings.split_iterator(&trimmed, "|") {
			for len(staff.measures) <= cur_bar {
				append(&staff.measures, Staff_Measure{})
			}
			sm := &staff.measures[cur_bar]
			for len(sm.voices) <= voice_idx {
				append(&sm.voices, Voice{})
			}
			parse_bar(strings.trim_space(bar_text), &sm.voices[voice_idx])
			cur_bar += 1
		}
	}
}

parse_bar :: proc(bar_text: string, voice: ^Voice) {
	if len(bar_text) == 0 {
		return
	}
	tokens := strings.fields(bar_text)
	defer delete(tokens)
	last_dur := Rational{1, 4}
	for tok in tokens {
		body := tok
		dur := last_dur
		if colon := strings.index_byte(tok, ':'); colon >= 0 {
			body = tok[:colon]
			if parsed, ok := parse_rational(tok[colon + 1:]); ok {
				dur = parsed
				last_dur = parsed
			}
		}
		entry := Entry {
			duration = dur,
		}
		if body != "r" && body != "R" {
			note_rest := body
			for note_tok in strings.split_iterator(&note_rest, "+") {
				if note, ok := parse_note(note_tok); ok {
					append(&entry.notes, note)
				}
			}
		}
		append(&voice.entries, entry)
	}
}

parse_note :: proc(tok: string) -> (n: Note, ok: bool) {
	s := tok
	if len(s) == 0 {
		return {}, false
	}
	if s[0] == '~' {
		n.tie_end = true
		s = s[1:]
	}
	if len(s) > 0 && s[len(s) - 1] == '~' {
		n.tie_start = true
		s = s[:len(s) - 1]
	}
	if len(s) < 2 {
		return {}, false
	}
	switch s[0] {
	case 'C', 'c':
		n.pitch.step = .C
	case 'D', 'd':
		n.pitch.step = .D
	case 'E', 'e':
		n.pitch.step = .E
	case 'F', 'f':
		n.pitch.step = .F
	case 'G', 'g':
		n.pitch.step = .G
	case 'A', 'a':
		n.pitch.step = .A
	case 'B', 'b':
		n.pitch.step = .B
	case:
		return {}, false
	}
	s = s[1:]
	for len(s) > 0 {
		if s[0] == '#' {
			n.pitch.alter += 1
			s = s[1:]
		}
		else if s[0] == 'b' {
			n.pitch.alter -= 1
			s = s[1:]
		}
		else {
			break
		}
	}
	oct, oct_ok := strconv.parse_int(s)
	if !oct_ok {
		return {}, false
	}
	n.pitch.octave = i8(oct)
	return n, true
}

// ---------------------------------------------------------------------------
// PDF Encoding Helpers
// ---------------------------------------------------------------------------

write_pdf_document :: proc(
	path: string,
	page: Page_Setup,
	font_bytes: []u8,
	cmds: []Pdf_Cmd,
) -> bool {
	if len(font_bytes) == 0 {
		return false
	}

	font: stbtt.fontinfo
	if !stbtt.InitFont(&font, raw_data(font_bytes), 0) {
		return false
	}
	unit_scale := stbtt.ScaleForMappingEmToPixels(&font, 1.0)

	page_w := page.width_pt
	page_h := page.height_pt

	stream := strings.builder_make()
	defer strings.builder_destroy(&stream)

	cur_rgb := [3]f32{-1.0, -1.0, -1.0}
	for cmd in cmds {
		switch c in cmd {
		case Pdf_Rect:
			if c.w <= 0.0 || c.h <= 0.0 || c.color.a <= 0.0 {
				continue
			}
			rgb := [3]f32{c.color.r, c.color.g, c.color.b}
			if rgb != cur_rgb {
				fmt.sbprintf(&stream, "%.4f %.4f %.4f rg\n", rgb.r, rgb.g, rgb.b)
				cur_rgb = rgb
			}
			pdf_x := c.x
			pdf_y := page_h - (c.y + c.h)
			fmt.sbprintf(&stream, "%.3f %.3f %.3f %.3f re f\n", pdf_x, pdf_y, c.w, c.h)

		case Pdf_Glyph:
			if c.color.a <= 0.0 || c.em_size <= 0.0 {
				continue
			}
			rgb := [3]f32{c.color.r, c.color.g, c.color.b}
			if rgb != cur_rgb {
				fmt.sbprintf(&stream, "%.4f %.4f %.4f rg\n", rgb.r, rgb.g, rgb.b)
				cur_rgb = rgb
			}
			write_pdf_glyph(&stream, &font, unit_scale, page_h, c)
		}
	}

	content := strings.to_string(stream)

	pdf := strings.builder_make()
	defer strings.builder_destroy(&pdf)

	strings.write_string(&pdf, "%PDF-1.4\n%\xE2\xE3\xCF\xD3\n")

	offsets: [5]int
	offsets[1] = len(pdf.buf)
	strings.write_string(&pdf, "1 0 obj\n<< /Type /Catalog /Pages 2 0 R >>\nendobj\n")

	offsets[2] = len(pdf.buf)
	strings.write_string(&pdf, "2 0 obj\n<< /Type /Pages /Kids [3 0 R] /Count 1 >>\nendobj\n")

	offsets[3] = len(pdf.buf)
	fmt.sbprintf(
		&pdf,
		"3 0 obj\n<< /Type /Page /Parent 2 0 R /MediaBox [0 0 %.3f %.3f] /Contents 4 0 R >>\nendobj\n",
		page_w,
		page_h,
	)

	offsets[4] = len(pdf.buf)
	fmt.sbprintf(&pdf, "4 0 obj\n<< /Length %d >>\nstream\n", len(content))
	strings.write_string(&pdf, content)
	strings.write_string(&pdf, "\nendstream\nendobj\n")

	xref_offset := len(pdf.buf)
	strings.write_string(&pdf, "xref\n0 5\n0000000000 65535 f \n")
	for i in 1 ..= 4 {
		fmt.sbprintf(&pdf, "%010d 00000 n \n", offsets[i])
	}
	strings.write_string(&pdf, "trailer\n<< /Size 5 /Root 1 0 R >>\nstartxref\n")
	fmt.sbprintf(&pdf, "%d\n", xref_offset)
	strings.write_string(&pdf, "%%EOF\n")

	return os.write_entire_file(path, pdf.buf[:]) == nil
}

@(private = "file")
write_pdf_glyph :: proc(
	b: ^strings.Builder,
	font: ^stbtt.fontinfo,
	unit_scale: f32,
	page_h: f32,
	cmd: Pdf_Glyph,
) {
	glyph_idx := stbtt.FindGlyphIndex(font, cmd.cp)
	if glyph_idx == 0 {
		return
	}

	raw_verts: [^]stbtt.vertex
	num_verts := stbtt.GetGlyphShape(font, glyph_idx, &raw_verts)
	if num_verts <= 0 || raw_verts == nil {
		return
	}
	defer stbtt.FreeShape(font, raw_verts)

	sc := unit_scale * cmd.em_size
	ox := cmd.origin_x
	oy := page_h - cmd.origin_y

	cur_x := ox
	cur_y := oy
	has_path := false

	for v in raw_verts[:num_verts] {
		px := ox + f32(v.x) * sc
		py := oy + f32(v.y) * sc

		switch stbtt.vmove(v.type) {
		case .none:
		case .vmove:
			fmt.sbprintf(b, "%.3f %.3f m\n", px, py)
			cur_x, cur_y = px, py
			has_path = true
		case .vline:
			fmt.sbprintf(b, "%.3f %.3f l\n", px, py)
			cur_x, cur_y = px, py
			has_path = true
		case .vcurve:
			qx := ox + f32(v.cx) * sc
			qy := oy + f32(v.cy) * sc
			c1x := (cur_x + 2.0 * qx) / 3.0
			c1y := (cur_y + 2.0 * qy) / 3.0
			c2x := (px + 2.0 * qx) / 3.0
			c2y := (py + 2.0 * qy) / 3.0
			fmt.sbprintf(b, "%.3f %.3f %.3f %.3f %.3f %.3f c\n", c1x, c1y, c2x, c2y, px, py)
			cur_x, cur_y = px, py
			has_path = true
		case .vcubic:
			c1x := ox + f32(v.cx) * sc
			c1y := oy + f32(v.cy) * sc
			c2x := ox + f32(v.cx1) * sc
			c2y := oy + f32(v.cy1) * sc
			fmt.sbprintf(b, "%.3f %.3f %.3f %.3f %.3f %.3f c\n", c1x, c1y, c2x, c2y, px, py)
			cur_x, cur_y = px, py
			has_path = true
		}
	}

	if has_path {
		strings.write_string(b, "f\n")
	}
}

