# Watermarks

A watermark is text or a graphic drawn on every exported photo. It is sized relative to the photo, so it looks the same at any export size. The Export dialog edits one watermark; the same object is `watermark` in `export` params (see `docs/control-protocol.md`), the MCP `export` tool and saved export presets. Vertical text is described in [vertical-watermarks.md](vertical-watermarks.md).

## Settings

All keys are optional. Fractions are of the photo's short edge unless noted.

| Key | Meaning | Default |
|---|---|---|
| `text` | The text. Empty with no `image` draws nothing. | |
| `image` | A PNG or JPEG drawn instead of the text. | none |
| `imageWidth` | The graphic's width as a fraction of the photo's width, 0.01 to 1. | 0.2 |
| `vertical` | Upright columns, right to left. | false |
| `size` | Text height, 0.005 to 0.5. | 0.035 |
| `opacity` | 0 to 1. | 0.7 |
| `color`, `shadow` | Text colour (sRGB) and a soft shadow. | white, on |
| `anchor` | One of nine positions: `topLeft`, `top`, `topRight`, `left`, `center`, `right`, `bottomLeft`, `bottom`, `bottomRight`. | `bottomRight` |
| `insetX`, `insetY` | Margins to the outer edge of the watermark (including its frame), 0 to 0.4. Unused along an axis where the anchor is centred. | 0.025 |
| `rotation` | 0, 90, 180 or 270 degrees clockwise. | 0 |
| `borderWidth`, `borderColor` | A frame around the watermark, 0 to 0.05 (0 = none). | 0, white |
| `padding` | Space between the watermark and its frame or box, 0 to 0.1. | 0 |
| `backgroundOpacity`, `backgroundColor` | A filled box behind it, opacity 0 to 1 (0 = none), multiplied by `opacity`. | 0, black |
| `radius` | Corner radius of the frame and box, 0 to 0.05. | 0 |

The frame and box grow the placed area; they are drawn before the text or graphic. Settings written by older versions load unchanged.

## Saved watermarks and sharing

- **Saved watermarks:** the Export dialog keeps named watermarks as one `.json` each in `<settings folder>/watermarks/`. Tap or click one to apply it; **Save current** stores the one being edited.
- **Share file:** **Export watermark…** writes a single `.json` (`kind: "lightcraft-watermark"`, `version: 1`) holding the settings and, for a graphic, the picture itself as base64, so it works on another machine. **Import watermark…** reads one. An imported graphic must be a real PNG or JPEG of at most 6 MB; it is stored once, named by its content, under `<settings folder>/watermarks/`. Out-of-range numbers are clamped and unknown keys ignored. The code is `crates/engine/src/watermark_pack.rs`.
- Where the host has no file dialog (the web build) the buttons are hidden; saved watermarks need a settings folder.
