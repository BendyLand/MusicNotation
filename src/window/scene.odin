package window

Scene :: struct {
	window: ^Window,
}

scene_init :: proc(w: ^Window, spaces: ..Layer_Space) -> Scene {
	s := Scene {
		window = w,
	}
	for space in spaces {
		scene_push(&s, space)
	}
	return s
}

scene_push :: proc(s: ^Scene, space: Layer_Space) -> int {
	r := &s.window.renderer
	assert(r.layer_count < MAX_LAYERS, "Layer stack overflow")
	idx := r.layer_count
	r.layer_count += 1
	// Mutate fields in place instead of overwriting the struct so any existing verts capacity is reused.
	r.layers[idx].space = space
	r.layers[idx].visible = true
	clear(&r.layers[idx].verts)
	return idx
}

scene_pop :: proc(s: ^Scene) {
	r := &s.window.renderer
	assert(r.layer_count > 0, "Layer stack underflow")
	r.layer_count -= 1
	clear(&r.layers[r.layer_count].verts)
}

scene_peek :: proc(s: ^Scene) -> ^Layer {
	r := &s.window.renderer
	assert(r.layer_count > 0, "Layer stack is empty")
	return &r.layers[r.layer_count - 1]
}

scene_layer :: proc(s: ^Scene, index: int) -> ^Layer {
	r := &s.window.renderer
	assert(index >= 0 && index < r.layer_count, "Layer index out of bounds")
	return &r.layers[index]
}

scene_layer_count :: proc(s: ^Scene) -> int {
	return s.window.renderer.layer_count
}

scene_begin :: proc(s: ^Scene, clear_color: [4]f32) {
	begin_frame(s.window, clear_color)
}

scene_end :: proc(s: ^Scene, cam: Camera) {
	end_frame(s.window, cam)
}

scene_set_visible :: proc(s: ^Scene, index: int, visible: bool) {
	scene_layer(s, index).visible = visible
}

scene_toggle_visible :: proc(s: ^Scene, index: int) -> bool {
	l := scene_layer(s, index)
	l.visible = !l.visible
	return l.visible
}

scene_clear_layer :: proc(s: ^Scene, index: int) {
	clear(&scene_layer(s, index).verts)
}

