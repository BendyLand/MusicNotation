package main

import "score"
import "utils"
import win "window"

apply_wizard_result :: proc(
	s: ^utils.Score,
	cam: ^utils.Camera,
	sel: ^utils.Selection,
	wiz: ^utils.Wizard_State,
	win_w, win_h: f32,
) {
	score.destroy(s)
	s^ = score.from_wizard(wiz)
	score.save_score(s)
	sel^ = {}
	cam^ = utils.fit_camera_to_page(s.page, win_w, win_h)
	wiz.active = false
	wiz.focus = .None
}

handle_wizard_event :: proc(
	event: utils.Event,
	wiz: ^utils.Wizard_State,
	s: ^utils.Score,
	fonts: ^utils.Fonts,
	cam: ^utils.Camera,
	sel: ^utils.Selection,
	win_w, win_h: f32,
	running: ^bool,
) -> bool {
	#partial switch e in event {
	case utils.Event_Quit:
		running^ = false
		return false
	case utils.Event_Redraw:
		return true
	case utils.Event_Text_Input:
		return win.wizard_text_input(wiz, e)
	case utils.Event_Key_Down:
		switch win.wizard_key_down(wiz, e) {
		case .None:
			return false
		case .Redraw:
			return true
		case .Cancel:
			if wiz.can_cancel {
				wiz.active = false
				wiz.focus = .None
				wiz.selecting_text = false
				return true
			}
			running^ = false
			return false
		case .Finish:
			apply_wizard_result(s, cam, sel, wiz, win_w, win_h)
			return true
		}
	case utils.Event_Mouse_Down:
		if e.button == .Left {
			switch win.wizard_click(wiz, fonts, win_w, win_h, f32(e.x), f32(e.y)) {
			case .None:
				return false
			case .Redraw:
				return true
			case .Cancel:
				if wiz.can_cancel {
					wiz.active = false
					wiz.focus = .None
					wiz.selecting_text = false
					return true
				}
			case .Finish:
				apply_wizard_result(s, cam, sel, wiz, win_w, win_h)
				return true
			}
		}
	case utils.Event_Mouse_Move:
		return win.wizard_mouse_move(wiz, fonts, win_w, win_h, f32(e.x), f32(e.y))
	case utils.Event_Mouse_Up:
		if e.button == .Left {
			win.wizard_mouse_up(wiz)
		}
	case utils.Event_Mouse_Wheel:
		return win.wizard_scroll(wiz, e.dy)
	}
	return false
}
