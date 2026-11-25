package window

import "../utils"
import "core:fmt"
import gl "vendor:OpenGL"
import sdl "vendor:sdl2"

create :: proc(title: cstring, target_w, target_h, min_w, min_h: i32) -> (w: utils.Window, ok: bool) {
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
				case .E:
					key = .E
				case .P:
					key = .P
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
					button = utils.translate_mouse_button(ev.button.button),
					x      = ev.button.x,
					y      = ev.button.y,
				},
			)

		case .MOUSEBUTTONUP:
			append(
				&w.events,
				utils.Event_Mouse_Up {
					button = utils.translate_mouse_button(ev.button.button),
					x      = ev.button.x,
					y      = ev.button.y,
				},
			)

		case .MOUSEMOTION:
			append(
				&w.events,
				utils.Event_Mouse_Move {
					x  = ev.motion.x,
					y  = ev.motion.y,
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
