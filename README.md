# Notation

A lightweight desktop music notation and engraving editor written in Odin with SDL2 and OpenGL 3.3.

> **Status:** Early work in progress.

## Features

- **SMuFL Engraving:** Hardware-accelerated 2D page rendering using `Bravura.otf` glyph atlases.
- **Interactive Note Entry:** Finale-style ghost cursor with beat snapping, chord stacking, automatic rest splitting, and accidental overrides.
- **TOML Score Serialization:** Custom zero-dependency TOML parser and compact pipe-delimited measure/voice notation format (`demo.toml`).
- **Vector PDF Export:** Native PDF 1.4 generation (`score.pdf`) using outlined Bézier glyph paths and vector staff geometry.

## Requirements & Build

- [Odin](https://odin-lang.org/) compiler
- SDL2 & OpenGL 3.3 development libraries
- `Bravura.otf` placed in the project root

```sh
# Build and run with Odin directly
odin run src -out:notation

# Or via lash
lash run
```

## Controls

| Input | Action |
| :--- | :--- |
| **Left Click** | Select measure (Select mode) / Place or remove note (Note Entry mode) |
| **Right Drag** | Pan canvas |
| **Mouse Wheel** | Zoom in / out (`0` to reset camera) |
| **`Tab`** | Toggle Select and Note Entry modes |
| **`1` – `6`** | Switch to Note Entry with Whole, Half, Quarter, 8th, 16th, or 32nd duration |
| **`R`** | Toggle rest input |
| **`-` / `N` / `=`** | Toggle Flat, Natural, or Sharp accidental override |
| **`Backspace` / `Delete`** | Pop last entry in hovered measure (Note Entry) or clear measure (Select) |
| **`Ctrl + S`** | Save score to `demo.toml` |
| **`Ctrl + E` / `Ctrl + P`** | Export page to `score.pdf` |
| **Hold `Ctrl`** | Inspect hovered render layer |
| **`Escape`** | Exit Note Entry / Clear selection / Quit |

## License

See [LICENSE](./LICENSE) for details.
