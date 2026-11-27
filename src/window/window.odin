package window

import "../utils"
import "core:fmt"
import gl "vendor:OpenGL"
import sdl "vendor:sdl2"

create :: proc(
	title: cstring,
	target_w, target_h, min_w, min_h: i32,
) -> (
	w: utils.Window,
	ok: bool,
) {
	if sdl.Init({.VIDEO}) != 0 {
		fmt.eprintfln("SDL_Init failed: %s", sdl.GetError())
		return {}, false
	}
	sdl.GL_SetAttribute(.CONTEXT_MAJOR_VERSION, 3)
	sdl.GL_SetAttribute(.CONTEXT_MINOR_VERSION, 3)
	sdl.GL_SetAttribute(.CONTEXT_PROFILE_MASK, i32(sdl.GLprofile.CORE))
	sdl.GL_SetAttribute(.CONTEXT_FLAGS, i32(sdl.GLcontextFlag.FORWARD_COMPATIBLE_FLAG))
	sdl.GL_SetAttribute(.DOUBLEBUFFER, 1)
	sdl.GL_SetAttribute(.MULTISAMPLEBUFFERS, 1)
	sdl.GL_SetAttribute(.MULTISAMPLESAMPLES, 4)
	init_w, init_h := utils.compute_initial_size(target_w, target_h, min_w, min_h)
	handle := sdl.CreateWindow(
		title,
		sdl.WINDOWPOS_CENTERED,
		sdl.WINDOWPOS_CENTERED,
		init_w,
		init_h,
		{.OPENGL, .RESIZABLE, .ALLOW_HIGHDPI, .HIDDEN},
	)
	if handle == nil {
		fmt.eprintfln("CreateWindow failed: %s", sdl.GetError())
		sdl.Quit()
		return {}, false
	}
	gl_ctx := sdl.GL_CreateContext(handle)
	if gl_ctx == nil {
		fmt.eprintfln("GL_CreateContext failed: %s", sdl.GetError())
		sdl.DestroyWindow(handle)
		sdl.Quit()
		return {}, false
	}
	sdl.GL_MakeCurrent(handle, gl_ctx)
	sdl.GL_SetSwapInterval(1)
	gl.load_up_to(3, 3, sdl.gl_set_proc_address)
	gl.Enable(gl.MULTISAMPLE)
	renderer, r_ok := renderer_init()
	if !r_ok {
		sdl.GL_DeleteContext(gl_ctx)
		sdl.DestroyWindow(handle)
		sdl.Quit()
		return {}, false
	}
	sdl.StopTextInput()
	sdl.SetWindowMinimumSize(handle, init_w, init_h)
	sdl.ShowWindow(handle)
	w.handle = handle
	w.gl_ctx = gl_ctx
	w.renderer = renderer
	w.min_w = min_w
	w.min_h = min_h
	sdl.GetWindowSize(handle, &w.win_w, &w.win_h)
	sdl.GL_GetDrawableSize(handle, &w.draw_w, &w.draw_h)
	return w, true
}

destroy :: proc(w: ^utils.Window) {
	if w.text_input_active {
		sdl.StopTextInput()
		w.text_input_active = false
	}
	sdl.ShowCursor(1)
	delete(w.events)
	renderer_destroy(&w.renderer)
	sdl.GL_DeleteContext(w.gl_ctx)
	sdl.DestroyWindow(w.handle)
	sdl.Quit()
}

ctrl_held :: proc() -> bool {
	return (sdl.GetModState() & sdl.KMOD_CTRL) != {}
}

shift_held :: proc() -> bool {
	return (sdl.GetModState() & sdl.KMOD_SHIFT) != {}
}

mouse_pos :: proc() -> [2]f32 {
	x, y: i32
	sdl.GetMouseState(&x, &y)
	return {f32(x), f32(y)}
}

set_cursor_visible :: proc(visible: bool) {
	target: i32 = visible ? 1 : 0
	if sdl.ShowCursor(-1) != target {
		sdl.ShowCursor(target)
	}
}

set_text_input :: proc(w: ^utils.Window, active: bool) {
	if w.text_input_active == active {
		return
	}
	w.text_input_active = active
	if active {
		sdl.StartTextInput()
	}
	else {
		sdl.StopTextInput()
	}
}

wait_events :: proc(w: ^utils.Window) -> ([]utils.Event, bool) {
	clear(&w.events)
	ev: sdl.Event
	if !sdl.WaitEvent(&ev) {
		return nil, false
	}
	for {
		#partial switch ev.type {
		case .QUIT:
			append(&w.events, utils.Event_Quit{})
		case .KEYDOWN:
			sc := ev.key.keysym.scancode
			if (sc == .LCTRL || sc == .RCTRL) && ev.key.repeat == 0 {
				append(&w.events, utils.Event_Redraw{})
			}
			else {
				key := utils.Key.Unknown
				#partial switch sc {
				case .ESCAPE:
					key = .Escape
				case .RETURN, .KP_ENTER:
					key = .Enter
				case .TAB:
					key = .Tab
				case .BACKSPACE:
					key = .Backspace
				case .DELETE:
					key = .Delete
				case .LEFT:
					key = .Left
				case .RIGHT:
					key = .Right
				case .UP:
					key = .Up
				case .DOWN:
					key = .Down
				case .HOME:
					key = .Home
				case .END:
					key = .End
				case .NUM0:
					key = .Num_0
				case .NUM1:
					key = .Num_1
				case .NUM2:
					key = .Num_2
				case .NUM3:
					key = .Num_3
				case .NUM4:
					key = .Num_4
				case .NUM5:
					key = .Num_5
				case .NUM6:
					key = .Num_6
				case .A:
					key = .A
				case .R:
					key = .R
				case .S:
					key = .S
				case .E:
					key = .E
				case .P:
					key = .P
				case .N:
					key = .N
				case .L:
					key = .L
				case .U:
					key = .U
				case .MINUS:
					key = .Minus
				case .EQUALS:
					key = .Equals
				}
				append(
					&w.events,
					utils.Event_Key_Down{key = key, ctrl = ctrl_held(), shift = shift_held()},
				)
			}
		case .KEYUP:
			sc := ev.key.keysym.scancode
			if sc == .LCTRL || sc == .RCTRL {
				append(&w.events, utils.Event_Redraw{})
			}
		case .TEXTINPUT:
			ti := utils.Event_Text_Input{}
			for i in 0 ..< len(ev.text.text) {
				b := u8(ev.text.text[i])
				if b == 0 {
					break
				}
				ti.text[i] = b
				ti.len = i + 1
			}
			if ti.len > 0 {
				append(&w.events, ti)
			}
		case .MOUSEBUTTONDOWN:
			append(
				&w.events,
				utils.Event_Mouse_Down {
					button = utils.translate_mouse_button(ev.button.button),
					x = ev.button.x,
					y = ev.button.y,
				},
			)
		case .MOUSEBUTTONUP:
			append(
				&w.events,
				utils.Event_Mouse_Up {
					button = utils.translate_mouse_button(ev.button.button),
					x = ev.button.x,
					y = ev.button.y,
				},
			)
		case .MOUSEMOTION:
			append(
				&w.events,
				utils.Event_Mouse_Move {
					x = ev.motion.x,
					y = ev.motion.y,
					dx = ev.motion.xrel,
					dy = ev.motion.yrel,
				},
			)
		case .MOUSEWHEEL:
			append(&w.events, utils.Event_Mouse_Wheel{dy = ev.wheel.y})
		case .WINDOWEVENT:
			#partial switch ev.window.event {
			case .EXPOSED, .FOCUS_GAINED:
				if !w.unlocked_min_size {
					sdl.SetWindowMinimumSize(w.handle, w.min_w, w.min_h)
					w.unlocked_min_size = true
				}
				append(&w.events, utils.Event_Redraw{})
			case .SIZE_CHANGED:
				w.win_w = ev.window.data1
				w.win_h = ev.window.data2
				sdl.GL_GetDrawableSize(w.handle, &w.draw_w, &w.draw_h)
				fmt.printfln(
					"Resized: %dx%d (drawable: %dx%d)",
					w.win_w,
					w.win_h,
					w.draw_w,
					w.draw_h,
				)
				append(&w.events, utils.Event_Redraw{})
			}
		}
		if !sdl.PollEvent(&ev) {
			break
		}
	}
	return w.events[:], true
}

toolbar_click :: proc(tool: ^utils.Editor_Tool, mx, my: f32) -> utils.Toolbar_Action {
	if my < utils.BTN_Y || my > utils.BTN_Y + utils.BTN_SIZE {
		return .None
	}
	if mx >= utils.BTN_NEW_X && mx <= utils.BTN_NEW_X + utils.BTN_SIZE {
		return .New_Score
	}
	if mx >= utils.BTN_SELECT_X && mx <= utils.BTN_SELECT_X + utils.BTN_SIZE {
		tool.mode = .Select
		return .Tool_Changed
	}
	for i in 0 ..< 6 {
		bx := utils.BTN_NOTES_X0 + f32(i) * utils.BTN_STEP_X
		if mx >= bx && mx <= bx + utils.BTN_SIZE {
			tool.mode = .Note_Entry
			tool.duration = utils.Note_Kind(i)
			return .Tool_Changed
		}
	}
	if mx >= utils.BTN_REST_X && mx <= utils.BTN_REST_X + utils.BTN_SIZE {
		if tool.mode == .Select {
			tool.mode = .Note_Entry
			tool.is_rest = true
		}
		else {
			tool.is_rest = !tool.is_rest
		}
		return .Tool_Changed
	}
	acc_modes := [3]utils.Accidental_Override{.Flat, .Natural, .Sharp}
	for mode, i in acc_modes {
		bx := utils.BTN_ACC_X0 + f32(i) * utils.BTN_STEP_X
		if mx >= bx && mx <= bx + utils.BTN_SIZE {
			utils.toggle_accidental(tool, mode)
			return .Tool_Changed
		}
	}
	if mx >= utils.BTN_ADD_BAR_X && mx <= utils.BTN_ADD_BAR_X + utils.BTN_SIZE {
		return .Add_Measure
	}
	if mx >= utils.BTN_REM_BAR_X && mx <= utils.BTN_REM_BAR_X + utils.BTN_SIZE {
		return .Remove_Measure
	}
	if mx >= utils.BTN_PUSH_DOWN_X && mx <= utils.BTN_PUSH_DOWN_X + utils.BTN_SIZE {
		return .Push_Measure_Down
	}
	if mx >= utils.BTN_PULL_UP_X && mx <= utils.BTN_PULL_UP_X + utils.BTN_SIZE {
		return .Pull_Measure_Up
	}
	if mx >= utils.BTN_LOCK_SYS_X && mx <= utils.BTN_LOCK_SYS_X + utils.BTN_SIZE {
		return .Toggle_System_Lock
	}
	if mx >= utils.BTN_EXPORT_X && mx <= utils.BTN_EXPORT_X + utils.BTN_SIZE {
		return .Export_Pdf
	}
	return .None
}

begin_frame :: proc(w: ^utils.Window, clear_color: [4]f32) {
	sdl.GL_GetDrawableSize(w.handle, &w.draw_w, &w.draw_h)
	sdl.GetWindowSize(w.handle, &w.win_w, &w.win_h)

	gl.Viewport(0, 0, w.draw_w, w.draw_h)
	gl.ClearColor(clear_color.r, clear_color.g, clear_color.b, clear_color.a)
	gl.Clear(gl.COLOR_BUFFER_BIT)

	renderer_begin_frame(&w.renderer)
}

end_frame :: proc(w: ^utils.Window, cam: utils.Camera) {
	renderer_flush(&w.renderer, cam, f32(w.win_w), f32(w.win_h))
	sdl.GL_SwapWindow(w.handle)
}

@(private = "file")
wizard_focused_rect :: proc(wl: utils.Wizard_Layout, focus: utils.Wizard_Field) -> (utils.Rect, bool) {
	switch focus {
	case .Title:
		return wl.field_title, true
	case .Subtitle:
		return wl.field_subtitle, true
	case .Composer:
		return wl.field_composer, true
	case .Part_Name:
		return wl.field_part_name, true
	case .None:
		return {}, false
	}
	return {}, false
}
 
wizard_mouse_move :: proc(
	wiz: ^utils.Wizard_State,
	fonts: ^utils.Fonts,
	win_w, win_h, mx, my: f32,
) -> bool {
	if !wiz.selecting_text {
		return false
	}
	// Safety check: if the left button was released outside the window, stop selecting.
	if (sdl.GetMouseState(nil, nil) & sdl.BUTTON_LMASK) == 0 {
		wiz.selecting_text = false
		return false
	}
	tb := utils.wizard_active_buf(wiz)
	if tb == nil {
		wiz.selecting_text = false
		return false
	}
	wl := compute_wizard_layout(win_w, win_h)
	r, ok := wizard_focused_rect(wl, wiz.focus)
	if !ok {
		return false
	}
	next_caret := utils.caret_from_click(&fonts.text, utils.text_buf_str(tb), r.x + 8.0, mx, 13.0)
	if next_caret != wiz.caret {
		wiz.caret = next_caret
		return true
	}
	return false
}

wizard_mouse_up :: proc(wiz: ^utils.Wizard_State) {
	wiz.selecting_text = false
}

wizard_text_input :: proc(wiz: ^utils.Wizard_State, e: utils.Event_Text_Input) -> bool {
	tb := utils.wizard_active_buf(wiz)
	if tb == nil || e.len <= 0 {
		return false
	}
	changed := false
	if lo, hi, has_sel := utils.wizard_sel_range(wiz, tb.len); has_sel {
		changed = utils.text_buf_delete_range(tb, lo, hi)
		wiz.caret = lo
		wiz.sel_anchor = lo
	}
	text := e.text
	if utils.text_buf_insert_ascii(tb, &wiz.caret, text[:e.len]) {
		wiz.sel_anchor = wiz.caret
		changed = true
	}
	return changed
}

wizard_scroll :: proc(wiz: ^utils.Wizard_State, dy: i32) -> bool {
	if dy == 0 {
		return false
	}
	if wiz.step == .Instruments && len(wiz.parts) > utils.WIZ_VISIBLE_PART_ROWS {
		max_scroll := len(wiz.parts) - utils.WIZ_VISIBLE_PART_ROWS
		next := clamp(wiz.part_scroll - int(dy), 0, max_scroll)
		if next != wiz.part_scroll {
			wiz.part_scroll = next
			return true
		}
	}
	else if wiz.step == .Open_File && len(wiz.open_files) > utils.WIZ_VISIBLE_FILE_ROWS {
		max_scroll := len(wiz.open_files) - utils.WIZ_VISIBLE_FILE_ROWS
		next := clamp(wiz.file_scroll - int(dy), 0, max_scroll)
		if next != wiz.file_scroll {
			wiz.file_scroll = next
			return true
		}
	}
	return false
}

wizard_click :: proc(
	wiz: ^utils.Wizard_State,
	fonts: ^utils.Fonts,
	win_w, win_h, mx, my: f32,
) -> utils.Wizard_Action {
	wl := compute_wizard_layout(win_w, win_h)
	text_atlas := &fonts.text
	wiz.selecting_text = false
	if utils.rect_contains(wl.btn_open_mode, mx, my) {
		if wiz.step == .Open_File {
			wiz.step = .Document
			utils.wizard_focus_field(wiz, .Title)
		}
		else {
			utils.wizard_refresh_files(wiz)
			wiz.step = .Open_File
			utils.wizard_focus_field(wiz, .None)
		}
		return .Redraw
	}
	if wiz.can_cancel && utils.rect_contains(wl.btn_cancel, mx, my) {
		return .Cancel
	}
	if (wiz.step == .Instruments || wiz.step == .Time_And_Key) && utils.rect_contains(wl.btn_back, mx, my) {
		if wiz.step == .Time_And_Key {
			wiz.step = .Instruments
			utils.wizard_focus_field(wiz, .None)
		}
		else {
			wiz.step = .Document
			utils.wizard_focus_field(wiz, .Title)
		}
		return .Redraw
	}
	if utils.rect_contains(wl.btn_next, mx, my) {
		switch wiz.step {
		case .Document:
			wiz.step = .Instruments
			utils.wizard_focus_field(wiz, .None)
			return .Redraw
		case .Instruments:
			wiz.step = .Time_And_Key
			utils.wizard_focus_field(wiz, .None)
			return .Redraw
		case .Time_And_Key:
			return .Finish
		case .Open_File:
			if wiz.selected_file >= 0 && wiz.selected_file < len(wiz.open_files) {
				return .Open_File
			}
			return .None
		}
	}
	switch wiz.step {
	case .Document:
		if utils.rect_contains(wl.field_title, mx, my) {
			next_caret := utils.caret_from_click(
				text_atlas,
				utils.text_buf_str(&wiz.title),
				wl.field_title.x + 8.0,
				mx,
				13.0,
			)
			if wiz.focus != .Title || !shift_held() {
				wiz.sel_anchor = next_caret
			}
			wiz.focus = .Title
			wiz.caret = next_caret
			wiz.selecting_text = true
			return .Redraw
		}
		if utils.rect_contains(wl.field_subtitle, mx, my) {
			next_caret := utils.caret_from_click(
				text_atlas,
				utils.text_buf_str(&wiz.subtitle),
				wl.field_subtitle.x + 8.0,
				mx,
				13.0,
			)
			if wiz.focus != .Subtitle || !shift_held() {
				wiz.sel_anchor = next_caret
			}
			wiz.focus = .Subtitle
			wiz.caret = next_caret
			wiz.selecting_text = true
			return .Redraw
		}
		if utils.rect_contains(wl.field_composer, mx, my) {
			next_caret := utils.caret_from_click(
				text_atlas,
				utils.text_buf_str(&wiz.composer),
				wl.field_composer.x + 8.0,
				mx,
				13.0,
			)
			if wiz.focus != .Composer || !shift_held() {
				wiz.sel_anchor = next_caret
			}
			wiz.focus = .Composer
			wiz.caret = next_caret
			wiz.selecting_text = true
			return .Redraw
		}
		for i in 0 ..< 3 {
			if utils.rect_contains(wl.btn_staff_size[i], mx, my) {
				wiz.staff_size = utils.Staff_Size_Preset(i)
				return .Redraw
			}
			if utils.rect_contains(wl.btn_page_size[i], mx, my) {
				wiz.page_size = utils.Page_Size_Preset(i)
				return .Redraw
			}
		}
		if utils.rect_contains(wl.btn_orient[0], mx, my) {
			wiz.landscape = false
			return .Redraw
		}
		if utils.rect_contains(wl.btn_orient[1], mx, my) {
			wiz.landscape = true
			return .Redraw
		}
	case .Instruments:
		for i in 0 ..< 5 {
			if utils.rect_contains(wl.btn_ensemble[i], mx, my) {
				utils.wizard_apply_ensemble(wiz, utils.Ensemble_Preset(i))
				return .Redraw
			}
		}
		if utils.rect_contains(wl.btn_add_part[0], mx, my) {
			if utils.wizard_add_part(wiz, "Treble", .Treble, false) {return .Redraw}
		}
		if utils.rect_contains(wl.btn_add_part[1], mx, my) {
			if utils.wizard_add_part(wiz, "Bass", .Bass, false) {return .Redraw}
		}
		if utils.rect_contains(wl.btn_add_part[2], mx, my) {
			if utils.wizard_add_part(wiz, "Alto", .Alto, false) {return .Redraw}
		}
		if utils.rect_contains(wl.btn_add_part[3], mx, my) {
			if utils.wizard_add_part(wiz, "Tenor", .Tenor, false) {return .Redraw}
		}
		if utils.rect_contains(wl.btn_add_part[4], mx, my) {
			if utils.wizard_add_part(wiz, "Piano", .Treble, true) {return .Redraw}
		}
		for vis_i in 0 ..< utils.WIZ_VISIBLE_PART_ROWS {
			p_idx := wiz.part_scroll + vis_i
			if p_idx >= len(wiz.parts) {
				break
			}
			if utils.rect_contains(wl.part_rows[vis_i], mx, my) {
				wiz.selected_part = p_idx
				if wiz.focus == .Part_Name {
					utils.wizard_focus_field(wiz, .Part_Name)
				}
				return .Redraw
			}
		}
		if utils.rect_contains(wl.btn_part_up, mx, my) {
			if wiz.selected_part > 0 && wiz.selected_part < len(wiz.parts) {
				wiz.parts[wiz.selected_part], wiz.parts[wiz.selected_part - 1] =
					wiz.parts[wiz.selected_part - 1], wiz.parts[wiz.selected_part]
				wiz.selected_part -= 1
				utils.wizard_clamp_scroll(wiz)
				return .Redraw
			}
		}
		if utils.rect_contains(wl.btn_part_down, mx, my) {
			if wiz.selected_part >= 0 && wiz.selected_part + 1 < len(wiz.parts) {
				wiz.parts[wiz.selected_part], wiz.parts[wiz.selected_part + 1] =
					wiz.parts[wiz.selected_part + 1], wiz.parts[wiz.selected_part]
				wiz.selected_part += 1
				utils.wizard_clamp_scroll(wiz)
				return .Redraw
			}
		}
		if utils.rect_contains(wl.btn_part_remove, mx, my) {
			if len(wiz.parts) > 1 && wiz.selected_part >= 0 && wiz.selected_part < len(wiz.parts) {
				ordered_remove(&wiz.parts, wiz.selected_part)
				utils.wizard_clamp_scroll(wiz)
				if wiz.focus == .Part_Name {
					utils.wizard_focus_field(wiz, .Part_Name)
				}
				return .Redraw
			}
		}
		if wiz.selected_part >= 0 && wiz.selected_part < len(wiz.parts) {
			sel_part := &wiz.parts[wiz.selected_part]
			if utils.rect_contains(wl.field_part_name, mx, my) {
				next_caret := utils.caret_from_click(
					text_atlas,
					utils.text_buf_str(&sel_part.name),
					wl.field_part_name.x + 8.0,
					mx,
					13.0,
				)
				if wiz.focus != .Part_Name || !shift_held() {
					wiz.sel_anchor = next_caret
				}
				wiz.focus = .Part_Name
				wiz.caret = next_caret
				wiz.selecting_text = true
				return .Redraw
			}
			for i in 0 ..< 5 {
				if utils.rect_contains(wl.btn_part_clef[i], mx, my) {
					if i == 4 {
						sel_part.is_grand = true
						sel_part.clef = .Treble
					}
					else {
						sel_part.is_grand = false
						sel_part.clef = utils.Clef(i)
					}
					return .Redraw
				}
			}
		}
	case .Time_And_Key:
		ts_presets := [6]utils.Rational{{4, 4}, {3, 4}, {2, 4}, {6, 8}, {2, 2}, {12, 8}}
		for ts, i in ts_presets {
			if utils.rect_contains(wl.btn_ts_preset[i], mx, my) {
				wiz.time_sig = ts
				return .Redraw
			}
		}
		if utils.rect_contains(wl.btn_ts_num_dec, mx, my) {
			wiz.time_sig.num = clamp(wiz.time_sig.num - 1, 1, 16)
			return .Redraw
		}
		if utils.rect_contains(wl.btn_ts_num_inc, mx, my) {
			wiz.time_sig.num = clamp(wiz.time_sig.num + 1, 1, 16)
			return .Redraw
		}
		if utils.rect_contains(wl.btn_ts_den_dec, mx, my) {
			wiz.time_sig.den = utils.step_beat_unit(wiz.time_sig.den, -1)
			return .Redraw
		}
		if utils.rect_contains(wl.btn_ts_den_inc, mx, my) {
			wiz.time_sig.den = utils.step_beat_unit(wiz.time_sig.den, 1)
			return .Redraw
		}
		bar_deltas := [4]int{-4, -1, 1, 4}
		for delta, i in bar_deltas {
			if utils.rect_contains(wl.btn_bars[i], mx, my) {
				wiz.measure_count = clamp(wiz.measure_count + delta, 1, 64)
				return .Redraw
			}
		}
		if utils.rect_contains(wl.btn_fill_rests, mx, my) {
			wiz.fill_rests = !wiz.fill_rests
			return .Redraw
		}
		if utils.rect_contains(wl.btn_key_mode[0], mx, my) {
			wiz.is_minor = false
			return .Redraw
		}
		if utils.rect_contains(wl.btn_key_mode[1], mx, my) {
			wiz.is_minor = true
			return .Redraw
		}
		if utils.rect_contains(wl.btn_key_flat, mx, my) {
			wiz.fifths = clamp(wiz.fifths - 1, -7, 7)
			return .Redraw
		}
		if utils.rect_contains(wl.btn_key_sharp, mx, my) {
			wiz.fifths = clamp(wiz.fifths + 1, -7, 7)
			return .Redraw
		}
	case .Open_File:
		for vis_i in 0 ..< utils.WIZ_VISIBLE_FILE_ROWS {
			f_idx := wiz.file_scroll + vis_i
			if f_idx >= len(wiz.open_files) {
				break
			}
			if utils.rect_contains(wl.file_rows[vis_i], mx, my) {
				wiz.selected_file = f_idx
				return .Redraw
			}
		}
	}
	if wiz.focus != .None {
		wiz.focus = .None
		return .Redraw
	}
	return .None
}

wizard_key_down :: proc(wiz: ^utils.Wizard_State, e: utils.Event_Key_Down) -> utils.Wizard_Action {
	if tb := utils.wizard_active_buf(wiz); tb != nil {
		if e.ctrl && e.key == .A {
			wiz.sel_anchor = 0
			wiz.caret = tb.len
			return .Redraw
		}
		#partial switch e.key {
		case .Backspace:
			if lo, hi, has_sel := utils.wizard_sel_range(wiz, tb.len); has_sel {
				utils.text_buf_delete_range(tb, lo, hi)
				wiz.caret = lo
				wiz.sel_anchor = lo
				return .Redraw
			}
			if utils.text_buf_backspace(tb, &wiz.caret, e.ctrl) {
				wiz.sel_anchor = wiz.caret
				return .Redraw
			}
			return .None
		case .Delete:
			if lo, hi, has_sel := utils.wizard_sel_range(wiz, tb.len); has_sel {
				utils.text_buf_delete_range(tb, lo, hi)
				wiz.caret = lo
				wiz.sel_anchor = lo
				return .Redraw
			}
			if utils.text_buf_delete(tb, &wiz.caret) {
				wiz.sel_anchor = wiz.caret
				return .Redraw
			}
			return .None
		case .Left:
			if e.shift {
				if wiz.caret > 0 {
					wiz.caret -= 1
					return .Redraw
				}
				return .None
			}
			if lo, _, has_sel := utils.wizard_sel_range(wiz, tb.len); has_sel {
				wiz.caret = lo
				wiz.sel_anchor = lo
				return .Redraw
			}
			if wiz.caret > 0 {
				wiz.caret -= 1
				wiz.sel_anchor = wiz.caret
				return .Redraw
			}
			return .None
		case .Right:
			if e.shift {
				if wiz.caret < tb.len {
					wiz.caret += 1
					return .Redraw
				}
				return .None
			}
			if _, hi, has_sel := utils.wizard_sel_range(wiz, tb.len); has_sel {
				wiz.caret = hi
				wiz.sel_anchor = hi
				return .Redraw
			}
			if wiz.caret < tb.len {
				wiz.caret += 1
				wiz.sel_anchor = wiz.caret
				return .Redraw
			}
			return .None
		case .Home:
			wiz.caret = 0
			if !e.shift {
				wiz.sel_anchor = 0
			}
			return .Redraw
		case .End:
			wiz.caret = tb.len
			if !e.shift {
				wiz.sel_anchor = tb.len
			}
			return .Redraw
		case .Tab:
			if wiz.step == .Document {
				if e.shift {
					switch wiz.focus {
					case .Title:
						utils.wizard_focus_field(wiz, .Composer)
					case .Subtitle:
						utils.wizard_focus_field(wiz, .Title)
					case .Composer:
						utils.wizard_focus_field(wiz, .Subtitle)
					case .None, .Part_Name:
						utils.wizard_focus_field(wiz, .Title)
					}
				}
				else {
					switch wiz.focus {
					case .Title:
						utils.wizard_focus_field(wiz, .Subtitle)
					case .Subtitle:
						utils.wizard_focus_field(wiz, .Composer)
					case .Composer:
						utils.wizard_focus_field(wiz, .Title)
					case .None, .Part_Name:
						utils.wizard_focus_field(wiz, .Title)
					}
				}
				return .Redraw
			}
		}
	}

	#partial switch e.key {
	case .Escape:
		return .Cancel
	case .Enter:
		switch wiz.step {
		case .Document:
			wiz.step = .Instruments
			utils.wizard_focus_field(wiz, .None)
			return .Redraw
		case .Instruments:
			wiz.step = .Time_And_Key
			utils.wizard_focus_field(wiz, .None)
			return .Redraw
		case .Time_And_Key:
			return .Finish
		case .Open_File:
			if wiz.selected_file >= 0 && wiz.selected_file < len(wiz.open_files) {
				return .Open_File
			}
			return .None
		}
	case .Up:
		if wiz.step == .Instruments && wiz.focus == .None && wiz.selected_part > 0 {
			wiz.selected_part -= 1
			utils.wizard_clamp_scroll(wiz)
			return .Redraw
		}
		if wiz.step == .Open_File && wiz.selected_file > 0 {
			wiz.selected_file -= 1
			utils.wizard_clamp_file_scroll(wiz)
			return .Redraw
		}
	case .Down:
		if wiz.step == .Instruments &&
		   wiz.focus == .None &&
		   wiz.selected_part + 1 < len(wiz.parts) {
			wiz.selected_part += 1
			utils.wizard_clamp_scroll(wiz)
			return .Redraw
		}
		if wiz.step == .Open_File && wiz.selected_file + 1 < len(wiz.open_files) {
			wiz.selected_file += 1
			utils.wizard_clamp_file_scroll(wiz)
			return .Redraw
		}
	}
	return .None
}
