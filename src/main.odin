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

LAYER_PAGE    :: 0
LAYER_SCORE   :: 1
LAYER_OVERLAY :: 2
LAYER_UI      :: 3

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
	scene := win.scene_init(&w, .World, .World, .World, .Screen)
	cam := win.Camera {
		pos  = {s.page.width_pt * 0.5, s.page.height_pt * 0.5},
		zoom = 0.95,
	}
	draw_scene(&scene, &s, cam)
	panning := false
	running := true
	main_loop(&cam, &scene, &s, &running, &panning)
}

main_loop :: proc(
	cam: ^win.Camera,
	scene: ^win.Scene,
	s: ^score.Score,
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
			draw_scene(scene, s, cam^)
		}
	}
}

draw_scene :: proc(scene: ^win.Scene, s: ^score.Score, cam: win.Camera) {
	win.scene_begin(scene, {0.22, 0.23, 0.25, 1.0})
	draw_page(win.scene_layer(scene, LAYER_PAGE), s.page)
	draw_score(win.scene_layer(scene, LAYER_SCORE), s)
	draw_overlay(win.scene_layer(scene, LAYER_OVERLAY), s)
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

draw_score :: proc(l: ^win.Layer, s: ^score.Score) {
	page := s.page
	staff_w := page.width_pt - page.margin_left - page.margin_right
	space := page.staff_space_pt
	line_thick: f32 = 0.8
	staff_h := 4.0 * space + line_thick
	measure_count := max(1, len(s.measures))
	measure_w := staff_w / f32(measure_count)
	ink := [4]f32{0.10, 0.10, 0.10, 1.0}
	staff_y := page.margin_top + 48.0
	for &part in s.parts {
		for &staff in part.staves {
			// 5 staff lines
			for i in 0 ..< 5 {
				y := staff_y + f32(i) * space
				win.draw_rect(l, page.margin_left, y, staff_w, line_thick, ink)
			}
			// Barlines
			for m in 0 ..= measure_count {
				x := page.margin_left + f32(m) * measure_w
				if m == measure_count {
					x -= 1.2
				}
				win.draw_rect(l, x, staff_y, 1.2, staff_h, ink)
			}
			// Placeholder noteheads driven by the Score data
			note_w := space * 1.25
			note_h := space * 0.9
			for m_idx in 0 ..< min(len(staff.measures), measure_count) {
				bar_x := page.margin_left + f32(m_idx) * measure_w
				sm := &staff.measures[m_idx]
				for &voice in sm.voices {
					if len(voice.entries) == 0 {
						continue
					}
					slot_w := measure_w / f32(len(voice.entries))
					for &entry, e_idx in voice.entries {
						cx := bar_x + (f32(e_idx) + 0.5) * slot_w
						for note in entry.notes {
							cy := pitch_to_staff_y(note.pitch, staff.clef, staff_y, space)
							win.draw_rect(
								l,
								cx - note_w * 0.5,
								cy - note_h * 0.5,
								note_w,
								note_h,
								ink,
							)
						}
					}
				}
			}
			staff_y += staff_h + space * 8.0
		}
	}
}

pitch_to_staff_y :: proc(p: score.Pitch, clef: score.Clef, staff_top_y, staff_space: f32) -> f32 {
	// Diatonic step of the top staff line: F5 (Treble), A3 (Bass), G4 (Alto), E4 (Tenor)
	top_line_diatonic: int
	switch clef {
	case .Treble: top_line_diatonic = 5 * 7 + int(score.Step.F)
	case .Bass:   top_line_diatonic = 3 * 7 + int(score.Step.A)
	case .Alto:   top_line_diatonic = 4 * 7 + int(score.Step.G)
	case .Tenor:  top_line_diatonic = 4 * 7 + int(score.Step.E)
	}
	note_diatonic := int(p.octave) * 7 + int(p.step)
	steps_below_top := top_line_diatonic - note_diatonic
	return staff_top_y + f32(steps_below_top) * (staff_space * 0.5)
}

draw_overlay :: proc(l: ^win.Layer, s: ^score.Score) {
	page := s.page
	staff_w := page.width_pt - page.margin_left - page.margin_right
	measure_w := staff_w / f32(max(1, len(s.measures)))
	staff_y := page.margin_top + 48.0
	staff_h := 4.0 * page.staff_space_pt + 0.8
	win.draw_rect(
		l,
		page.margin_left,
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

