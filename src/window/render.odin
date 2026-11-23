package window

import "core:fmt"
import "core:math/linalg"
import "core:mem"
import "core:os"
import gl "vendor:OpenGL"
import stbtt "vendor:stb/truetype"

@(private = "file")
VERT_SRC :: `#version 330 core
layout (location = 0) in vec2 a_pos;
layout (location = 1) in vec2 a_uv;
layout (location = 2) in vec4 a_color;
layout (location = 3) in float a_mode;

uniform mat4 u_proj;

out vec2 v_uv;
out vec4 v_color;
out float v_mode;

void main() {
	v_uv = a_uv;
	v_color = a_color;
	v_mode = a_mode;
	gl_Position = u_proj * vec4(a_pos, 0.0, 1.0);
}
`

@(private = "file")
FRAG_SRC :: `#version 330 core
in vec2 v_uv;
in vec4 v_color;
in float v_mode;

uniform sampler2D u_atlas;

out vec4 frag_color;

void main() {
	if (v_mode > 0.5) {
		float alpha = texture(u_atlas, v_uv).r;
		if (alpha <= 0.001) {
			discard;
		}
		frag_color = vec4(v_color.rgb, v_color.a * alpha);
	}
	else {
		frag_color = v_color;
	}
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
	r.atlas_loc = gl.GetUniformLocation(r.program, "u_atlas")

	gl.GenVertexArrays(1, &r.vao)
	gl.GenBuffers(1, &r.vbo)

	gl.BindVertexArray(r.vao)
	gl.BindBuffer(gl.ARRAY_BUFFER, r.vbo)

	gl.EnableVertexAttribArray(0)
	gl.VertexAttribPointer(0, 2, gl.FLOAT, gl.FALSE, size_of(Vertex), offset_of(Vertex, pos))

	gl.EnableVertexAttribArray(1)
	gl.VertexAttribPointer(1, 2, gl.FLOAT, gl.FALSE, size_of(Vertex), offset_of(Vertex, uv))

	gl.EnableVertexAttribArray(2)
	gl.VertexAttribPointer(2, 4, gl.FLOAT, gl.FALSE, size_of(Vertex), offset_of(Vertex, color))

	gl.EnableVertexAttribArray(3)
	gl.VertexAttribPointer(3, 1, gl.FLOAT, gl.FALSE, size_of(Vertex), offset_of(Vertex, mode))

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
		l.atlas_tex = 0
	}
}

atlas_create :: proc(path: string, codepoints: []rune) -> (atlas: Glyph_Atlas, ok: bool) {
	font_bytes, read_err := os.read_entire_file(path, context.allocator)
	if read_err != nil {
		fmt.eprintfln("Failed to read font file %s: %v", path, read_err)
		return {}, false
	}
	defer delete(font_bytes)

	font: stbtt.fontinfo
	if !stbtt.InitFont(&font, raw_data(font_bytes), 0) {
		fmt.eprintfln("Failed to initialize font: %s", path)
		return {}, false
	}

	pixels := make([]u8, ATLAS_SIZE * ATLAS_SIZE)
	defer delete(pixels)

	atlas.glyphs = make(map[rune]Glyph_Metrics)

	scale := stbtt.ScaleForMappingEmToPixels(&font, ATLAS_EM_PX)
	gap := 8
	pen_x := gap
	pen_y := gap
	row_h := 0

	for cp in codepoints {
		if cp in atlas.glyphs {
			continue
		}
		glyph_idx := stbtt.FindGlyphIndex(&font, cp)
		if glyph_idx == 0 {
			continue
		}

		bm_w, bm_h, xoff, yoff: i32
		bitmap := stbtt.GetGlyphBitmap(&font, scale, scale, glyph_idx, &bm_w, &bm_h, &xoff, &yoff)
		if bitmap == nil {
			continue
		}
		defer stbtt.FreeBitmap(bitmap, nil)

		w := int(bm_w)
		h := int(bm_h)
		if pen_x + w + gap > ATLAS_SIZE {
			pen_x = gap
			pen_y += row_h + gap
			row_h = 0
		}
		if pen_y + h + gap > ATLAS_SIZE {
			fmt.eprintfln("Glyph atlas full while packing U+%04X", cp)
			break
		}

		for row in 0 ..< h {
			dst_off := (pen_y + row) * ATLAS_SIZE + pen_x
			src_off := row * w
			mem.copy(&pixels[dst_off], mem.ptr_offset(bitmap, src_off), w)
		}

		adv_i, lsb_i: i32
		stbtt.GetGlyphHMetrics(&font, glyph_idx, &adv_i, &lsb_i)

		atlas.glyphs[cp] = Glyph_Metrics {
			u0      = f32(pen_x) / f32(ATLAS_SIZE),
			v0      = f32(pen_y) / f32(ATLAS_SIZE),
			u1      = f32(pen_x + w) / f32(ATLAS_SIZE),
			v1      = f32(pen_y + h) / f32(ATLAS_SIZE),
			x0      = f32(xoff) / ATLAS_EM_PX,
			y0      = f32(yoff) / ATLAS_EM_PX,
			x1      = f32(xoff + bm_w) / ATLAS_EM_PX,
			y1      = f32(yoff + bm_h) / ATLAS_EM_PX,
			advance = (f32(adv_i) * scale) / ATLAS_EM_PX,
		}

		pen_x += w + gap
		if h > row_h {
			row_h = h
		}
	}

	gl.GenTextures(1, &atlas.tex)
	gl.BindTexture(gl.TEXTURE_2D, atlas.tex)
	gl.PixelStorei(gl.UNPACK_ALIGNMENT, 1)
	gl.TexImage2D(
		gl.TEXTURE_2D,
		0,
		gl.R8,
		ATLAS_SIZE,
		ATLAS_SIZE,
		0,
		gl.RED,
		gl.UNSIGNED_BYTE,
		raw_data(pixels),
	)
	gl.GenerateMipmap(gl.TEXTURE_2D)
	gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR_MIPMAP_LINEAR)
	gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.LINEAR)
	gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE)
	gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE)
	gl.BindTexture(gl.TEXTURE_2D, 0)

	return atlas, true
}

atlas_destroy :: proc(atlas: ^Glyph_Atlas) {
	if atlas.tex != 0 {
		gl.DeleteTextures(1, &atlas.tex)
		atlas.tex = 0
	}
	delete(atlas.glyphs)
}

glyph_advance :: proc(atlas: ^Glyph_Atlas, cp: rune, em_size: f32) -> f32 {
	if g, ok := atlas.glyphs[cp]; ok {
		return g.advance * em_size
	}
	return 0
}

draw_glyph :: proc(
	l: ^Layer,
	atlas: ^Glyph_Atlas,
	cp: rune,
	origin_x, origin_y, em_size: f32,
	color: [4]f32,
) {
	g, ok := atlas.glyphs[cp]
	if !ok || atlas.tex == 0 {
		return
	}

	l.atlas_tex = atlas.tex

	x0 := origin_x + g.x0 * em_size
	y0 := origin_y + g.y0 * em_size
	x1 := origin_x + g.x1 * em_size
	y1 := origin_y + g.y1 * em_size

	append(
		&l.verts,
		Vertex{{x0, y0}, {g.u0, g.v0}, color, 1.0},
		Vertex{{x1, y0}, {g.u1, g.v0}, color, 1.0},
		Vertex{{x1, y1}, {g.u1, g.v1}, color, 1.0},
		Vertex{{x0, y0}, {g.u0, g.v0}, color, 1.0},
		Vertex{{x1, y1}, {g.u1, g.v1}, color, 1.0},
		Vertex{{x0, y1}, {g.u0, g.v1}, color, 1.0},
	)
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
		Vertex{{x0, y0}, {0, 0}, color, 0.0},
		Vertex{{x1, y0}, {0, 0}, color, 0.0},
		Vertex{{x1, y1}, {0, 0}, color, 0.0},
		Vertex{{x0, y0}, {0, 0}, color, 0.0},
		Vertex{{x1, y1}, {0, 0}, color, 0.0},
		Vertex{{x0, y1}, {0, 0}, color, 0.0},
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
	gl.Uniform1i(r.atlas_loc, 0)
	gl.BindVertexArray(r.vao)
	gl.BindBuffer(gl.ARRAY_BUFFER, r.vbo)
	for &l in r.layers[:r.layer_count] {
		if !l.visible || len(l.verts) == 0 {
			continue
		}
		if l.atlas_tex != 0 {
			gl.ActiveTexture(gl.TEXTURE0)
			gl.BindTexture(gl.TEXTURE_2D, l.atlas_tex)
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