/*
    2026 (c) Oleh, https://github.com/zm69

    Load diagnostics: every problem found while loading KDL, with its file, line, column and
    span, a message and an optional suggestion.
*/
package ode_dos

// Core
    import "core:fmt"
    import "core:os"
    import "core:strings"

///////////////////////////////////////////////////////////////////////////////
// Load_Error

    Load_Error :: struct {
        file:       string,
        line:       int,
        column:     int,
        span:       int,    // characters to underline
        message:    string,
        suggestion: string, // "" when none
    }

    // Problems from the last load; valid until the next load.
    world__errors :: proc(self: ^World) -> []Load_Error {
        return self.load_errors[:]
    }

    // "file:line:column", the source line with the span underlined, the message and any suggestion.
    load_error__format :: proc(e: Load_Error, allocator := context.allocator) -> string {
        b := strings.builder_make(allocator)
        fmt.sbprintf(&b, "%s:%d:%d\n", e.file, e.line, e.column)

        if line, ok := source_line(e.file, e.line); ok {
            fmt.sbprintf(&b, "  %s\n  ", line)
            col := 1
            for r in line {
                if col >= e.column do break
                if r == '\t' {
                    strings.write_byte(&b, '\t')
                } else {
                    strings.write_byte(&b, ' ')
                }
                col += 1
            }
            for _ in 0..<max(e.span, 1) do strings.write_byte(&b, '^')
            strings.write_byte(&b, '\n')
        }

        fmt.sbprintf(&b, "  %s", e.message)
        if e.suggestion != "" do fmt.sbprintf(&b, " — did you mean %q?", e.suggestion)
        return strings.to_string(b)
    }

///////////////////////////////////////////////////////////////////////////////
// Private

    @(private)
    source_line :: proc(path: string, line: int) -> (string, bool) {
        if line <= 0 do return "", false
        data, err := os.read_entire_file_from_path(path, context.temp_allocator)
        if err != nil do return "", false

        text := string(data)
        n, start := 1, 0
        for i := 0; i <= len(text); i += 1 {
            if i < len(text) && text[i] != '\n' do continue
            if n == line {
                s := text[start:i]
                if len(s) > 0 && s[len(s) - 1] == '\r' do s = s[:len(s) - 1]
                return s, true
            }
            n += 1
            start = i + 1
        }
        return "", false
    }

    // The candidate closest to name when it is close enough to be a typo; "" otherwise.
    @(private)
    suggest :: proc(name: string, candidates: []string) -> string {
        best := ""
        best_distance := max(1, len(name) / 3) + 1
        for c in candidates {
            if d := edit_distance(name, c); d < best_distance {
                best, best_distance = c, d
            }
        }
        return best
    }

    // Levenshtein distance, ignoring ASCII letter case; long strings count as far apart.
    @(private)
    edit_distance :: proc(a, b: string) -> int {
        if len(a) > 64 || len(b) > 64 do return max(len(a), len(b))

        prev, cur: [65]int
        for j in 0..=len(b) do prev[j] = j
        for i in 1..=len(a) {
            cur[0] = i
            for j in 1..=len(b) {
                cost := ascii_lower(a[i - 1]) == ascii_lower(b[j - 1]) ? 0 : 1
                cur[j] = min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + cost)
            }
            prev = cur
        }
        return prev[len(b)]
    }
