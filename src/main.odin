package main

import "core:fmt"
import "score"
import win "window"

MIN_WIDTH     :: 320
MIN_HEIGHT    :: 240
TARGET_WIDTH  :: 800
TARGET_HEIGHT :: 900

main :: proc() {
	// setup
	context.allocator = track_leaks_init()
	defer track_leaks_finish()
	s, loaded := score.load(score.SCORE_PATH)
	if !loaded {
		s = score.make_demo()
		if !score.save(&s, score.SCORE_PATH) {
			fmt.eprintfln("Failed to write %s", score.SCORE_PATH)
		}
	}
	defer score.destroy(&s)
	w, ok := win.create("Notation", TARGET_WIDTH, TARGET_HEIGHT, MIN_WIDTH, MIN_HEIGHT)
	if !ok do return 
	defer win.destroy(&w)
	atlas, font_ok := win.atlas_create(score.FONT_PATH, score.SMUFL_GLYPHS[:])
	if !font_ok do return 
	defer win.atlas_destroy(&atlas)
	// start
	scene := win.scene_init(&w, .World, .World, .World, .Screen)
	cam := win.Camera {
		pos  = {s.page.width_pt * 0.5, s.page.height_pt * 0.5},
		zoom = 0.95,
	}
	win.draw_scene(&scene, &s, &atlas, cam)
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
				}
				else if win.ctrl_held() {
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
			win.draw_scene(scene, s, atlas, cam^)
		}
	}
}

