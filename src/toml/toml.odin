package toml

import "core:math"
import "core:mem"
import "core:os"
import "core:strconv"
import "core:strings"
import "core:unicode/utf8"

Table_Kind :: enum {
	Implicit, // Intermediate table created by [a.b] or [[a.b]] (can be explicitly opened later)
	Explicit, // Explicitly opened via [a] or [[a]] (cannot be re-opened)
	Dotted, // Intermediate table created by dotted key a.b = 1 (cannot be opened via [a])
	Inline, // Created via { ... } (completely immutable)
}

Date_Time_Kind :: enum {
	Offset_Date_Time,
	Local_Date_Time,
	Local_Date,
	Local_Time,
}

Date_Time :: struct {
	kind:           Date_Time_Kind,
	year:           i32,
	month:          u8,
	day:            u8,
	hour:           u8,
	minute:         u8,
	second:         u8,
	nanosecond:     u32,
	offset_minutes: i16, // Signed offset from UTC in minutes (for Offset_Date_Time)
}

Table :: struct {
	entries: map[string]Value,
	kind:    Table_Kind,
}

Array :: struct {
	items:          [dynamic]Value,
	is_table_array: bool,
}

Value :: union {
	string,
	i64,
	f64,
	bool,
	Date_Time,
	^Table,
	^Array,
}

Error :: struct {
	message: string,
	line:    int,
	col:     int,
}

@(private = "file")
Parser :: struct {
	src:       string,
	pos:       int,
	line:      int,
	col:       int,
	allocator: mem.Allocator,
	err:       Error,
	has_err:   bool,
}

parse :: proc(
	input: string,
	allocator := context.allocator,
) -> (
	root: ^Table,
	err: Error,
	ok: bool,
) {
	if !utf8.valid_string(input) {
		return nil, Error{message = "Invalid UTF-8 input", line = 1, col = 1}, false
	}

	p := Parser {
		src       = input,
		pos       = 0,
		line      = 1,
		col       = 1,
		allocator = allocator,
	}

	root = new(Table, allocator)
	root.entries = make(map[string]Value, allocator = allocator)
	root.kind = .Explicit

	cur_table := root

	for !eof(&p) {
		skip_ws(&p)
		if eof(&p) {
			break
		}

		ch := peek(&p)
		if ch == '#' {
			if !skip_comment(&p) {
				destroy(root, allocator)
				return nil, p.err, false
			}
			continue
		}
		if ch == '\n' || ch == '\r' {
			if !consume_newline(&p) {
				destroy(root, allocator)
				return nil, p.err, false
			}
			continue
		}

		if ch == '[' {
			next_table, header_ok := parse_table_header(&p, root)
			if !header_ok {
				destroy(root, allocator)
				return nil, p.err, false
			}
			cur_table = next_table
		} else {
			if !parse_key_value(&p, cur_table, false) {
				destroy(root, allocator)
				return nil, p.err, false
			}
		}

		if !expect_line_end(&p) {
			destroy(root, allocator)
			return nil, p.err, false
		}
	}

	return root, {}, true
}

parse_file :: proc(
	path: string,
	allocator := context.allocator,
) -> (
	root: ^Table,
	err: Error,
	ok: bool,
) {
	data, read_err := os.read_entire_file(path, allocator)
	if read_err != nil {
		return nil, Error{message = "Failed to read file", line = 0, col = 0}, false
	}
	defer delete(data, allocator)
	return parse(string(data), allocator)
}

destroy :: proc(t: ^Table, allocator := context.allocator) {
	if t == nil {
		return
	}
	for k, v in t.entries {
		delete(k, allocator)
		destroy_value(v, allocator)
	}
	delete(t.entries)
	free(t, allocator)
}

@(private = "file")
destroy_array :: proc(a: ^Array, allocator: mem.Allocator) {
	if a == nil {
		return
	}
	for v in a.items {
		destroy_value(v, allocator)
	}
	delete(a.items)
	free(a, allocator)
}

@(private = "file")
destroy_value :: proc(v: Value, allocator: mem.Allocator) {
	switch val in v {
	case string:
		delete(val, allocator)
	case ^Table:
		destroy(val, allocator)
	case ^Array:
		destroy_array(val, allocator)
	case i64, f64, bool, Date_Time:
	}
}

// ---------------------------------------------------------------------------
// Cursor & Error Helpers
// ---------------------------------------------------------------------------

@(private = "file")
eof :: proc(p: ^Parser) -> bool {
	return p.pos >= len(p.src)
}

@(private = "file")
peek :: proc(p: ^Parser) -> u8 {
	if p.pos >= len(p.src) {
		return 0
	}
	return p.src[p.pos]
}

@(private = "file")
peek_at :: proc(p: ^Parser, offset: int) -> u8 {
	idx := p.pos + offset
	if idx < 0 || idx >= len(p.src) {
		return 0
	}
	return p.src[idx]
}

@(private = "file")
advance :: proc(p: ^Parser) -> u8 {
	if p.pos >= len(p.src) {
		return 0
	}
	ch := p.src[p.pos]
	p.pos += 1
	if ch == '\n' {
		p.line += 1
		p.col = 1
	} else {
		p.col += 1
	}
	return ch
}

@(private = "file")
fail :: proc(p: ^Parser, msg: string) -> bool {
	if !p.has_err {
		p.err = Error {
			message = msg,
			line    = p.line,
			col     = p.col,
		}
		p.has_err = true
	}
	return false
}

@(private = "file")
skip_ws :: proc(p: ^Parser) {
	for !eof(p) {
		ch := peek(p)
		if ch == ' ' || ch == '\t' {
			advance(p)
		} else {
			break
		}
	}
}

@(private = "file")
consume_newline :: proc(p: ^Parser) -> bool {
	if peek(p) == '\r' {
		if peek_at(p, 1) != '\n' {
			return fail(p, "Bare carriage return is not allowed")
		}
		advance(p)
		advance(p)
		return true
	}
	if peek(p) == '\n' {
		advance(p)
		return true
	}
	return false
}

@(private = "file")
skip_comment :: proc(p: ^Parser) -> bool {
	if peek(p) != '#' {
		return true
	}
	advance(p)
	for !eof(p) {
		ch := peek(p)
		if ch == '\n' || ch == '\r' {
			return consume_newline(p)
		}
		if is_disallowed_control(ch) {
			return fail(p, "Control character not allowed in comment")
		}
		advance(p)
	}
	return true
}

@(private = "file")
skip_ws_and_newlines :: proc(p: ^Parser) -> bool {
	for !eof(p) {
		ch := peek(p)
		if ch == ' ' || ch == '\t' {
			advance(p)
		} else if ch == '\n' || ch == '\r' {
			if !consume_newline(p) {
				return false
			}
		} else if ch == '#' {
			if !skip_comment(p) {
				return false
			}
		} else {
			break
		}
	}
	return true
}

@(private = "file")
expect_line_end :: proc(p: ^Parser) -> bool {
	skip_ws(p)
	if eof(p) {
		return true
	}
	ch := peek(p)
	if ch == '#' {
		return skip_comment(p)
	}
	if ch == '\n' || ch == '\r' {
		return consume_newline(p)
	}
	return fail(p, "Expected end of line")
}

@(private = "file")
is_disallowed_control :: proc(ch: u8) -> bool {
	return (ch <= 0x08) || (ch >= 0x0A && ch <= 0x1F) || ch == 0x7F
}

@(private = "file")
is_bare_key_char :: proc(ch: u8) -> bool {
	return(
		(ch >= 'a' && ch <= 'z') ||
		(ch >= 'A' && ch <= 'Z') ||
		(ch >= '0' && ch <= '9') ||
		ch == '_' ||
		ch == '-' \
	)
}

@(private = "file")
is_digit :: proc(ch: u8) -> bool {
	return ch >= '0' && ch <= '9'
}

@(private = "file")
is_hex_digit :: proc(ch: u8) -> bool {
	return is_digit(ch) || (ch >= 'a' && ch <= 'f') || (ch >= 'A' && ch <= 'F')
}

// ---------------------------------------------------------------------------
// Tables & Key-Value Pairs
// ---------------------------------------------------------------------------

@(private = "file")
parse_table_header :: proc(p: ^Parser, root: ^Table) -> (^Table, bool) {
	advance(p) // consume '['
	is_array := false
	if peek(p) == '[' {
		is_array = true
		advance(p)
	}

	keys, keys_ok := parse_key_path(p)
	if !keys_ok {
		return nil, false
	}
	defer delete(keys)

	skip_ws(p)
	if peek(p) != ']' {
		free_key_slice(keys[:], p.allocator)
		fail(p, "Expected ']' to close table header")
		return nil, false
	}
	advance(p)
	if is_array {
		if peek(p) != ']' {
			free_key_slice(keys[:], p.allocator)
			fail(p, "Expected ']]' to close array of tables header")
			return nil, false
		}
		advance(p)
	}

	cur := root
	// Traverse intermediate segments
	for i in 0 ..< len(keys) - 1 {
		key := keys[i]
		existing, exists := cur.entries[key]
		if !exists {
			sub := new(Table, p.allocator)
			sub.entries = make(map[string]Value, allocator = p.allocator)
			sub.kind = .Implicit
			cur.entries[key] = sub
			cur = sub
		} else {
			delete(key, p.allocator)
			switch v in existing {
			case ^Table:
				if v.kind == .Inline {
					free_key_slice(keys[i + 1:], p.allocator)
					fail(p, "Cannot extend inline table")
					return nil, false
				}
				cur = v
			case ^Array:
				if !v.is_table_array || len(v.items) == 0 {
					free_key_slice(keys[i + 1:], p.allocator)
					fail(p, "Cannot index non-table array in header")
					return nil, false
				}
				last := v.items[len(v.items) - 1]
				tbl, is_tbl := last.(^Table)
				if !is_tbl {
					free_key_slice(keys[i + 1:], p.allocator)
					fail(p, "Expected table element in array of tables")
					return nil, false
				}
				cur = tbl
			case string, i64, f64, bool, Date_Time:
				free_key_slice(keys[i + 1:], p.allocator)
				fail(p, "Key is already defined as a non-table value")
				return nil, false
			}
		}
	}

	last_key := keys[len(keys) - 1]
	if is_array {
		existing, exists := cur.entries[last_key]
		arr: ^Array
		if !exists {
			arr = new(Array, p.allocator)
			arr.items = make([dynamic]Value, p.allocator)
			arr.is_table_array = true
			cur.entries[last_key] = arr
		} else {
			delete(last_key, p.allocator)
			a, is_arr := existing.(^Array)
			if !is_arr || !a.is_table_array {
				fail(p, "Cannot redefine existing key as array of tables")
				return nil, false
			}
			arr = a
		}
		elem := new(Table, p.allocator)
		elem.entries = make(map[string]Value, allocator = p.allocator)
		elem.kind = .Explicit
		append(&arr.items, elem)
		return elem, true
	}

	existing, exists := cur.entries[last_key]
	if !exists {
		tbl := new(Table, p.allocator)
		tbl.entries = make(map[string]Value, allocator = p.allocator)
		tbl.kind = .Explicit
		cur.entries[last_key] = tbl
		return tbl, true
	}

	delete(last_key, p.allocator)
	tbl, is_tbl := existing.(^Table)
	if !is_tbl {
		fail(p, "Cannot redefine existing value as table")
		return nil, false
	}
	if tbl.kind != .Implicit {
		fail(p, "Cannot redefine table")
		return nil, false
	}
	tbl.kind = .Explicit
	return tbl, true
}

@(private = "file")
parse_key_value :: proc(p: ^Parser, table: ^Table, in_inline: bool) -> bool {
	keys, keys_ok := parse_key_path(p)
	if !keys_ok {
		return false
	}
	defer delete(keys)

	skip_ws(p)
	if peek(p) != '=' {
		free_key_slice(keys[:], p.allocator)
		return fail(p, "Expected '=' after key")
	}
	advance(p)
	skip_ws(p)

	val, val_ok := parse_value(p)
	if !val_ok {
		free_key_slice(keys[:], p.allocator)
		return false
	}

	cur := table
	for i in 0 ..< len(keys) - 1 {
		key := keys[i]
		existing, exists := cur.entries[key]
		if !exists {
			sub := new(Table, p.allocator)
			sub.entries = make(map[string]Value, allocator = p.allocator)
			sub.kind = .Dotted
			cur.entries[key] = sub
			cur = sub
		} else {
			delete(key, p.allocator)
			sub, is_tbl := existing.(^Table)
			if !is_tbl {
				destroy_value(val, p.allocator)
				free_key_slice(keys[i + 1:], p.allocator)
				return fail(p, "Cannot traverse non-table with dotted key")
			}
			if sub.kind != .Dotted {
				destroy_value(val, p.allocator)
				free_key_slice(keys[i + 1:], p.allocator)
				return fail(p, "Cannot add dotted key to already-defined table")
			}
			cur = sub
		}
	}

	last_key := keys[len(keys) - 1]
	if last_key in cur.entries {
		delete(last_key, p.allocator)
		destroy_value(val, p.allocator)
		return fail(p, "Duplicate key")
	}

	if in_inline {
		if tbl, is_tbl := val.(^Table); is_tbl {
			mark_table_inline(tbl)
		}
	}

	cur.entries[last_key] = val
	return true
}

@(private = "file")
mark_table_inline :: proc(t: ^Table) {
	t.kind = .Inline
	for _, v in t.entries {
		if sub, ok := v.(^Table); ok {
			mark_table_inline(sub)
		}
	}
}

@(private = "file")
free_key_slice :: proc(keys: []string, allocator: mem.Allocator) {
	for k in keys {
		delete(k, allocator)
	}
}

@(private = "file")
parse_key_path :: proc(p: ^Parser) -> (keys: [dynamic]string, ok: bool) {
	keys = make([dynamic]string, p.allocator)
	success := false
	defer if !success {
		free_key_slice(keys[:], p.allocator)
		delete(keys)
	}

	for {
		skip_ws(p)
		seg, seg_ok := parse_key_segment(p)
		if !seg_ok {
			return nil, false
		}
		append(&keys, seg)

		skip_ws(p)
		if peek(p) == '.' {
			advance(p)
			continue
		}
		break
	}

	success = true
	return keys, true
}

@(private = "file")
parse_key_segment :: proc(p: ^Parser) -> (string, bool) {
	ch := peek(p)
	if ch == '"' {
		if peek_at(p, 1) == '"' && peek_at(p, 2) == '"' {
			fail(p, "Multiline basic string cannot be used as a key")
			return "", false
		}
		return parse_basic_string(p)
	}
	if ch == '\'' {
		if peek_at(p, 1) == '\'' && peek_at(p, 2) == '\'' {
			fail(p, "Multiline literal string cannot be used as a key")
			return "", false
		}
		return parse_literal_string(p)
	}
	start := p.pos
	for !eof(p) && is_bare_key_char(peek(p)) {
		advance(p)
	}
	if p.pos == start {
		fail(p, "Expected key")
		return "", false
	}
	return strings.clone(p.src[start:p.pos], p.allocator), true
}

// ---------------------------------------------------------------------------
// Values
// ---------------------------------------------------------------------------

@(private = "file")
parse_value :: proc(p: ^Parser) -> (Value, bool) {
	if eof(p) {
		fail(p, "Expected value")
		return nil, false
	}

	ch := peek(p)
	switch ch {
	case '"':
		if peek_at(p, 1) == '"' && peek_at(p, 2) == '"' {
			s, ok := parse_ml_basic_string(p)
			return s, ok
		}
		s, ok := parse_basic_string(p)
		return s, ok

	case '\'':
		if peek_at(p, 1) == '\'' && peek_at(p, 2) == '\'' {
			s, ok := parse_ml_literal_string(p)
			return s, ok
		}
		s, ok := parse_literal_string(p)
		return s, ok

	case '[':
		return parse_array(p)

	case '{':
		return parse_inline_table(p)

	case 't':
		if strings.has_prefix(p.src[p.pos:], "true") && is_value_delim(peek_at(p, 4)) {
			for _ in 0 ..< 4 {advance(p)}
			return true, true
		}
		fail(p, "Invalid value")
		return nil, false

	case 'f':
		if strings.has_prefix(p.src[p.pos:], "false") && is_value_delim(peek_at(p, 5)) {
			for _ in 0 ..< 5 {advance(p)}
			return false, true
		}
		fail(p, "Invalid value")
		return nil, false

	case 'i', 'n', '+', '-':
		return parse_number(p)

	case '0' ..= '9':
		if looks_like_date(p) || looks_like_time(p) {
			dt, ok := parse_datetime(p)
			return dt, ok
		}
		return parse_number(p)
	}

	fail(p, "Unexpected character in value")
	return nil, false
}

@(private = "file")
is_value_delim :: proc(ch: u8) -> bool {
	return(
		ch == 0 ||
		ch == ' ' ||
		ch == '\t' ||
		ch == '\n' ||
		ch == '\r' ||
		ch == '#' ||
		ch == ',' ||
		ch == ']' ||
		ch == '}' \
	)
}

// ---------------------------------------------------------------------------
// Strings
// ---------------------------------------------------------------------------

@(private = "file")
parse_basic_string :: proc(p: ^Parser) -> (string, bool) {
	advance(p) // consume '"'
	b := strings.builder_make(p.allocator)
	success := false
	defer if !success {strings.builder_destroy(&b)}

	for !eof(p) {
		ch := peek(p)
		if ch == '"' {
			advance(p)
			success = true
			return strings.to_string(b), true
		}
		if ch == '\\' {
			advance(p)
			if !parse_escape(p, &b) {
				return "", false
			}
			continue
		}
		if ch == '\n' || ch == '\r' || is_disallowed_control(ch) {
			fail(p, "Invalid character in basic string")
			return "", false
		}
		strings.write_byte(&b, advance(p))
	}

	fail(p, "Unterminated basic string")
	return "", false
}

@(private = "file")
parse_ml_basic_string :: proc(p: ^Parser) -> (string, bool) {
	advance(p); advance(p); advance(p) // consume '"""'
	if peek(p) == '\n' || peek(p) == '\r' {
		if !consume_newline(p) {
			return "", false
		}
	}

	b := strings.builder_make(p.allocator)
	success := false
	defer if !success {strings.builder_destroy(&b)}

	for !eof(p) {
		ch := peek(p)
		if ch == '"' {
			quotes := 0
			for peek_at(p, quotes) == '"' {
				quotes += 1
			}
			if quotes >= 3 {
				if quotes > 5 {
					fail(p, "Too many consecutive quotes in multiline basic string")
					return "", false
				}
				for _ in 0 ..< quotes - 3 {
					strings.write_byte(&b, '"')
				}
				for _ in 0 ..< quotes {
					advance(p)
				}
				success = true
				return strings.to_string(b), true
			}
			for _ in 0 ..< quotes {
				strings.write_byte(&b, advance(p))
			}
			continue
		}
		if ch == '\\' {
			advance(p)
			// Line-ending backslash trims trailing horizontal whitespace + newlines
			if peek(p) == ' ' || peek(p) == '\t' || peek(p) == '\n' || peek(p) == '\r' {
				skip_ws(p)
				if !(peek(p) == '\n' || peek(p) == '\r') {
					fail(p, "Invalid line-ending backslash in multiline string")
					return "", false
				}
				for !eof(p) {
					c := peek(p)
					if c == ' ' || c == '\t' {
						advance(p)
					} else if c == '\n' || c == '\r' {
						if !consume_newline(p) {
							return "", false
						}
					} else {
						break
					}
				}
				continue
			}
			if !parse_escape(p, &b) {
				return "", false
			}
			continue
		}
		if ch == '\r' {
			if !consume_newline(p) {
				return "", false
			}
			strings.write_byte(&b, '\n')
			continue
		}
		if ch == '\n' {
			strings.write_byte(&b, advance(p))
			continue
		}
		if is_disallowed_control(ch) {
			fail(p, "Control character not allowed in multiline basic string")
			return "", false
		}
		strings.write_byte(&b, advance(p))
	}

	fail(p, "Unterminated multiline basic string")
	return "", false
}

@(private = "file")
parse_escape :: proc(p: ^Parser, b: ^strings.Builder) -> bool {
	if eof(p) {
		return fail(p, "Unexpected EOF in escape sequence")
	}
	ch := advance(p)
	switch ch {
	case 'b':
		strings.write_byte(b, '\b')
	case 't':
		strings.write_byte(b, '\t')
	case 'n':
		strings.write_byte(b, '\n')
	case 'f':
		strings.write_byte(b, '\f')
	case 'r':
		strings.write_byte(b, '\r')
	case '"':
		strings.write_byte(b, '"')
	case '\\':
		strings.write_byte(b, '\\')
	case 'u':
		return parse_unicode_escape(p, b, 4)
	case 'U':
		return parse_unicode_escape(p, b, 8)
	case:
		return fail(p, "Invalid escape sequence")
	}
	return true
}

@(private = "file")
parse_unicode_escape :: proc(p: ^Parser, b: ^strings.Builder, digits: int) -> bool {
	val: u32 = 0
	for _ in 0 ..< digits {
		if eof(p) || !is_hex_digit(peek(p)) {
			return fail(p, "Invalid unicode escape sequence")
		}
		c := advance(p)
		d: u32
		switch c {
		case '0' ..= '9':
			d = u32(c - '0')
		case 'a' ..= 'f':
			d = u32(c - 'a' + 10)
		case 'A' ..= 'F':
			d = u32(c - 'A' + 10)
		}
		val = (val << 4) | d
	}
	if val > 0x10FFFF || (val >= 0xD800 && val <= 0xDFFF) {
		return fail(p, "Unicode escape is not a valid scalar value")
	}
	strings.write_rune(b, rune(val))
	return true
}

@(private = "file")
parse_literal_string :: proc(p: ^Parser) -> (string, bool) {
	advance(p) // consume '\''
	start := p.pos
	for !eof(p) {
		ch := peek(p)
		if ch == '\'' {
			s := strings.clone(p.src[start:p.pos], p.allocator)
			advance(p)
			return s, true
		}
		if ch == '\n' || ch == '\r' || is_disallowed_control(ch) {
			fail(p, "Invalid character in literal string")
			return "", false
		}
		advance(p)
	}
	fail(p, "Unterminated literal string")
	return "", false
}

@(private = "file")
parse_ml_literal_string :: proc(p: ^Parser) -> (string, bool) {
	advance(p); advance(p); advance(p) // consume "'''"
	if peek(p) == '\n' || peek(p) == '\r' {
		if !consume_newline(p) {
			return "", false
		}
	}

	b := strings.builder_make(p.allocator)
	success := false
	defer if !success {strings.builder_destroy(&b)}

	for !eof(p) {
		ch := peek(p)
		if ch == '\'' {
			quotes := 0
			for peek_at(p, quotes) == '\'' {
				quotes += 1
			}
			if quotes >= 3 {
				if quotes > 5 {
					fail(p, "Too many consecutive quotes in multiline literal string")
					return "", false
				}
				for _ in 0 ..< quotes - 3 {
					strings.write_byte(&b, '\'')
				}
				for _ in 0 ..< quotes {
					advance(p)
				}
				success = true
				return strings.to_string(b), true
			}
			for _ in 0 ..< quotes {
				strings.write_byte(&b, advance(p))
			}
			continue
		}
		if ch == '\r' {
			if !consume_newline(p) {
				return "", false
			}
			strings.write_byte(&b, '\n')
			continue
		}
		if ch == '\n' {
			strings.write_byte(&b, advance(p))
			continue
		}
		if is_disallowed_control(ch) {
			fail(p, "Control character not allowed in multiline literal string")
			return "", false
		}
		strings.write_byte(&b, advance(p))
	}

	fail(p, "Unterminated multiline literal string")
	return "", false
}

// ---------------------------------------------------------------------------
// Arrays & Inline Tables
// ---------------------------------------------------------------------------

@(private = "file")
parse_array :: proc(p: ^Parser) -> (^Array, bool) {
	advance(p) // consume '['
	arr := new(Array, p.allocator)
	arr.items = make([dynamic]Value, p.allocator)
	success := false
	defer if !success {destroy_array(arr, p.allocator)}

	for {
		if !skip_ws_and_newlines(p) {
			return nil, false
		}
		if eof(p) {
			fail(p, "Unterminated array")
			return nil, false
		}
		if peek(p) == ']' {
			advance(p)
			success = true
			return arr, true
		}

		val, val_ok := parse_value(p)
		if !val_ok {
			return nil, false
		}
		append(&arr.items, val)

		if !skip_ws_and_newlines(p) {
			return nil, false
		}
		if peek(p) == ',' {
			advance(p)
			continue
		}
		if peek(p) == ']' {
			advance(p)
			success = true
			return arr, true
		}
		fail(p, "Expected ',' or ']' in array")
		return nil, false
	}
}

@(private = "file")
parse_inline_table :: proc(p: ^Parser) -> (^Table, bool) {
	advance(p) // consume '{'
	tbl := new(Table, p.allocator)
	tbl.entries = make(map[string]Value, allocator = p.allocator)
	tbl.kind = .Explicit
	success := false
	defer if !success {destroy(tbl, p.allocator)}

	skip_ws(p)
	if peek(p) == '}' {
		advance(p)
		tbl.kind = .Inline
		success = true
		return tbl, true
	}

	for {
		skip_ws(p)
		if eof(p) || peek(p) == '\n' || peek(p) == '\r' {
			fail(p, "Inline table cannot contain newlines")
			return nil, false
		}
		if !parse_key_value(p, tbl, true) {
			return nil, false
		}
		skip_ws(p)
		if peek(p) == ',' {
			advance(p)
			skip_ws(p)
			if peek(p) == '}' {
				fail(p, "Trailing comma not allowed in inline table")
				return nil, false
			}
			continue
		}
		if peek(p) == '}' {
			advance(p)
			mark_table_inline(tbl)
			success = true
			return tbl, true
		}
		fail(p, "Expected ',' or '}' in inline table")
		return nil, false
	}
}

// ---------------------------------------------------------------------------
// Numbers (Integers & Floats)
// ---------------------------------------------------------------------------

@(private = "file")
parse_number :: proc(p: ^Parser) -> (Value, bool) {
	start := p.pos
	for !eof(p) && !is_value_delim(peek(p)) {
		advance(p)
	}
	raw := p.src[start:p.pos]
	if len(raw) == 0 {
		fail(p, "Expected number")
		return nil, false
	}

	// Special floats
	switch raw {
	case "inf", "+inf":
		return math.inf_f64(1), true
	case "-inf":
		return math.inf_f64(-1), true
	case "nan", "+nan":
		return math.nan_f64(), true
	case "-nan":
		return -math.nan_f64(), true
	}

	// Prefixed integers: 0x, 0o, 0b (no sign allowed)
	if len(raw) >= 2 && raw[0] == '0' && (raw[1] == 'x' || raw[1] == 'o' || raw[1] == 'b') {
		base: int
		switch raw[1] {
		case 'x':
			base = 16
		case 'o':
			base = 8
		case 'b':
			base = 2
		}
		digits := raw[2:]
		clean, ok := clean_digits(digits, base)
		if !ok {
			fail(p, "Invalid prefixed integer")
			return nil, false
		}
		defer delete(clean)
		v, parsed := strconv.parse_i64_of_base(clean, base)
		if !parsed {
			fail(p, "Integer out of 64-bit range")
			return nil, false
		}
		return v, true
	}

	// Determine if float (contains '.' or 'e'/'E')
	is_float := false
	for i in 0 ..< len(raw) {
		if raw[i] == '.' || raw[i] == 'e' || raw[i] == 'E' {
			is_float = true
			break
		}
	}

	if is_float {
		clean, ok := validate_and_clean_float(raw)
		if !ok {
			fail(p, "Invalid float literal")
			return nil, false
		}
		defer delete(clean)
		v, parsed := strconv.parse_f64(clean)
		if !parsed {
			fail(p, "Float out of range")
			return nil, false
		}
		return v, true
	}

	// Decimal integer
	clean, ok := validate_and_clean_dec_int(raw)
	if !ok {
		fail(p, "Invalid integer literal")
		return nil, false
	}
	defer delete(clean)
	v, parsed := strconv.parse_i64_of_base(clean, 10)
	if !parsed {
		fail(p, "Integer out of 64-bit range")
		return nil, false
	}
	return v, true
}

@(private = "file")
clean_digits :: proc(s: string, base: int) -> (string, bool) {
	if len(s) == 0 || s[0] == '_' || s[len(s) - 1] == '_' {
		return "", false
	}
	b := strings.builder_make()
	prev_under := false
	for i in 0 ..< len(s) {
		ch := s[i]
		if ch == '_' {
			if prev_under {
				strings.builder_destroy(&b)
				return "", false
			}
			prev_under = true
			continue
		}
		prev_under = false
		valid := false
		switch base {
		case 2:
			valid = ch == '0' || ch == '1'
		case 8:
			valid = ch >= '0' && ch <= '7'
		case 10:
			valid = is_digit(ch)
		case 16:
			valid = is_hex_digit(ch)
		}
		if !valid {
			strings.builder_destroy(&b)
			return "", false
		}
		strings.write_byte(&b, ch)
	}
	return strings.to_string(b), true
}

@(private = "file")
validate_and_clean_dec_int :: proc(raw: string) -> (string, bool) {
	s := raw
	sign: u8 = 0
	if s[0] == '+' || s[0] == '-' {
		sign = s[0]
		s = s[1:]
	}
	if len(s) == 0 {
		return "", false
	}
	// Leading zero forbidden unless single '0'
	if s[0] == '0' && len(s) > 1 {
		return "", false
	}
	digits, ok := clean_digits(s, 10)
	if !ok {
		return "", false
	}
	if sign == '-' {
		res := strings.concatenate({"-", digits})
		delete(digits)
		return res, true
	}
	return digits, true
}

@(private = "file")
validate_and_clean_float :: proc(raw: string) -> (string, bool) {
	s := raw
	b := strings.builder_make()
	success := false
	defer if !success {strings.builder_destroy(&b)}

	if s[0] == '+' || s[0] == '-' {
		if s[0] == '-' {
			strings.write_byte(&b, '-')
		}
		s = s[1:]
	}
	if len(s) == 0 {
		return "", false
	}

	// Split exponent
	exp_idx := -1
	for i in 0 ..< len(s) {
		if s[i] == 'e' || s[i] == 'E' {
			exp_idx = i
			break
		}
	}

	mantissa := exp_idx >= 0 ? s[:exp_idx] : s
	exp_part := exp_idx >= 0 ? s[exp_idx + 1:] : ""

	// Split integer and fractional parts
	dot_idx := strings.index_byte(mantissa, '.')
	int_part := dot_idx >= 0 ? mantissa[:dot_idx] : mantissa
	frac_part := dot_idx >= 0 ? mantissa[dot_idx + 1:] : ""

	if len(int_part) == 0 || (int_part[0] == '0' && len(int_part) > 1) {
		return "", false
	}
	clean_int, ok_int := clean_digits(int_part, 10)
	if !ok_int {
		return "", false
	}
	defer delete(clean_int)
	strings.write_string(&b, clean_int)

	if dot_idx >= 0 {
		if len(frac_part) == 0 {
			return "", false
		}
		clean_frac, ok_frac := clean_digits(frac_part, 10)
		if !ok_frac {
			return "", false
		}
		defer delete(clean_frac)
		strings.write_byte(&b, '.')
		strings.write_string(&b, clean_frac)
	}

	if exp_idx >= 0 {
		if len(exp_part) == 0 {
			return "", false
		}
		exp_sign: u8 = 0
		if exp_part[0] == '+' || exp_part[0] == '-' {
			exp_sign = exp_part[0]
			exp_part = exp_part[1:]
		}
		clean_exp, ok_exp := clean_digits(exp_part, 10)
		if !ok_exp {
			return "", false
		}
		defer delete(clean_exp)
		strings.write_byte(&b, 'e')
		if exp_sign != 0 {
			strings.write_byte(&b, exp_sign)
		}
		strings.write_string(&b, clean_exp)
	}

	success = true
	return strings.to_string(b), true
}

// ---------------------------------------------------------------------------
// RFC 3339 Dates & Times
// ---------------------------------------------------------------------------

@(private = "file")
looks_like_date :: proc(p: ^Parser) -> bool {
	return(
		is_digit(peek_at(p, 0)) &&
		is_digit(peek_at(p, 1)) &&
		is_digit(peek_at(p, 2)) &&
		is_digit(peek_at(p, 3)) &&
		peek_at(p, 4) == '-' \
	)
}

@(private = "file")
looks_like_time :: proc(p: ^Parser) -> bool {
	return is_digit(peek_at(p, 0)) && is_digit(peek_at(p, 1)) && peek_at(p, 2) == ':'
}

@(private = "file")
parse_fixed_digits :: proc(p: ^Parser, count: int) -> (int, bool) {
	val := 0
	for _ in 0 ..< count {
		if eof(p) || !is_digit(peek(p)) {
			return 0, false
		}
		val = val * 10 + int(advance(p) - '0')
	}
	return val, true
}

@(private = "file")
parse_datetime :: proc(p: ^Parser) -> (dt: Date_Time, ok: bool) {
	if looks_like_time(p) {
		if !parse_time_fields(p, &dt) {
			return {}, false
		}
		if !is_value_delim(peek(p)) {
			fail(p, "Unexpected trailing characters after local time")
			return {}, false
		}
		dt.kind = .Local_Time
		return dt, true
	}

	// Date: YYYY-MM-DD
	year, ok_y := parse_fixed_digits(p, 4)
	if !ok_y || peek(p) != '-' {
		fail(p, "Invalid date")
		return {}, false
	}
	advance(p)
	month, ok_m := parse_fixed_digits(p, 2)
	if !ok_m || peek(p) != '-' {
		fail(p, "Invalid date")
		return {}, false
	}
	advance(p)
	day, ok_d := parse_fixed_digits(p, 2)
	if !ok_d || !valid_calendar_date(year, month, day) {
		fail(p, "Invalid calendar date")
		return {}, false
	}

	dt.year = i32(year)
	dt.month = u8(month)
	dt.day = u8(day)

	// Check for time separator ('T', 't', or ' ' followed by HH:)
	sep := peek(p)
	has_time := false
	if sep == 'T' || sep == 't' {
		advance(p)
		has_time = true
	} else if sep == ' ' &&
	   is_digit(peek_at(p, 1)) &&
	   is_digit(peek_at(p, 2)) &&
	   peek_at(p, 3) == ':' {
		advance(p)
		has_time = true
	}

	if !has_time {
		if !is_value_delim(peek(p)) {
			fail(p, "Unexpected trailing characters after local date")
			return {}, false
		}
		dt.kind = .Local_Date
		return dt, true
	}

	if !parse_time_fields(p, &dt) {
		return {}, false
	}

	// Check for timezone offset
	tz := peek(p)
	if tz == 'Z' || tz == 'z' {
		advance(p)
		dt.kind = .Offset_Date_Time
		dt.offset_minutes = 0
	} else if tz == '+' || tz == '-' {
		sign: i16 = tz == '-' ? -1 : 1
		advance(p)
		oh, ok_oh := parse_fixed_digits(p, 2)
		if !ok_oh || peek(p) != ':' {
			fail(p, "Invalid timezone offset")
			return {}, false
		}
		advance(p)
		om, ok_om := parse_fixed_digits(p, 2)
		if !ok_om || oh > 23 || om > 59 {
			fail(p, "Timezone offset out of range")
			return {}, false
		}
		dt.kind = .Offset_Date_Time
		dt.offset_minutes = sign * i16(oh * 60 + om)
	} else {
		dt.kind = .Local_Date_Time
	}

	if !is_value_delim(peek(p)) {
		fail(p, "Unexpected trailing characters after datetime")
		return {}, false
	}

	return dt, true
}

@(private = "file")
parse_time_fields :: proc(p: ^Parser, dt: ^Date_Time) -> bool {
	hour, ok_h := parse_fixed_digits(p, 2)
	if !ok_h || peek(p) != ':' {
		return fail(p, "Invalid time")
	}
	advance(p)
	minute, ok_m := parse_fixed_digits(p, 2)
	if !ok_m || peek(p) != ':' {
		return fail(p, "Invalid time")
	}
	advance(p)
	second, ok_s := parse_fixed_digits(p, 2)
	if !ok_s || hour > 23 || minute > 59 || second > 59 {
		return fail(p, "Time out of range")
	}

	dt.hour = u8(hour)
	dt.minute = u8(minute)
	dt.second = u8(second)

	if peek(p) == '.' {
		advance(p)
		if !is_digit(peek(p)) {
			return fail(p, "Expected digits after decimal point in time")
		}
		ns: u32 = 0
		scale: u32 = 100_000_000
		for !eof(p) && is_digit(peek(p)) {
			d := u32(advance(p) - '0')
			if scale > 0 {
				ns += d * scale
				scale /= 10
			}
		}
		dt.nanosecond = ns
	}

	return true
}

@(private = "file")
valid_calendar_date :: proc(year, month, day: int) -> bool {
	if month < 1 || month > 12 || day < 1 {
		return false
	}
	days_in_month := [12]int{31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31}
	max_day := days_in_month[month - 1]
	if month == 2 && ((year % 4 == 0 && year % 100 != 0) || (year % 400 == 0)) {
		max_day = 29
	}
	return day <= max_day
}
