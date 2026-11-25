package window

import "../score"
import win "../window"
import "core:fmt"
import "core:math/linalg"
import "core:mem"
import "core:os"
import gl "vendor:OpenGL"
import stbtt "vendor:stb/truetype"

Bar_Accidental_State :: struct {
	active: [11][score.Step]i8,
}

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

draw_scene :: proc(scene: ^win.Scene, s: ^score.Score, atlas: ^win.Glyph_Atlas, cam: win.Camera) {
	win.scene_begin(scene, {0.22, 0.23, 0.25, 1.0})
	draw_page(win.scene_layer(scene, score.LAYER_PAGE), s.page)
	draw_score(win.scene_layer(scene, score.LAYER_SCORE), s, atlas)
	draw_overlay(win.scene_layer(scene, score.LAYER_OVERLAY), s, atlas)
	draw_ui(
		win.scene_layer(scene, score.LAYER_UI),
		f32(scene.window.win_w),
		f32(scene.window.win_h),
	)
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

draw_ui :: proc(l: ^win.Layer, win_w, win_h: f32) {
	toolbar_h: f32 = 36.0
	status_h: f32 = 24.0
	win.draw_rect(l, 0, 0, win_w, toolbar_h, {0.14, 0.15, 0.17, 0.96})
	win.draw_rect(l, 0, toolbar_h, win_w, 1.0, {0.08, 0.08, 0.10, 1.0})
	win.draw_rect(l, 0, win_h - status_h, win_w, status_h, {0.14, 0.15, 0.17, 0.96})
}

staff_header_width :: proc(s: ^score.Score, atlas: ^win.Glyph_Atlas) -> f32 {
	space := s.page.staff_space_pt
	em_size := space * 4.0
	fallback_w := space * 0.8 + win.glyph_advance(atlas, score.SMUFL_G_CLEF, em_size) + space * 0.9
	max_w: f32 = 0.0
	for &part in s.parts {
		for &staff in part.staves {
			w :=
				space * 0.8 +
				win.glyph_advance(atlas, clef_glyph(staff.clef), em_size) +
				space * 0.9
			if len(staff.measures) > 0 {
				meta := staff.measures[0].meta
				fifths := abs(int(meta.key_sig))
				if fifths > 0 {
					w += f32(fifths) * space * 1.05 + space * 0.6
				}
				ts := meta.time_sig
				ts_w := max(
					measure_time_num(atlas, ts.num, em_size),
					measure_time_num(atlas, ts.den, em_size),
				)
				w += ts_w + space * 1.4
			}
			max_w = max(max_w, w)
		}
	}
	return max_w > 0.0 ? max_w : fallback_w
}

draw_score :: proc(l: ^win.Layer, s: ^score.Score, atlas: ^win.Glyph_Atlas) {
	page := s.page
	staff_w := page.width_pt - page.margin_left - page.margin_right
	space := page.staff_space_pt
	em_size := space * 4.0
	line_thick: f32 = max(0.6, space * 0.12)
	staff_h := 4.0 * space + line_thick
	total_measures := max(1, score.measure_count(s))
	header_w := staff_header_width(s, atlas)
	music_x0 := page.margin_left + header_w
	measure_w := max(space * 4.0, (staff_w - header_w) / f32(total_measures))
	ink := [4]f32{0.08, 0.08, 0.08, 1.0}
	staff_y := page.margin_top + 48.0
	for &part in s.parts {
		for &staff in part.staves {
			top_center_y := staff_y + line_thick * 0.5
			// 5 staff lines
			for i in 0 ..< 5 {
				y := staff_y + f32(i) * space
				draw_rect(l, page.margin_left, y, staff_w, line_thick, ink)
			}
			// Opening barline + measure barlines
			bar_thick := max(1.0, space * 0.18)
			draw_rect(l, page.margin_left, staff_y, bar_thick, staff_h, ink)
			for m in 1 ..= total_measures {
				x := music_x0 + f32(m) * measure_w
				if m == total_measures {
					x = page.margin_left + staff_w - bar_thick
				}
				draw_rect(l, x, staff_y, bar_thick, staff_h, ink)
			}
			// Opening clef, key signature, and time signature
			cursor_x := page.margin_left + space * 0.8
			draw_clef(l, atlas, staff.clef, cursor_x, top_center_y, space, em_size, ink)
			cursor_x += win.glyph_advance(atlas, clef_glyph(staff.clef), em_size) + space * 0.9
			if len(staff.measures) > 0 {
				init_meta := staff.measures[0].meta
				if init_meta.key_sig != 0 {
					cursor_x = draw_key_sig(
						l,
						atlas,
						staff.clef,
						init_meta.key_sig,
						cursor_x,
						top_center_y,
						space,
						em_size,
						ink,
					)
					cursor_x += space * 0.6
				}
				draw_time_sig(
					l,
					atlas,
					init_meta.time_sig,
					cursor_x,
					top_center_y,
					space,
					em_size,
					ink,
				)
			}
			// Notes, rests, and mid-score signature changes
			for m_idx in 0 ..< min(len(staff.measures), total_measures) {
				bar_x := music_x0 + f32(m_idx) * measure_w
				sm := &staff.measures[m_idx]
				bar_acc := bar_accidentals_init(sm.meta.key_sig)
				notes_x0 := bar_x
				if m_idx > 0 {
					prev_meta := staff.measures[m_idx - 1].meta
					key_changed := sm.meta.key_sig != prev_meta.key_sig
					time_changed := sm.meta.time_sig != prev_meta.time_sig
					if key_changed || time_changed {
						sig_x := bar_x + space * 0.6
						if key_changed && sm.meta.key_sig != 0 {
							sig_x = draw_key_sig(
								l,
								atlas,
								staff.clef,
								sm.meta.key_sig,
								sig_x,
								top_center_y,
								space,
								em_size,
								ink,
							)
							sig_x += space * 0.5
						}
						if time_changed {
							ts := sm.meta.time_sig
							draw_time_sig(l, atlas, ts, sig_x, top_center_y, space, em_size, ink)
							ts_w := max(
								measure_time_num(atlas, ts.num, em_size),
								measure_time_num(atlas, ts.den, em_size),
							)
							sig_x += ts_w + space * 0.6
						}
						notes_x0 = sig_x
					}
				}
				usable_w := max(space * 2.0, (bar_x + measure_w) - notes_x0)
				for &voice in sm.voices {
					if len(voice.entries) == 0 {
						continue
					}
					slot_w := usable_w / f32(len(voice.entries))
					for &entry, e_idx in voice.entries {
						cx := notes_x0 + (f32(e_idx) + 0.5) * slot_w
						draw_entry(
							l,
							atlas,
							&entry,
							staff.clef,
							&bar_acc,
							cx,
							top_center_y,
							space,
							line_thick,
							em_size,
							ink,
						)
					}
				}
			}
			staff_y += staff_h + space * 9.0
		}
	}
}

bar_accidentals_init :: proc(key_sig: i8) -> Bar_Accidental_State {
	sharp_order := [7]score.Step{.F, .C, .G, .D, .A, .E, .B}
	flat_order := [7]score.Step{.B, .E, .A, .D, .G, .C, .F}
	key_alter: [score.Step]i8
	if key_sig > 0 {
		for i in 0 ..< min(int(key_sig), 7) {
			key_alter[sharp_order[i]] = 1
		}
	}
	else if key_sig < 0 {
		for i in 0 ..< min(int(-key_sig), 7) {
			key_alter[flat_order[i]] = -1
		}
	}
	state: Bar_Accidental_State
	for oct in 0 ..< len(state.active) {
		state.active[oct] = key_alter
	}
	return state
}

should_draw_accidental :: proc(state: ^Bar_Accidental_State, note: score.Note) -> bool {
	p := note.pitch
	oct := clamp(int(p.octave), 0, len(state.active) - 1)
	current := state.active[oct][p.step]
	state.active[oct][p.step] = p.alter

	if note.tie_end {
		return false
	}
	return p.alter != current
}

clef_glyph :: proc(clef: score.Clef) -> rune {
	switch clef {
	case .Treble:
		return score.SMUFL_G_CLEF
	case .Bass:
		return score.SMUFL_F_CLEF
	case .Alto:
		return score.SMUFL_C_CLEF
	case .Tenor:
		return score.SMUFL_C_CLEF
	}
	return score.SMUFL_G_CLEF
}

draw_clef :: proc(
	l: ^win.Layer,
	atlas: ^win.Glyph_Atlas,
	clef: score.Clef,
	x, top_center_y, space, em_size: f32,
	color: [4]f32,
) {
	y := top_center_y
	switch clef {
	case .Treble:
		y += 3.0 * space // G4 line (2nd from bottom)
	case .Bass:
		y += 1.0 * space // F3 line (2nd from top)
	case .Alto:
		y += 2.0 * space // Middle line
	case .Tenor:
		y += 1.0 * space // 2nd line from top
	}
	win.draw_glyph(l, atlas, clef_glyph(clef), x, y, em_size, color)
}

draw_key_sig :: proc(
	l: ^win.Layer,
	atlas: ^win.Glyph_Atlas,
	clef: score.Clef,
	fifths: i8,
	start_x, top_center_y, space, em_size: f32,
	color: [4]f32,
) -> f32 {
	sharp_steps := [score.Clef][7]int {
		.Treble = {0, 3, -1, 2, 5, 1, 4},
		.Bass   = {2, 5, 1, 4, 7, 3, 6},
		.Alto   = {1, 4, 0, 3, 6, 2, 5},
		.Tenor  = {7, 3, 6, 2, 5, 1, 4},
	}
	flat_steps := [score.Clef][7]int {
		.Treble = {4, 1, 5, 2, 6, 3, 7},
		.Bass   = {6, 3, 7, 4, 8, 5, 9},
		.Alto   = {5, 2, 6, 3, 7, 4, 8},
		.Tenor  = {3, 0, 4, 1, 5, 2, 6},
	}
	x := start_x
	count := min(abs(int(fifths)), 7)
	cp := fifths > 0 ? score.SMUFL_ACCIDENTAL_SHARP : score.SMUFL_ACCIDENTAL_FLAT
	steps := fifths > 0 ? sharp_steps[clef] : flat_steps[clef]
	for i in 0 ..< count {
		y := top_center_y + f32(steps[i]) * (space * 0.5)
		win.draw_glyph(l, atlas, cp, x, y, em_size, color)
		x += space * 1.05
	}
	return x
}

measure_time_num :: proc(atlas: ^win.Glyph_Atlas, n: i32, em_size: f32) -> f32 {
	if n <= 0 {
		return win.glyph_advance(atlas, score.SMUFL_TIME_SIG_0, em_size)
	}
	w: f32 = 0
	v := n
	for v > 0 {
		d := v % 10
		w += win.glyph_advance(atlas, score.SMUFL_TIME_SIG_0 + rune(d), em_size)
		v /= 10
	}
	return w
}

draw_time_num :: proc(
	l: ^win.Layer,
	atlas: ^win.Glyph_Atlas,
	n: i32,
	cx, cy, em_size: f32,
	color: [4]f32,
) {
	digits: [8]i32
	count := 0
	v := n
	if v <= 0 {
		digits[0] = 0
		count = 1
	}
	else {
		for v > 0 && count < len(digits) {
			digits[count] = v % 10
			v /= 10
			count += 1
		}
	}
	total_w := measure_time_num(atlas, n, em_size)
	x := cx - total_w * 0.5
	for i := count - 1; i >= 0; i -= 1 {
		cp := score.SMUFL_TIME_SIG_0 + rune(digits[i])
		win.draw_glyph(l, atlas, cp, x, cy, em_size, color)
		x += win.glyph_advance(atlas, cp, em_size)
	}
}

draw_time_sig :: proc(
	l: ^win.Layer,
	atlas: ^win.Glyph_Atlas,
	ts: score.Rational,
	x, top_center_y, space, em_size: f32,
	color: [4]f32,
) {
	num_w := measure_time_num(atlas, ts.num, em_size)
	den_w := measure_time_num(atlas, ts.den, em_size)
	cx := x + max(num_w, den_w) * 0.5
	draw_time_num(l, atlas, ts.num, cx, top_center_y + 1.0 * space, em_size, color)
	draw_time_num(l, atlas, ts.den, cx, top_center_y + 3.0 * space, em_size, color)
}

draw_entry :: proc(
	l: ^win.Layer,
	atlas: ^win.Glyph_Atlas,
	entry: ^score.Entry,
	clef: score.Clef,
	bar_acc: ^Bar_Accidental_State,
	cx, top_center_y, space, line_thick, em_size: f32,
	color: [4]f32,
) {
	kind, dots := classify_duration(entry.duration)
	if len(entry.notes) == 0 {
		draw_rest(l, atlas, kind, dots, cx, top_center_y, space, em_size, color)
		return
	}
	min_step := max(int)
	max_step := min(int)
	for note in entry.notes {
		st := pitch_to_staff_step(note.pitch, clef)
		if st < min_step {min_step = st}
		if st > max_step {max_step = st}
	}
	top_dist := 4 - min_step
	bot_dist := max_step - 4
	stem_up := bot_dist > top_dist
	head_cp := notehead_glyph(kind)
	head_w := win.glyph_advance(atlas, head_cp, em_size)
	head_x := cx - head_w * 0.5
	// Ledger lines above (<= -2) and below (>= 10)
	ledger_w := head_w + space * 0.75
	ledger_thick := line_thick * 1.15
	if min_step <= -2 {
		for st := -2; st >= min_step; st -= 2 {
			ly := top_center_y + f32(st) * (space * 0.5) - ledger_thick * 0.5
			win.draw_rect(l, cx - ledger_w * 0.5, ly, ledger_w, ledger_thick, color)
		}
	}
	if max_step >= 10 {
		for st := 10; st <= max_step; st += 2 {
			ly := top_center_y + f32(st) * (space * 0.5) - ledger_thick * 0.5
			win.draw_rect(l, cx - ledger_w * 0.5, ly, ledger_w, ledger_thick, color)
		}
	}
	// Noteheads, accidentals, and augmentation dots
	for note in entry.notes {
		st := pitch_to_staff_step(note.pitch, clef)
		cy := top_center_y + f32(st) * (space * 0.5)
		win.draw_glyph(l, atlas, head_cp, head_x, cy, em_size, color)
		if should_draw_accidental(bar_acc, note) {
			acc_cp := accidental_glyph(note.pitch.alter)
			acc_w := win.glyph_advance(atlas, acc_cp, em_size)
			win.draw_glyph(l, atlas, acc_cp, head_x - acc_w - space * 0.25, cy, em_size, color)
		}
		if dots > 0 {
			dot_y := (st % 2 == 0) ? cy - space * 0.5 : cy
			for d in 0 ..< dots {
				dot_x := head_x + head_w + space * (0.35 + f32(d) * 0.55)
				win.draw_glyph(
					l,
					atlas,
					score.SMUFL_AUGMENTATION_DOT,
					dot_x,
					dot_y,
					em_size,
					color,
				)
			}
		}
	}
	// Stem & SMuFL flag
	if kind != score.Note_Kind.Whole {
		stem_thick := max(0.7, space * 0.12)
		stem_len := space * 3.5
		mid_y := top_center_y + 2.0 * space
		high_y := top_center_y + f32(min_step) * (space * 0.5)
		low_y := top_center_y + f32(max_step) * (space * 0.5)
		stem_x: f32
		stem_top, stem_bot: f32
		if stem_up {
			stem_x = head_x + head_w - stem_thick
			stem_bot = low_y - space * 0.14
			stem_top = min(high_y - stem_len, mid_y)
		}
		else {
			stem_x = head_x
			stem_top = high_y + space * 0.14
			stem_bot = max(low_y + stem_len, mid_y)
		}
		win.draw_rect(l, stem_x, stem_top, stem_thick, stem_bot - stem_top, color)
		if flag_cp, has_flag := flag_glyph(kind, stem_up); has_flag {
			tip_y := stem_up ? stem_top : stem_bot
			win.draw_glyph(l, atlas, flag_cp, stem_x, tip_y, em_size, color)
		}
	}
}

notehead_glyph :: proc(kind: score.Note_Kind) -> rune {
	switch kind {
	case .Whole:
		return score.SMUFL_NOTEHEAD_WHOLE
	case .Half:
		return score.SMUFL_NOTEHEAD_HALF
	case .Quarter, .Eighth, .Sixteenth, .Thirty_Second:
		return score.SMUFL_NOTEHEAD_BLACK
	}
	return score.SMUFL_NOTEHEAD_BLACK
}

flag_glyph :: proc(kind: score.Note_Kind, stem_up: bool) -> (rune, bool) {
	#partial switch kind {
	case .Eighth:
		return stem_up ? score.SMUFL_FLAG_8TH_UP : score.SMUFL_FLAG_8TH_DOWN, true
	case .Sixteenth:
		return stem_up ? score.SMUFL_FLAG_16TH_UP : score.SMUFL_FLAG_16TH_DOWN, true
	case .Thirty_Second:
		return stem_up ? score.SMUFL_FLAG_32ND_UP : score.SMUFL_FLAG_32ND_DOWN, true
	}
	return 0, false
}

accidental_glyph :: proc(alter: i8) -> rune {
	switch alter {
	case -2:
		return score.SMUFL_ACCIDENTAL_DOUBLE_FLAT
	case -1:
		return score.SMUFL_ACCIDENTAL_FLAT
	case 1:
		return score.SMUFL_ACCIDENTAL_SHARP
	case 2:
		return score.SMUFL_ACCIDENTAL_DOUBLE_SHARP
	case:
		return score.SMUFL_ACCIDENTAL_NATURAL
	}
}

draw_rest :: proc(
	l: ^win.Layer,
	atlas: ^win.Glyph_Atlas,
	kind: score.Note_Kind,
	dots: int,
	cx, top_center_y, space, em_size: f32,
	color: [4]f32,
) {
	cp: rune
	ry := top_center_y + 2.0 * space
	switch kind {
	case .Whole:
		cp = score.SMUFL_REST_WHOLE
		ry = top_center_y + 1.0 * space
	case .Half:
		cp = score.SMUFL_REST_HALF
	case .Quarter:
		cp = score.SMUFL_REST_QUARTER
	case .Eighth:
		cp = score.SMUFL_REST_8TH
	case .Sixteenth:
		cp = score.SMUFL_REST_16TH
	case .Thirty_Second:
		cp = score.SMUFL_REST_32ND
	}

	rw := win.glyph_advance(atlas, cp, em_size)
	rx := cx - rw * 0.5
	win.draw_glyph(l, atlas, cp, rx, ry, em_size, color)

	if dots > 0 {
		dot_y := top_center_y + 1.5 * space
		for d in 0 ..< dots {
			dot_x := rx + rw + space * (0.35 + f32(d) * 0.55)
			win.draw_glyph(l, atlas, score.SMUFL_AUGMENTATION_DOT, dot_x, dot_y, em_size, color)
		}
	}
}

classify_duration :: proc(r: score.Rational) -> (kind: score.Note_Kind, dots: int) {
	if r.num <= 0 || r.den <= 0 {
		return .Quarter, 0
	}
	g := gcd_i32(r.num, r.den)
	num := r.num / g
	den := r.den / g

	base_den := den
	if num == 3 && den >= 2 {
		dots = 1
		base_den = den / 2
	}
	else if num == 7 && den >= 4 {
		dots = 2
		base_den = den / 4
	}
	else if num != 1 {
		val := f64(num) / f64(den)
		if val >= 0.75 {return .Whole, 0}
		if val >= 0.375 {return .Half, 0}
		if val >= 0.1875 {return .Quarter, 0}
		if val >= 0.09375 {return .Eighth, 0}
		if val >= 0.046875 {return .Sixteenth, 0}
		return .Thirty_Second, 0
	}

	switch base_den {
	case 1:
		return .Whole, dots
	case 2:
		return .Half, dots
	case 4:
		return .Quarter, dots
	case 8:
		return .Eighth, dots
	case 16:
		return .Sixteenth, dots
	case:
		if base_den < 1 {return .Whole, dots}
		return .Thirty_Second, dots
	}
}

gcd_i32 :: proc(a, b: i32) -> i32 {
	x, y := a, b
	for y != 0 {
		x, y = y, x % y
	}
	return x
}

pitch_to_staff_step :: proc(p: score.Pitch, clef: score.Clef) -> int {
	top_line_diatonic: int
	switch clef {
	case .Treble:
		top_line_diatonic = 5 * 7 + int(score.Step.F)
	case .Bass:
		top_line_diatonic = 3 * 7 + int(score.Step.A)
	case .Alto:
		top_line_diatonic = 4 * 7 + int(score.Step.G)
	case .Tenor:
		top_line_diatonic = 4 * 7 + int(score.Step.E)
	}
	note_diatonic := int(p.octave) * 7 + int(p.step)
	return top_line_diatonic - note_diatonic
}

draw_overlay :: proc(l: ^win.Layer, s: ^score.Score, atlas: ^win.Glyph_Atlas) {
	page := s.page
	staff_w := page.width_pt - page.margin_left - page.margin_right
	header_w := staff_header_width(s, atlas)
	measure_w := max(
		page.staff_space_pt * 4.0,
		(staff_w - header_w) / f32(max(1, score.measure_count(s))),
	)
	staff_y := page.margin_top + 48.0
	staff_h := 4.0 * page.staff_space_pt + max(0.6, page.staff_space_pt * 0.12)
	win.draw_rect(
		l,
		page.margin_left + header_w,
		staff_y - 4.0,
		measure_w,
		staff_h + 8.0,
		{0.20, 0.50, 0.95, 0.22},
	)
}
