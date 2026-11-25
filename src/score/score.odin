package score

import "core:strings"

import "../utils"

make_demo :: proc() -> utils.Score {
	s := utils.Score {
		version  = utils.FORMAT_VERSION,
		title    = strings.clone("Demo Score"),
		composer = strings.clone("Anonymous"),
		page     = utils.default_page_setup(),
	}
	part := utils.Part {
		name = strings.clone("Piano"),
	}
	treble := utils.Staff {
		clef = .Treble,
	}
	for _ in 0 ..< 4 {
		append(
			&treble.measures,
			utils.Staff_Measure {
				meta = utils.Measure_Meta {
					time_sig = {4, 4},
					key_sig  = 0,
				},
			},
		)
	}
	append(&part.staves, treble)
	append(&s.parts, part)
	return s
}

