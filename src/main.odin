package main

import "core:fmt"
import gl "vendor:OpenGL"
import sdl "vendor:sdl2"

TARGET_WIDTH :: 800
TARGET_HEIGHT :: 900
MIN_WIDTH :: 320
MIN_HEIGHT :: 240

main :: proc() {
	render_window(TARGET_WIDTH, TARGET_HEIGHT, MIN_WIDTH, MIN_HEIGHT)
}

render_window :: proc(target_width, target_height, min_width, min_height: i32) {
	if sdl.Init({.VIDEO}) != 0 {
		fmt.eprintfln("SDL_Init failed: %s", sdl.GetError())
		return
	}
	defer sdl.Quit()
	sdl.GL_SetAttribute(.CONTEXT_MAJOR_VERSION, 3)
	sdl.GL_SetAttribute(.CONTEXT_MINOR_VERSION, 3)
	sdl.GL_SetAttribute(.CONTEXT_PROFILE_MASK, i32(sdl.GLprofile.CORE))
	sdl.GL_SetAttribute(.CONTEXT_FLAGS, i32(sdl.GLcontextFlag.FORWARD_COMPATIBLE_FLAG))
	sdl.GL_SetAttribute(.DOUBLEBUFFER, 1)
	sdl.GL_SetAttribute(.MULTISAMPLEBUFFERS, 1)
	sdl.GL_SetAttribute(.MULTISAMPLESAMPLES, 4)
	init_w, init_h := compute_initial_size(target_width, target_height)
	window := sdl.CreateWindow(
		"Notation",
		sdl.WINDOWPOS_CENTERED,
		sdl.WINDOWPOS_CENTERED,
		init_w,
		init_h,
		{.OPENGL, .RESIZABLE, .ALLOW_HIGHDPI, .HIDDEN},
	)
	if window == nil {
		fmt.eprintfln("CreateWindow failed: %s", sdl.GetError())
		return
	}
	defer sdl.DestroyWindow(window)
	gl_ctx := sdl.GL_CreateContext(window)
	if gl_ctx == nil {
		fmt.eprintfln("GL_CreateContext failed: %s", sdl.GetError())
		return
	}
	defer sdl.GL_DeleteContext(gl_ctx)
	sdl.GL_MakeCurrent(window, gl_ctx)
	sdl.GL_SetSwapInterval(1)
	gl.load_up_to(3, 3, sdl.gl_set_proc_address)
	gl.Enable(gl.MULTISAMPLE)
	// Lock min size before mapping so the WM centers the full portrait frame instead of clamping it.
	sdl.SetWindowMinimumSize(window, init_w, init_h)
	sdl.ShowWindow(window)
	// Draw and swap the initial buffer immediately (required on Wayland to complete mapping).
	render_frame(window)
	unlocked_min_size := false
	running := true
	needs_redraw := false
	for running {
		event: sdl.Event
		if !sdl.WaitEvent(&event) {
			break
		}
		for {
			#partial switch event.type {
			case .QUIT:
				running = false
			case .KEYDOWN:
				if event.key.keysym.scancode == .ESCAPE {
					running = false
				}
				needs_redraw = true
			case .WINDOWEVENT:
				#partial switch event.window.event {
				case .EXPOSED, .FOCUS_GAINED:
					if !unlocked_min_size {
						sdl.SetWindowMinimumSize(window, min_width, min_height)
						unlocked_min_size = true
					}
					needs_redraw = true
				case .SIZE_CHANGED:
					drawable_w, drawable_h: i32
					sdl.GL_GetDrawableSize(window, &drawable_w, &drawable_h)
					fmt.printfln(
						"Resized: %dx%d (drawable: %dx%d)",
						event.window.data1,
						event.window.data2,
						drawable_w,
						drawable_h,
					)
					needs_redraw = true
				}
			case .MOUSEBUTTONDOWN, .MOUSEBUTTONUP, .MOUSEMOTION, .MOUSEWHEEL:
				needs_redraw = true
			}
			if !sdl.PollEvent(&event) {
				break
			}
		}
		if running && needs_redraw {
			render_frame(window)
			needs_redraw = false
		}
	}
}

compute_initial_size :: proc(target_w, target_h: i32) -> (w, h: i32) {
	usable: sdl.Rect
	if sdl.GetDisplayUsableBounds(0, &usable) != 0 {
		return target_w, target_h
	}

	// Leave room for OS panels/decorations if running on a smaller display, preserving aspect ratio.
	max_h := max(i32(MIN_HEIGHT), usable.h - 80)
	max_w := max(i32(MIN_WIDTH), usable.w - 80)

	scale := min(f32(1.0), f32(max_h) / f32(target_h), f32(max_w) / f32(target_w))
	return i32(f32(target_w) * scale), i32(f32(target_h) * scale)
}

render_frame :: proc(window: ^sdl.Window) {
	w, h: i32
	sdl.GL_GetDrawableSize(window, &w, &h)

	gl.Viewport(0, 0, w, h)
	gl.ClearColor(0.97, 0.96, 0.93, 1.0)
	gl.Clear(gl.COLOR_BUFFER_BIT)

	sdl.GL_SwapWindow(window)
}
