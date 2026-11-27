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

WIZ_CARD_W :: f32(640.0)
WIZ_CARD_H :: f32(480.0)

Wizard_Layout :: struct {
	card:            utils.Rect,
	btn_cancel:      utils.Rect,
	btn_back:        utils.Rect,
	btn_next:        utils.Rect,
	// Step 1: Document
	field_title:     utils.Rect,
	field_subtitle:  utils.Rect,
	field_composer:  utils.Rect,
	btn_staff_size:  [3]utils.Rect,
	btn_page_size:   [3]utils.Rect,
	btn_orient:      [2]utils.Rect,
	page_preview:    utils.Rect,
	// Step 2: Instruments
	btn_ensemble:    [5]utils.Rect,
	btn_add_part:    [5]utils.Rect,
	part_list:       utils.Rect,
	part_rows:       [utils.WIZ_VISIBLE_PART_ROWS]utils.Rect,
	btn_part_up:     utils.Rect,
	btn_part_down:   utils.Rect,
	btn_part_remove: utils.Rect,
	field_part_name: utils.Rect,
	btn_part_clef:   [5]utils.Rect,
	// Step 3: Time & Key
	btn_ts_preset:   [6]utils.Rect,
	btn_ts_num_dec:  utils.Rect,
	btn_ts_num_inc:  utils.Rect,
	ts_num_box:      utils.Rect,
	btn_ts_den_dec:  utils.Rect,
	btn_ts_den_inc:  utils.Rect,
	ts_den_box:      utils.Rect,
	ts_preview:      utils.Rect,
	btn_bars:        [4]utils.Rect,
	bars_box:        utils.Rect,
	btn_fill_rests:  utils.Rect,
	btn_key_mode:    [2]utils.Rect,
	btn_key_flat:    utils.Rect,
	btn_key_sharp:   utils.Rect,
	key_name_box:    utils.Rect,
	ks_preview:      utils.Rect,
}

compute_wizard_layout :: proc(win_w, win_h: f32) -> Wizard_Layout {
	l: Wizard_Layout
	card_w := min(WIZ_CARD_W, max(300.0, win_w - 24.0))
	card_h := min(WIZ_CARD_H, max(220.0, win_h - 24.0))
	cx := (win_w - card_w) * 0.5
	cy := (win_h - card_h) * 0.5
	l.card = {cx, cy, card_w, card_h}

	footer_y := cy + card_h - 40.0
	l.btn_cancel = {cx + 20.0, footer_y, 88.0, 28.0}
	l.btn_back = {cx + card_w - 204.0, footer_y, 88.0, 28.0}
	l.btn_next = {cx + card_w - 108.0, footer_y, 88.0, 28.0}

	body_x := cx + 20.0
	body_y := cy + 62.0
	body_w := card_w - 40.0

	// Step 1: Document
	left_w := body_w * 0.56
	l.field_title = {body_x, body_y + 18.0, left_w, 32.0}
	l.field_subtitle = {body_x, body_y + 80.0, left_w, 32.0}
	l.field_composer = {body_x, body_y + 142.0, left_w, 32.0}
	ss_w := (left_w - 12.0) / 3.0
	for i in 0 ..< 3 {
		l.btn_staff_size[i] = {body_x + f32(i) * (ss_w + 6.0), body_y + 214.0, ss_w, 28.0}
	}

	right_x := body_x + left_w + 20.0
	right_w := body_w - left_w - 20.0
	ps_w := (right_w - 12.0) / 3.0
	for i in 0 ..< 3 {
		l.btn_page_size[i] = {right_x + f32(i) * (ps_w + 6.0), body_y + 18.0, ps_w, 28.0}
	}
	or_w := (right_w - 8.0) * 0.5
	l.btn_orient[0] = {right_x, body_y + 80.0, or_w, 28.0}
	l.btn_orient[1] = {right_x + or_w + 8.0, body_y + 80.0, or_w, 28.0}
	l.page_preview = {right_x, body_y + 124.0, right_w, 198.0}

	// Step 2: Instruments
	col1_w: f32 = 200.0
	for i in 0 ..< 5 {
		l.btn_ensemble[i] = {body_x, body_y + 18.0 + f32(i) * 30.0, col1_w, 26.0}
	}
	add_w := (col1_w - 6.0) * 0.5
	l.btn_add_part[0] = {body_x, body_y + 198.0, add_w, 26.0}
	l.btn_add_part[1] = {body_x + add_w + 6.0, body_y + 198.0, add_w, 26.0}
	l.btn_add_part[2] = {body_x, body_y + 230.0, add_w, 26.0}
	l.btn_add_part[3] = {body_x + add_w + 6.0, body_y + 230.0, add_w, 26.0}
	l.btn_add_part[4] = {body_x, body_y + 262.0, col1_w, 26.0}

	col2_x := body_x + col1_w + 20.0
	col2_w := body_w - col1_w - 20.0
	row_h: f32 = 28.0
	list_h := f32(utils.WIZ_VISIBLE_PART_ROWS) * row_h + 8.0
	l.part_list = {col2_x, body_y + 18.0, col2_w, list_h}
	for i in 0 ..< utils.WIZ_VISIBLE_PART_ROWS {
		l.part_rows[i] = {col2_x + 4.0, body_y + 22.0 + f32(i) * row_h, col2_w - 8.0, row_h - 2.0}
	}
	ctrl_y := l.part_list.y + l.part_list.h + 8.0
	ctrl_w := (col2_w - 12.0) / 3.0
	l.btn_part_up = {col2_x, ctrl_y, ctrl_w, 26.0}
	l.btn_part_down = {col2_x + ctrl_w + 6.0, ctrl_y, ctrl_w, 26.0}
	l.btn_part_remove = {col2_x + (ctrl_w + 6.0) * 2.0, ctrl_y, ctrl_w, 26.0}

	l.field_part_name = {col2_x, ctrl_y + 52.0, col2_w, 30.0}
	clef_w := (col2_w - 16.0) / 5.0
	for i in 0 ..< 5 {
		l.btn_part_clef[i] = {col2_x + f32(i) * (clef_w + 4.0), ctrl_y + 92.0, clef_w, 26.0}
	}

	// Step 3: Time & Key
	half_w := (body_w - 24.0) * 0.5
	tk_rx := body_x + half_w + 24.0
	ts_bw := (half_w - 12.0) / 3.0
	for i in 0 ..< 6 {
		col := i % 3
		row := i / 3
		l.btn_ts_preset[i] = {
			body_x + f32(col) * (ts_bw + 6.0),
			body_y + 18.0 + f32(row) * 34.0,
			ts_bw,
			28.0,
		}
	}
	l.btn_ts_num_dec = {body_x + 64.0, body_y + 96.0, 28.0, 26.0}
	l.ts_num_box = {body_x + 94.0, body_y + 96.0, 36.0, 26.0}
	l.btn_ts_num_inc = {body_x + 132.0, body_y + 96.0, 28.0, 26.0}
	l.btn_ts_den_dec = {body_x + 64.0, body_y + 130.0, 28.0, 26.0}
	l.ts_den_box = {body_x + 94.0, body_y + 130.0, 36.0, 26.0}
	l.btn_ts_den_inc = {body_x + 132.0, body_y + 130.0, 28.0, 26.0}
	l.ts_preview = {body_x + 174.0, body_y + 96.0, half_w - 174.0, 60.0}

	bars_y := body_y + 200.0
	l.btn_bars[0] = {body_x, bars_y, 44.0, 28.0}
	l.btn_bars[1] = {body_x + 50.0, bars_y, 40.0, 28.0}
	l.bars_box = {body_x + 96.0, bars_y, half_w - 192.0, 28.0}
	l.btn_bars[2] = {body_x + half_w - 90.0, bars_y, 40.0, 28.0}
	l.btn_bars[3] = {body_x + half_w - 44.0, bars_y, 44.0, 28.0}
	l.btn_fill_rests = {body_x, body_y + 248.0, half_w, 28.0}

	km_w := (half_w - 8.0) * 0.5
	l.btn_key_mode[0] = {tk_rx, body_y + 18.0, km_w, 28.0}
	l.btn_key_mode[1] = {tk_rx + km_w + 8.0, body_y + 18.0, km_w, 28.0}
	l.btn_key_flat = {tk_rx, body_y + 56.0, 74.0, 28.0}
	l.key_name_box = {tk_rx + 80.0, body_y + 56.0, half_w - 160.0, 28.0}
	l.btn_key_sharp = {tk_rx + half_w - 74.0, body_y + 56.0, 74.0, 28.0}
	l.ks_preview = {tk_rx, body_y + 100.0, half_w, 176.0}

	return l
}

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
	gl.VertexAttribPointer(
		0,
		2,
		gl.FLOAT,
		gl.FALSE,
		size_of(utils.Vertex),
		offset_of(utils.Vertex, pos),
	)

	gl.EnableVertexAttribArray(1)
	gl.VertexAttribPointer(
		1,
		2,
		gl.FLOAT,
		gl.FALSE,
		size_of(utils.Vertex),
		offset_of(utils.Vertex, uv),
	)

	gl.EnableVertexAttribArray(2)
	gl.VertexAttribPointer(
		2,
		4,
		gl.FLOAT,
		gl.FALSE,
		size_of(utils.Vertex),
		offset_of(utils.Vertex, color),
	)

	gl.EnableVertexAttribArray(3)
	gl.VertexAttribPointer(
		3,
		1,
		gl.FLOAT,
		gl.FALSE,
		size_of(utils.Vertex),
		offset_of(utils.Vertex, mode),
	)

	gl.BindVertexArray(0)

	gl.Disable(gl.DEPTH_TEST)
	gl.Enable(gl.BLEND)
	gl.BlendFunc(gl.SRC_ALPHA, gl.ONE_MINUS_SRC_ALPHA)

	return r, true
}

renderer_destroy :: proc(r: ^utils.Renderer) {
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
	gl.ActiveTexture(gl.TEXTURE0)
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
			len(l.verts) * size_of(utils.Vertex),
			raw_data(l.verts),
			gl.STREAM_DRAW,
		)

		run_start := 0
		cur_tex: u32 = 0
		vert_count := len(l.verts)
		for i := 0; i + 2 < vert_count; i += 3 {
			tri_tex := l.verts[i].tex
			if tri_tex != 0 {
				if cur_tex == 0 {
					cur_tex = tri_tex
				}
				else if tri_tex != cur_tex {
					gl.BindTexture(gl.TEXTURE_2D, cur_tex)
					gl.DrawArrays(gl.TRIANGLES, i32(run_start), i32(i - run_start))
					run_start = i
					cur_tex = tri_tex
				}
			}
		}
		if run_start < vert_count {
			if cur_tex != 0 {
				gl.BindTexture(gl.TEXTURE_2D, cur_tex)
			}
			gl.DrawArrays(gl.TRIANGLES, i32(run_start), i32(vert_count - run_start))
		}
	}

	gl.BindTexture(gl.TEXTURE_2D, 0)
	gl.BindVertexArray(0)
	gl.UseProgram(0)
}

atlas_create :: proc(
	path: string,
	codepoints: []rune,
	em_px: f32 = utils.ATLAS_EM_PX,
) -> (
	atlas: utils.Glyph_Atlas,
	ok: bool,
) {
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

	scale := stbtt.ScaleForMappingEmToPixels(&font, em_px)
	ascent_i, descent_i, line_gap_i: i32
	stbtt.GetFontVMetrics(&font, &ascent_i, &descent_i, &line_gap_i)
	atlas.ascent = (f32(ascent_i) * scale) / em_px
	atlas.descent = (f32(descent_i) * scale) / em_px
	atlas.line_gap = (f32(line_gap_i) * scale) / em_px

	gap := 6
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

		adv_i, lsb_i: i32
		stbtt.GetGlyphHMetrics(&font, glyph_idx, &adv_i, &lsb_i)
		advance_em := (f32(adv_i) * scale) / em_px

		bm_w, bm_h, xoff, yoff: i32
		bitmap := stbtt.GetGlyphBitmap(&font, scale, scale, glyph_idx, &bm_w, &bm_h, &xoff, &yoff)
		if bitmap == nil || bm_w <= 0 || bm_h <= 0 {
			if bitmap != nil {
				stbtt.FreeBitmap(bitmap, nil)
			}
			atlas.glyphs[cp] = utils.Glyph_Metrics {
				advance = advance_em,
			}
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

		atlas.glyphs[cp] = utils.Glyph_Metrics {
			u0      = f32(pen_x) / f32(utils.ATLAS_SIZE),
			v0      = f32(pen_y) / f32(utils.ATLAS_SIZE),
			u1      = f32(pen_x + w) / f32(utils.ATLAS_SIZE),
			v1      = f32(pen_y + h) / f32(utils.ATLAS_SIZE),
			x0      = f32(xoff) / em_px,
			y0      = f32(yoff) / em_px,
			x1      = f32(xoff + bm_w) / em_px,
			y1      = f32(yoff + bm_h) / em_px,
			advance = advance_em,
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

fonts_create :: proc() -> (fonts: utils.Fonts, ok: bool) {
	music, music_ok := atlas_create(
		utils.MUSIC_FONT_PATH,
		utils.SMUFL_GLYPHS[:],
		utils.ATLAS_EM_PX,
	)
	if !music_ok {
		return {}, false
	}

	ascii: [95]rune
	for i in 0 ..< 95 {
		ascii[i] = rune(0x20 + i)
	}
	text, text_ok := atlas_create(utils.TEXT_FONT_PATH, ascii[:], utils.TEXT_ATLAS_EM_PX)
	if !text_ok {
		atlas_destroy(&music)
		return {}, false
	}

	fonts.music = music
	fonts.text = text
	return fonts, true
}

fonts_destroy :: proc(fonts: ^utils.Fonts) {
	atlas_destroy(&fonts.music)
	atlas_destroy(&fonts.text)
}

draw_glyph :: proc(
	l: ^utils.Layer,
	atlas: ^utils.Glyph_Atlas,
	cp: rune,
	origin_x, origin_y, em_size: f32,
	color: [4]f32,
) {
	if atlas == nil {
		return
	}
	if l.pdf_cmds != nil {
		append(
			l.pdf_cmds,
			utils.Pdf_Glyph {
				font_bytes = atlas.font_bytes,
				cp = cp,
				origin_x = origin_x,
				origin_y = origin_y,
				em_size = em_size,
				color = color,
			},
		)
		return
	}

	g, ok := atlas.glyphs[cp]
	if !ok || atlas.tex == 0 || g.x1 <= g.x0 || g.y1 <= g.y0 {
		return
	}

	x0 := origin_x + g.x0 * em_size
	y0 := origin_y + g.y0 * em_size
	x1 := origin_x + g.x1 * em_size
	y1 := origin_y + g.y1 * em_size

	append(
		&l.verts,
		utils.Vertex{{x0, y0}, {g.u0, g.v0}, color, 1.0, atlas.tex},
		utils.Vertex{{x1, y0}, {g.u1, g.v0}, color, 1.0, atlas.tex},
		utils.Vertex{{x1, y1}, {g.u1, g.v1}, color, 1.0, atlas.tex},
		utils.Vertex{{x0, y0}, {g.u0, g.v0}, color, 1.0, atlas.tex},
		utils.Vertex{{x1, y1}, {g.u1, g.v1}, color, 1.0, atlas.tex},
		utils.Vertex{{x0, y1}, {g.u0, g.v1}, color, 1.0, atlas.tex},
	)
}

draw_text :: proc(
	l: ^utils.Layer,
	atlas: ^utils.Glyph_Atlas,
	text: string,
	x, baseline_y, em_size: f32,
	color: [4]f32,
) {
	if atlas == nil || len(text) == 0 {
		return
	}
	cursor_x := x
	for cp in text {
		draw_glyph(l, atlas, cp, cursor_x, baseline_y, em_size, color)
		cursor_x += utils.glyph_advance(atlas, cp, em_size)
	}
}

draw_text_centered :: proc(
	l: ^utils.Layer,
	atlas: ^utils.Glyph_Atlas,
	text: string,
	r: utils.Rect,
	em_size: f32,
	color: [4]f32,
) {
	tw := utils.measure_text(atlas, text, em_size)
	tx := r.x + (r.w - tw) * 0.5
	ty := utils.text_baseline_in_rect(atlas, r.y, r.h, em_size)
	draw_text(l, atlas, text, tx, ty, em_size, color)
}

draw_text_clipped :: proc(
	l: ^utils.Layer,
	atlas: ^utils.Glyph_Atlas,
	text: string,
	x, baseline_y, max_w, em_size: f32,
	color: [4]f32,
) {
	if atlas == nil || len(text) == 0 || max_w <= 0 {
		return
	}
	cursor_x := x
	for cp in text {
		adv := utils.glyph_advance(atlas, cp, em_size)
		if cursor_x + adv > x + max_w {
			break
		}
		draw_glyph(l, atlas, cp, cursor_x, baseline_y, em_size, color)
		cursor_x += adv
	}
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
		utils.Vertex{{x0, y0}, {0, 0}, color, 0.0, 0},
		utils.Vertex{{x1, y0}, {0, 0}, color, 0.0, 0},
		utils.Vertex{{x1, y1}, {0, 0}, color, 0.0, 0},
		utils.Vertex{{x0, y0}, {0, 0}, color, 0.0, 0},
		utils.Vertex{{x1, y1}, {0, 0}, color, 0.0, 0},
		utils.Vertex{{x0, y1}, {0, 0}, color, 0.0, 0},
	)
}

draw_rect_outline :: proc(l: ^utils.Layer, x, y, w, h, thick: f32, color: [4]f32) {
	draw_rect(l, x, y, w, thick, color)
	draw_rect(l, x, y + h - thick, w, thick, color)
	draw_rect(l, x, y + thick, thick, max(0.0, h - thick * 2.0), color)
	draw_rect(l, x + w - thick, y + thick, thick, max(0.0, h - thick * 2.0), color)
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

draw_scene :: proc(
	scene: ^utils.Scene,
	s: ^utils.Score,
	fonts: ^utils.Fonts,
	cam: utils.Camera,
	sel: utils.Selection,
	tool: utils.Editor_Tool,
	wiz: ^utils.Wizard_State,
	panning: bool,
) {
	win_w := f32(scene.window.win_w)
	win_h := f32(scene.window.win_h)
	mouse := mouse_pos()
	wiz_open := wiz != nil && wiz.active
	inspecting := ctrl_held() && !wiz_open
	layout := utils.compute_score_layout(s, &fonts.music)

	scene_begin(scene, {0.22, 0.23, 0.25, 1.0})
	draw_page(scene_layer(scene, utils.LAYER_PAGE), s.page, layout.page_count)
	draw_score(scene_layer(scene, utils.LAYER_SCORE), s, fonts)

	overlay := scene_layer(scene, utils.LAYER_OVERLAY)
	draw_overlay(overlay, s, &fonts.music, sel)
	if !wiz_open && tool.mode == .Note_Entry && !panning && !inspecting {
		if mouse.y > utils.TOOLBAR_H && mouse.y < win_h - utils.STATUS_H {
			world_mouse := utils.screen_to_world(cam, win_w, win_h, mouse)
			draw_note_cursor(overlay, s, &fonts.music, tool, world_mouse)
		}
	}

	draw_ui(scene_layer(scene, utils.LAYER_UI), s, fonts, tool, sel, win_w, win_h)

	pushed_wizard := false
	if wiz_open {
		scene_push(scene, .Screen)
		draw_wizard(scene_peek(scene), wiz, fonts, win_w, win_h)
		pushed_wizard = true
	}

	pushed_inspector := false
	if inspecting {
		hovered := scene_hit_test(scene, cam, mouse)
		scene_push(scene, .Screen)
		draw_layer_badge(scene_peek(scene), hovered, mouse, win_w, win_h)
		pushed_inspector = true
	}

	scene_end(scene, cam)

	if pushed_inspector {
		scene_pop(scene)
	}
	if pushed_wizard {
		scene_pop(scene)
	}
}

draw_page :: proc(l: ^utils.Layer, page: utils.Page_Setup, page_count: int) {
	page_step_y := page.height_pt + utils.PAGE_GAP_PT
	for p in 0 ..< max(1, page_count) {
		py := f32(p) * page_step_y
		draw_rect(l, 6, py + 8, page.width_pt, page.height_pt, {0.0, 0.0, 0.0, 0.28})
		draw_rect(l, 0, py, page.width_pt, page.height_pt, {0.98, 0.97, 0.94, 1.0})
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

draw_score :: proc(l: ^utils.Layer, s: ^utils.Score, fonts: ^utils.Fonts) {
	atlas := &fonts.music
	text_atlas := &fonts.text
	layout := utils.compute_score_layout(s, atlas)
	page := s.page
	staff_w := layout.staff_w
	space := layout.space
	em_size := space * 4.0
	line_thick := layout.line_thick
	staff_h := layout.staff_h
	ink := [4]f32{0.08, 0.08, 0.08, 1.0}
	muted_ink := [4]f32{0.22, 0.22, 0.24, 1.0}

	// Score header block (Title, Subtitle, Composer)
	if len(s.title) > 0 {
		title_em: f32 = 20.0
		tw := utils.measure_text(text_atlas, s.title, title_em)
		draw_text(
			l,
			text_atlas,
			s.title,
			(page.width_pt - tw) * 0.5,
			page.margin_top * 0.65,
			title_em,
			ink,
		)
	}
	if len(s.subtitle) > 0 {
		sub_em: f32 = 11.5
		sw := utils.measure_text(text_atlas, s.subtitle, sub_em)
		draw_text(
			l,
			text_atlas,
			s.subtitle,
			(page.width_pt - sw) * 0.5,
			page.margin_top * 0.65 + 16.0,
			sub_em,
			muted_ink,
		)
	}
	if len(s.composer) > 0 {
		comp_em: f32 = 10.5
		cw := utils.measure_text(text_atlas, s.composer, comp_em)
		draw_text(
			l,
			text_atlas,
			s.composer,
			page.width_pt - page.margin_right - cw,
			layout.first_staff_y - space * 2.2,
			comp_em,
			ink,
		)
	}

	bar_thick := max(1.0, space * 0.18)

	for sys_idx in 0 ..< layout.system_count {
		sys := layout.systems[sys_idx]
		sys_bars := sys.end_measure - sys.start_measure
		staff_y := sys.y

		for &part in s.parts {
			part_top_y := staff_y
			part_staff_count := len(part.staves)

			for &staff in part.staves {
				top_center_y := staff_y + line_thick * 0.5
				for i in 0 ..< 5 {
					y := staff_y + f32(i) * space
					draw_rect(l, page.margin_left, y, staff_w, line_thick, ink)
				}
				draw_rect(l, page.margin_left, staff_y, bar_thick, staff_h, ink)
				for m in 1 ..= sys_bars {
					x := sys.music_x0 + f32(m) * sys.measure_w
					if m == sys_bars {
						x = page.margin_left + staff_w - bar_thick
					}
					draw_rect(l, x, staff_y, bar_thick, staff_h, ink)
				}

				cursor_x := page.margin_left + space * 0.8
				draw_clef(l, atlas, staff.clef, cursor_x, top_center_y, space, em_size, ink)
				cursor_x += utils.glyph_advance(atlas, utils.clef_glyph(staff.clef), em_size) + space * 0.9
				if sys.start_measure < len(staff.measures) {
					init_meta := staff.measures[sys.start_measure].meta
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
					show_time :=
						sys.start_measure == 0 ||
						(sys.start_measure > 0 && init_meta.time_sig != staff.measures[sys.start_measure - 1].meta.time_sig)
					if show_time {
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
				}

				for m_idx in sys.start_measure ..< min(len(staff.measures), sys.end_measure) {
					bar_x := sys.music_x0 + f32(m_idx - sys.start_measure) * sys.measure_w
					sm := &staff.measures[m_idx]
					if m_idx > sys.start_measure {
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

					notes_x0, usable_w := utils.measure_notes_bounds(&staff, m_idx, sys, space, atlas)
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

			if part_staff_count > 0 {
				part_bot_y := part_top_y + f32(part_staff_count - 1) * layout.staff_step_y + staff_h
				if part_staff_count > 1 {
					span_h := part_bot_y - part_top_y
					draw_rect(l, page.margin_left, part_top_y, bar_thick, span_h, ink)
					draw_rect(l, page.margin_left - space * 0.65, part_top_y, space * 0.32, span_h, ink)
					for m in 1 ..= sys_bars {
						x := sys.music_x0 + f32(m) * sys.measure_w
						if m == sys_bars {
							x = page.margin_left + staff_w - bar_thick
						}
						draw_rect(l, x, part_top_y, bar_thick, span_h, ink)
					}
				}
				if sys_idx == 0 && len(part.name) > 0 {
					name_em: f32 = 8.5
					nw := utils.measure_text(text_atlas, part.name, name_em)
					right_edge := page.margin_left - (part_staff_count > 1 ? space * 1.2 : space * 0.8)
					nx := max(6.0, right_edge - nw)
					ny := utils.text_baseline_in_rect(text_atlas, part_top_y, part_bot_y - part_top_y, name_em)
					draw_text_clipped(l, text_atlas, part.name, nx, ny, max(0.0, right_edge - 6.0), name_em, ink)
				}
			}
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
		y += 3.0 * space
	case .Bass:
		y += 1.0 * space
	case .Alto:
		y += 2.0 * space
	case .Tenor:
		y += 1.0 * space
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
		.Tenor  = {6, 2, 5, 1, 4, 0, 3},
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
				draw_glyph(l, atlas, utils.SMUFL_AUGMENTATION_DOT, dot_x, dot_y, em_size, color)
			}
		}
	}
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
			draw_rest(
				l,
				atlas,
				tool.duration,
				0,
				world_pos.x,
				world_pos.y - 2.0 * space,
				space,
				em_size,
				idle_ghost,
			)
		}
		else {
			draw_note_symbol(
				l,
				atlas,
				tool.duration,
				true,
				world_pos.x,
				world_pos.y,
				space,
				idle_ghost,
			)
		}
		return
	}
	ghost_color :=
		target.will_delete ? [4]f32{0.88, 0.30, 0.26, 0.80} : [4]f32{0.18, 0.48, 0.92, 0.78}
	preview_kind, preview_dots := utils.classify_duration(target.effective_dur)
	if tool.is_rest {
		draw_rest(
			l,
			atlas,
			preview_kind,
			preview_dots,
			target.cx,
			target.top_center_y,
			space,
			em_size,
			ghost_color,
		)
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

@(private = "file")
draw_wizard_button :: proc(
	l: ^utils.Layer,
	text_atlas: ^utils.Glyph_Atlas,
	label: string,
	r: utils.Rect,
	active: bool,
	primary: bool,
) {
	bg := [4]f32{0.21, 0.23, 0.27, 1.0}
	border := [4]f32{0.30, 0.33, 0.38, 1.0}
	fg := [4]f32{0.88, 0.90, 0.94, 1.0}
	if active || primary {
		bg = {0.22, 0.46, 0.82, 1.0}
		border = {0.38, 0.62, 0.96, 1.0}
		fg = {0.99, 0.99, 1.0, 1.0}
	}
	draw_rect(l, r.x, r.y, r.w, r.h, bg)
	draw_rect_outline(l, r.x, r.y, r.w, r.h, 1.0, border)
	draw_text_centered(l, text_atlas, label, r, 12.5, fg)
}

@(private = "file")
draw_wizard_text_input :: proc(
	l: ^utils.Layer,
	text_atlas: ^utils.Glyph_Atlas,
	label: string,
	tb: ^utils.Text_Buf,
	focused: bool,
	caret: int,
	sel_anchor: int,
	r: utils.Rect,
) {
	draw_text(l, text_atlas, label, r.x, r.y - 6.0, 12.0, {0.76, 0.79, 0.85, 1.0})
	bg := focused ? [4]f32{0.10, 0.11, 0.14, 1.0} : [4]f32{0.12, 0.13, 0.16, 1.0}
	border := focused ? [4]f32{0.28, 0.56, 0.95, 1.0} : [4]f32{0.28, 0.30, 0.35, 1.0}
	draw_rect(l, r.x, r.y, r.w, r.h, bg)
	draw_rect_outline(l, r.x, r.y, r.w, r.h, focused ? 1.5 : 1.0, border)
	val := utils.text_buf_str(tb)
	pad_x: f32 = 8.0
	em: f32 = 13.0
	max_x := r.x + r.w - pad_x
	if focused {
		a := clamp(sel_anchor, 0, tb.len)
		b := clamp(caret, 0, tb.len)
		if a != b {
			lo := min(a, b)
			hi := max(a, b)
			x0 := min(max_x, r.x + pad_x + utils.measure_text(text_atlas, string(tb.buf[:lo]), em))
			x1 := min(max_x, r.x + pad_x + utils.measure_text(text_atlas, string(tb.buf[:hi]), em))
			if x1 > x0 {
				draw_rect(l, x0, r.y + 5.0, x1 - x0, r.h - 10.0, {0.22, 0.46, 0.82, 0.65})
			}
		}
	}
	baseline_y := utils.text_baseline_in_rect(text_atlas, r.y, r.h, em)
	draw_text_clipped(
		l,
		text_atlas,
		val,
		r.x + pad_x,
		baseline_y,
		r.w - pad_x * 2.0,
		em,
		{0.95, 0.96, 0.98, 1.0},
	)
	if focused {
		cur := clamp(caret, 0, tb.len)
		prefix_w := utils.measure_text(text_atlas, string(tb.buf[:cur]), em)
		caret_x := min(max_x, r.x + pad_x + prefix_w)
		draw_rect(l, caret_x, r.y + 6.0, 1.5, r.h - 12.0, {0.42, 0.70, 1.0, 0.95})
	}
}

draw_wizard :: proc(
	l: ^utils.Layer,
	wiz: ^utils.Wizard_State,
	fonts: ^utils.Fonts,
	win_w, win_h: f32,
) {
	music_atlas := &fonts.music
	text_atlas := &fonts.text
	wl := compute_wizard_layout(win_w, win_h)
	c := wl.card

	draw_rect(l, 0, 0, win_w, win_h, {0.05, 0.06, 0.08, 0.72})
	draw_rect(l, c.x + 6.0, c.y + 8.0, c.w, c.h, {0.0, 0.0, 0.0, 0.45})
	draw_rect(l, c.x, c.y, c.w, c.h, {0.16, 0.17, 0.20, 1.0})
	draw_rect(l, c.x, c.y, c.w, 44.0, {0.12, 0.13, 0.16, 1.0})
	draw_rect(l, c.x, c.y + 44.0, c.w, 1.0, {0.26, 0.28, 0.33, 1.0})
	draw_rect(l, c.x, c.y + c.h - 52.0, c.w, 1.0, {0.26, 0.28, 0.33, 1.0})
	draw_rect_outline(l, c.x, c.y, c.w, c.h, 1.0, {0.32, 0.35, 0.42, 1.0})

	step_titles := [utils.Wizard_Step]string {
		.Document     = "Document Setup Wizard  -  Step 1 of 3: Document & Page",
		.Instruments  = "Document Setup Wizard  -  Step 2 of 3: Ensemble & Staves",
		.Time_And_Key = "Document Setup Wizard  -  Step 3 of 3: Time, Key & Measures",
	}
	header_by := utils.text_baseline_in_rect(text_atlas, c.y, 44.0, 13.5)
	draw_text(
		l,
		text_atlas,
		step_titles[wiz.step],
		c.x + 18.0,
		header_by,
		13.5,
		{0.95, 0.96, 0.99, 1.0},
	)

	label_col := [4]f32{0.76, 0.79, 0.85, 1.0}


	switch wiz.step {
	case .Document:
		draw_wizard_text_input(
			l,
			text_atlas,
			"Title",
			&wiz.title,
			wiz.focus == .Title,
			wiz.caret,
			wiz.sel_anchor,
			wl.field_title,
		)
		draw_wizard_text_input(
			l,
			text_atlas,
			"Subtitle",
			&wiz.subtitle,
			wiz.focus == .Subtitle,
			wiz.caret,
			wiz.sel_anchor,
			wl.field_subtitle,
		)
		draw_wizard_text_input(
			l,
			text_atlas,
			"Composer",
			&wiz.composer,
			wiz.focus == .Composer,
			wiz.caret,
			wiz.sel_anchor,
			wl.field_composer,
		)

		draw_text(
			l,
			text_atlas,
			"Staff Size",
			wl.btn_staff_size[0].x,
			wl.btn_staff_size[0].y - 6.0,
			12.0,
			label_col,
		)
		staff_labels := [3]string{"Small", "Medium", "Large"}
		for i in 0 ..< 3 {
			draw_wizard_button(
				l,
				text_atlas,
				staff_labels[i],
				wl.btn_staff_size[i],
				wiz.staff_size == utils.Staff_Size_Preset(i),
				false,
			)
		}

		draw_text(
			l,
			text_atlas,
			"Page Size",
			wl.btn_page_size[0].x,
			wl.btn_page_size[0].y - 6.0,
			12.0,
			label_col,
		)
		page_labels := [3]string{"Letter", "A4", "Tabloid"}
		for i in 0 ..< 3 {
			draw_wizard_button(
				l,
				text_atlas,
				page_labels[i],
				wl.btn_page_size[i],
				wiz.page_size == utils.Page_Size_Preset(i),
				false,
			)
		}

		draw_text(
			l,
			text_atlas,
			"Orientation",
			wl.btn_orient[0].x,
			wl.btn_orient[0].y - 6.0,
			12.0,
			label_col,
		)
		draw_wizard_button(l, text_atlas, "Portrait", wl.btn_orient[0], !wiz.landscape, false)
		draw_wizard_button(l, text_atlas, "Landscape", wl.btn_orient[1], wiz.landscape, false)

		pr := wl.page_preview
		draw_rect(l, pr.x, pr.y, pr.w, pr.h, {0.12, 0.13, 0.16, 1.0})
		draw_rect_outline(l, pr.x, pr.y, pr.w, pr.h, 1.0, {0.26, 0.28, 0.33, 1.0})
		sheet_w: f32 = wiz.landscape ? 132.0 : 96.0
		sheet_h: f32 = wiz.landscape ? 96.0 : 128.0
		sx := pr.x + (pr.w - sheet_w) * 0.5
		sy := pr.y + (pr.h - sheet_h) * 0.5
		draw_rect(l, sx + 3.0, sy + 4.0, sheet_w, sheet_h, {0.0, 0.0, 0.0, 0.35})
		draw_rect(l, sx, sy, sheet_w, sheet_h, {0.97, 0.96, 0.93, 1.0})
		for line_i in 0 ..< 3 {
			ly := sy + 24.0 + f32(line_i) * 22.0
			if ly + 6.0 < sy + sheet_h - 10.0 {
				draw_rect(l, sx + 12.0, ly, sheet_w - 24.0, 1.0, {0.35, 0.35, 0.38, 1.0})
				draw_rect(l, sx + 12.0, ly + 3.0, sheet_w - 24.0, 1.0, {0.35, 0.35, 0.38, 1.0})
			}
		}

	case .Instruments:
		draw_text(
			l,
			text_atlas,
			"Ensemble Presets",
			wl.btn_ensemble[0].x,
			wl.btn_ensemble[0].y - 6.0,
			12.0,
			label_col,
		)
		ens_labels := [5]string {
			"Solo Staff",
			"Piano (Grand Staff)",
			"Choir (SATB)",
			"String Quartet",
			"Brass Quintet",
		}
		for i in 0 ..< 5 {
			draw_wizard_button(l, text_atlas, ens_labels[i], wl.btn_ensemble[i], false, false)
		}

		draw_text(
			l,
			text_atlas,
			"Add Instrument",
			wl.btn_add_part[0].x,
			wl.btn_add_part[0].y - 6.0,
			12.0,
			label_col,
		)
		add_labels := [5]string{"+ Treble", "+ Bass", "+ Alto", "+ Tenor", "+ Grand Staff"}
		for i in 0 ..< 5 {
			draw_wizard_button(l, text_atlas, add_labels[i], wl.btn_add_part[i], false, false)
		}

		hdr_buf: [64]u8
		hdr_str := fmt.bprintf(
			hdr_buf[:],
			"Score Order (%d/%d)",
			len(wiz.parts),
			utils.WIZ_MAX_PARTS,
		)
		draw_text(l, text_atlas, hdr_str, wl.part_list.x, wl.part_list.y - 6.0, 12.0, label_col)
		draw_rect(
			l,
			wl.part_list.x,
			wl.part_list.y,
			wl.part_list.w,
			wl.part_list.h,
			{0.12, 0.13, 0.16, 1.0},
		)
		draw_rect_outline(
			l,
			wl.part_list.x,
			wl.part_list.y,
			wl.part_list.w,
			wl.part_list.h,
			1.0,
			{0.26, 0.28, 0.33, 1.0},
		)

		for vis_i in 0 ..< utils.WIZ_VISIBLE_PART_ROWS {
			p_idx := wiz.part_scroll + vis_i
			if p_idx >= len(wiz.parts) {
				break
			}
			rr := wl.part_rows[vis_i]
			is_sel := p_idx == wiz.selected_part
			if is_sel {
				draw_rect(l, rr.x, rr.y, rr.w, rr.h, {0.22, 0.46, 0.82, 1.0})
			}
			wp := &wiz.parts[p_idx]
			row_buf: [96]u8
			tag := wp.is_grand ? "Grand" : utils.clef_to_string(wp.clef)
			row_str := fmt.bprintf(
				row_buf[:],
				"%d. %s  [%s]",
				p_idx + 1,
				utils.text_buf_str(&wp.name),
				tag,
			)
			rby := utils.text_baseline_in_rect(text_atlas, rr.y, rr.h, 12.0)
			draw_text_clipped(
				l,
				text_atlas,
				row_str,
				rr.x + 8.0,
				rby,
				rr.w - 16.0,
				12.0,
				is_sel ? {0.99, 0.99, 1.0, 1.0} : {0.86, 0.88, 0.92, 1.0},
			)
		}

		draw_wizard_button(l, text_atlas, "Move Up", wl.btn_part_up, false, false)
		draw_wizard_button(l, text_atlas, "Move Down", wl.btn_part_down, false, false)
		draw_wizard_button(l, text_atlas, "Remove", wl.btn_part_remove, false, false)

		if wiz.selected_part >= 0 && wiz.selected_part < len(wiz.parts) {
			sel_part := &wiz.parts[wiz.selected_part]
			draw_wizard_text_input(
				l,
				text_atlas,
				"Selected Part Name",
				&sel_part.name,
				wiz.focus == .Part_Name,
				wiz.caret,
				wiz.sel_anchor,
				wl.field_part_name,
			)
			clef_labels := [5]string{"Treble", "Bass", "Alto", "Tenor", "Grand"}
			for i in 0 ..< 5 {
				is_act :=
					(i == 4) ? sel_part.is_grand : (!sel_part.is_grand && sel_part.clef == utils.Clef(i))
				draw_wizard_button(
					l,
					text_atlas,
					clef_labels[i],
					wl.btn_part_clef[i],
					is_act,
					false,
				)
			}
		}

	case .Time_And_Key:
		draw_text(
			l,
			text_atlas,
			"Time Signature",
			wl.btn_ts_preset[0].x,
			wl.btn_ts_preset[0].y - 6.0,
			12.0,
			label_col,
		)
		ts_presets := [6]utils.Rational{{4, 4}, {3, 4}, {2, 4}, {6, 8}, {2, 2}, {12, 8}}
		ts_labels := [6]string{"4/4", "3/4", "2/4", "6/8", "2/2", "12/8"}
		for ts, i in ts_presets {
			draw_wizard_button(
				l,
				text_atlas,
				ts_labels[i],
				wl.btn_ts_preset[i],
				wiz.time_sig == ts,
				false,
			)
		}

		num_by := utils.text_baseline_in_rect(
			text_atlas,
			wl.btn_ts_num_dec.y,
			wl.btn_ts_num_dec.h,
			12.0,
		)
		draw_text(l, text_atlas, "Beats:", wl.btn_ts_preset[0].x, num_by, 12.0, label_col)
		draw_wizard_button(l, text_atlas, "-", wl.btn_ts_num_dec, false, false)
		num_buf: [16]u8
		draw_text_centered(
			l,
			text_atlas,
			fmt.bprintf(num_buf[:], "%d", wiz.time_sig.num),
			wl.ts_num_box,
			13.0,
			{0.96, 0.97, 0.99, 1.0},
		)
		draw_wizard_button(l, text_atlas, "+", wl.btn_ts_num_inc, false, false)

		den_by := utils.text_baseline_in_rect(
			text_atlas,
			wl.btn_ts_den_dec.y,
			wl.btn_ts_den_dec.h,
			12.0,
		)
		draw_text(l, text_atlas, "Unit:", wl.btn_ts_preset[0].x, den_by, 12.0, label_col)
		draw_wizard_button(l, text_atlas, "-", wl.btn_ts_den_dec, false, false)
		den_buf: [16]u8
		draw_text_centered(
			l,
			text_atlas,
			fmt.bprintf(den_buf[:], "%d", wiz.time_sig.den),
			wl.ts_den_box,
			13.0,
			{0.96, 0.97, 0.99, 1.0},
		)
		draw_wizard_button(l, text_atlas, "+", wl.btn_ts_den_inc, false, false)

		tp := wl.ts_preview
		draw_rect(l, tp.x, tp.y, tp.w, tp.h, {0.97, 0.96, 0.93, 1.0})
		draw_rect_outline(l, tp.x, tp.y, tp.w, tp.h, 1.0, {0.30, 0.32, 0.36, 1.0})
		p_space: f32 = 8.5
		p_top_y := tp.y + (tp.h - 4.0 * p_space) * 0.5
		for si in 0 ..< 5 {
			draw_rect(
				l,
				tp.x + 8.0,
				p_top_y + f32(si) * p_space,
				tp.w - 16.0,
				1.0,
				{0.20, 0.20, 0.22, 1.0},
			)
		}
		draw_time_sig(
			l,
			music_atlas,
			wiz.time_sig,
			tp.x + tp.w * 0.5 - 8.0,
			p_top_y + 0.5,
			p_space,
			p_space * 4.0,
			{0.08, 0.08, 0.08, 1.0},
		)

		draw_text(
			l,
			text_atlas,
			"Initial Measures",
			wl.btn_bars[0].x,
			wl.btn_bars[0].y - 6.0,
			12.0,
			label_col,
		)
		bar_labels := [4]string{"-4", "-1", "+1", "+4"}
		for i in 0 ..< 4 {
			draw_wizard_button(l, text_atlas, bar_labels[i], wl.btn_bars[i], false, false)
		}
		draw_rect(
			l,
			wl.bars_box.x,
			wl.bars_box.y,
			wl.bars_box.w,
			wl.bars_box.h,
			{0.12, 0.13, 0.16, 1.0},
		)
		draw_rect_outline(
			l,
			wl.bars_box.x,
			wl.bars_box.y,
			wl.bars_box.w,
			wl.bars_box.h,
			1.0,
			{0.28, 0.30, 0.35, 1.0},
		)
		mc_buf: [16]u8
		draw_text_centered(
			l,
			text_atlas,
			fmt.bprintf(mc_buf[:], "%d", wiz.measure_count),
			wl.bars_box,
			13.5,
			{0.96, 0.97, 0.99, 1.0},
		)

		fill_label :=
			wiz.fill_rests ? "[x] Fill Measures with Rests" : "[ ] Fill Measures with Rests"
		draw_wizard_button(l, text_atlas, fill_label, wl.btn_fill_rests, wiz.fill_rests, false)

		// Right column: Key Signature
		draw_text(
			l,
			text_atlas,
			"Key Signature",
			wl.btn_key_mode[0].x,
			wl.btn_key_mode[0].y - 6.0,
			12.0,
			label_col,
		)
		draw_wizard_button(l, text_atlas, "Major", wl.btn_key_mode[0], !wiz.is_minor, false)
		draw_wizard_button(l, text_atlas, "Minor", wl.btn_key_mode[1], wiz.is_minor, false)

		draw_wizard_button(l, text_atlas, "Flat (-)", wl.btn_key_flat, false, false)
		draw_rect(
			l,
			wl.key_name_box.x,
			wl.key_name_box.y,
			wl.key_name_box.w,
			wl.key_name_box.h,
			{0.12, 0.13, 0.16, 1.0},
		)
		draw_rect_outline(
			l,
			wl.key_name_box.x,
			wl.key_name_box.y,
			wl.key_name_box.w,
			wl.key_name_box.h,
			1.0,
			{0.28, 0.30, 0.35, 1.0},
		)
		draw_text_centered(
			l,
			text_atlas,
			utils.key_sig_name(wiz.fifths, wiz.is_minor),
			wl.key_name_box,
			12.5,
			{0.96, 0.97, 0.99, 1.0},
		)
		draw_wizard_button(l, text_atlas, "Sharp (+)", wl.btn_key_sharp, false, false)

		kp := wl.ks_preview
		draw_rect(l, kp.x, kp.y, kp.w, kp.h, {0.97, 0.96, 0.93, 1.0})
		draw_rect_outline(l, kp.x, kp.y, kp.w, kp.h, 1.0, {0.30, 0.32, 0.36, 1.0})
		preview_clef := utils.Clef.Treble
		if len(wiz.parts) > 0 && !wiz.parts[0].is_grand {
			preview_clef = wiz.parts[0].clef
		}
		k_space: f32 = 9.5
		k_em := k_space * 4.0
		k_staff_y := kp.y + (kp.h - 4.0 * k_space) * 0.5
		k_ink := [4]f32{0.08, 0.08, 0.08, 1.0}
		for si in 0 ..< 5 {
			draw_rect(l, kp.x + 16.0, k_staff_y + f32(si) * k_space, kp.w - 32.0, 1.2, k_ink)
		}
		k_cur_x := kp.x + 24.0
		draw_clef(l, music_atlas, preview_clef, k_cur_x, k_staff_y + 0.6, k_space, k_em, k_ink)
		k_cur_x +=
			utils.glyph_advance(music_atlas, utils.clef_glyph(preview_clef), k_em) + k_space * 0.9
		if wiz.fifths != 0 {
			draw_key_sig(
				l,
				music_atlas,
				preview_clef,
				wiz.fifths,
				k_cur_x,
				k_staff_y + 0.6,
				k_space,
				k_em,
				k_ink,
			)
		}
	}

	if wiz.can_cancel {
		draw_wizard_button(l, text_atlas, "Cancel", wl.btn_cancel, false, false)
	}
	if wiz.step != .Document {
		draw_wizard_button(l, text_atlas, "Back", wl.btn_back, false, false)
	}
	next_label := wiz.step == .Time_And_Key ? "Finish" : "Next"
	draw_wizard_button(l, text_atlas, next_label, wl.btn_next, false, true)
}

draw_overlay :: proc(
	l: ^utils.Layer,
	s: ^utils.Score,
	atlas: ^utils.Glyph_Atlas,
	sel: utils.Selection,
) {
	layout := utils.compute_score_layout(s, atlas)
	locked_sys: [utils.MAX_SYSTEMS]bool

	// Non-printing padlock icon outside the right margin for locked systems
	for sys_idx in 0 ..< layout.system_count {
		sys := layout.systems[sys_idx]
		if utils.is_system_locked(s, sys, layout.total_measures) {
			locked_sys[sys_idx] = true
			lx := s.page.margin_left + layout.staff_w + 8.0
			ly := sys.y + 2.0
			col := [4]f32{0.92, 0.66, 0.20, 0.92}
			draw_rect_outline(l, lx + 1.5, ly, 6.0, 4.5, 1.4, col)
			draw_rect(l, lx, ly + 3.5, 9.0, 5.5, col)
		}
	}

	// Non-printing break badges above individual unlocked measure boundaries
	for sys_idx in 0 ..< layout.system_count {
		sys := layout.systems[sys_idx]
		for m_idx in sys.start_measure ..< min(len(s.breaks), sys.end_measure) {
			if m_idx <= 0 {
				continue
			}
			brk := s.breaks[m_idx]
			if brk == .Auto {
				continue
			}
			if locked_sys[sys_idx] {
				continue
			}
			if brk == .Force_Next && sys_idx > 0 && locked_sys[sys_idx - 1] {
				continue
			}
			bx := sys.music_x0 + f32(m_idx - sys.start_measure) * sys.measure_w
			by := sys.y - layout.space * 2.2
			if brk == .Force_Next {
				col := [4]f32{0.22, 0.54, 0.96, 0.90}
				draw_rect(l, bx, by, 8.0, 2.0, col)
				draw_rect(l, bx + 6.0, by, 2.0, 6.5, col)
				draw_rect(l, bx + 4.0, by + 4.5, 6.0, 1.5, col)
			}
			else if brk == .Lock_Prev {
				col := [4]f32{0.92, 0.66, 0.20, 0.92}
				draw_rect(l, bx - 4.5, by + 2.5, 9.0, 4.5, col)
				draw_rect_outline(l, bx - 3.0, by - 1.0, 6.0, 4.5, 1.4, col)
			}
		}
	}

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
	sys, sys_ok := utils.find_system_for_measure(&layout, sel.measure_idx)
	if !sys_ok {
		return
	}

	flat_staff_idx := 0
	for p_i in 0 ..< sel.part_idx {
		flat_staff_idx += len(s.parts[p_i].staves)
	}
	flat_staff_idx += sel.staff_idx

	x := sys.music_x0 + f32(sel.measure_idx - sys.start_measure) * sys.measure_w
	y := sys.y + f32(flat_staff_idx) * layout.staff_step_y
	draw_rect(
		l,
		x,
		y - 4.0,
		sys.measure_w,
		layout.staff_h + 8.0,
		{0.20, 0.50, 0.95, 0.22},
	)
}

draw_ui :: proc(
	l: ^utils.Layer,
	s: ^utils.Score,
	fonts: ^utils.Fonts,
	tool: utils.Editor_Tool,
	sel: utils.Selection,
	win_w, win_h: f32,
) {
	atlas := &fonts.music
	text_atlas := &fonts.text
	layout := utils.compute_score_layout(s, atlas)

	draw_rect(l, 0, 0, win_w, utils.TOOLBAR_H, {0.14, 0.15, 0.17, 0.96})
	draw_rect(l, 0, utils.TOOLBAR_H, win_w, 1.0, {0.08, 0.08, 0.10, 1.0})

	bg_idle := [4]f32{0.20, 0.22, 0.25, 1.0}
	bg_active := [4]f32{0.22, 0.46, 0.82, 1.0}
	bg_armed := [4]f32{0.25, 0.32, 0.42, 1.0}
	fg_idle := [4]f32{0.82, 0.84, 0.88, 1.0}
	fg_dim := [4]f32{0.44, 0.46, 0.50, 1.0}
	fg_active := [4]f32{0.98, 0.99, 1.0, 1.0}
	divider_col := [4]f32{0.28, 0.30, 0.34, 1.0}

	// New Score / Setup Wizard button
	draw_rect(l, utils.BTN_NEW_X, utils.BTN_Y, utils.BTN_SIZE, utils.BTN_SIZE, bg_idle)
	npx := utils.BTN_NEW_X + 8.0
	npy := utils.BTN_Y + 6.0
	draw_rect_outline(l, npx, npy, 12.0, 16.0, 1.5, fg_idle)
	draw_rect(l, npx + 3.5, npy + 7.25, 5.0, 1.5, fg_idle)
	draw_rect(l, npx + 5.25, npy + 5.5, 1.5, 5.0, fg_idle)
	draw_rect(l, utils.BTN_NEW_X + utils.BTN_SIZE + 5.0, utils.BTN_Y + 4.0, 1.0, utils.BTN_SIZE - 8.0, divider_col)

	// Select Mode button
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
	draw_rect(l, utils.BTN_REST_X + utils.BTN_SIZE + 5.0, utils.BTN_Y + 4.0, 1.0, utils.BTN_SIZE - 8.0, divider_col)

	// 3 Accidental Override buttons
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
	draw_rect(l, utils.BTN_ACC_X0 + 2.0 * utils.BTN_STEP_X + utils.BTN_SIZE + 5.0, utils.BTN_Y + 4.0, 1.0, utils.BTN_SIZE - 8.0, divider_col)

	// Add / Remove Measure buttons
	total_bars := utils.measure_count(s)
	add_col := total_bars < 64 ? fg_idle : fg_dim
	draw_rect(l, utils.BTN_ADD_BAR_X, utils.BTN_Y, utils.BTN_SIZE, utils.BTN_SIZE, bg_idle)
	draw_rect(l, utils.BTN_ADD_BAR_X + 6.0, utils.BTN_Y + 7.0, 1.5, 14.0, add_col)
	draw_rect(l, utils.BTN_ADD_BAR_X + 20.5, utils.BTN_Y + 7.0, 1.5, 14.0, add_col)
	draw_rect(l, utils.BTN_ADD_BAR_X + 10.5, utils.BTN_Y + 13.25, 7.0, 1.5, add_col)
	draw_rect(l, utils.BTN_ADD_BAR_X + 13.25, utils.BTN_Y + 10.5, 1.5, 7.0, add_col)

	rem_col := total_bars > 1 ? fg_idle : fg_dim
	draw_rect(l, utils.BTN_REM_BAR_X, utils.BTN_Y, utils.BTN_SIZE, utils.BTN_SIZE, bg_idle)
	draw_rect(l, utils.BTN_REM_BAR_X + 6.0, utils.BTN_Y + 7.0, 1.5, 14.0, rem_col)
	draw_rect(l, utils.BTN_REM_BAR_X + 20.5, utils.BTN_Y + 7.0, 1.5, 14.0, rem_col)
	draw_rect(l, utils.BTN_REM_BAR_X + 10.5, utils.BTN_Y + 13.25, 7.0, 1.5, rem_col)
	draw_rect(l, utils.BTN_REM_BAR_X + utils.BTN_SIZE + 5.0, utils.BTN_Y + 4.0, 1.0, utils.BTN_SIZE - 8.0, divider_col)

	// Layout Management buttons: Push Down, Pull Up, Lock/Unlock System
	can_push := false
	can_pull := false
	sys_locked := false
	if sel.active {
		if sys, ok := utils.find_system_for_measure(&layout, sel.measure_idx); ok {
			can_push = sel.measure_idx > sys.start_measure
			can_pull = sel.measure_idx > 0 && sel.measure_idx == sys.start_measure
			sys_locked = utils.is_system_locked(s, sys, layout.total_measures)
		}
	}

	// Push Measure to Next Line (down arrow)
	draw_rect(l, utils.BTN_PUSH_DOWN_X, utils.BTN_Y, utils.BTN_SIZE, utils.BTN_SIZE, bg_idle)
	pd_col := can_push ? fg_idle : fg_dim
	pd_cx := utils.BTN_PUSH_DOWN_X + 14.0
	draw_rect(l, pd_cx - 1.0, utils.BTN_Y + 7.0, 2.0, 10.0, pd_col)
	draw_rect(l, pd_cx - 4.0, utils.BTN_Y + 14.0, 8.0, 1.5, pd_col)
	draw_rect(l, pd_cx - 2.5, utils.BTN_Y + 15.5, 5.0, 1.5, pd_col)
	draw_rect(l, pd_cx - 1.0, utils.BTN_Y + 17.0, 2.0, 1.5, pd_col)
	draw_rect(l, utils.BTN_PUSH_DOWN_X + 7.0, utils.BTN_Y + 20.5, 14.0, 1.5, pd_col)

	// Pull Measure to Previous Line (up arrow)
	draw_rect(l, utils.BTN_PULL_UP_X, utils.BTN_Y, utils.BTN_SIZE, utils.BTN_SIZE, bg_idle)
	pu_col := can_pull ? fg_idle : fg_dim
	pu_cx := utils.BTN_PULL_UP_X + 14.0
	draw_rect(l, utils.BTN_PULL_UP_X + 7.0, utils.BTN_Y + 6.0, 14.0, 1.5, pu_col)
	draw_rect(l, pu_cx - 1.0, utils.BTN_Y + 11.0, 2.0, 10.0, pu_col)
	draw_rect(l, pu_cx - 4.0, utils.BTN_Y + 12.5, 8.0, 1.5, pu_col)
	draw_rect(l, pu_cx - 2.5, utils.BTN_Y + 11.0, 5.0, 1.5, pu_col)
	draw_rect(l, pu_cx - 1.0, utils.BTN_Y + 9.5, 2.0, 1.5, pu_col)

	// Lock / Unlock System (padlock)
	lock_bg := (sel.active && sys_locked) ? bg_active : bg_idle
	lock_col := !sel.active ? fg_dim : (sys_locked ? fg_active : fg_idle)
	draw_rect(l, utils.BTN_LOCK_SYS_X, utils.BTN_Y, utils.BTN_SIZE, utils.BTN_SIZE, lock_bg)
	draw_rect_outline(l, utils.BTN_LOCK_SYS_X + 10.0, utils.BTN_Y + 7.0, 8.0, 6.5, 1.5, lock_col)
	draw_rect(l, utils.BTN_LOCK_SYS_X + 8.0, utils.BTN_Y + 12.5, 12.0, 8.5, lock_col)
	draw_rect(l, utils.BTN_LOCK_SYS_X + utils.BTN_SIZE + 5.0, utils.BTN_Y + 4.0, 1.0, utils.BTN_SIZE - 8.0, divider_col)

	// Export PDF button
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
	status_y := win_h - utils.STATUS_H
	draw_rect(l, 0, status_y, win_w, utils.STATUS_H, {0.14, 0.15, 0.17, 0.96})
	status_buf: [192]u8
	mode_str := tool.mode == .Select ? "Select" : "Note Entry"
	status_str: string
	if sel.active && sel.part_idx < len(s.parts) {
		lock_str := sys_locked ? " [Locked]" : ""
		status_str = fmt.bprintf(
			status_buf[:],
			"%s  |  Bar %d/%d (%s)%s  |  Down/Up: Move Line  |  L/U: Lock/Unlock",
			mode_str,
			sel.measure_idx + 1,
			total_bars,
			s.parts[sel.part_idx].name,
			lock_str,
		)
	}
	else {
		status_str = fmt.bprintf(
			status_buf[:],
			"%s  |  %d Bars, %d Pages  |  Ctrl+N: Wizard  |  Ctrl+=/Ctrl+-: Add/Del Bar",
			mode_str,
			total_bars,
			layout.page_count,
		)
	}
	by := utils.text_baseline_in_rect(text_atlas, status_y, utils.STATUS_H, 12.0)
	draw_text(l, text_atlas, status_str, 10.0, by, 12.0, {0.72, 0.75, 0.80, 1.0})
}
