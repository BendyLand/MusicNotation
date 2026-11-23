package window

import "core:fmt"
import "core:math/linalg"
import gl "vendor:OpenGL"

Layer_Space :: enum {
	World,
	Screen,
}

Vertex :: struct {
	pos:   [2]f32,
	color: [4]f32,
}

Camera :: struct {
	pos:  [2]f32, // World coordinate at the center of the viewport (in points)
	zoom: f32, // Pixels per world unit
}

Layer :: struct {
	space:   Layer_Space,
	visible: bool,
	verts:   [dynamic]Vertex,
}

Renderer :: struct {
	program:  u32,
	vao:      u32,
	vbo:      u32,
	proj_loc: i32,
	layers:   [dynamic]Layer,
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
	for &l in r.layers {
		delete(l.verts)
	}
	delete(r.layers)
	gl.DeleteBuffers(1, &r.vbo)
	gl.DeleteVertexArrays(1, &r.vao)
	gl.DeleteProgram(r.program)
}

renderer_begin_frame :: proc(r: ^Renderer) {
	for &l in r.layers {
		clear(&l.verts)
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
	for &l in r.layers {
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
