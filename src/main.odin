package main

import "utils"
import "score"
import win "window"

main :: proc() {
	context.allocator = track_leaks_init()
	defer track_leaks_finish()
	s, loaded := utils.load(utils.SCORE_PATH)
	if !loaded {
		s = score.make_demo()
		utils.save_score(&s)
	}
	defer utils.destroy(&s)
	w, ok := win.create("Notation", utils.TARGET_WIDTH, utils.TARGET_HEIGHT, utils.MIN_WIDTH, utils.MIN_HEIGHT)
	if !ok {
		return
	}
	defer win.destroy(&w)
	atlas, font_ok := win.atlas_create(utils.FONT_PATH, utils.SMUFL_GLYPHS[:])
	if !font_ok {
		return
	}
	defer win.atlas_destroy(&atlas)
	scene := win.scene_init(&w, .World, .World, .World, .Screen)
	cam := utils.Camera {
		pos  = {s.page.width_pt * 0.5, s.page.height_pt * 0.5},
		zoom = 0.95,
	}
	sel := utils.Selection{}
	tool := utils.Editor_Tool {
		mode       = .Select,
		duration   = .Quarter,
		is_rest    = false,
		accidental = .None,
	}
	drag := utils.Drag_State{}
	running := true
	win.draw_scene(&scene, &s, &atlas, cam, sel, tool, drag.panning)
	main_loop(&cam, &scene, &s, &atlas, &sel, &tool, &drag, &running)
}

main_loop :: proc(
	cam: ^utils.Camera,
	scene: ^utils.Scene,
	s: ^utils.Score,
	atlas: ^utils.Glyph_Atlas,
	sel: ^utils.Selection,
	tool: ^utils.Editor_Tool,
	drag: ^utils.Drag_State,
	running: ^bool,
) {
	for running^ {
		events, wait_ok := win.wait_events(scene.window)
		if !wait_ok {
			break
		}
		needs_redraw := false
		for event in events {
			#partial switch e in event {
			case utils.Event_Quit:
				running^ = false
			case utils.Event_Redraw:
				needs_redraw = true
			case utils.Event_Key_Down:
				if e.ctrl {
					if e.key == .S {
						utils.save_score(s)
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
				case .Backspace, .Delete:
					if tool.mode == .Select && sel.active {
						sm := &s.parts[sel.part_idx].staves[sel.staff_idx].measures[sel.measure_idx]
						utils.clear_measure(sm)
						utils.save_score(s)
						needs_redraw = true
					}
					else if tool.mode == .Note_Entry {
						mouse := win.mouse_pos()
						win_w := f32(scene.window.win_w)
						win_h := f32(scene.window.win_h)
						if mouse.y > utils.TOOLBAR_H && mouse.y < win_h - utils.STATUS_H {
							world := win.screen_to_world(cam^, win_w, win_h, mouse)
							if win.pop_entry_at_world(s, atlas, world) {
								utils.save_score(s)
								needs_redraw = true
							}
						}
					}
				case .Num_0:
					cam.pos = {s.page.width_pt * 0.5, s.page.height_pt * 0.5}
					cam.zoom = 0.95
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
					win_w := f32(scene.window.win_w)
					win_h := f32(scene.window.win_h)
					mx := f32(e.x)
					my := f32(e.y)
					if my <= utils.TOOLBAR_H {
						if win.toolbar_click(tool, mx, my) {
							if tool.mode == .Note_Entry {
								sel^ = {}
							}
							needs_redraw = true
						}
					}
					else if my < win_h - utils.STATUS_H {
						world := win.screen_to_world(cam^, win_w, win_h, {mx, my})
						if tool.mode == .Select {
							drag.left_down = true
							drag.press_pos = {e.x, e.y}
							drag.cur_pos = {e.x, e.y}
							next_sel := win.hit_test_measure(s, atlas, world)
							if next_sel != sel^ {
								sel^ = next_sel
								needs_redraw = true
							}
						}
						else if tool.mode == .Note_Entry {
							if win.apply_note_click(s, atlas, tool^, world) {
								utils.save_score(s)
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
					drag.left_down = false
				}
			case utils.Event_Mouse_Move:
				if drag.panning {
					cam.pos.x -= f32(e.dx) / cam.zoom
					cam.pos.y -= f32(e.dy) / cam.zoom
					needs_redraw = true
				}
				else {
					if drag.left_down {
						drag.cur_pos = {e.x, e.y}
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

		mouse := win.mouse_pos()
		win_h := f32(scene.window.win_h)
		in_canvas := mouse.y > utils.TOOLBAR_H && mouse.y < win_h - utils.STATUS_H
		hide_os_cursor :=
			tool.mode == .Note_Entry && in_canvas && !drag.panning && !win.ctrl_held()
		win.set_cursor_visible(!hide_os_cursor)

		if running^ && needs_redraw {
			win.draw_scene(scene, s, atlas, cam^, sel^, tool^, drag.panning)
		}
	}
}
