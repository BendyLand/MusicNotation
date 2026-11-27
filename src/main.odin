package main

import "core:os"
import "score"
import "utils"
import win "window"

main :: proc() {
	context.allocator = track_leaks_init()
	defer track_leaks_finish()
	wiz: utils.Wizard_State
	defer utils.wizard_destroy(&wiz)
	s: utils.Score
	loaded := false
	if len(os.args) > 1 {
		s, loaded = score.load(os.args[1])
	}
	if !loaded {
		s = score.make_demo()
		utils.wizard_init(&wiz, false)
	}
	defer score.destroy(&s)
	w, ok := win.create(
		"Notation",
		utils.TARGET_WIDTH,
		utils.TARGET_HEIGHT,
		utils.MIN_WIDTH,
		utils.MIN_HEIGHT,
	)
	if !ok {
		return
	}
	defer win.destroy(&w)
	fonts, font_ok := win.fonts_create()
	if !font_ok {
		return
	}
	defer win.fonts_destroy(&fonts)
	scene := win.scene_init(&w, .World, .World, .World, .Screen)
	cam := utils.fit_camera_to_page(s.page, f32(w.win_w), f32(w.win_h))
	sel := utils.Selection{}
	tool := utils.Editor_Tool {
		mode       = .Select,
		duration   = .Quarter,
		is_rest    = false,
		accidental = .None,
	}
	drag := utils.Drag_State{}
	running := true
	win.set_text_input(&w, wiz.active && wiz.focus != .None)
	win.draw_scene(&scene, &s, &fonts, cam, sel, tool, &wiz, drag)
	main_loop(&cam, &scene, &s, &fonts, &sel, &tool, &drag, &wiz, &running)
}

add_measure_action :: proc(s: ^utils.Score, sel: ^utils.Selection) -> bool {
	target_idx := sel.active ? sel.end_measure + 1 : utils.measure_count(s)
	if !score.insert_measure(s, target_idx) {
		return false
	}
	if sel.active {
		sel.start_measure = target_idx
		sel.end_measure = target_idx
	}
	score.save_score(s)
	return true
}

remove_measure_action :: proc(s: ^utils.Score, sel: ^utils.Selection) -> bool {
	total := utils.measure_count(s)
	if total <= 1 {
		return false
	}
	if !sel.active {
		if !score.remove_measure(s, total - 1) {
			return false
		}
		score.save_score(s)
		return true
	}

	m_lo := clamp(sel.start_measure, 0, total - 1)
	m_hi := clamp(sel.end_measure, m_lo, total - 1)
	removed_any := false
	for m := m_hi; m >= m_lo; m -= 1 {
		if utils.measure_count(s) <= 1 {
			break
		}
		if score.remove_measure(s, m) {
			removed_any = true
		}
	}
	if !removed_any {
		return false
	}
	new_total := utils.measure_count(s)
	clamped := clamp(m_lo, 0, max(0, new_total - 1))
	sel.start_measure = clamped
	sel.end_measure = clamped
	score.save_score(s)
	return true
}

main_loop :: proc(
	cam: ^utils.Camera,
	scene: ^utils.Scene,
	s: ^utils.Score,
	fonts: ^utils.Fonts,
	sel: ^utils.Selection,
	tool: ^utils.Editor_Tool,
	drag: ^utils.Drag_State,
	wiz: ^utils.Wizard_State,
	running: ^bool,
) {
	for running^ {
		events, wait_ok := win.wait_events(scene.window)
		if !wait_ok {
			break
		}
		needs_redraw := false
		win_w := f32(scene.window.win_w)
		win_h := f32(scene.window.win_h)
		for event in events {
			if wiz.active {
				if handle_wizard_event(event, wiz, s, fonts, cam, sel, win_w, win_h, running) {
					needs_redraw = true
				}
				continue
			}
			switch e in event {
			case utils.Event_Quit:
				running^ = false
			case utils.Event_Redraw:
				needs_redraw = true
			case utils.Event_Text_Input:
			case utils.Event_Key_Down:
				if e.ctrl {
					#partial switch e.key {
					case .A:
						tool.mode = .Select
						sel^ = utils.select_all_measures(s)
						needs_redraw = true
					case .N:
						drag^ = {}
						utils.wizard_init(wiz, true)
						needs_redraw = true
					case .S:
						score.save_score(s)
					case .E, .P:
						score.export_score_pdf(s, fonts)
					case .Equals:
						if add_measure_action(s, sel) {
							needs_redraw = true
						}
					case .Minus, .Backspace, .Delete:
						if remove_measure_action(s, sel) {
							needs_redraw = true
						}
					}
					continue
				}
				#partial switch e.key {
				case .Escape:
					if tool.mode == .Note_Entry {
						tool.mode = .Select
						needs_redraw = true
					}
					else if sel.active {
						sel^ = {}
						needs_redraw = true
					}
					else {
						running^ = false
					}
				case .Tab:
					if tool.mode == .Select {
						tool.mode = .Note_Entry
						sel^ = {}
					}
					else {
						tool.mode = .Select
					}
					needs_redraw = true
				case .Down:
					if tool.mode == .Select && sel.active {
						layout := utils.compute_score_layout(s, &fonts.music)
						if score.push_measure_next_line(s, &layout, sel.start_measure) {
							score.save_score(s)
							needs_redraw = true
						}
					}
				case .Up:
					if tool.mode == .Select && sel.active {
						layout := utils.compute_score_layout(s, &fonts.music)
						if score.pull_measure_prev_line(s, &layout, sel.start_measure) {
							score.save_score(s)
							needs_redraw = true
						}
					}
				case .L:
					if tool.mode == .Select && sel.active {
						layout := utils.compute_score_layout(s, &fonts.music)
						if score.lock_system(s, &layout, sel.start_measure) {
							score.save_score(s)
							needs_redraw = true
						}
					}
				case .U:
					if tool.mode == .Select && sel.active {
						layout := utils.compute_score_layout(s, &fonts.music)
						if score.unlock_system(s, &layout, sel.start_measure) {
							score.save_score(s)
							needs_redraw = true
						}
					}
				case .Backspace, .Delete:
					if tool.mode == .Select && sel.active {
						if score.clear_selection(s, sel^) {
							score.save_score(s)
							needs_redraw = true
						}
					}
					else if tool.mode == .Note_Entry {
						mouse := win.mouse_pos()
						if mouse.y > utils.TOOLBAR_H && mouse.y < win_h - utils.STATUS_H {
							world := utils.screen_to_world(cam^, win_w, win_h, mouse)
							if score.pop_entry_at_world(s, &fonts.music, world) {
								score.save_score(s)
								needs_redraw = true
							}
						}
					}
				case .Num_0:
					cam^ = utils.fit_camera_to_page(s.page, win_w, win_h)
					needs_redraw = true
				case .Num_1:
					tool.mode = .Note_Entry
					tool.duration = .Whole
					sel^ = {}
					needs_redraw = true
				case .Num_2:
					tool.mode = .Note_Entry
					tool.duration = .Half
					sel^ = {}
					needs_redraw = true
				case .Num_3:
					tool.mode = .Note_Entry
					tool.duration = .Quarter
					sel^ = {}
					needs_redraw = true
				case .Num_4:
					tool.mode = .Note_Entry
					tool.duration = .Eighth
					sel^ = {}
					needs_redraw = true
				case .Num_5:
					tool.mode = .Note_Entry
					tool.duration = .Sixteenth
					sel^ = {}
					needs_redraw = true
				case .Num_6:
					tool.mode = .Note_Entry
					tool.duration = .Thirty_Second
					sel^ = {}
					needs_redraw = true
				case .R:
					if tool.mode == .Select {
						tool.mode = .Note_Entry
						tool.is_rest = true
						sel^ = {}
					}
					else {
						tool.is_rest = !tool.is_rest
					}
					needs_redraw = true
				case .Minus:
					utils.toggle_accidental(tool, .Flat)
					sel^ = {}
					needs_redraw = true
				case .N:
					utils.toggle_accidental(tool, .Natural)
					sel^ = {}
					needs_redraw = true
				case .Equals:
					utils.toggle_accidental(tool, .Sharp)
					sel^ = {}
					needs_redraw = true
				}
			case utils.Event_Mouse_Down:
				if e.button == .Right {
					drag.panning = true
					needs_redraw = true
				}
				else if e.button == .Left {
					mx := f32(e.x)
					my := f32(e.y)
					if my <= utils.TOOLBAR_H {
						switch win.toolbar_click(tool, mx, my) {
						case .None:
						case .New_Score:
							drag^ = {}
							utils.wizard_init(wiz, true)
							needs_redraw = true
						case .Tool_Changed:
							if tool.mode == .Note_Entry {
								sel^ = {}
							}
							needs_redraw = true
						case .Add_Measure:
							if add_measure_action(s, sel) {
								needs_redraw = true
							}
						case .Remove_Measure:
							if remove_measure_action(s, sel) {
								needs_redraw = true
							}
						case .Push_Measure_Down:
							if sel.active {
								layout := utils.compute_score_layout(s, &fonts.music)
								if score.push_measure_next_line(s, &layout, sel.start_measure) {
									score.save_score(s)
									needs_redraw = true
								}
							}
						case .Pull_Measure_Up:
							if sel.active {
								layout := utils.compute_score_layout(s, &fonts.music)
								if score.pull_measure_prev_line(s, &layout, sel.start_measure) {
									score.save_score(s)
									needs_redraw = true
								}
							}
						case .Toggle_System_Lock:
							if sel.active {
								layout := utils.compute_score_layout(s, &fonts.music)
								if score.toggle_system_lock(s, &layout, sel.start_measure) {
									score.save_score(s)
									needs_redraw = true
								}
							}
						case .Export_Pdf:
							score.export_score_pdf(s, fonts)
						}
					}
					else if my < win_h - utils.STATUS_H {
						world := utils.screen_to_world(cam^, win_w, win_h, {mx, my})
						if tool.mode == .Select {
							drag.left_down = true
							drag.marquee = false
							drag.press_pos = {e.x, e.y}
							drag.cur_pos = {e.x, e.y}
							next_sel := utils.hit_test_measure(s, &fonts.music, world)
							if next_sel != sel^ {
								sel^ = next_sel
								needs_redraw = true
							}
						}
						else if tool.mode == .Note_Entry {
							if score.apply_note_click(s, &fonts.music, tool^, world) {
								score.save_score(s)
								needs_redraw = true
							}
						}
					}
				}
			case utils.Event_Mouse_Up:
				if e.button == .Right {
					drag.panning = false
					needs_redraw = true
				}
				else if e.button == .Left {
					if drag.marquee {
						needs_redraw = true
					}
					drag.left_down = false
					drag.marquee = false
				}
			case utils.Event_Mouse_Move:
				if drag.panning {
					cam.pos.x -= f32(e.dx) / cam.zoom
					cam.pos.y -= f32(e.dy) / cam.zoom
					needs_redraw = true
				}
				else {
					if drag.left_down && tool.mode == .Select {
						drag.cur_pos = {e.x, e.y}
						dx := abs(drag.cur_pos.x - drag.press_pos.x)
						dy := abs(drag.cur_pos.y - drag.press_pos.y)
						if !drag.marquee && (dx > 4 || dy > 4) {
							drag.marquee = true
						}
						if drag.marquee {
							p0 := utils.screen_to_world(
								cam^,
								win_w,
								win_h,
								{f32(drag.press_pos.x), f32(drag.press_pos.y)},
							)
							p1 := utils.screen_to_world(
								cam^,
								win_w,
								win_h,
								{f32(drag.cur_pos.x), f32(drag.cur_pos.y)},
							)
							world_r := utils.Rect {
								x = min(p0.x, p1.x),
								y = min(p0.y, p1.y),
								w = abs(p1.x - p0.x),
								h = abs(p1.y - p0.y),
							}
							sel^ = utils.select_measures_in_rect(s, &fonts.music, world_r)
							needs_redraw = true
						}
					}
					if tool.mode == .Note_Entry || win.ctrl_held() {
						needs_redraw = true
					}
				}
			case utils.Event_Mouse_Wheel:
				if e.dy != 0 {
					factor: f32 = e.dy > 0 ? 1.1 : (1.0 / 1.1)
					cam.zoom = clamp(cam.zoom * factor, 0.25, 8.0)
					needs_redraw = true
				}
			}
		}
		win.set_text_input(scene.window, wiz.active && wiz.focus != .None)
		mouse := win.mouse_pos()
		in_canvas := mouse.y > utils.TOOLBAR_H && mouse.y < win_h - utils.STATUS_H
		hide_os_cursor :=
			!wiz.active &&
			tool.mode == .Note_Entry &&
			in_canvas &&
			!drag.panning &&
			!win.ctrl_held()
		win.set_cursor_visible(!hide_os_cursor)
		if running^ && needs_redraw {
			win.draw_scene(scene, s, fonts, cam^, sel^, tool^, wiz, drag^)
		}
	}
}
