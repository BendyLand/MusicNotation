package utils

import "core:fmt"
import "core:os"
import "core:strconv"
import "core:strings"

import "../toml"

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

save_score :: proc(s: ^Score) {
	if !save(s, SCORE_PATH) {
		fmt.eprintfln("Failed to write %s", SCORE_PATH)
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

measure_count :: proc(s: ^Score) -> int {
	n := 0
	for &part in s.parts {
		for &staff in part.staves {
			n = max(n, len(staff.measures))
		}
	}
	return n
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
			if len(staff.measures) == 0 {
				strings.write_string(&b, "voices = {}\n")
				continue
			}
			max_voices := 0
			for &sm in staff.measures {
				max_voices = max(max_voices, len(sm.voices))
			}
			strings.write_string(&b, "voices = { ")
			write_meta_voice(&b, staff.measures[:])
			for v_idx in 0 ..< max_voices {
				fmt.sbprintf(&b, ", v%d = \"|", v_idx + 1)
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
	if s.version != FORMAT_VERSION {
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
					meta_str := ""
					if voices_tbl, has_voices := get_table(st_tbl, "voices"); has_voices {
						for v_key, v_val in voices_tbl.entries {
							if v_key == "meta" {
								continue
							}
							v_idx, key_ok := parse_voice_key(v_key)
							v_str, is_str := v_val.(string)
							if !key_ok || !is_str {
								continue
							}
							parse_voice_text(v_str, &staff, v_idx)
						}
						meta_str = get_string(voices_tbl, "meta", "")
					}
					parse_meta_voice(meta_str, &staff)
					append(&part.staves, staff)
				}
			}
			append(&s.parts, part)
		}
	}
	return s, true
}

destroy :: proc(s: ^Score) {
	delete(s.title)
	delete(s.composer)
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

@(private = "file")
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


clear_measure :: proc(sm: ^Staff_Measure) {
	for &v in sm.voices {
		for &entry in v.entries {
			delete(entry.notes)
		}
		delete(v.entries)
	}
	clear(&sm.voices)
}

pop_last_entry :: proc(sm: ^Staff_Measure) -> bool {
	if len(sm.voices) == 0 || len(sm.voices[0].entries) == 0 {
		return false
	}
	v := &sm.voices[0]
	last := pop(&v.entries)
	delete(last.notes)
	return true
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

