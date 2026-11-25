package window

import "../utils"
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

// ---------------------------------------------------------------------------
// OpenGL Renderer & Glyph Atlas Lifecycle
// ---------------------------------------------------------------------------

renderer_init :: proc() -> (r: utils.Renderer, ok: bool) {
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
	gl.VertexAttribPointer(0, 2, gl.FLOAT, gl.FALSE, size_of(utils.Vertex), offset_of(utils.Vertex, pos))

	gl.EnableVertexAttribArray(1)
	gl.VertexAttribPointer(1, 2, gl.FLOAT, gl.FALSE, size_of(utils.Vertex), offset_of(utils.Vertex, uv))

	gl.EnableVertexAttribArray(2)
	gl.VertexAttribPointer(2, 4, gl.FLOAT, gl.FALSE, size_of(utils.Vertex), offset_of(utils.Vertex, color))

	gl.EnableVertexAttribArray(3)
	gl.VertexAttribPointer(3, 1, gl.FLOAT, gl.FALSE, size_of(utils.Vertex), offset_of(utils.Vertex, mode))

	gl.BindVertexArray(0)

	// 2D painter's algorithm: disable depth testing, enable standard alpha blending.
	gl.Disable(gl.DEPTH_TEST)
	gl.Enable(gl.BLEND)
	gl.BlendFunc(gl.SRC_ALPHA, gl.ONE_MINUS_SRC_ALPHA)

	return r, true
}

renderer_destroy :: proc(r: ^utils.Renderer) {
	// Free every slot that was ever used, even if currently popped.
	for &l in r.layers {
		delete(l.verts)
	}
	gl.DeleteBuffers(1, &r.vbo)
	gl.DeleteVertexArrays(1, &r.vao)
	gl.DeleteProgram(r.program)
}

renderer_begin_frame :: proc(r: ^utils.Renderer) {
	for &l in r.layers[:r.layer_count] {
		clear(&l.verts)
		l.atlas_tex = 0
	}
}

renderer_flush :: proc(r: ^utils.Renderer, cam: utils.Camera, win_w, win_h: f32) {
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
			len(l.verts) * size_of(utils.Vertex),
			raw_data(l.verts),
			gl.STREAM_DRAW,
		)
		gl.DrawArrays(gl.TRIANGLES, 0, i32(len(l.verts)))
	}
	gl.BindVertexArray(0)
	gl.UseProgram(0)
}

atlas_create :: proc(path: string, codepoints: []rune) -> (atlas: utils.Glyph_Atlas, ok: bool) {
	font_bytes, read_err := os.read_entire_file(path, context.allocator)
	if read_err != nil {
		fmt.eprintfln("Failed to read font file %s: %v", path, read_err)
		return {}, false
	}

	font: stbtt.fontinfo
	if !stbtt.InitFont(&font, raw_data(font_bytes), 0) {
		fmt.eprintfln("Failed to initialize font: %s", path)
		delete(font_bytes)
		return {}, false
	}

	atlas.font_bytes = font_bytes
	pixels := make([]u8, utils.ATLAS_SIZE * utils.ATLAS_SIZE)
	defer delete(pixels)

	atlas.glyphs = make(map[rune]utils.Glyph_Metrics)

	scale := stbtt.ScaleForMappingEmToPixels(&font, utils.ATLAS_EM_PX)
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
		if pen_x + w + gap > utils.ATLAS_SIZE {
			pen_x = gap
			pen_y += row_h + gap
			row_h = 0
		}
		if pen_y + h + gap > utils.ATLAS_SIZE {
			fmt.eprintfln("Glyph atlas full while packing U+%04X", cp)
			break
		}

		for row in 0 ..< h {
			dst_off := (pen_y + row) * utils.ATLAS_SIZE + pen_x
			src_off := row * w
			mem.copy(&pixels[dst_off], mem.ptr_offset(bitmap, src_off), w)
		}

		adv_i, lsb_i: i32
		stbtt.GetGlyphHMetrics(&font, glyph_idx, &adv_i, &lsb_i)

		atlas.glyphs[cp] = utils.Glyph_Metrics {
			u0      = f32(pen_x) / f32(utils.ATLAS_SIZE),
			v0      = f32(pen_y) / f32(utils.ATLAS_SIZE),
			u1      = f32(pen_x + w) / f32(utils.ATLAS_SIZE),
			v1      = f32(pen_y + h) / f32(utils.ATLAS_SIZE),
			x0      = f32(xoff) / utils.ATLAS_EM_PX,
			y0      = f32(yoff) / utils.ATLAS_EM_PX,
			x1      = f32(xoff + bm_w) / utils.ATLAS_EM_PX,
			y1      = f32(yoff + bm_h) / utils.ATLAS_EM_PX,
			advance = (f32(adv_i) * scale) / utils.ATLAS_EM_PX,
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
		utils.ATLAS_SIZE,
		utils.ATLAS_SIZE,
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

atlas_destroy :: proc(atlas: ^utils.Glyph_Atlas) {
	if atlas.tex != 0 {
		gl.DeleteTextures(1, &atlas.tex)
		atlas.tex = 0
	}
	delete(atlas.glyphs)
	delete(atlas.font_bytes)
	atlas.font_bytes = nil
}

// ---------------------------------------------------------------------------
// Layer Drawing Primitives
// ---------------------------------------------------------------------------

draw_glyph :: proc(
	l: ^utils.Layer,
	atlas: ^utils.Glyph_Atlas,
	cp: rune,
	origin_x, origin_y, em_size: f32,
	color: [4]f32,
) {
	if l.pdf_cmds != nil {
		append(
			l.pdf_cmds,
			utils.Pdf_Glyph {
				cp       = cp,
				origin_x = origin_x,
				origin_y = origin_y,
				em_size  = em_size,
				color    = color,
			},
		)
		return
	}

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
		utils.Vertex{{x0, y0}, {g.u0, g.v0}, color, 1.0},
		utils.Vertex{{x1, y0}, {g.u1, g.v0}, color, 1.0},
		utils.Vertex{{x1, y1}, {g.u1, g.v1}, color, 1.0},
		utils.Vertex{{x0, y0}, {g.u0, g.v0}, color, 1.0},
		utils.Vertex{{x1, y1}, {g.u1, g.v1}, color, 1.0},
		utils.Vertex{{x0, y1}, {g.u0, g.v1}, color, 1.0},
	)
}

draw_rect :: proc(l: ^utils.Layer, x, y, w, h: f32, color: [4]f32) {
	if l.pdf_cmds != nil {
		append(l.pdf_cmds, utils.Pdf_Rect{x = x, y = y, w = w, h = h, color = color})
		return
	}

	x0 := x
	y0 := y
	x1 := x + w
	y1 := y + h

	append(
		&l.verts,
		utils.Vertex{{x0, y0}, {0, 0}, color, 0.0},
		utils.Vertex{{x1, y0}, {0, 0}, color, 0.0},
		utils.Vertex{{x1, y1}, {0, 0}, color, 0.0},
		utils.Vertex{{x0, y0}, {0, 0}, color, 0.0},
		utils.Vertex{{x1, y1}, {0, 0}, color, 0.0},
		utils.Vertex{{x0, y1}, {0, 0}, color, 0.0},
	)
}

draw_int :: proc(l: ^utils.Layer, value: int, x, y, pixel_size: f32, color: [4]f32) {
	buf: [16]int
	count := utils.format_int_glyphs(value, &buf)
	cursor_x := x
	for i in 0 ..< count {
		glyph := utils.DIGIT_GLYPHS[buf[i]]
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

// ---------------------------------------------------------------------------
// Scene, Score, Overlay, & UI Rendering
// ---------------------------------------------------------------------------

draw_scene :: proc(
	scene: ^utils.Scene,
	s: ^utils.Score,
	atlas: ^utils.Glyph_Atlas,
	cam: utils.Camera,
	sel: utils.Selection,
	tool: utils.Editor_Tool,
	panning: bool,
) {
	win_w := f32(scene.window.win_w)
	win_h := f32(scene.window.win_h)
	mouse := mouse_pos()
	inspecting := ctrl_held()

	scene_begin(scene, {0.22, 0.23, 0.25, 1.0})
	draw_page(scene_layer(scene, utils.LAYER_PAGE), s.page)
	draw_score(scene_layer(scene, utils.LAYER_SCORE), s, atlas)

	overlay := scene_layer(scene, utils.LAYER_OVERLAY)
	draw_overlay(overlay, s, atlas, sel)
	if tool.mode == .Note_Entry && !panning && !inspecting {
		if mouse.y > utils.TOOLBAR_H && mouse.y < win_h - utils.STATUS_H {
			world_mouse := utils.screen_to_world(cam, win_w, win_h, mouse)
			draw_note_cursor(overlay, s, atlas, tool, world_mouse)
		}
	}

	draw_ui(scene_layer(scene, utils.LAYER_UI), atlas, tool, win_w, win_h)

	pushed_inspector := false
	if inspecting {
		hovered := scene_hit_test(scene, cam, mouse)
		scene_push(scene, .Screen)
		draw_layer_badge(
			scene_peek(scene),
			hovered,
			mouse,
			win_w,
			win_h,
		)
		pushed_inspector = true
	}
	scene_end(scene, cam)
	if pushed_inspector {
		scene_pop(scene)
	}
}

draw_layer_badge :: proc(l: ^utils.Layer, layer_idx: int, mouse: [2]f32, win_w, win_h: f32) {
	pixel_size: f32 = 3.0
	pad_x: f32 = 8.0
	pad_y: f32 = 6.0
	num_w, num_h := utils.measure_int(layer_idx, pixel_size)
	box_w := num_w + pad_x * 2.0
	box_h := num_h + pad_y * 2.0
	x := clamp(mouse.x + 14.0, 4.0, max(4.0, win_w - box_w - 4.0))
	y := clamp(mouse.y + 14.0, 4.0, max(4.0, win_h - box_h - 4.0))
	draw_rect(l, x - 1.0, y - 1.0, box_w + 2.0, box_h + 2.0, {0.35, 0.60, 1.0, 0.85})
	draw_rect(l, x, y, box_w, box_h, {0.10, 0.11, 0.14, 0.94})
	draw_int(l, layer_idx, x + pad_x, y + pad_y, pixel_size, {0.95, 0.96, 0.98, 1.0})
}

draw_page :: proc(l: ^utils.Layer, page: utils.Page_Setup) {
	draw_rect(l, 6, 8, page.width_pt, page.height_pt, {0.0, 0.0, 0.0, 0.28})
	draw_rect(l, 0, 0, page.width_pt, page.height_pt, {0.98, 0.97, 0.94, 1.0})
}

draw_score :: proc(l: ^utils.Layer, s: ^utils.Score, atlas: ^utils.Glyph_Atlas) {
	layout := utils.compute_score_layout(s, atlas)
	page := s.page
	staff_w := layout.staff_w
	space := layout.space
	em_size := space * 4.0
	line_thick := layout.line_thick
	staff_h := layout.staff_h
	total_measures := layout.total_measures
	music_x0 := layout.music_x0
	measure_w := layout.measure_w
	ink := [4]f32{0.08, 0.08, 0.08, 1.0}
	staff_y := layout.first_staff_y

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
			cursor_x += utils.glyph_advance(atlas, utils.clef_glyph(staff.clef), em_size) + space * 0.9
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
							draw_time_sig(
								l,
								atlas,
								sm.meta.time_sig,
								sig_x,
								top_center_y,
								space,
								em_size,
								ink,
							)
						}
					}
				}

				notes_x0, usable_w := utils.measure_notes_bounds(&staff, m_idx, layout, atlas)
				cap := utils.measure_capacity(sm.meta)

				for &voice in sm.voices {
					if len(voice.entries) == 0 {
						continue
					}
					bar_acc := utils.bar_accidentals_init(sm.meta.key_sig)
					used := utils.voice_duration_sum(voice.entries[:])
					effective_cap := utils.rational_cmp(used, cap) > 0 ? used : cap
					cur_off := utils.Rational{0, 1}
					for &entry in voice.entries {
						cx := utils.beat_to_x(notes_x0, usable_w, space, cur_off, effective_cap)
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
						cur_off = utils.rational_add(cur_off, entry.duration)
					}
				}
			}
			staff_y += layout.staff_step_y
		}
	}
}

draw_clef :: proc(
	l: ^utils.Layer,
	atlas: ^utils.Glyph_Atlas,
	clef: utils.Clef,
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
	draw_glyph(l, atlas, utils.clef_glyph(clef), x, y, em_size, color)
}

draw_key_sig :: proc(
	l: ^utils.Layer,
	atlas: ^utils.Glyph_Atlas,
	clef: utils.Clef,
	fifths: i8,
	start_x, top_center_y, space, em_size: f32,
	color: [4]f32,
) -> f32 {
	sharp_steps := [utils.Clef][7]int {
		.Treble = {0, 3, -1, 2, 5, 1, 4},
		.Bass   = {2, 5, 1, 4, 7, 3, 6},
		.Alto   = {1, 4, 0, 3, 6, 2, 5},
		.Tenor  = {7, 3, 6, 2, 5, 1, 4},
	}
	flat_steps := [utils.Clef][7]int {
		.Treble = {4, 1, 5, 2, 6, 3, 7},
		.Bass   = {6, 3, 7, 4, 8, 5, 9},
		.Alto   = {5, 2, 6, 3, 7, 4, 8},
		.Tenor  = {3, 0, 4, 1, 5, 2, 6},
	}
	x := start_x
	count := min(abs(int(fifths)), 7)
	cp := fifths > 0 ? utils.SMUFL_ACCIDENTAL_SHARP : utils.SMUFL_ACCIDENTAL_FLAT
	steps := fifths > 0 ? sharp_steps[clef] : flat_steps[clef]
	for i in 0 ..< count {
		y := top_center_y + f32(steps[i]) * (space * 0.5)
		draw_glyph(l, atlas, cp, x, y, em_size, color)
		x += space * 1.05
	}
	return x
}

draw_time_num :: proc(
	l: ^utils.Layer,
	atlas: ^utils.Glyph_Atlas,
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
	total_w := utils.measure_time_num(atlas, n, em_size)
	x := cx - total_w * 0.5
	for i := count - 1; i >= 0; i -= 1 {
		cp := utils.SMUFL_TIME_SIG_0 + rune(digits[i])
		draw_glyph(l, atlas, cp, x, cy, em_size, color)
		x += utils.glyph_advance(atlas, cp, em_size)
	}
}

draw_time_sig :: proc(
	l: ^utils.Layer,
	atlas: ^utils.Glyph_Atlas,
	ts: utils.Rational,
	x, top_center_y, space, em_size: f32,
	color: [4]f32,
) {
	num_w := utils.measure_time_num(atlas, ts.num, em_size)
	den_w := utils.measure_time_num(atlas, ts.den, em_size)
	cx := x + max(num_w, den_w) * 0.5
	draw_time_num(l, atlas, ts.num, cx, top_center_y + 1.0 * space, em_size, color)
	draw_time_num(l, atlas, ts.den, cx, top_center_y + 3.0 * space, em_size, color)
}

draw_entry :: proc(
	l: ^utils.Layer,
	atlas: ^utils.Glyph_Atlas,
	entry: ^utils.Entry,
	clef: utils.Clef,
	bar_acc: ^utils.Bar_Accidental_State,
	cx, top_center_y, space, line_thick, em_size: f32,
	color: [4]f32,
) {
	kind, dots := utils.classify_duration(entry.duration)
	if len(entry.notes) == 0 {
		draw_rest(l, atlas, kind, dots, cx, top_center_y, space, em_size, color)
		return
	}
	min_step := max(int)
	max_step := min(int)
	for note in entry.notes {
		st := utils.pitch_to_staff_step(note.pitch, clef)
		if st < min_step {min_step = st}
		if st > max_step {max_step = st}
	}
	top_dist := 4 - min_step
	bot_dist := max_step - 4
	stem_up := bot_dist > top_dist
	head_cp := utils.notehead_glyph(kind)
	head_w := utils.glyph_advance(atlas, head_cp, em_size)
	head_x := cx - head_w * 0.5
	// Ledger lines above (<= -2) and below (>= 10)
	ledger_w := head_w + space * 0.75
	ledger_thick := line_thick * 1.15
	if min_step <= -2 {
		for st := -2; st >= min_step; st -= 2 {
			ly := top_center_y + f32(st) * (space * 0.5) - ledger_thick * 0.5
			draw_rect(l, cx - ledger_w * 0.5, ly, ledger_w, ledger_thick, color)
		}
	}
	if max_step >= 10 {
		for st := 10; st <= max_step; st += 2 {
			ly := top_center_y + f32(st) * (space * 0.5) - ledger_thick * 0.5
			draw_rect(l, cx - ledger_w * 0.5, ly, ledger_w, ledger_thick, color)
		}
	}
	// Noteheads, accidentals, and augmentation dots
	for note in entry.notes {
		st := utils.pitch_to_staff_step(note.pitch, clef)
		cy := top_center_y + f32(st) * (space * 0.5)
		draw_glyph(l, atlas, head_cp, head_x, cy, em_size, color)
		if utils.should_draw_accidental(bar_acc, note) {
			acc_cp := utils.accidental_glyph(note.pitch.alter)
			acc_w := utils.glyph_advance(atlas, acc_cp, em_size)
			draw_glyph(l, atlas, acc_cp, head_x - acc_w - space * 0.25, cy, em_size, color)
		}
		if dots > 0 {
			dot_y := (st % 2 == 0) ? cy - space * 0.5 : cy
			for d in 0 ..< dots {
				dot_x := head_x + head_w + space * (0.35 + f32(d) * 0.55)
				draw_glyph(
					l,
					atlas,
					utils.SMUFL_AUGMENTATION_DOT,
					dot_x,
					dot_y,
					em_size,
					color,
				)
			}
		}
	}
	// Stem & SMuFL flag
	if kind != utils.Note_Kind.Whole {
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
		draw_rect(l, stem_x, stem_top, stem_thick, stem_bot - stem_top, color)
		if flag_cp, has_flag := utils.flag_glyph(kind, stem_up); has_flag {
			tip_y := stem_up ? stem_top : stem_bot
			draw_glyph(l, atlas, flag_cp, stem_x, tip_y, em_size, color)
		}
	}
}

draw_rest :: proc(
	l: ^utils.Layer,
	atlas: ^utils.Glyph_Atlas,
	kind: utils.Note_Kind,
	dots: int,
	cx, top_center_y, space, em_size: f32,
	color: [4]f32,
) {
	cp: rune
	ry := top_center_y + 2.0 * space
	switch kind {
	case .Whole:
		cp = utils.SMUFL_REST_WHOLE
		ry = top_center_y + 1.0 * space
	case .Half:
		cp = utils.SMUFL_REST_HALF
	case .Quarter:
		cp = utils.SMUFL_REST_QUARTER
	case .Eighth:
		cp = utils.SMUFL_REST_8TH
	case .Sixteenth:
		cp = utils.SMUFL_REST_16TH
	case .Thirty_Second:
		cp = utils.SMUFL_REST_32ND
	}

	rw := utils.glyph_advance(atlas, cp, em_size)
	rx := cx - rw * 0.5
	draw_glyph(l, atlas, cp, rx, ry, em_size, color)

	if dots > 0 {
		dot_y := top_center_y + 1.5 * space
		for d in 0 ..< dots {
			dot_x := rx + rw + space * (0.35 + f32(d) * 0.55)
			draw_glyph(l, atlas, utils.SMUFL_AUGMENTATION_DOT, dot_x, dot_y, em_size, color)
		}
	}
}

draw_overlay :: proc(
	l: ^utils.Layer,
	s: ^utils.Score,
	atlas: ^utils.Glyph_Atlas,
	sel: utils.Selection,
) {
	if !sel.active {
		return
	}
	if sel.part_idx < 0 || sel.part_idx >= len(s.parts) {
		return
	}
	part := &s.parts[sel.part_idx]
	if sel.staff_idx < 0 || sel.staff_idx >= len(part.staves) {
		return
	}
	if sel.measure_idx < 0 || sel.measure_idx >= len(part.staves[sel.staff_idx].measures) {
		return
	}

	layout := utils.compute_score_layout(s, atlas)
	flat_staff_idx := 0
	for p_i in 0 ..< sel.part_idx {
		flat_staff_idx += len(s.parts[p_i].staves)
	}
	flat_staff_idx += sel.staff_idx

	x := layout.music_x0 + f32(sel.measure_idx) * layout.measure_w
	y := layout.first_staff_y + f32(flat_staff_idx) * layout.staff_step_y
	draw_rect(
		l,
		x,
		y - 4.0,
		layout.measure_w,
		layout.staff_h + 8.0,
		{0.20, 0.50, 0.95, 0.22},
	)
}

draw_note_symbol :: proc(
	l: ^utils.Layer,
	atlas: ^utils.Glyph_Atlas,
	kind: utils.Note_Kind,
	stem_up: bool,
	cx, cy, space: f32,
	color: [4]f32,
) {
	em_size := space * 4.0
	head_cp := utils.notehead_glyph(kind)
	head_w := utils.glyph_advance(atlas, head_cp, em_size)
	head_x := cx - head_w * 0.5
	draw_glyph(l, atlas, head_cp, head_x, cy, em_size, color)

	if kind != .Whole {
		stem_thick := max(0.7, space * 0.12)
		stem_len := space * 3.5
		stem_x: f32
		stem_top, stem_bot: f32
		if stem_up {
			stem_x = head_x + head_w - stem_thick
			stem_bot = cy - space * 0.14
			stem_top = cy - stem_len
		}
		else {
			stem_x = head_x
			stem_top = cy + space * 0.14
			stem_bot = cy + stem_len
		}
		draw_rect(l, stem_x, stem_top, stem_thick, stem_bot - stem_top, color)
		if flag_cp, has_flag := utils.flag_glyph(kind, stem_up); has_flag {
			tip_y := stem_up ? stem_top : stem_bot
			draw_glyph(l, atlas, flag_cp, stem_x, tip_y, em_size, color)
		}
	}
}

draw_note_cursor :: proc(
	l: ^utils.Layer,
	s: ^utils.Score,
	atlas: ^utils.Glyph_Atlas,
	tool: utils.Editor_Tool,
	world_pos: [2]f32,
) {
	layout := utils.compute_score_layout(s, atlas)
	space := layout.space
	em_size := space * 4.0

	target := utils.resolve_note_target(s, atlas, tool, world_pos)
	if target.kind == .None {
		idle_ghost := [4]f32{0.18, 0.48, 0.92, 0.45}
		if tool.is_rest {
			draw_rest(l, atlas, tool.duration, 0, world_pos.x, world_pos.y - 2.0 * space, space, em_size, idle_ghost)
		}
		else {
			draw_note_symbol(l, atlas, tool.duration, true, world_pos.x, world_pos.y, space, idle_ghost)
		}
		return
	}

	ghost_color := target.will_delete ? [4]f32{0.88, 0.30, 0.26, 0.80} : [4]f32{0.18, 0.48, 0.92, 0.78}
	preview_kind, preview_dots := utils.classify_duration(target.effective_dur)

	if tool.is_rest {
		draw_rest(l, atlas, preview_kind, preview_dots, target.cx, target.top_center_y, space, em_size, ghost_color)
		return
	}

	half_space := space * 0.5
	cy := target.top_center_y + f32(target.staff_step) * half_space
	stem_up := target.staff_step > 4

	head_cp := utils.notehead_glyph(preview_kind)
	head_w := utils.glyph_advance(atlas, head_cp, em_size)
	head_x := target.cx - head_w * 0.5

	ledger_w := head_w + space * 0.75
	ledger_thick := layout.line_thick * 1.15
	if target.staff_step <= -2 {
		for st := -2; st >= target.staff_step; st -= 2 {
			ly := target.top_center_y + f32(st) * half_space - ledger_thick * 0.5
			draw_rect(l, target.cx - ledger_w * 0.5, ly, ledger_w, ledger_thick, ghost_color)
		}
	}
	else if target.staff_step >= 10 {
		for st := 10; st <= target.staff_step; st += 2 {
			ly := target.top_center_y + f32(st) * half_space - ledger_thick * 0.5
			draw_rect(l, target.cx - ledger_w * 0.5, ly, ledger_w, ledger_thick, ghost_color)
		}
	}

	if target.draw_acc && !target.will_delete {
		acc_cp := utils.accidental_glyph(target.pitch.alter)
		acc_w := utils.glyph_advance(atlas, acc_cp, em_size)
		draw_glyph(l, atlas, acc_cp, head_x - acc_w - space * 0.25, cy, em_size, ghost_color)
	}

	draw_note_symbol(l, atlas, preview_kind, stem_up, target.cx, cy, space, ghost_color)
}

draw_ui :: proc(
	l: ^utils.Layer,
	atlas: ^utils.Glyph_Atlas,
	tool: utils.Editor_Tool,
	win_w, win_h: f32,
) {
	draw_rect(l, 0, 0, win_w, utils.TOOLBAR_H, {0.14, 0.15, 0.17, 0.96})
	draw_rect(l, 0, utils.TOOLBAR_H, win_w, 1.0, {0.08, 0.08, 0.10, 1.0})
	bg_idle := [4]f32{0.20, 0.22, 0.25, 1.0}
	bg_active := [4]f32{0.22, 0.46, 0.82, 1.0}
	bg_armed := [4]f32{0.25, 0.32, 0.42, 1.0}
	fg_idle := [4]f32{0.82, 0.84, 0.88, 1.0}
	fg_active := [4]f32{0.98, 0.99, 1.0, 1.0}
	divider_col := [4]f32{0.28, 0.30, 0.34, 1.0}
	// Select Mode button (4-corner selection reticle)
	sel_active := tool.mode == .Select
	draw_rect(l, utils.BTN_SELECT_X, utils.BTN_Y, utils.BTN_SIZE, utils.BTN_SIZE, sel_active ? bg_active : bg_idle)
	ret_col := sel_active ? fg_active : fg_idle
	rx0 := utils.BTN_SELECT_X + 7.0
	ry0 := utils.BTN_Y + 7.0
	rx1 := utils.BTN_SELECT_X + utils.BTN_SIZE - 7.0
	ry1 := utils.BTN_Y + utils.BTN_SIZE - 7.0
	arm: f32 = 4.0
	th: f32 = 1.5
	draw_rect(l, rx0, ry0, arm, th, ret_col)
	draw_rect(l, rx0, ry0, th, arm, ret_col)
	draw_rect(l, rx1 - arm, ry0, arm, th, ret_col)
	draw_rect(l, rx1 - th, ry0, th, arm, ret_col)
	draw_rect(l, rx0, ry1 - th, arm, th, ret_col)
	draw_rect(l, rx0, ry1 - arm, th, arm, ret_col)
	draw_rect(l, rx1 - arm, ry1 - th, arm, th, ret_col)
	draw_rect(l, rx1 - th, ry1 - arm, th, arm, ret_col)
	// Divider 1
	draw_rect(l, utils.BTN_SELECT_X + utils.BTN_SIZE + 5.0, utils.BTN_Y + 4.0, 1.0, utils.BTN_SIZE - 8.0, divider_col)
	// 6 Note Duration buttons
	icon_space: f32 = 3.4
	for i in 0 ..< 6 {
		kind := utils.Note_Kind(i)
		bx := utils.BTN_NOTES_X0 + f32(i) * utils.BTN_STEP_X
		active := tool.mode == .Note_Entry && tool.duration == kind
		draw_rect(l, bx, utils.BTN_Y, utils.BTN_SIZE, utils.BTN_SIZE, active ? bg_active : bg_idle)
		fg := active ? fg_active : fg_idle
		cx := bx + utils.BTN_SIZE * 0.5
		cy := kind == .Whole ? (utils.BTN_Y + utils.BTN_SIZE * 0.5) : (utils.BTN_Y + 19.5)
		draw_note_symbol(l, atlas, kind, true, cx, cy, icon_space, fg)
	}
	// Rest Toggle button
	rest_active := tool.mode == .Note_Entry && tool.is_rest
	rest_armed := tool.mode == .Select && tool.is_rest
	rest_bg := rest_active ? bg_active : (rest_armed ? bg_armed : bg_idle)
	draw_rect(l, utils.BTN_REST_X, utils.BTN_Y, utils.BTN_SIZE, utils.BTN_SIZE, rest_bg)
	rest_em := icon_space * 4.2
	rw := utils.glyph_advance(atlas, utils.SMUFL_REST_QUARTER, rest_em)
	draw_glyph(
		l,
		atlas,
		utils.SMUFL_REST_QUARTER,
		utils.BTN_REST_X + (utils.BTN_SIZE - rw) * 0.5,
		utils.BTN_Y + utils.BTN_SIZE * 0.5,
		rest_em,
		rest_active ? fg_active : fg_idle,
	)
	// Divider 2
	draw_rect(l, utils.BTN_REST_X + utils.BTN_SIZE + 5.0, utils.BTN_Y + 4.0, 1.0, utils.BTN_SIZE - 8.0, divider_col)
	// 3 Accidental Override buttons (Flat, Natural, Sharp)
	acc_modes := [3]utils.Accidental_Override{.Flat, .Natural, .Sharp}
	acc_glyphs := [3]rune {
		utils.SMUFL_ACCIDENTAL_FLAT,
		utils.SMUFL_ACCIDENTAL_NATURAL,
		utils.SMUFL_ACCIDENTAL_SHARP,
	}
	acc_y_offs := [3]f32{2.0, 0.0, 0.0}
	acc_em := icon_space * 4.4
	for mode, i in acc_modes {
		bx := utils.BTN_ACC_X0 + f32(i) * utils.BTN_STEP_X
		active := tool.mode == .Note_Entry && tool.accidental == mode && !tool.is_rest
		armed := tool.accidental == mode && !active
		draw_rect(l, bx, utils.BTN_Y, utils.BTN_SIZE, utils.BTN_SIZE, active ? bg_active : (armed ? bg_armed : bg_idle))
		cp := acc_glyphs[i]
		aw := utils.glyph_advance(atlas, cp, acc_em)
		draw_glyph(
			l,
			atlas,
			cp,
			bx + (utils.BTN_SIZE - aw) * 0.5,
			utils.BTN_Y + utils.BTN_SIZE * 0.5 + acc_y_offs[i],
			acc_em,
			active ? fg_active : fg_idle,
		)
	}
	// Divider 3
	draw_rect(l, utils.BTN_ACC_X0 + 2.0 * utils.BTN_STEP_X + utils.BTN_SIZE + 5.0, utils.BTN_Y + 4.0, 1.0, utils.BTN_SIZE - 8.0, divider_col)
	// Export PDF button (page sheet + downward export arrow)
	draw_rect(l, utils.BTN_EXPORT_X, utils.BTN_Y, utils.BTN_SIZE, utils.BTN_SIZE, bg_idle)
	px := utils.BTN_EXPORT_X + 8.0
	py := utils.BTN_Y + 6.0
	draw_rect(l, px, py, 12.0, 1.5, fg_idle)
	draw_rect(l, px, py + 14.5, 12.0, 1.5, fg_idle)
	draw_rect(l, px, py, 1.5, 16.0, fg_idle)
	draw_rect(l, px + 10.5, py, 1.5, 16.0, fg_idle)
	cx := utils.BTN_EXPORT_X + 14.0
	draw_rect(l, cx - 1.0, py + 3.5, 2.0, 6.0, fg_idle)
	draw_rect(l, cx - 3.0, py + 8.0, 6.0, 1.5, fg_idle)
	draw_rect(l, cx - 2.0, py + 9.5, 4.0, 1.5, fg_idle)
	draw_rect(l, cx - 1.0, py + 11.0, 2.0, 1.5, fg_idle)
	// Bottom status bar
	draw_rect(l, 0, win_h - utils.STATUS_H, win_w, utils.STATUS_H, {0.14, 0.15, 0.17, 0.96})
}
