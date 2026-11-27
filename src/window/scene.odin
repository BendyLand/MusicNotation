package window

import "../utils"

scene_init :: proc(w: ^utils.Window, spaces: ..utils.Layer_Space) -> utils.Scene {
	s := utils.Scene {
		window = w,
	}
	for space in spaces {
		scene_push(&s, space)
	}
	return s
}

scene_push :: proc(s: ^utils.Scene, space: utils.Layer_Space) -> int {
	r := &s.window.renderer
	assert(r.layer_count < utils.MAX_LAYERS, "Layer stack overflow")
	idx := r.layer_count
	r.layer_count += 1
	// Mutate fields in place instead of overwriting the struct so any existing verts capacity is reused.
	r.layers[idx].space = space
	r.layers[idx].visible = true
	r.layers[idx].pdf_cmds = nil
	clear(&r.layers[idx].verts)
	return idx
}

scene_pop :: proc(s: ^utils.Scene) {
	r := &s.window.renderer
	assert(r.layer_count > 0, "Layer stack underflow")
	r.layer_count -= 1
	clear(&r.layers[r.layer_count].verts)
}

scene_peek :: proc(s: ^utils.Scene) -> ^utils.Layer {
	r := &s.window.renderer
	assert(r.layer_count > 0, "Layer stack is empty")
	return &r.layers[r.layer_count - 1]
}

scene_layer :: proc(s: ^utils.Scene, index: int) -> ^utils.Layer {
	r := &s.window.renderer
	assert(index >= 0 && index < r.layer_count, "Layer index out of bounds")
	return &r.layers[index]
}

scene_layer_count :: proc(s: ^utils.Scene) -> int {
	return s.window.renderer.layer_count
}

scene_begin :: proc(s: ^utils.Scene, clear_color: [4]f32) {
	begin_frame(s.window, clear_color)
}

scene_end :: proc(s: ^utils.Scene, cam: utils.Camera) {
	end_frame(s.window, cam)
}

scene_set_visible :: proc(s: ^utils.Scene, index: int, visible: bool) {
	scene_layer(s, index).visible = visible
}

scene_toggle_visible :: proc(s: ^utils.Scene, index: int) -> bool {
	l := scene_layer(s, index)
	l.visible = !l.visible
	return l.visible
}

scene_clear_layer :: proc(s: ^utils.Scene, index: int) {
	clear(&scene_layer(s, index).verts)
}

scene_hit_test :: proc(s: ^utils.Scene, cam: utils.Camera, screen_pos: [2]f32) -> int {
	r := &s.window.renderer
	world_pos := utils.screen_to_world(cam, f32(s.window.win_w), f32(s.window.win_h), screen_pos)

	for i := r.layer_count - 1; i >= 0; i -= 1 {
		l := &r.layers[i]
		if !l.visible || len(l.verts) < 3 {
			continue
		}

		pt := l.space == .Screen ? screen_pos : world_pos
		for v := 0; v + 2 < len(l.verts); v += 3 {
			if utils.point_in_triangle(pt, l.verts[v].pos, l.verts[v + 1].pos, l.verts[v + 2].pos) {
				return i
			}
		}
	}

	return -1
}

