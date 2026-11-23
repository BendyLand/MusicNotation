package window

import "core:fmt"
import "core:math/linalg"
import gl "vendor:OpenGL"

MAX_LAYERS :: 32

Layer :: struct {
	space:   Layer_Space,
	visible: bool,
	verts:   [dynamic]Vertex,
}

Renderer :: struct {
	program:     u32,
	vao:         u32,
	vbo:         u32,
	proj_loc:    i32,
	layers:      [MAX_LAYERS]Layer,
	layer_count: int,
}

@(private = "file")
VERT_SRC :: `#version 330 core
layout (location = 0) in vec2 a_pos;
layout (location = 1) in vec4 a_color;

uniform mat4 u_proj;

out vec4 v_color;

void main() {
	v_color = a_color;
	gl_Position = u_proj * vec4(a_pos, 0.0, 1.0);
}
`

@(private = "file")
FRAG_SRC :: `#version 330 core
in vec4 v_color;
out vec4 frag_color;

void main() {
	frag_color = v_color;
}
`

@(private = "file")
DIGIT_GLYPHS := [11][5]u8 {
	{0b111, 0b101, 0b101, 0b101, 0b111}, // 0
	{0b010, 0b110, 0b010, 0b010, 0b111}, // 1
	{0b111, 0b001, 0b111, 0b100, 0b111}, // 2
	{0b111, 0b001, 0b111, 0b001, 0b111}, // 3
	{0b101, 0b101, 0b111, 0b001, 0b001}, // 4
	{0b111, 0b100, 0b111, 0b001, 0b111}, // 5
	{0b111, 0b100, 0b111, 0b101, 0b111}, // 6
	{0b111, 0b001, 0b001, 0b010, 0b010}, // 7
	{0b111, 0b101, 0b111, 0b101, 0b111}, // 8
	{0b111, 0b101, 0b111, 0b001, 0b111}, // 9
	{0b000, 0b000, 0b111, 0b000, 0b000}, // -
}

renderer_init :: proc() -> (r: Renderer, ok: bool) {
	program, shader_ok := gl.load_shaders_source(VERT_SRC, FRAG_SRC)
	if !shader_ok {
		fmt.eprintln("Failed to compile 2D shader program")
		return {}, false
	}
	r.program = program
	r.proj_loc = gl.GetUniformLocation(r.program, "u_proj")
	gl.GenVertexArrays(1, &r.vao)
	gl.GenBuffers(1, &r.vbo)
	gl.BindVertexArray(r.vao)
	gl.BindBuffer(gl.ARRAY_BUFFER, r.vbo)
	gl.EnableVertexAttribArray(0)
	gl.VertexAttribPointer(0, 2, gl.FLOAT, gl.FALSE, size_of(Vertex), offset_of(Vertex, pos))
	gl.EnableVertexAttribArray(1)
	gl.VertexAttribPointer(1, 4, gl.FLOAT, gl.FALSE, size_of(Vertex), offset_of(Vertex, color))
	gl.BindVertexArray(0)
	// 2D painter's algorithm: disable depth testing, enable standard alpha blending.
	gl.Disable(gl.DEPTH_TEST)
	gl.Enable(gl.BLEND)
	gl.BlendFunc(gl.SRC_ALPHA, gl.ONE_MINUS_SRC_ALPHA)
	return r, true
}

renderer_destroy :: proc(r: ^Renderer) {
	// Free every slot that was ever used, even if currently popped.
	for &l in r.layers {
		delete(l.verts)
	}
	gl.DeleteBuffers(1, &r.vbo)
	gl.DeleteVertexArrays(1, &r.vao)
	gl.DeleteProgram(r.program)
}

renderer_begin_frame :: proc(r: ^Renderer) {
	for &l in r.layers[:r.layer_count] {
		clear(&l.verts)
	}
}

screen_to_world :: proc(cam: Camera, win_w, win_h: f32, screen_pos: [2]f32) -> [2]f32 {
	return {
		cam.pos.x + (screen_pos.x - win_w * 0.5) / cam.zoom,
		cam.pos.y + (screen_pos.y - win_h * 0.5) / cam.zoom,
	}
}

draw_rect :: proc(l: ^Layer, x, y, w, h: f32, color: [4]f32) {
	x0 := x
	y0 := y
	x1 := x + w
	y1 := y + h
	append(
		&l.verts,
		Vertex{{x0, y0}, color},
		Vertex{{x1, y0}, color},
		Vertex{{x1, y1}, color},
		Vertex{{x0, y0}, color},
		Vertex{{x1, y1}, color},
		Vertex{{x0, y1}, color},
	)
}

measure_int :: proc(value: int, pixel_size: f32) -> (w, h: f32) {
	buf: [16]int
	count := format_int_glyphs(value, &buf)
	return f32(count * 4 - 1) * pixel_size, 5.0 * pixel_size
}

draw_int :: proc(l: ^Layer, value: int, x, y, pixel_size: f32, color: [4]f32) {
	buf: [16]int
	count := format_int_glyphs(value, &buf)
	cursor_x := x
	for i in 0 ..< count {
		glyph := DIGIT_GLYPHS[buf[i]]
		for row in 0 ..< 5 {
			bits := glyph[row]
			for col in 0 ..< 3 {
				if (bits & (1 << u8(2 - col))) != 0 {
					draw_rect(
						l,
						cursor_x + f32(col) * pixel_size,
						y + f32(row) * pixel_size,
						pixel_size,
						pixel_size,
						color,
					)
				}
			}
		}
		cursor_x += 4.0 * pixel_size
	}
}

@(private = "file")
format_int_glyphs :: proc(value: int, buf: ^[16]int) -> int {
	n := 0
	v := value
	if v == 0 {
		buf[0] = 0
		return 1
	}
	if v < 0 {
		buf[0] = 10 // '-'
		n = 1
		v = -v
	}
	start := n
	for v > 0 && n < len(buf) {
		buf[n] = v % 10
		v /= 10
		n += 1
	}
	// Reverse digits in place
	for lo, hi := start, n - 1; lo < hi; lo, hi = lo + 1, hi - 1 {
		buf[lo], buf[hi] = buf[hi], buf[lo]
	}
	return n
}

renderer_flush :: proc(r: ^Renderer, cam: Camera, win_w, win_h: f32) {
	if win_w <= 0 || win_h <= 0 {
		return
	}
	screen_proj := linalg.matrix_ortho3d_f32(0, win_w, win_h, 0, -1, 1)
	half_w := (win_w * 0.5) / cam.zoom
	half_h := (win_h * 0.5) / cam.zoom
	world_proj := linalg.matrix_ortho3d_f32(
		cam.pos.x - half_w,
		cam.pos.x + half_w,
		cam.pos.y + half_h,
		cam.pos.y - half_h,
		-1,
		1,
	)
	gl.UseProgram(r.program)
	gl.BindVertexArray(r.vao)
	gl.BindBuffer(gl.ARRAY_BUFFER, r.vbo)
	for &l in r.layers[:r.layer_count] {
		if !l.visible || len(l.verts) == 0 {
			continue
		}
		proj := l.space == .Screen ? screen_proj : world_proj
		gl.UniformMatrix4fv(r.proj_loc, 1, gl.FALSE, &proj[0, 0])
		gl.BufferData(
			gl.ARRAY_BUFFER,
			len(l.verts) * size_of(Vertex),
			raw_data(l.verts),
			gl.STREAM_DRAW,
		)
		gl.DrawArrays(gl.TRIANGLES, 0, i32(len(l.verts)))
	}
	gl.BindVertexArray(0)
	gl.UseProgram(0)
}
