package score

import "../toml"
import "../utils"
import win "../window"
import "core:fmt"
import "core:os"
import "core:strings"
import "core:strconv"

make_demo :: proc() -> utils.Score {
	s := utils.Score {
		version  = utils.FORMAT_VERSION,
		title    = strings.clone("Demo Score"),
		subtitle = strings.clone(""),
		composer = strings.clone("Anonymous"),
		page     = utils.default_page_setup(),
	}
	part := utils.Part {
		name = strings.clone("Piano"),
	}
	treble := utils.Staff {
		clef = .Treble,
	}
	for _ in 0 ..< 4 {
		append(
			&treble.measures,
			utils.Staff_Measure {
				meta = utils.Measure_Meta {
					time_sig = {4, 4},
					key_sig  = 0,
				},
			},
		)
	}
	append(&part.staves, treble)
	append(&s.parts, part)
	return s
}

@(private = "file")
build_wizard_staff :: proc(
	clef: utils.Clef,
	bars: int,
	ts: utils.Rational,
	fifths: i8,
	fill_rests: bool,
) -> utils.Staff {
	staff := utils.Staff {
		clef = clef,
	}
	for _ in 0 ..< bars {
		sm := utils.Staff_Measure {
			meta = utils.Measure_Meta {
				time_sig = ts,
				key_sig  = fifths,
			},
		}
		if fill_rests {
			v := utils.Voice{}
			utils.inject_remainder_rests(&v.entries, 0, ts)
			append(&sm.voices, v)
		}
		append(&staff.measures, sm)
	}
	return staff
}

from_wizard :: proc(wiz: ^utils.Wizard_State) -> utils.Score {
	s := utils.Score {
		version  = utils.FORMAT_VERSION,
		title    = strings.clone(utils.text_buf_str(&wiz.title)),
		subtitle = strings.clone(utils.text_buf_str(&wiz.subtitle)),
		composer = strings.clone(utils.text_buf_str(&wiz.composer)),
		page     = utils.wizard_page_setup(wiz),
	}

	bars := clamp(wiz.measure_count, 1, 64)
	ts := wiz.time_sig.num > 0 && wiz.time_sig.den > 0 ? wiz.time_sig : utils.Rational{4, 4}
	fifths := clamp(wiz.fifths, -7, 7)

	if len(wiz.parts) == 0 {
		part := utils.Part {
			name = strings.clone("Treble"),
		}
		append(&part.staves, build_wizard_staff(.Treble, bars, ts, fifths, wiz.fill_rests))
		append(&s.parts, part)
		return s
	}

	for &wp in wiz.parts {
		part := utils.Part {
			name = strings.clone(utils.text_buf_str(&wp.name)),
		}
		if wp.is_grand {
			append(&part.staves, build_wizard_staff(.Treble, bars, ts, fifths, wiz.fill_rests))
			append(&part.staves, build_wizard_staff(.Bass, bars, ts, fifths, wiz.fill_rests))
		}
		else {
			append(&part.staves, build_wizard_staff(wp.clef, bars, ts, fifths, wiz.fill_rests))
		}
		append(&s.parts, part)
	}

	return s
}

load :: proc(path: string) -> (s: utils.Score, ok: bool) {
	root, err, parsed := toml.parse_file(path)
	if !parsed {
		if err.line > 0 {
			fmt.eprintfln("Failed to parse %s (%d:%d): %s", path, err.line, err.col, err.message)
		}
		return {}, false
	}
	defer toml.destroy(root)

	s.version = utils.get_int(root, "version", 0)
	if s.version != utils.FORMAT_VERSION {
		return {}, false
	}

	s.title = strings.clone(utils.get_string(root, "title", ""))
	s.subtitle = strings.clone(utils.get_string(root, "subtitle", ""))
	s.composer = strings.clone(utils.get_string(root, "composer", ""))
	s.page = utils.default_page_setup()

	if page_tbl, has_page := utils.get_table(root, "page"); has_page {
		s.page.width_pt = utils.get_f32(page_tbl, "width_pt", s.page.width_pt)
		s.page.height_pt = utils.get_f32(page_tbl, "height_pt", s.page.height_pt)
		s.page.margin_top = utils.get_f32(page_tbl, "margin_top", s.page.margin_top)
		s.page.margin_bottom = utils.get_f32(page_tbl, "margin_bottom", s.page.margin_bottom)
		s.page.margin_left = utils.get_f32(page_tbl, "margin_left", s.page.margin_left)
		s.page.margin_right = utils.get_f32(page_tbl, "margin_right", s.page.margin_right)
		s.page.staff_space_pt = utils.get_f32(page_tbl, "staff_space_pt", s.page.staff_space_pt)
	}

	if parts_arr, has_parts := utils.get_array(root, "parts"); has_parts {
		for p_item in parts_arr.items {
			p_tbl, is_p_tbl := p_item.(^toml.Table)
			if !is_p_tbl {
				continue
			}
			part := utils.Part {
				name = strings.clone(utils.get_string(p_tbl, "name", "")),
			}
			if staves_arr, has_staves := utils.get_array(p_tbl, "staves"); has_staves {
				for st_item in staves_arr.items {
					st_tbl, is_st_tbl := st_item.(^toml.Table)
					if !is_st_tbl {
						continue
					}
					staff := utils.Staff {
						clef = utils.string_to_clef(utils.get_string(st_tbl, "clef", "treble")),
					}
					meta_str := ""
					if voices_tbl, has_voices := utils.get_table(st_tbl, "voices"); has_voices {
						for v_key, v_val in voices_tbl.entries {
							if v_key == "meta" {
								continue
							}
							v_idx, key_ok := utils.parse_voice_key(v_key)
							v_str, is_str := v_val.(string)
							if !key_ok || !is_str {
								continue
							}
							utils.parse_voice_text(v_str, &staff, v_idx)
						}
						meta_str = utils.get_string(voices_tbl, "meta", "")
					}
					utils.parse_meta_voice(meta_str, &staff)
					append(&part.staves, staff)
				}
			}
			append(&s.parts, part)
		}
	}

	if layout_tbl, has_layout := utils.get_table(root, "layout"); has_layout {
		breaks_str := utils.get_string(layout_tbl, "breaks", "")
		if len(breaks_str) > 0 {
			tokens := strings.fields(breaks_str)
			defer delete(tokens)
			for tok in tokens {
				colon := strings.index_byte(tok, ':')
				if colon < 0 {
					continue
				}
				idx, ok_idx := strconv.parse_int(tok[:colon])
				if !ok_idx || idx <= 0 || idx >= 64 {
					continue
				}
				tag := tok[colon + 1:]
				brk := utils.Measure_Break.Auto
				if tag == "next" {
					brk = .Force_Next
				}
				else if tag == "lock" {
					brk = .Lock_Prev
				}
				if brk != .Auto {
					for len(s.breaks) <= idx {
						append(&s.breaks, utils.Measure_Break.Auto)
					}
					s.breaks[idx] = brk
				}
			}
		}
	}

	return s, true
}

save :: proc(s: ^utils.Score, path: string) -> bool {
	s.version = utils.FORMAT_VERSION
	b := strings.builder_make()
	defer strings.builder_destroy(&b)

	fmt.sbprintfln(&b, "version = %d", s.version)
	strings.write_string(&b, "title = ")
	utils.write_toml_string(&b, s.title)
	strings.write_byte(&b, '\n')
	strings.write_string(&b, "subtitle = ")
	utils.write_toml_string(&b, s.subtitle)
	strings.write_byte(&b, '\n')
	strings.write_string(&b, "composer = ")
	utils.write_toml_string(&b, s.composer)
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

	has_breaks := false
	for brk in s.breaks {
		if brk != .Auto {
			has_breaks = true
			break
		}
	}
	if has_breaks {
		strings.write_string(&b, "\n[layout]\nbreaks = \"")
		first := true
		for brk, idx in s.breaks {
			if brk == .Auto {
				continue
			}
			if !first {
				strings.write_byte(&b, ' ')
			}
			first = false
			tag := brk == .Force_Next ? "next" : "lock"
			fmt.sbprintf(&b, "%d:%s", idx, tag)
		}
		strings.write_string(&b, "\"\n")
	}

	for &part in s.parts {
		strings.write_string(&b, "\n[[parts]]\n")
		strings.write_string(&b, "name = ")
		utils.write_toml_string(&b, part.name)
		strings.write_byte(&b, '\n')

		for &staff in part.staves {
			strings.write_string(&b, "\n[[parts.staves]]\n")
			fmt.sbprintfln(&b, "clef = \"%s\"", utils.clef_to_string(staff.clef))
			if len(staff.measures) == 0 {
				strings.write_string(&b, "voices = {}\n")
				continue
			}

			max_voices := 0
			for &sm in staff.measures {
				max_voices = max(max_voices, len(sm.voices))
			}

			strings.write_string(&b, "voices = { ")
			utils.write_meta_voice(&b, staff.measures[:])
			for v_idx in 0 ..< max_voices {
				fmt.sbprintf(&b, ", v%d = \"|", v_idx + 1)
				for &sm in staff.measures {
					if v_idx < len(sm.voices) {
						last_dur := utils.Rational{}
						for &entry in sm.voices[v_idx].entries {
							strings.write_byte(&b, ' ')
							utils.write_entry(&b, &entry, entry.duration != last_dur)
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

destroy :: proc(s: ^utils.Score) {
	delete(s.title)
	delete(s.subtitle)
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
	delete(s.breaks)
}

save_score :: proc(s: ^utils.Score) {
	if !save(s, utils.SCORE_PATH) {
		fmt.eprintfln("Failed to write %s", utils.SCORE_PATH)
	}
}

clear_measure :: proc(sm: ^utils.Staff_Measure) {
	for &v in sm.voices {
		for &entry in v.entries {
			delete(entry.notes)
		}
		delete(v.entries)
	}
	clear(&sm.voices)
}

pop_last_entry :: proc(sm: ^utils.Staff_Measure) -> bool {
	if len(sm.voices) == 0 || len(sm.voices[0].entries) == 0 {
		return false
	}
	v := &sm.voices[0]
	last := pop(&v.entries)
	delete(last.notes)
	return true
}

pop_entry_at_world :: proc(
	s: ^utils.Score,
	atlas: ^utils.Glyph_Atlas,
	world_pos: [2]f32,
) -> bool {
	sel := utils.hit_test_measure(s, atlas, world_pos)
	if !sel.active {
		return false
	}
	sm := &s.parts[sel.part_idx].staves[sel.staff_idx].measures[sel.measure_idx]
	return pop_last_entry(sm)
}

apply_note_click :: proc(
	s: ^utils.Score,
	atlas: ^utils.Glyph_Atlas,
	tool: utils.Editor_Tool,
	world_pos: [2]f32,
) -> bool {
	target := utils.resolve_note_target(s, atlas, tool, world_pos)
	#partial switch target.kind {
	case .None:
		return false

	case .Append_Entry:
		sm := &s.parts[target.part_idx].staves[target.staff_idx].measures[target.measure_idx]
		if len(sm.voices) == 0 {
			append(&sm.voices, utils.Voice{})
		}
		entry := utils.Entry {
			duration = target.effective_dur,
		}
		if !tool.is_rest {
			append(&entry.notes, utils.Note{pitch = target.pitch})
		}
		append(&sm.voices[0].entries, entry)
		return true

	case .Existing_Entry:
		sm := &s.parts[target.part_idx].staves[target.staff_idx].measures[target.measure_idx]
		if len(sm.voices) == 0 || target.entry_idx >= len(sm.voices[0].entries) {
			return false
		}
		v := &sm.voices[0]
		entry := &v.entries[target.entry_idx]

		if tool.is_rest {
			if len(entry.notes) == 0 {
				return false
			}
			clear(&entry.notes)
			return true
		}

		// Pitched click onto an existing rest: fill or split the rest
		if len(entry.notes) == 0 {
			old_dur := entry.duration
			req_dur := utils.note_kind_to_rational(tool.duration)
			if utils.rational_cmp(req_dur, old_dur) < 0 {
				entry.duration = req_dur
				append(&entry.notes, utils.Note{pitch = target.pitch})
				rem := utils.rational_sub(old_dur, req_dur)
				utils.inject_remainder_rests(&v.entries, target.entry_idx + 1, rem)
			}
			else {
				append(&entry.notes, utils.Note{pitch = target.pitch})
			}
			return true
		}

		// Pitched click onto an existing note/chord: update accidental, remove duplicate, or add chord tone
		for &n, n_idx in entry.notes {
			if n.pitch.step == target.pitch.step && n.pitch.octave == target.pitch.octave {
				if tool.accidental != .None && n.pitch.alter != target.pitch.alter {
					n.pitch.alter = target.pitch.alter
					utils.sort_chord_notes(entry.notes[:])
					return true
				}
				ordered_remove(&entry.notes, n_idx)
				if len(entry.notes) == 0 && target.entry_idx == len(v.entries) - 1 {
					last := pop(&v.entries)
					delete(last.notes)
				}
				return true
			}
		}

		append(&entry.notes, utils.Note{pitch = target.pitch})
		utils.sort_chord_notes(entry.notes[:])
		return true
	}

	return false
}

export_score_pdf :: proc(s: ^utils.Score, fonts: ^utils.Fonts) {
	if export_pdf(s, fonts, utils.PDF_PATH) {
		fmt.printfln("Exported %s", utils.PDF_PATH)
	}
	else {
		fmt.eprintfln("Failed to export %s", utils.PDF_PATH)
	}
}

destroy_measure :: proc(sm: ^utils.Staff_Measure) {
	clear_measure(sm)
	delete(sm.voices)
	sm.voices = nil
}

insert_measure :: proc(s: ^utils.Score, at_idx: int) -> bool {
	total := utils.measure_count(s)
	if total >= 64 {
		return false
	}
	idx := clamp(at_idx, 0, total)

	for &part in s.parts {
		for &staff in part.staves {
			meta := utils.Measure_Meta {
				time_sig = {4, 4},
				key_sig  = 0,
			}
			if len(staff.measures) > 0 {
				ref_idx := idx > 0 ? min(idx - 1, len(staff.measures) - 1) : 0
				meta = staff.measures[ref_idx].meta
			}
			new_sm := utils.Staff_Measure {
				meta = meta,
			}
			insert_at := clamp(idx, 0, len(staff.measures))
			inject_at(&staff.measures, insert_at, new_sm)
		}
	}

	for len(s.breaks) < total {
		append(&s.breaks, utils.Measure_Break.Auto)
	}
	inject_at(&s.breaks, idx, utils.Measure_Break.Auto)
	return true
}

remove_measure :: proc(s: ^utils.Score, at_idx: int) -> bool {
	total := utils.measure_count(s)
	if total <= 1 || at_idx < 0 || at_idx >= total {
		return false
	}

	for &part in s.parts {
		for &staff in part.staves {
			if at_idx < len(staff.measures) {
				destroy_measure(&staff.measures[at_idx])
				ordered_remove(&staff.measures, at_idx)
			}
		}
	}

	if at_idx < len(s.breaks) {
		ordered_remove(&s.breaks, at_idx)
	}
	return true
}

toggle_measure_break :: proc(s: ^utils.Score, m_idx: int, target: utils.Measure_Break) -> bool {
	total := utils.measure_count(s)
	if m_idx <= 0 || m_idx >= total {
		return false
	}
	for len(s.breaks) < total {
		append(&s.breaks, utils.Measure_Break.Auto)
	}
	s.breaks[m_idx] = (s.breaks[m_idx] == target) ? .Auto : target
	return true
}

export_pdf :: proc(s: ^utils.Score, fonts: ^utils.Fonts, path: string) -> bool {
	if len(fonts.music.font_bytes) == 0 {
		return false
	}
	layout := utils.compute_score_layout(s, &fonts.music)
	cmds: [dynamic]utils.Pdf_Cmd
	defer delete(cmds)

	export_layer := utils.Layer {
		space    = .World,
		visible  = true,
		pdf_cmds = &cmds,
	}
	win.draw_score(&export_layer, s, fonts)

	return utils.write_pdf_document(path, s.page, layout.page_count, cmds[:])
}

ensure_breaks_len :: proc(s: ^utils.Score, total: int) {
	for len(s.breaks) < total {
		append(&s.breaks, utils.Measure_Break.Auto)
	}
}

is_system_locked :: proc(s: ^utils.Score, sys: utils.System_Layout, total_measures: int) -> bool {
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

@(private = "file")
ensure_breaks_len :: proc(s: ^utils.Score, total: int) {
	for len(s.breaks) < total {
		append(&s.breaks, utils.Measure_Break.Auto)
	}
}

push_measure_next_line :: proc(s: ^utils.Score, layout: ^utils.Score_Layout, m_idx: int) -> bool {
	total := utils.measure_count(s)
	sys, ok := utils.find_system_for_measure(layout, m_idx)
	if !ok || m_idx <= sys.start_measure || m_idx >= total {
		return false
	}
	ensure_breaks_len(s, total)
	s.breaks[m_idx] = .Force_Next
	return true
}

pull_measure_prev_line :: proc(s: ^utils.Score, layout: ^utils.Score_Layout, m_idx: int) -> bool {
	total := utils.measure_count(s)
	sys, ok := utils.find_system_for_measure(layout, m_idx)
	if !ok || m_idx <= 0 || m_idx != sys.start_measure || m_idx >= total {
		return false
	}
	ensure_breaks_len(s, total)
	s.breaks[m_idx] = .Lock_Prev
	return true
}

lock_system :: proc(s: ^utils.Score, layout: ^utils.Score_Layout, m_idx: int) -> bool {
	total := utils.measure_count(s)
	sys, ok := utils.find_system_for_measure(layout, m_idx)
	if !ok || total <= 1 {
		return false
	}
	ensure_breaks_len(s, total)
	for m in sys.start_measure + 1 ..< sys.end_measure {
		s.breaks[m] = .Lock_Prev
	}
	if sys.start_measure > 0 {
		s.breaks[sys.start_measure] = .Force_Next
	}
	if sys.end_measure < total {
		s.breaks[sys.end_measure] = .Force_Next
	}
	return true
}

unlock_system :: proc(s: ^utils.Score, layout: ^utils.Score_Layout, m_idx: int) -> bool {
	sys, ok := utils.find_system_for_measure(layout, m_idx)
	if !ok {
		return false
	}
	changed := false
	end_clamped := min(sys.end_measure + 1, len(s.breaks))
	for m in sys.start_measure ..< end_clamped {
		if s.breaks[m] != .Auto {
			s.breaks[m] = .Auto
			changed = true
		}
	}
	return changed
}

toggle_system_lock :: proc(s: ^utils.Score, layout: ^utils.Score_Layout, m_idx: int) -> bool {
	total := utils.measure_count(s)
	sys, ok := utils.find_system_for_measure(layout, m_idx)
	if !ok {
		return false
	}
	if utils.is_system_locked(s, sys, total) {
		return unlock_system(s, layout, m_idx)
	}
	return lock_system(s, layout, m_idx)
}

add_measure_action :: proc(s: ^utils.Score, sel: ^utils.Selection) -> bool {
	target_idx := sel.active ? sel.measure_idx + 1 : utils.measure_count(s)
	if !insert_measure(s, target_idx) {
		return false
	}
	if sel.active {
		sel.measure_idx = target_idx
	}
	save_score(s)
	return true
}

remove_measure_action :: proc(s: ^utils.Score, sel: ^utils.Selection) -> bool {
	total := utils.measure_count(s)
	if total <= 1 {
		return false
	}
	target_idx := sel.active ? sel.measure_idx : total - 1
	if !remove_measure(s, target_idx) {
		return false
	}
	if sel.active {
		new_total := utils.measure_count(s)
		sel.measure_idx = clamp(sel.measure_idx, 0, max(0, new_total - 1))
	}
	save_score(s)
	return true
}

