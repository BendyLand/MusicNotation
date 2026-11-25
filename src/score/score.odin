package score

import "../toml"
import "../utils"
import win "../window"
import "core:fmt"
import "core:os"
import "core:strings"

make_demo :: proc() -> utils.Score {
	s := utils.Score {
		version  = utils.FORMAT_VERSION,
		title    = strings.clone("Demo Score"),
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

save_score :: proc(s: ^utils.Score) {
	if !save(s, utils.SCORE_PATH) {
		fmt.eprintfln("Failed to write %s", utils.SCORE_PATH)
	}
}

destroy :: proc(s: ^utils.Score) {
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

export_pdf :: proc(s: ^utils.Score, atlas: ^utils.Glyph_Atlas, path: string) -> bool {
	if len(atlas.font_bytes) == 0 {
		return false
	}
	cmds: [dynamic]utils.Pdf_Cmd
	defer delete(cmds)

	export_layer := utils.Layer {
		space    = .World,
		visible  = true,
		pdf_cmds = &cmds,
	}
	win.draw_score(&export_layer, s, atlas)

	return utils.write_pdf_document(path, s.page, atlas.font_bytes, cmds[:])
}

export_score_pdf :: proc(s: ^utils.Score, atlas: ^utils.Glyph_Atlas) {
	if export_pdf(s, atlas, utils.PDF_PATH) {
		fmt.printfln("Exported %s", utils.PDF_PATH)
	}
	else {
		fmt.eprintfln("Failed to export %s", utils.PDF_PATH)
	}
}
