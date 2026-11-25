package main

import "core:fmt"
import "core:mem"

when ODIN_DEBUG {
	@(private = "file")
	debug_track: mem.Tracking_Allocator
}

track_leaks_init :: proc() -> mem.Allocator {
	when ODIN_DEBUG {
		mem.tracking_allocator_init(&debug_track, context.allocator)
		return mem.tracking_allocator(&debug_track)
	}
	else {
		return context.allocator
	}
}

track_leaks_finish :: proc() {
	when ODIN_DEBUG {
		if len(debug_track.allocation_map) > 0 {
			fmt.eprintfln("=== %v allocations not freed: ===", len(debug_track.allocation_map))
			for _, entry in debug_track.allocation_map {
				fmt.eprintfln("- %v bytes @ %v", entry.size, entry.location)
			}
		}
		if len(debug_track.bad_free_array) > 0 {
			fmt.eprintfln("=== %v incorrect frees: ===", len(debug_track.bad_free_array))
			for entry in debug_track.bad_free_array {
				fmt.eprintfln("- %p @ %v", entry.memory, entry.location)
			}
		}
		mem.tracking_allocator_destroy(&debug_track)
	}
}
