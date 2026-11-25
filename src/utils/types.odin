package utils

import sdl "vendor:sdl2"

FORMAT_VERSION :: 2

MIN_WIDTH     :: 320
MIN_HEIGHT    :: 240
TARGET_WIDTH  :: 800
TARGET_HEIGHT :: 900

MAX_LAYERS  :: 32
ATLAS_SIZE  :: 1024
ATLAS_EM_PX :: f32(128.0)
TOOLBAR_H   :: f32(36.0)
STATUS_H    :: f32(24.0)

SCORE_PATH :: "demo.toml"
FONT_PATH  :: "Bravura.otf"

LAYER_PAGE    :: 0
LAYER_SCORE   :: 1
LAYER_OVERLAY :: 2
LAYER_UI      :: 3

// SMuFL codepoints (Bravura)
SMUFL_G_CLEF                  :: rune(0xE050)
SMUFL_C_CLEF                  :: rune(0xE05C)
SMUFL_F_CLEF                  :: rune(0xE062)
SMUFL_TIME_SIG_0              :: rune(0xE080)
SMUFL_NOTEHEAD_WHOLE          :: rune(0xE0A2)
SMUFL_NOTEHEAD_HALF           :: rune(0xE0A3)
SMUFL_NOTEHEAD_BLACK          :: rune(0xE0A4)
SMUFL_AUGMENTATION_DOT        :: rune(0xE1E7)
SMUFL_FLAG_8TH_UP             :: rune(0xE240)
SMUFL_FLAG_8TH_DOWN           :: rune(0xE241)
SMUFL_FLAG_16TH_UP            :: rune(0xE242)
SMUFL_FLAG_16TH_DOWN          :: rune(0xE243)
SMUFL_FLAG_32ND_UP            :: rune(0xE244)
SMUFL_FLAG_32ND_DOWN          :: rune(0xE245)
SMUFL_ACCIDENTAL_FLAT         :: rune(0xE260)
SMUFL_ACCIDENTAL_NATURAL      :: rune(0xE261)
SMUFL_ACCIDENTAL_SHARP        :: rune(0xE262)
SMUFL_ACCIDENTAL_DOUBLE_SHARP :: rune(0xE263)
SMUFL_ACCIDENTAL_DOUBLE_FLAT  :: rune(0xE264)
SMUFL_REST_WHOLE              :: rune(0xE4E3)
SMUFL_REST_HALF               :: rune(0xE4E4)
SMUFL_REST_QUARTER            :: rune(0xE4E5)
SMUFL_REST_8TH                :: rune(0xE4E6)
SMUFL_REST_16TH               :: rune(0xE4E7)
SMUFL_REST_32ND               :: rune(0xE4E8)

SMUFL_GLYPHS := [?]rune {
	SMUFL_G_CLEF,
	SMUFL_C_CLEF,
	SMUFL_F_CLEF,
	SMUFL_TIME_SIG_0 + 0,
	SMUFL_TIME_SIG_0 + 1,
	SMUFL_TIME_SIG_0 + 2,
	SMUFL_TIME_SIG_0 + 3,
	SMUFL_TIME_SIG_0 + 4,
	SMUFL_TIME_SIG_0 + 5,
	SMUFL_TIME_SIG_0 + 6,
	SMUFL_TIME_SIG_0 + 7,
	SMUFL_TIME_SIG_0 + 8,
	SMUFL_TIME_SIG_0 + 9,
	SMUFL_NOTEHEAD_WHOLE,
	SMUFL_NOTEHEAD_HALF,
	SMUFL_NOTEHEAD_BLACK,
	SMUFL_AUGMENTATION_DOT,
	SMUFL_FLAG_8TH_UP,
	SMUFL_FLAG_8TH_DOWN,
	SMUFL_FLAG_16TH_UP,
	SMUFL_FLAG_16TH_DOWN,
	SMUFL_FLAG_32ND_UP,
	SMUFL_FLAG_32ND_DOWN,
	SMUFL_ACCIDENTAL_FLAT,
	SMUFL_ACCIDENTAL_NATURAL,
	SMUFL_ACCIDENTAL_SHARP,
	SMUFL_ACCIDENTAL_DOUBLE_SHARP,
	SMUFL_ACCIDENTAL_DOUBLE_FLAT,
	SMUFL_REST_WHOLE,
	SMUFL_REST_HALF,
	SMUFL_REST_QUARTER,
	SMUFL_REST_8TH,
	SMUFL_REST_16TH,
	SMUFL_REST_32ND,
}

Note_Kind :: enum {
	Whole,
	Half,
	Quarter,
	Eighth,
	Sixteenth,
	Thirty_Second,
}

Rational :: struct {
	num: i32,
	den: i32,
}

Step :: enum {
	C,
	D,
	E,
	F,
	G,
	A,
	B,
}

Clef :: enum {
	Treble,
	Bass,
	Alto,
	Tenor,
}

Pitch :: struct {
	step:   Step,
	octave: i8,
	alter:  i8, // -2 = bb, -1 = b, 0 = natural, 1 = #, 2 = x
}

Note :: struct {
	pitch:     Pitch,
	tie_start: bool,
	tie_end:   bool,
}

// A single rhythmic slot in a voice. Empty `notes` array = Rest.
Entry :: struct {
	duration: Rational,
	notes:    [dynamic]Note,
}

Voice :: struct {
	entries: [dynamic]Entry,
}

Measure_Meta :: struct {
	time_sig: Rational, // e.g., {4, 4}
	key_sig:  i8,       // fifths: -7 (Cb) to +7 (C#)
}

Staff_Measure :: struct {
	meta:   Measure_Meta,
	voices: [dynamic]Voice,
}

Staff :: struct {
	clef:     Clef,
	measures: [dynamic]Staff_Measure,
}

Part :: struct {
	name:   string,
	staves: [dynamic]Staff,
}

Page_Setup :: struct {
	width_pt:       f32,
	height_pt:      f32,
	margin_top:     f32,
	margin_bottom:  f32,
	margin_left:    f32,
	margin_right:   f32,
	staff_space_pt: f32,
}

Score :: struct {
	version:  int,
	title:    string,
	composer: string,
	page:     Page_Setup,
	parts:    [dynamic]Part,
}

Bar_Accidental_State :: struct {
	active: [11][Step]i8,
}

Drag_State :: struct {
	panning:   bool,
	left_down: bool,
	press_pos: [2]i32,
	cur_pos:   [2]i32,
}

Selection :: struct {
	active:      bool,
	part_idx:    int,
	staff_idx:   int,
	measure_idx: int,
}

Edit_Mode :: enum {
	Select,
	Note_Entry,
}

Accidental_Override :: enum {
	None,
	Flat,
	Natural,
	Sharp,
}

Editor_Tool :: struct {
	mode:       Edit_Mode,
	duration:   Note_Kind,
	is_rest:    bool,
	accidental: Accidental_Override,
}

Note_Target_Kind :: enum {
	None,
	Append_Entry,
	Existing_Entry,
}

Note_Target :: struct {
	kind:          Note_Target_Kind,
	part_idx:      int,
	staff_idx:     int,
	measure_idx:   int,
	entry_idx:     int,
	cx:            f32,
	top_center_y:  f32,
	staff_step:    int,
	clef:          Clef,
	pitch:         Pitch,
	draw_acc:      bool,
	will_delete:   bool,
	effective_dur: Rational,
}

Score_Layout :: struct {
	staff_w:        f32,
	space:          f32,
	line_thick:     f32,
	staff_h:        f32,
	staff_step_y:   f32,
	first_staff_y:  f32,
	total_measures: int,
	header_w:       f32,
	music_x0:       f32,
	measure_w:      f32,
}

Layer_Space :: enum {
	World,
	Screen,
}

Vertex :: struct {
	pos:   [2]f32,
	uv:    [2]f32,
	color: [4]f32,
	mode:  f32, // 0.0 = solid geometry, 1.0 = alpha glyph
}

Camera :: struct {
	pos:  [2]f32, // World coordinate at the center of the viewport (in points)
	zoom: f32,    // Pixels per world unit
}

Glyph_Metrics :: struct {
	u0, v0, u1, v1: f32, // UV rect in atlas [0..1]
	x0, y0, x1, y1: f32, // Quad bounds relative to glyph origin in em units
	advance:        f32, // Horizontal advance in em units
}

Glyph_Atlas :: struct {
	tex:    u32,
	glyphs: map[rune]Glyph_Metrics,
}

Layer :: struct {
	space:     Layer_Space,
	visible:   bool,
	atlas_tex: u32,
	verts:     [dynamic]Vertex,
}

Renderer :: struct {
	program:     u32,
	vao:         u32,
	vbo:         u32,
	proj_loc:    i32,
	atlas_loc:   i32,
	layers:      [MAX_LAYERS]Layer,
	layer_count: int,
}

Key :: enum {
	Unknown,
	Escape,
	Tab,
	Backspace,
	Delete,
	Num_0,
	Num_1,
	Num_2,
	Num_3,
	Num_4,
	Num_5,
	Num_6,
	R,
	S,
	N,
	Minus,
	Equals,
}

Mouse_Button :: enum {
	Unknown,
	Left,
	Middle,
	Right,
}

Event_Quit :: struct {}
Event_Redraw :: struct {}

Event_Key_Down :: struct {
	key:  Key,
	ctrl: bool,
}

Event_Mouse_Down :: struct {
	button: Mouse_Button,
	x, y:   i32,
}

Event_Mouse_Up :: struct {
	button: Mouse_Button,
	x, y:   i32,
}

Event_Mouse_Move :: struct {
	x, y:   i32,
	dx, dy: i32,
}

Event_Mouse_Wheel :: struct {
	dy: i32,
}

Event :: union {
	Event_Quit,
	Event_Redraw,
	Event_Key_Down,
	Event_Mouse_Down,
	Event_Mouse_Up,
	Event_Mouse_Move,
	Event_Mouse_Wheel,
}

Window :: struct {
	handle:            ^sdl.Window,
	gl_ctx:            sdl.GLContext,
	renderer:          Renderer,
	min_w, min_h:      i32,
	win_w, win_h:      i32,
	draw_w, draw_h:    i32,
	unlocked_min_size: bool,
	events:            [dynamic]Event,
}

Scene :: struct {
	window: ^Window,
}


