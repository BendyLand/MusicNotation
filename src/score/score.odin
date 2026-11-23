package score

import "../toml"
import "core:fmt"
import "core:os"
import "core:strconv"
import "core:strings"

FORMAT_VERSION :: 1

Rational :: struct {
	num: i32,
	den: i32,
}

Step :: enum {
	C,
	D,
	E,
	F,
	G,
	A,
	B,
}

Clef :: enum {
	Treble,
	Bass,
	Alto,
	Tenor,
}

Accidental_Display :: enum {
	Auto,
	Force, // accidental gets preference
	Nice, // other symbol gets preference
}

Pitch :: struct {
	step:       Step,
	octave:     i8,
	alter:      i8, // -2 = bb, -1 = b, 0 = natural, 1 = #, 2 = x
	accidental: Accidental_Display,
}

Note :: struct {
	pitch:     Pitch,
	tie_start: bool,
	tie_end:   bool,
}

// A single rhythmic slot in a voice. Empty `notes` array = Rest.
Entry :: struct {
	duration: Rational,
	notes:    [dynamic]Note,
}

Voice :: struct {
	entries: [dynamic]Entry,
}

Staff_Measure :: struct {
	voices: [dynamic]Voice,
}

Staff :: struct {
	clef:     Clef,
	measures: [dynamic]Staff_Measure,
}

Part :: struct {
	name:   string,
	staves: [dynamic]Staff,
}

Measure_Meta :: struct {
	time_sig: Rational, // e.g., {4, 4}
	key_sig:  i8, // fifths: -7 (Cb) to +7 (C#)
}

Page_Setup :: struct {
	width_pt:       f32,
	height_pt:      f32,
	margin_top:     f32,
	margin_bottom:  f32,
	margin_left:    f32,
	margin_right:   f32,
	staff_space_pt: f32,
}

Score :: struct {
	version:  int,
	title:    string,
	composer: string,
	page:     Page_Setup,
	measures: [dynamic]Measure_Meta,
	parts:    [dynamic]Part,
}

default_page_setup :: proc() -> Page_Setup {
	return Page_Setup {
		width_pt = 612.0,
		height_pt = 792.0,
		margin_top = 72.0,
		margin_bottom = 72.0,
		margin_left = 54.0,
		margin_right = 54.0,
		staff_space_pt = 6.0,
	}
}

make_demo :: proc() -> Score {
	s := Score {
		version  = FORMAT_VERSION,
		title    = strings.clone("Demo Score"),
		composer = strings.clone("Anonymous"),
		page     = default_page_setup(),
	}
	for _ in 0 ..< 4 {
		append(&s.measures, Measure_Meta{time_sig = {4, 4}, key_sig = 0})
	}
	part := Part {
		name = strings.clone("Piano"),
	}
	treble := Staff {
		clef = .Treble,
	}
	demo_bars := [4][4]Pitch {
		{{.C, 4, 0, .Auto}, {.D, 4, 0, .Auto}, {.E, 4, 0, .Auto}, {.F, 4, 0, .Auto}},
		{{.G, 4, 0, .Auto}, {.A, 4, 0, .Auto}, {.B, 4, 0, .Auto}, {.C, 5, 0, .Auto}},
		{{.C, 5, 0, .Auto}, {.B, 4, 0, .Auto}, {.A, 4, 0, .Auto}, {.G, 4, 0, .Auto}},
		{{.F, 4, 0, .Auto}, {.E, 4, 0, .Auto}, {.D, 4, 0, .Auto}, {.C, 4, 0, .Auto}},
	}
	for bar in demo_bars {
		sm := Staff_Measure{}
		v := Voice{}
		for p in bar {
			e := Entry {
				duration = {1, 4},
			}
			append(&e.notes, Note{pitch = p})
			append(&v.entries, e)
		}
		append(&sm.voices, v)
		append(&treble.measures, sm)
	}
	append(&part.staves, treble)
	append(&s.parts, part)
	return s
}

save :: proc(s: ^Score, path: string) -> bool {
	s.version = FORMAT_VERSION

	b := strings.builder_make()
	defer strings.builder_destroy(&b)

	fmt.sbprintfln(&b, "version = %d", s.version)
	strings.write_string(&b, "title = ")
	write_toml_string(&b, s.title)
	strings.write_byte(&b, '\n')
	strings.write_string(&b, "composer = ")
	write_toml_string(&b, s.composer)
	strings.write_byte(&b, '\n')

	init_time := Rational{4, 4}
	init_key: i8 = 0
	if len(s.measures) > 0 {
		init_time = s.measures[0].time_sig
		init_key = s.measures[0].key_sig
	}
	fmt.sbprintfln(&b, "time = \"%d/%d\"", init_time.num, init_time.den)
	fmt.sbprintfln(&b, "key = %d", init_key)

	if has_global_changes(s.measures[:]) {
		strings.write_string(&b, "global = \"|")
		unchanged := 1 // bar 1 is already captured by top-level time/key
		for i in 1 ..< len(s.measures) {
			prev := s.measures[i - 1]
			cur := s.measures[i]
			time_changed := cur.time_sig != prev.time_sig
			key_changed := cur.key_sig != prev.key_sig

			if !time_changed && !key_changed {
				unchanged += 1
				continue
			}

			if unchanged == 1 {
				strings.write_string(&b, " |")
			}
			else if unchanged > 1 {
				fmt.sbprintf(&b, " x%d |", unchanged)
			}
			unchanged = 0

			if time_changed {
				fmt.sbprintf(&b, " time:%d/%d", cur.time_sig.num, cur.time_sig.den)
			}
			if key_changed {
				fmt.sbprintf(&b, " key:%d", cur.key_sig)
			}
			strings.write_string(&b, " |")
		}
		strings.write_string(&b, "\"\n")
	}

	p := s.page
	strings.write_string(&b, "\n[page]\n")
	fmt.sbprintfln(&b, "width_pt = %g", p.width_pt)
	fmt.sbprintfln(&b, "height_pt = %g", p.height_pt)
	fmt.sbprintfln(&b, "margin_top = %g", p.margin_top)
	fmt.sbprintfln(&b, "margin_bottom = %g", p.margin_bottom)
	fmt.sbprintfln(&b, "margin_left = %g", p.margin_left)
	fmt.sbprintfln(&b, "margin_right = %g", p.margin_right)
	fmt.sbprintfln(&b, "staff_space_pt = %g", p.staff_space_pt)

	for &part in s.parts {
		strings.write_string(&b, "\n[[parts]]\n")
		strings.write_string(&b, "name = ")
		write_toml_string(&b, part.name)
		strings.write_byte(&b, '\n')

		for &staff in part.staves {
			strings.write_string(&b, "\n[[parts.staves]]\n")
			fmt.sbprintfln(&b, "clef = \"%s\"", clef_to_string(staff.clef))

			max_voices := 0
			for &sm in staff.measures {
				max_voices = max(max_voices, len(sm.voices))
			}

			if max_voices == 0 {
				strings.write_string(&b, "voices = {}\n")
				continue
			}

			strings.write_string(&b, "voices = { ")
			for v_idx in 0 ..< max_voices {
				if v_idx > 0 {
					strings.write_string(&b, ", ")
				}
				fmt.sbprintf(&b, "v%d = \"|", v_idx + 1)
				for &sm in staff.measures {
					if v_idx < len(sm.voices) {
						last_dur := Rational{}
						for &entry in sm.voices[v_idx].entries {
							strings.write_byte(&b, ' ')
							write_entry(&b, &entry, entry.duration != last_dur)
							last_dur = entry.duration
						}
					}
					strings.write_string(&b, " |")
				}
				strings.write_byte(&b, '"')
			}
			strings.write_string(&b, " }\n")
		}
	}

	return os.write_entire_file(path, b.buf[:]) == nil
}

load :: proc(path: string) -> (s: Score, ok: bool) {
	root, err, parsed := toml.parse_file(path)
	if !parsed {
		if err.line > 0 {
			fmt.eprintfln("Failed to parse %s (%d:%d): %s", path, err.line, err.col, err.message)
		}
		return {}, false
	}
	defer toml.destroy(root)

	s.version = get_int(root, "version", 0)
	if s.version == 0 {
		return {}, false
	}

	s.title = strings.clone(get_string(root, "title", ""))
	s.composer = strings.clone(get_string(root, "composer", ""))
	s.page = default_page_setup()

	if page_tbl, has_page := get_table(root, "page"); has_page {
		s.page.width_pt = get_f32(page_tbl, "width_pt", s.page.width_pt)
		s.page.height_pt = get_f32(page_tbl, "height_pt", s.page.height_pt)
		s.page.margin_top = get_f32(page_tbl, "margin_top", s.page.margin_top)
		s.page.margin_bottom = get_f32(page_tbl, "margin_bottom", s.page.margin_bottom)
		s.page.margin_left = get_f32(page_tbl, "margin_left", s.page.margin_left)
		s.page.margin_right = get_f32(page_tbl, "margin_right", s.page.margin_right)
		s.page.staff_space_pt = get_f32(page_tbl, "staff_space_pt", s.page.staff_space_pt)
	}

	max_measures := 0
	if parts_arr, has_parts := get_array(root, "parts"); has_parts {
		for p_item in parts_arr.items {
			p_tbl, is_p_tbl := p_item.(^toml.Table)
			if !is_p_tbl {
				continue
			}

			part := Part {
				name = strings.clone(get_string(p_tbl, "name", "")),
			}

			if staves_arr, has_staves := get_array(p_tbl, "staves"); has_staves {
				for st_item in staves_arr.items {
					st_tbl, is_st_tbl := st_item.(^toml.Table)
					if !is_st_tbl {
						continue
					}

					staff := Staff {
						clef = string_to_clef(get_string(st_tbl, "clef", "treble")),
					}

					if voices_tbl, has_voices := get_table(st_tbl, "voices"); has_voices {
						for v_key, v_val in voices_tbl.entries {
							v_idx, key_ok := parse_voice_key(v_key)
							v_str, is_str := v_val.(string)
							if !key_ok || !is_str {
								continue
							}
							parse_voice_text(v_str, &staff, v_idx)
						}
					}

					max_measures = max(max_measures, len(staff.measures))
					append(&part.staves, staff)
				}
			}

			append(&s.parts, part)
		}
	}

	init_time := Rational{4, 4}
	if ts, ts_ok := parse_rational(get_string(root, "time", "4/4")); ts_ok {
		init_time = ts
	}
	init_key := i8(get_int(root, "key", 0))

	for _ in 0 ..< max_measures {
		append(&s.measures, Measure_Meta{time_sig = init_time, key_sig = init_key})
	}

	if global_str := get_string(root, "global", ""); len(global_str) > 0 {
		apply_global_stream(global_str, &s.measures, init_time, init_key)
	}

	return s, true
}

destroy :: proc(s: ^Score) {
	delete(s.title)
	delete(s.composer)
	delete(s.measures)
	for &part in s.parts {
		delete(part.name)
		for &staff in part.staves {
			for &m in staff.measures {
				for &v in m.voices {
					for &entry in v.entries {
						delete(entry.notes)
					}
					delete(v.entries)
				}
				delete(m.voices)
			}
			delete(staff.measures)
		}
		delete(part.staves)
	}
	delete(s.parts)
}

// ---------------------------------------------------------------------------
// Global Stream Helpers
// ---------------------------------------------------------------------------

@(private = "file")
has_global_changes :: proc(measures: []Measure_Meta) -> bool {
	for i in 1 ..< len(measures) {
		if measures[i].time_sig != measures[i - 1].time_sig ||
		   measures[i].key_sig != measures[i - 1].key_sig {
			return true
		}
	}
	return false
}

@(private = "file")
apply_global_stream :: proc(
	text: string,
	measures: ^[dynamic]Measure_Meta,
	init_time: Rational,
	init_key: i8,
) {
	cur_bar := 0
	cur_time := init_time
	cur_key := init_key

	rest := text
	for raw_line in strings.split_lines_iterator(&rest) {
		line := strings.trim_space(raw_line)
		if len(line) == 0 || line[0] != '|' {
			continue
		}
		trimmed := strings.trim_suffix(strings.trim_prefix(line, "|"), "|")
		for bar_text in strings.split_iterator(&trimmed, "|") {
			seg := strings.trim_space(bar_text)
			if len(seg) == 0 {
				cur_bar += 1
				continue
			}

			tokens := strings.fields(seg)
			defer delete(tokens)

			// Skip token: e.g. "x16" advances cur_bar by 16 unchanged measures
			if len(tokens) == 1 &&
			   len(tokens[0]) >= 2 &&
			   (tokens[0][0] == 'x' || tokens[0][0] == 'X') {
				if skip, ok := strconv.parse_int(tokens[0][1:]); ok && skip > 0 {
					cur_bar += skip
					continue
				}
			}

			for len(measures^) <= cur_bar {
				append(measures, Measure_Meta{time_sig = cur_time, key_sig = cur_key})
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
						for i := cur_bar; i < len(measures^); i += 1 {
							measures[i].time_sig = ts
						}
					}
				case "key":
					if fifths, ok := strconv.parse_int(v); ok {
						cur_key = i8(fifths)
						for i := cur_bar; i < len(measures^); i += 1 {
							measures[i].key_sig = i8(fifths)
						}
					}
				}
			}

			cur_bar += 1
		}
	}
}

// ---------------------------------------------------------------------------
// TOML Extraction & Escaping Helpers
// ---------------------------------------------------------------------------

@(private = "file")
get_string :: proc(t: ^toml.Table, key: string, default_val: string) -> string {
	val, ok := t.entries[key]
	if !ok {
		return default_val
	}
	s, is_str := val.(string)
	return is_str ? s : default_val
}

@(private = "file")
get_int :: proc(t: ^toml.Table, key: string, default_val: int) -> int {
	val, ok := t.entries[key]
	if !ok {
		return default_val
	}
	n, is_int := val.(i64)
	return is_int ? int(n) : default_val
}

@(private = "file")
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

@(private = "file")
get_table :: proc(t: ^toml.Table, key: string) -> (^toml.Table, bool) {
	val, ok := t.entries[key]
	if !ok {
		return nil, false
	}
	tbl, is_tbl := val.(^toml.Table)
	return tbl, is_tbl
}

@(private = "file")
get_array :: proc(t: ^toml.Table, key: string) -> (^toml.Array, bool) {
	val, ok := t.entries[key]
	if !ok {
		return nil, false
	}
	arr, is_arr := val.(^toml.Array)
	return arr, is_arr
}

@(private = "file")
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

// ---------------------------------------------------------------------------
// Musical Notation Shorthand Serialization / Parsing
// ---------------------------------------------------------------------------

@(private = "file")
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

@(private = "file")
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

@(private = "file")
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

@(private = "file")
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

@(private = "file")
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
	switch n.pitch.accidental {
	case .Auto:
	case .Force:
		strings.write_byte(b, '!')
	case .Nice:
		strings.write_byte(b, '?')
	}
	if n.tie_start {
		strings.write_byte(b, '~')
	}
}

@(private = "file")
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

@(private = "file")
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

@(private = "file")
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
	if len(s) > 0 {
		switch s[len(s) - 1] {
		case '!':
			n.pitch.accidental = .Force
			s = s[:len(s) - 1]
		case '?':
			n.pitch.accidental = .Nice
			s = s[:len(s) - 1]
		}
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
