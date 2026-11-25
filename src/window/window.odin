package window

import "core:fmt"
import gl "vendor:OpenGL"
import sdl "vendor:sdl2"

import "../utils"

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
	init_w, init_h := compute_initial_size(target_w, target_h, min_w, min_h)
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
	// Lock min size before mapping so the WM centers the full portrait frame instead of clamping it.
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
				case .TAB:
					key = .Tab
				case .BACKSPACE:
					key = .Backspace
				case .DELETE:
					key = .Delete
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
				case .R:
					key = .R
				case .S:
					key = .S
				case .N:
					key = .N
				case .MINUS:
					key = .Minus
				case .EQUALS:
					key = .Equals
				}
				append(&w.events, utils.Event_Key_Down{key = key, ctrl = ctrl_held()})
			}

		case .KEYUP:
			sc := ev.key.keysym.scancode
			if sc == .LCTRL || sc == .RCTRL {
				append(&w.events, utils.Event_Redraw{})
			}

		case .MOUSEBUTTONDOWN:
			append(
				&w.events,
				utils.Event_Mouse_Down {
					button = translate_mouse_button(ev.button.button),
					x = ev.button.x,
					y = ev.button.y,
				},
			)

		case .MOUSEBUTTONUP:
			append(
				&w.events,
				utils.Event_Mouse_Up {
					button = translate_mouse_button(ev.button.button),
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
translate_mouse_button :: proc(btn: u8) -> utils.Mouse_Button {
	switch btn {
	case sdl.BUTTON_LEFT:
		return .Left
	case sdl.BUTTON_MIDDLE:
		return .Middle
	case sdl.BUTTON_RIGHT:
		return .Right
	case:
		return .Unknown
	}
}

@(private = "file")
compute_initial_size :: proc(target_w, target_h, min_w, min_h: i32) -> (w, h: i32) {
	usable: sdl.Rect
	if sdl.GetDisplayUsableBounds(0, &usable) != 0 {
		return target_w, target_h
	}
	max_h := max(i32(min_h), usable.h - 80)
	max_w := max(i32(min_w), usable.w - 80)
	scale := min(f32(1.0), f32(max_h) / f32(target_h), f32(max_w) / f32(target_w))
	return i32(f32(target_w) * scale), i32(f32(target_h) * scale)
}

compute_score_layout :: proc(s: ^utils.Score, atlas: ^utils.Glyph_Atlas) -> utils.Score_Layout {
	page := s.page
	staff_w := page.width_pt - page.margin_left - page.margin_right
	space := page.staff_space_pt
	line_thick: f32 = max(0.6, space * 0.12)
	staff_h := 4.0 * space + line_thick
	total_measures := max(1, utils.measure_count(s))
	header_w := staff_header_width(s, atlas)
	music_x0 := page.margin_left + header_w
	measure_w := max(space * 4.0, (staff_w - header_w) / f32(total_measures))
	return utils.Score_Layout {
		staff_w = staff_w,
		space = space,
		line_thick = line_thick,
		staff_h = staff_h,
		staff_step_y = staff_h + space * 9.0,
		first_staff_y = page.margin_top + 48.0,
		total_measures = total_measures,
		header_w = header_w,
		music_x0 = music_x0,
		measure_w = measure_w,
	}
}

hit_test_measure :: proc(
	s: ^utils.Score,
	atlas: ^utils.Glyph_Atlas,
	world_pos: [2]f32,
) -> utils.Selection {
	layout := compute_score_layout(s, atlas)
	if world_pos.x < layout.music_x0 {
		return {}
	}
	m_idx := int((world_pos.x - layout.music_x0) / layout.measure_w)
	if m_idx < 0 || m_idx >= layout.total_measures {
		return {}
	}
	hit_pad_y := layout.space * 3.0
	staff_y := layout.first_staff_y
	for &part, p_idx in s.parts {
		for &staff, s_idx in part.staves {
			if m_idx < len(staff.measures) &&
			   world_pos.y >= staff_y - hit_pad_y &&
			   world_pos.y <= staff_y + layout.staff_h + hit_pad_y {
				return utils.Selection {
					active = true,
					part_idx = p_idx,
					staff_idx = s_idx,
					measure_idx = m_idx,
				}
			}
			staff_y += layout.staff_step_y
		}
	}
	return {}
}
