package utils

import "../toml"
import "core:fmt"
import "core:os"
import "core:slice"
import "core:strconv"
import "core:strings"
import sdl "vendor:sdl2"
import stbtt "vendor:stb/truetype"

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

rect_contains :: proc(r: Rect, mx, my: f32) -> bool {
	return mx >= r.x && mx <= r.x + r.w && my >= r.y && my <= r.y + r.h
}

screen_to_world :: proc(cam: Camera, win_w, win_h: f32, screen_pos: [2]f32) -> [2]f32 {
	return {
		cam.pos.x + (screen_pos.x - win_w * 0.5) / cam.zoom,
		cam.pos.y + (screen_pos.y - win_h * 0.5) / cam.zoom,
	}
}

fit_camera_to_page :: proc(page: Page_Setup, win_w, win_h: f32) -> Camera {
	avail_w := max(f32(120.0), win_w - 48.0)
	avail_h := max(f32(120.0), win_h - TOOLBAR_H - STATUS_H - 48.0)
	zoom := clamp(min(avail_w / page.width_pt, avail_h / page.height_pt), 0.25, 2.0)
	return Camera{pos = {page.width_pt * 0.5, page.height_pt * 0.5}, zoom = zoom}
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

text_buf_set :: proc(tb: ^Text_Buf, s: string) {
	n := min(len(s), TEXT_BUF_MAX)
	for i in 0 ..< n {
		tb.buf[i] = s[i]
	}
	tb.len = n
}

text_buf_str :: proc(tb: ^Text_Buf) -> string {
	return string(tb.buf[:tb.len])
}

text_buf_insert_ascii :: proc(tb: ^Text_Buf, caret: ^int, bytes: []u8) -> bool {
	changed := false
	pos := clamp(caret^, 0, tb.len)
	for b in bytes {
		if b < 0x20 || b > 0x7E || tb.len >= TEXT_BUF_MAX {
			continue
		}
		for i := tb.len; i > pos; i -= 1 {
			tb.buf[i] = tb.buf[i - 1]
		}
		tb.buf[pos] = b
		tb.len += 1
		pos += 1
		changed = true
	}
	caret^ = pos
	return changed
}

text_buf_backspace :: proc(tb: ^Text_Buf, caret: ^int, delete_word: bool) -> bool {
	pos := clamp(caret^, 0, tb.len)
	if pos <= 0 {
		return false
	}
	start := pos - 1
	if delete_word {
		for start > 0 && tb.buf[start - 1] == ' ' {
			start -= 1
		}
		for start > 0 && tb.buf[start - 1] != ' ' {
			start -= 1
		}
	}
	removed := pos - start
	for i in start ..< tb.len - removed {
		tb.buf[i] = tb.buf[i + removed]
	}
	tb.len -= removed
	caret^ = start
	return true
}

text_buf_delete :: proc(tb: ^Text_Buf, caret: ^int) -> bool {
	pos := clamp(caret^, 0, tb.len)
	if pos >= tb.len {
		return false
	}
	for i in pos ..< tb.len - 1 {
		tb.buf[i] = tb.buf[i + 1]
	}
	tb.len -= 1
	return true
}

make_wizard_part :: proc(name: string, clef: Clef, is_grand := false) -> Wizard_Part {
	wp := Wizard_Part {
		clef     = clef,
		is_grand = is_grand,
	}
	text_buf_set(&wp.name, name)
	return wp
}

wizard_active_buf :: proc(wiz: ^Wizard_State) -> ^Text_Buf {
	switch wiz.focus {
	case .None:
		return nil
	case .Title:
		return &wiz.title
	case .Subtitle:
		return &wiz.subtitle
	case .Composer:
		return &wiz.composer
	case .Part_Name:
		if wiz.selected_part >= 0 && wiz.selected_part < len(wiz.parts) {
			return &wiz.parts[wiz.selected_part].name
		}
		return nil
	}
	return nil
}

wizard_focus_field :: proc(wiz: ^Wizard_State, field: Wizard_Field) {
	wiz.focus = field
	wiz.selecting_text = false
	if tb := wizard_active_buf(wiz); tb != nil {
		wiz.caret = tb.len
		wiz.sel_anchor = tb.len
	}
	else {
		wiz.caret = 0
		wiz.sel_anchor = 0
	}
}

wizard_clamp_file_scroll :: proc(wiz: ^Wizard_State) {
	if len(wiz.open_files) == 0 {
		wiz.selected_file = 0
		wiz.file_scroll = 0
		return
	}
	wiz.selected_file = clamp(wiz.selected_file, 0, len(wiz.open_files) - 1)
	if wiz.selected_file < wiz.file_scroll {
		wiz.file_scroll = wiz.selected_file
	}
	if wiz.selected_file >= wiz.file_scroll + WIZ_VISIBLE_FILE_ROWS {
		wiz.file_scroll = wiz.selected_file - WIZ_VISIBLE_FILE_ROWS + 1
	}
	max_scroll := max(0, len(wiz.open_files) - WIZ_VISIBLE_FILE_ROWS)
	wiz.file_scroll = clamp(wiz.file_scroll, 0, max_scroll)
}

wizard_refresh_files :: proc(wiz: ^Wizard_State) {
	for f in wiz.open_files {
		delete(f)
	}
	clear(&wiz.open_files)
	wiz.selected_file = 0
	wiz.file_scroll = 0

	fis, err := os.read_all_directory_by_path(".", context.allocator)
	if err != nil {
		return
	}
	defer os.file_info_slice_delete(fis, context.allocator)

	for fi in fis {
		if fi.type != .Directory && strings.has_suffix(fi.name, ".toml") {
			append(&wiz.open_files, strings.clone(fi.name))
		}
	}
	slice.sort(wiz.open_files[:])
	wizard_clamp_file_scroll(wiz)
}

wizard_init :: proc(wiz: ^Wizard_State, can_cancel: bool) {
	wiz.active = true
	wiz.can_cancel = can_cancel
	wiz.step = .Document
	text_buf_set(&wiz.title, "Untitled Score")
	text_buf_set(&wiz.subtitle, "")
	text_buf_set(&wiz.composer, "")
	wiz.page_size = .Letter
	wiz.landscape = false
	wiz.staff_size = .Medium
	wizard_apply_ensemble(wiz, .Grand_Staff)
	wiz.time_sig = {4, 4}
	wiz.fifths = 0
	wiz.is_minor = false
	wiz.measure_count = 4
	wiz.fill_rests = false
	wiz.selecting_text = false
	wizard_refresh_files(wiz)
	wizard_focus_field(wiz, .Title)
}

wizard_destroy :: proc(wiz: ^Wizard_State) {
	delete(wiz.parts)
	for f in wiz.open_files {
		delete(f)
	}
	delete(wiz.open_files)
}

wizard_clamp_scroll :: proc(wiz: ^Wizard_State) {
	if len(wiz.parts) == 0 {
		wiz.selected_part = 0
		wiz.part_scroll = 0
		return
	}
	wiz.selected_part = clamp(wiz.selected_part, 0, len(wiz.parts) - 1)
	max_scroll := max(0, len(wiz.parts) - WIZ_VISIBLE_PART_ROWS)
	wiz.part_scroll = clamp(wiz.part_scroll, 0, max_scroll)
	if wiz.selected_part < wiz.part_scroll {
		wiz.part_scroll = wiz.selected_part
	}
	else if wiz.selected_part >= wiz.part_scroll + WIZ_VISIBLE_PART_ROWS {
		wiz.part_scroll = wiz.selected_part - WIZ_VISIBLE_PART_ROWS + 1
	}
}

wizard_apply_ensemble :: proc(wiz: ^Wizard_State, preset: Ensemble_Preset) {
	clear(&wiz.parts)
	switch preset {
	case .Solo:
		append(&wiz.parts, make_wizard_part("Solo", .Treble, false))
	case .Grand_Staff:
		append(&wiz.parts, make_wizard_part("Piano", .Treble, true))
	case .Choir_SATB:
		append(&wiz.parts, make_wizard_part("Soprano", .Treble, false))
		append(&wiz.parts, make_wizard_part("Alto", .Treble, false))
		append(&wiz.parts, make_wizard_part("Tenor", .Tenor, false))
		append(&wiz.parts, make_wizard_part("Bass", .Bass, false))
	case .String_Quartet:
		append(&wiz.parts, make_wizard_part("Violin I", .Treble, false))
		append(&wiz.parts, make_wizard_part("Violin II", .Treble, false))
		append(&wiz.parts, make_wizard_part("Viola", .Alto, false))
		append(&wiz.parts, make_wizard_part("Violoncello", .Bass, false))
	case .Brass_Quintet:
		append(&wiz.parts, make_wizard_part("Trumpet I", .Treble, false))
		append(&wiz.parts, make_wizard_part("Trumpet II", .Treble, false))
		append(&wiz.parts, make_wizard_part("Horn in F", .Treble, false))
		append(&wiz.parts, make_wizard_part("Trombone", .Bass, false))
		append(&wiz.parts, make_wizard_part("Tuba", .Bass, false))
	}
	wiz.selected_part = 0
	wiz.part_scroll = 0
	if wiz.focus == .Part_Name {
		wizard_focus_field(wiz, .Part_Name)
	}
}

wizard_add_part :: proc(wiz: ^Wizard_State, name: string, clef: Clef, is_grand := false) -> bool {
	if len(wiz.parts) >= WIZ_MAX_PARTS {
		return false
	}
	append(&wiz.parts, make_wizard_part(name, clef, is_grand))
	wiz.selected_part = len(wiz.parts) - 1
	wizard_clamp_scroll(wiz)
	if wiz.focus == .Part_Name {
		wizard_focus_field(wiz, .Part_Name)
	}
	return true
}

wizard_page_setup :: proc(wiz: ^Wizard_State) -> Page_Setup {
	base_w: f32 = 612.0
	base_h: f32 = 792.0
	switch wiz.page_size {
	case .Letter:
		base_w = 612.0
		base_h = 792.0
	case .A4:
		base_w = 595.0
		base_h = 842.0
	case .Tabloid:
		base_w = 792.0
		base_h = 1224.0
	}
	if wiz.landscape {
		base_w, base_h = base_h, base_w
	}
	space: f32 = 6.0
	switch wiz.staff_size {
	case .Small:
		space = 5.0
	case .Medium:
		space = 6.0
	case .Large:
		space = 7.0
	}
	return Page_Setup {
		width_pt = base_w,
		height_pt = base_h,
		margin_top = 72.0,
		margin_bottom = 72.0,
		margin_left = 72.0,
		margin_right = 54.0,
		staff_space_pt = space,
	}
}

key_sig_name :: proc(fifths: i8, is_minor: bool) -> string {
	idx := clamp(int(fifths) + 7, 0, 14)
	major_names := [15]string {
		"Cb Major",
		"Gb Major",
		"Db Major",
		"Ab Major",
		"Eb Major",
		"Bb Major",
		"F Major",
		"C Major",
		"G Major",
		"D Major",
		"A Major",
		"E Major",
		"B Major",
		"F# Major",
		"C# Major",
	}
	minor_names := [15]string {
		"Ab Minor",
		"Eb Minor",
		"Bb Minor",
		"F Minor",
		"C Minor",
		"G Minor",
		"D Minor",
		"A Minor",
		"E Minor",
		"B Minor",
		"F# Minor",
		"C# Minor",
		"G# Minor",
		"D# Minor",
		"A# Minor",
	}
	return is_minor ? minor_names[idx] : major_names[idx]
}

step_beat_unit :: proc(cur: i32, delta: int) -> i32 {
	units := [6]i32{1, 2, 4, 8, 16, 32}
	idx := 2
	for u, i in units {
		if u == cur {
			idx = i
			break
		}
	}
	idx = clamp(idx + delta, 0, len(units) - 1)
	return units[idx]
}

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

glyph_advance :: proc(atlas: ^Glyph_Atlas, cp: rune, em_size: f32) -> f32 {
	if g, ok := atlas.glyphs[cp]; ok {
		return g.advance * em_size
	}
	return 0
}

measure_text :: proc(atlas: ^Glyph_Atlas, text: string, em_size: f32) -> f32 {
	w: f32 = 0.0
	for cp in text {
		w += glyph_advance(atlas, cp, em_size)
	}
	return w
}

text_baseline_in_rect :: proc(atlas: ^Glyph_Atlas, y, h, em_size: f32) -> f32 {
	return y + h * 0.5 + (atlas.ascent + atlas.descent) * 0.5 * em_size
}

caret_from_click :: proc(atlas: ^Glyph_Atlas, text: string, text_x, mx, em_size: f32) -> int {
	if mx <= text_x {
		return 0
	}
	cur_x := text_x
	for i in 0 ..< len(text) {
		adv := glyph_advance(atlas, rune(text[i]), em_size)
		if mx < cur_x + adv * 0.5 {
			return i
		}
		cur_x += adv
	}
	return len(text)
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
	return Pitch{step = Step(diatonic %% 7), octave = i8(diatonic / 7), alter = alter}
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
			prev_key :=
				int(prev.pitch.octave) * 14 + int(prev.pitch.step) * 2 + int(prev.pitch.alter)
			if prev_key <= cur_key {
				break
			}
			notes[j + 1] = notes[j]
			j -= 1
		}
		notes[j + 1] = cur
	}
}

inject_remainder_rests :: proc(entries: ^[dynamic]Entry, insert_idx: int, rem: Rational) {
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

default_page_setup :: proc() -> Page_Setup {
	return Page_Setup {
		width_pt = 612.0,
		height_pt = 792.0,
		margin_top = 72.0,
		margin_bottom = 72.0,
		margin_left = 72.0,
		margin_right = 54.0,
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
			w := space * 0.8 + glyph_advance(atlas, clef_glyph(staff.clef), em_size) + space * 0.9
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

beat_to_x :: proc(notes_x0, usable_w, space: f32, offset, cap: Rational) -> f32 {
	left_pad := min(space * 1.8, usable_w * 0.20)
	right_pad := min(space * 0.5, usable_w * 0.08)
	span := max(space * 1.0, usable_w - left_pad - right_pad)
	cap_f := max(f32(0.03125), rational_to_f32(cap))
	off_f := clamp(rational_to_f32(offset), 0.0, cap_f)
	return notes_x0 + left_pad + (off_f / cap_f) * span
}

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

wizard_sel_range :: proc(wiz: ^Wizard_State, tb_len: int) -> (lo, hi: int, has_sel: bool) {
	a := clamp(wiz.sel_anchor, 0, tb_len)
	b := clamp(wiz.caret, 0, tb_len)
	if a == b {
		return a, b, false
	}
	return min(a, b), max(a, b), true
}

text_buf_delete_range :: proc(tb: ^Text_Buf, lo, hi: int) -> bool {
	start := clamp(lo, 0, tb.len)
	end := clamp(hi, start, tb.len)
	removed := end - start
	if removed <= 0 {
		return false
	}
	for i in start ..< tb.len - removed {
		tb.buf[i] = tb.buf[i + removed]
	}
	tb.len -= removed
	return true
}

system_header_width :: proc(s: ^Score, atlas: ^Glyph_Atlas, start_m: int) -> f32 {
	space := s.page.staff_space_pt
	em_size := space * 4.0
	fallback_w := space * 0.8 + glyph_advance(atlas, SMUFL_G_CLEF, em_size) + space * 0.9
	max_w: f32 = 0.0
	for &part in s.parts {
		for &staff in part.staves {
			w := space * 0.8 + glyph_advance(atlas, clef_glyph(staff.clef), em_size) + space * 0.9
			if start_m < len(staff.measures) {
				meta := staff.measures[start_m].meta
				fifths := abs(int(meta.key_sig))
				if fifths > 0 {
					w += f32(fifths) * space * 1.05 + space * 0.6
				}
				show_time :=
					start_m == 0 ||
					(start_m > 0 && meta.time_sig != staff.measures[start_m - 1].meta.time_sig)
				if show_time {
					ts := meta.time_sig
					ts_w := max(
						measure_time_num(atlas, ts.num, em_size),
						measure_time_num(atlas, ts.den, em_size),
					)
					w += ts_w + space * 1.4
				}
			}
			max_w = max(max_w, w)
		}
	}
	return max_w > 0.0 ? max_w : fallback_w
}

measure_notes_bounds :: proc(
	staff: ^Staff,
	m_idx: int,
	sys: System_Layout,
	space: f32,
	atlas: ^Glyph_Atlas,
) -> (
	notes_x0, usable_w: f32,
) {
	bar_x := sys.music_x0 + f32(m_idx - sys.start_measure) * sys.measure_w
	notes_x0 = bar_x
	em_size := space * 4.0

	if m_idx > sys.start_measure && m_idx < len(staff.measures) {
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

	usable_w = max(space * 2.0, (bar_x + sys.measure_w) - notes_x0)
	return notes_x0, usable_w
}

resolve_note_target :: proc(
	s: ^Score,
	atlas: ^Glyph_Atlas,
	tool: Editor_Tool,
	world_pos: [2]f32,
) -> Note_Target {
	layout := compute_score_layout(s, atlas)
	if world_pos.x > s.page.margin_left + layout.staff_w {
		return {}
	}

	band_pad := layout.space * 4.5
	found_part := -1
	found_staff := -1
	found_m := -1
	found_staff_y: f32 = 0.0
	found_sys: System_Layout

	for sys_idx in 0 ..< layout.system_count {
		sys := layout.systems[sys_idx]
		if world_pos.x < sys.music_x0 {
			continue
		}
		local_m := int((world_pos.x - sys.music_x0) / sys.measure_w)
		m_idx := sys.start_measure + local_m
		if local_m < 0 || m_idx >= sys.end_measure {
			continue
		}

		staff_y := sys.y
		for &part, p_idx in s.parts {
			for &staff, s_idx in part.staves {
				if m_idx < len(staff.measures) &&
				   world_pos.y >= staff_y - band_pad &&
				   world_pos.y <= staff_y + layout.staff_h + band_pad {
					found_part = p_idx
					found_staff = s_idx
					found_m = m_idx
					found_staff_y = staff_y
					found_sys = sys
					break
				}
				staff_y += layout.staff_step_y
			}
			if found_part >= 0 {
				break
			}
		}
		if found_part >= 0 {
			break
		}
	}
	if found_part < 0 {
		return {}
	}

	staff := &s.parts[found_part].staves[found_staff]
	sm := &staff.measures[found_m]
	top_center_y := found_staff_y + layout.line_thick * 0.5
	half_space := layout.space * 0.5
	rel := (world_pos.y - top_center_y) / half_space
	staff_step := clamp(int(rel >= 0.0 ? rel + 0.5 : rel - 0.5), -10, 18)

	notes_x0, usable_w := measure_notes_bounds(staff, found_m, found_sys, layout.space, atlas)
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
		measure_idx  = found_m,
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
		if len(entries[best_idx].notes) == 0 &&
		   !tool.is_rest &&
		   rational_cmp(req_dur, entry_dur) < 0 {
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

compute_score_layout :: proc(s: ^Score, atlas: ^Glyph_Atlas) -> Score_Layout {
	page := s.page
	staff_w := page.width_pt - page.margin_left - page.margin_right
	space := page.staff_space_pt
	line_thick: f32 = max(0.6, space * 0.12)
	staff_h := 4.0 * space + line_thick
	staff_step_y := staff_h + space * 5.5

	total_staves := 0
	for &part in s.parts {
		total_staves += len(part.staves)
	}
	total_staves = max(1, total_staves)

	system_h := f32(total_staves - 1) * staff_step_y + staff_h
	system_gap := space * 8.5
	system_step_y := system_h + system_gap
	page_step_y := page.height_pt + PAGE_GAP_PT

	total_measures := max(1, measure_count(s))
	has_headers := len(s.title) > 0 || len(s.subtitle) > 0 || len(s.composer) > 0
	top_offset: f32 = has_headers ? 60.0 : 48.0
	first_staff_y := page.margin_top + top_offset

	layout := Score_Layout {
		staff_w        = staff_w,
		space          = space,
		line_thick     = line_thick,
		staff_h        = staff_h,
		staff_step_y   = staff_step_y,
		system_h       = system_h,
		system_step_y  = system_step_y,
		first_staff_y  = first_staff_y,
		total_staves   = total_staves,
		total_measures = total_measures,
		page_count     = 1,
		page_step_y    = page_step_y,
	}

	sys_start := 0
	cur_page := 0
	cur_y := first_staff_y
	sys_on_page := 0

	for sys_start < total_measures && layout.system_count < MAX_SYSTEMS {
		sys_end := sys_start + 1
		for sys_end < total_measures {
			brk := sys_end < len(s.breaks) ? s.breaks[sys_end] : .Auto
			if brk == .Force_Next {
				break
			}
			if brk == .Auto && (sys_end - sys_start) >= DEFAULT_BARS_PER_SYSTEM {
				break
			}
			sys_end += 1
		}

		page_bottom := f32(cur_page) * page_step_y + page.height_pt - page.margin_bottom
		if sys_on_page > 0 && cur_y + system_h > page_bottom {
			cur_page += 1
			cur_y = f32(cur_page) * page_step_y + page.margin_top
			sys_on_page = 0
		}

		header_w := system_header_width(s, atlas, sys_start)
		music_x0 := page.margin_left + header_w
		bars_in_sys := max(1, sys_end - sys_start)
		measure_w := max(space * 4.0, (staff_w - header_w) / f32(bars_in_sys))

		layout.systems[layout.system_count] = System_Layout {
			page_idx      = cur_page,
			start_measure = sys_start,
			end_measure   = sys_end,
			y             = cur_y,
			header_w      = header_w,
			music_x0      = music_x0,
			measure_w     = measure_w,
		}
		layout.system_count += 1
		cur_y += system_step_y
		sys_on_page += 1
		sys_start = sys_end
	}

	layout.page_count = max(1, cur_page + 1)
	return layout
}

write_pdf_document :: proc(
	path: string,
	page: Page_Setup,
	page_count: int,
	cmds: []Pdf_Cmd,
) -> bool {
	n_pages := max(1, page_count)
	page_w := page.width_pt
	page_h := page.height_pt
	page_step_y := page_h + PAGE_GAP_PT

	streams := make([]strings.Builder, n_pages)
	cur_rgbs := make([][3]f32, n_pages)
	for i in 0 ..< n_pages {
		streams[i] = strings.builder_make()
		cur_rgbs[i] = {-1.0, -1.0, -1.0}
	}
	defer {
		for &sb in streams {
			strings.builder_destroy(&sb)
		}
		delete(streams)
		delete(cur_rgbs)
	}

	cur_font: stbtt.fontinfo
	cur_font_ptr: rawptr = nil
	cur_unit_scale: f32 = 0.0

	for cmd in cmds {
		switch c in cmd {
		case Pdf_Rect:
			if c.w <= 0.0 || c.h <= 0.0 || c.color.a <= 0.0 {
				continue
			}
			p_idx := clamp(int(c.y / page_step_y), 0, n_pages - 1)
			local_y := c.y - f32(p_idx) * page_step_y
			rgb := [3]f32{c.color.r, c.color.g, c.color.b}
			if rgb != cur_rgbs[p_idx] {
				fmt.sbprintf(&streams[p_idx], "%.4f %.4f %.4f rg\n", rgb.r, rgb.g, rgb.b)
				cur_rgbs[p_idx] = rgb
			}
			pdf_x := c.x
			pdf_y := page_h - (local_y + c.h)
			fmt.sbprintf(&streams[p_idx], "%.3f %.3f %.3f %.3f re f\n", pdf_x, pdf_y, c.w, c.h)

		case Pdf_Glyph:
			if c.color.a <= 0.0 || c.em_size <= 0.0 || len(c.font_bytes) == 0 {
				continue
			}
			fptr := raw_data(c.font_bytes)
			if fptr != cur_font_ptr {
				if !stbtt.InitFont(&cur_font, fptr, 0) {
					continue
				}
				cur_font_ptr = fptr
				cur_unit_scale = stbtt.ScaleForMappingEmToPixels(&cur_font, 1.0)
			}
			p_idx := clamp(int(c.origin_y / page_step_y), 0, n_pages - 1)
			local_cmd := c
			local_cmd.origin_y = c.origin_y - f32(p_idx) * page_step_y
			rgb := [3]f32{c.color.r, c.color.g, c.color.b}
			if rgb != cur_rgbs[p_idx] {
				fmt.sbprintf(&streams[p_idx], "%.4f %.4f %.4f rg\n", rgb.r, rgb.g, rgb.b)
				cur_rgbs[p_idx] = rgb
			}
			write_pdf_glyph(&streams[p_idx], &cur_font, cur_unit_scale, page_h, local_cmd)
		}
	}

	pdf := strings.builder_make()
	defer strings.builder_destroy(&pdf)

	total_objs := 2 + n_pages * 2
	offsets := make([]int, total_objs + 1)
	defer delete(offsets)

	strings.write_string(&pdf, "%PDF-1.4\n%\xE2\xE3\xCF\xD3\n")

	offsets[1] = len(pdf.buf)
	strings.write_string(&pdf, "1 0 obj\n<< /Type /Catalog /Pages 2 0 R >>\nendobj\n")

	offsets[2] = len(pdf.buf)
	strings.write_string(&pdf, "2 0 obj\n<< /Type /Pages /Kids [")
	for p in 0 ..< n_pages {
		if p > 0 {
			strings.write_byte(&pdf, ' ')
		}
		fmt.sbprintf(&pdf, "%d 0 R", 3 + p * 2)
	}
	fmt.sbprintf(&pdf, "] /Count %d >>\nendobj\n", n_pages)

	for p in 0 ..< n_pages {
		page_obj := 3 + p * 2
		content_obj := 4 + p * 2
		content := strings.to_string(streams[p])

		offsets[page_obj] = len(pdf.buf)
		fmt.sbprintf(
			&pdf,
			"%d 0 obj\n<< /Type /Page /Parent 2 0 R /MediaBox [0 0 %.3f %.3f] /Contents %d 0 R >>\nendobj\n",
			page_obj,
			page_w,
			page_h,
			content_obj,
		)

		offsets[content_obj] = len(pdf.buf)
		fmt.sbprintf(&pdf, "%d 0 obj\n<< /Length %d >>\nstream\n", content_obj, len(content))
		strings.write_string(&pdf, content)
		strings.write_string(&pdf, "\nendstream\nendobj\n")
	}

	xref_offset := len(pdf.buf)
	fmt.sbprintf(&pdf, "xref\n0 %d\n0000000000 65535 f \n", total_objs + 1)
	for i in 1 ..= total_objs {
		fmt.sbprintf(&pdf, "%010d 00000 n \n", offsets[i])
	}
	fmt.sbprintf(&pdf, "trailer\n<< /Size %d /Root 1 0 R >>\nstartxref\n", total_objs + 1)
	fmt.sbprintf(&pdf, "%d\n", xref_offset)
	strings.write_string(&pdf, "%%EOF\n")

	return os.write_entire_file(path, pdf.buf[:]) == nil
}

find_system_for_measure :: proc(
	layout: ^Score_Layout,
	m_idx: int,
) -> (
	sys: System_Layout,
	ok: bool,
) {
	for i in 0 ..< layout.system_count {
		s := layout.systems[i]
		if m_idx >= s.start_measure && m_idx < s.end_measure {
			return s, true
		}
	}
	return {}, false
}

is_system_locked :: proc(s: ^Score, sys: System_Layout, total_measures: int) -> bool {
	if total_measures <= 1 || sys.end_measure <= sys.start_measure {
		return false
	}
	for m in sys.start_measure + 1 ..< sys.end_measure {
		if m >= len(s.breaks) || s.breaks[m] != .Lock_Prev {
			return false
		}
	}
	if sys.start_measure > 0 {
		if sys.start_measure >= len(s.breaks) || s.breaks[sys.start_measure] != .Force_Next {
			return false
		}
	}
	if sys.end_measure < total_measures {
		if sys.end_measure >= len(s.breaks) || s.breaks[sys.end_measure] != .Force_Next {
			return false
		}
	}
	return true
}

rects_overlap :: proc(a, b: Rect) -> bool {
	return a.x <= b.x + b.w && a.x + a.w >= b.x && a.y <= b.y + b.h && a.y + a.h >= b.y
}

total_staff_count :: proc(s: ^Score) -> int {
	total := 0
	for &part in s.parts {
		total += len(part.staves)
	}
	return total
}

staff_at_flat_index :: proc(s: ^Score, flat_idx: int) -> (part_idx, staff_idx: int, ok: bool) {
	if flat_idx < 0 {
		return 0, 0, false
	}
	cur := 0
	for &part, p_idx in s.parts {
		for _, s_idx in part.staves {
			if cur == flat_idx {
				return p_idx, s_idx, true
			}
			cur += 1
		}
	}
	return 0, 0, false
}

select_all_measures :: proc(s: ^Score) -> Selection {
	staves := total_staff_count(s)
	bars := measure_count(s)
	if staves <= 0 || bars <= 0 {
		return {}
	}
	return Selection {
		active = true,
		start_staff = 0,
		end_staff = staves - 1,
		start_measure = 0,
		end_measure = bars - 1,
	}
}

hit_test_measure :: proc(s: ^Score, atlas: ^Glyph_Atlas, world_pos: [2]f32) -> Selection {
	layout := compute_score_layout(s, atlas)
	hit_pad_y := layout.space * 3.0

	for sys_idx in 0 ..< layout.system_count {
		sys := layout.systems[sys_idx]
		if world_pos.x < sys.music_x0 {
			continue
		}
		local_m := int((world_pos.x - sys.music_x0) / sys.measure_w)
		m_idx := sys.start_measure + local_m
		if local_m < 0 || m_idx >= sys.end_measure {
			continue
		}

		staff_y := sys.y
		flat_s := 0
		for &part in s.parts {
			for &staff in part.staves {
				if m_idx < len(staff.measures) &&
				   world_pos.y >= staff_y - hit_pad_y &&
				   world_pos.y <= staff_y + layout.staff_h + hit_pad_y {
					return Selection {
						active = true,
						start_staff = flat_s,
						end_staff = flat_s,
						start_measure = m_idx,
						end_measure = m_idx,
					}
				}
				staff_y += layout.staff_step_y
				flat_s += 1
			}
		}
	}
	return {}
}

select_measures_in_rect :: proc(s: ^Score, atlas: ^Glyph_Atlas, world_r: Rect) -> Selection {
	layout := compute_score_layout(s, atlas)
	found := false
	min_s := max(int)
	max_s := -1
	min_m := max(int)
	max_m := -1

	for sys_idx in 0 ..< layout.system_count {
		sys := layout.systems[sys_idx]
		sys_rect := Rect {
			x = sys.music_x0,
			y = sys.y,
			w = f32(sys.end_measure - sys.start_measure) * sys.measure_w,
			h = layout.system_h,
		}
		if !rects_overlap(world_r, sys_rect) {
			continue
		}

		staff_y := sys.y
		flat_s := 0
		for &part in s.parts {
			for &staff in part.staves {
				for m_idx in sys.start_measure ..< min(sys.end_measure, len(staff.measures)) {
					bar_r := Rect {
						x = sys.music_x0 + f32(m_idx - sys.start_measure) * sys.measure_w,
						y = staff_y,
						w = sys.measure_w,
						h = layout.staff_h,
					}
					if rects_overlap(world_r, bar_r) {
						found = true
						min_s = min(min_s, flat_s)
						max_s = max(max_s, flat_s)
						min_m = min(min_m, m_idx)
						max_m = max(max_m, m_idx)
					}
				}
				staff_y += layout.staff_step_y
				flat_s += 1
			}
		}
	}

	if !found {
		return {}
	}
	return Selection {
		active = true,
		start_staff = min_s,
		end_staff = max_s,
		start_measure = min_m,
		end_measure = max_m,
	}
}
