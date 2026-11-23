package main

import "core:fmt"
import "core:mem"
import win "window"

TARGET_WIDTH :: 800
TARGET_HEIGHT :: 900
MIN_WIDTH :: 320
MIN_HEIGHT :: 240

// US Letter in PostScript points (8.5 x 11 inches at 72 pt/in).
PAGE_WIDTH :: 612.0
PAGE_HEIGHT :: 792.0

MARGIN_X :: 54.0
STAFF_Y :: 120.0
STAFF_SPACE :: 6.0
LINE_THICK :: 0.8
STAFF_H :: 4.0 * STAFF_SPACE + LINE_THICK

LAYER_PAGE :: 0
LAYER_SCORE :: 1
LAYER_OVERLAY :: 2
LAYER_UI :: 3

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
	w, ok := win.create("Notation", TARGET_WIDTH, TARGET_HEIGHT, MIN_WIDTH, MIN_HEIGHT)
	if !ok {
		return
	}
	defer win.destroy(&w)
	scene := win.scene_init(&w, .World, .World, .World, .Screen)
	cam := win.Camera {
		pos  = {PAGE_WIDTH * 0.5, PAGE_HEIGHT * 0.5},
		zoom = 0.95,
	}
	draw_scene(&scene, cam)
	panning := false
	running := true
	main_loop(&cam, &scene, &running, &panning)
}

main_loop :: proc(cam: ^win.Camera, scene: ^win.Scene, running, panning: ^bool) {
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
					cam.pos = {PAGE_WIDTH * 0.5, PAGE_HEIGHT * 0.5}
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
			case win.Event_Mouse_Wheel:
				if e.dy != 0 {
					factor: f32 = e.dy > 0 ? 1.1 : (1.0 / 1.1)
					cam.zoom = clamp(cam.zoom * factor, 0.25, 8.0)
					needs_redraw = true
				}
			}
		}
		if running^ && needs_redraw {
			draw_scene(scene, cam^)
		}
	}
}

draw_scene :: proc(s: ^win.Scene, cam: win.Camera) {
	win.scene_begin(s, {0.22, 0.23, 0.25, 1.0})
	draw_page(win.scene_layer(s, LAYER_PAGE))
	draw_score(win.scene_layer(s, LAYER_SCORE))
	draw_overlay(win.scene_layer(s, LAYER_OVERLAY))
	draw_ui(win.scene_layer(s, LAYER_UI), f32(s.window.win_w), f32(s.window.win_h))
	win.scene_end(s, cam)
}

draw_page :: proc(l: ^win.Layer) {
	win.draw_rect(l, 6, 8, PAGE_WIDTH, PAGE_HEIGHT, {0.0, 0.0, 0.0, 0.28})
	win.draw_rect(l, 0, 0, PAGE_WIDTH, PAGE_HEIGHT, {0.98, 0.97, 0.94, 1.0})
}

draw_score :: proc(l: ^win.Layer) {
	staff_w: f32 = PAGE_WIDTH - MARGIN_X * 2.0
	for i in 0 ..< 5 {
		y := STAFF_Y + f32(i) * STAFF_SPACE
		win.draw_rect(l, MARGIN_X, y, staff_w, LINE_THICK, {0.10, 0.10, 0.10, 1.0})
	}
	win.draw_rect(l, MARGIN_X, STAFF_Y, 1.2, STAFF_H, {0.10, 0.10, 0.10, 1.0})
	win.draw_rect(l, MARGIN_X + staff_w - 1.2, STAFF_Y, 1.2, STAFF_H, {0.10, 0.10, 0.10, 1.0})
}

draw_overlay :: proc(l: ^win.Layer) {
	win.draw_rect(l, MARGIN_X, STAFF_Y - 4.0, 140.0, STAFF_H + 8.0, {0.20, 0.50, 0.95, 0.22})
}

draw_ui :: proc(l: ^win.Layer, win_w, win_h: f32) {
	toolbar_h: f32 = 36.0
	status_h: f32 = 24.0
	win.draw_rect(l, 0, 0, win_w, toolbar_h, {0.14, 0.15, 0.17, 0.96})
	win.draw_rect(l, 0, toolbar_h, win_w, 1.0, {0.08, 0.08, 0.10, 1.0})
	win.draw_rect(l, 0, win_h - status_h, win_w, status_h, {0.14, 0.15, 0.17, 0.96})
}

