# LightCraft Per-Panel UX Spec

Platform: Rust/egui, iPad primary (landscape and portrait), iPhone secondary.
Inspiration note: patterns below draw only on public, general knowledge of how photo editors commonly work. No competitor app was inspected.

## 0. Global design language and shared rules

**Look.** Dark glass: panels are translucent near-black (#0D0E11 at about 70%) with background blur and a 0.5pt hairline at 10% white. Image area is always neutral dark (#101114 or darker) so colour judgement is not tinted.

**Ghost buttons.** Default controls have no fill and no border: icon or text at about 85% white. Pressed: 12% white fill, scale 0.97, 80 ms. Disabled: 35% opacity, no press response, VoiceOver still announces with a reason.

**ONE soft selected oval.** Exactly one selection style app-wide: a rounded capsule at about 18% white behind the selected item (tab, filter chip, tool, mask). Only one oval is visible per control group, and it slides between items (150 ms ease-out; instant under Reduce Motion). No coloured accents, underlines or checkmarks for selection. Slider thumbs and active-edit dots are not selection and use a thin white ring.

**Targets.** Every interactive element has a hit area of at least 44x44pt, even when the glyph is 20pt. Minimum 8pt between adjacent targets. Sliders have a 44pt-tall touch band.

**Universal gestures (all image-bearing panels).**
- Pinch: zoom 1x to 8x (fit to 1:1 to 8x pixel). Two-finger pan. Double-tap: toggle fit and 100%.
- Two-finger tap: undo. Three-finger tap: redo. Show a brief toast ("Undo: Exposure") for 1.2 s.
- Long-press on any slider, value or section header: reset that item to default, with a light haptic and a toast offering "Undo". Double-tap on a slider value is the equivalent shortcut.
- Hold on the image (Edit, Masking, Presets): show Original. Release returns to the edit.
- Apple Pencil: hover (M2 iPad and later) previews brush size and cursor. Pencil draws and paints (masks, heal, crop handles); finger pans and zooms. Pencil double-tap toggles brush and eraser. Pencil squeeze opens the tool palette. If no Pencil is paired, a "Draw with finger" toggle appears in the tool options, otherwise one finger pans.

**Global states.**
- Loading: low-resolution embedded preview appears within 150 ms, then the RAW decode refines. A thin 2pt progress line sits under the top bar. Never block with a modal spinner.
- Error: inline, specific and recoverable (what failed, one action). Use a glass banner at the top for 6 s, or persistent if user action is required. Never use a blocking alert for recoverable errors.
- Saving: edits are autosaved as non-destructive sidecar or database state. No Save button.

**Accessibility baseline.**
- VoiceOver: every control has a label, a value (for sliders, "Exposure, plus 0.5 stops"), a trait, and a hint only if the action is not obvious. Sliders support adjustable up and down (step = 1% of range) and a custom action "Reset to default".
- Reduce Transparency: glass becomes solid #16181D at 100% with a 1pt 20% white border. The selected oval becomes 28% white. Blurs are removed.
- Reduce Motion: no sliding oval, no zoom springs, crossfade only.
- Dynamic Type: all text scales to AX5. Labels wrap rather than truncate. Where a layout cannot hold large text (chips, tab bar), it switches to a scrolling or stacked layout. Glyph-only toolbars gain visible text labels at AX1 and above.
- Contrast: text at least 4.5:1 on glass over any image, ensured by a darkening scrim. Differentiate with shape and icon, not colour alone (red reject flag also has an X glyph).
- Bold Text, Increase Contrast, Button Shapes: honoured. Button Shapes adds a hairline outline to ghost buttons.
- Keyboard and trackpad (iPad): arrow keys step the focused slider, Cmd+Z / Shift+Cmd+Z undo and redo, backslash toggles before/after, 0 to 5 rate, P/X/U flag.

**Responsive frame.**
- iPad landscape: image canvas left or centre, 320pt right inspector (collapsible to 0), 56pt left tool rail, 52pt top bar.
- iPad portrait: image on top (about 58% of height), inspector as a bottom sheet with three detents (peek 96pt, half, full).
- iPhone: image on top, a bottom tool strip (56pt) plus a draggable sheet (peek, half, large). Single-column. Landscape iPhone uses the iPad landscape layout with a 280pt inspector and no left rail (tools move to a bottom strip).

---

## 1. Library grid and filters

**Purpose.** Browse, cull and select photos fast; find images by rating, flag, camera, date and edit status.

**Entry/exit.** Entry: app launch, or Back from Edit. Exit: tap a thumbnail opens Edit at that photo; long-press opens context menu and multi-select. Filter sheet dismisses by tapping outside or dragging down.

**Layout.**
- iPad landscape: left sidebar (240pt: Library, Albums, Recently Added, Imported, Folders) plus grid. Top bar: title and count, search, sort, filter button, select, import (+). Grid columns adapt: 5 to 8 (pinch changes density).
- iPad portrait: sidebar becomes a slide-over (opened from a top-left button). Grid 3 to 5 columns.
- iPhone: single-pane. Grid 3 columns (pinch 2 to 5). Top bar: title, search, "..." overflow. Filter chips are a horizontally scrolling row under the top bar. Albums are reached through a sheet.

**Controls and states.**
- Thumbnail cell: default shows image, 1pt gap; overlays only for flag, rating (when 1 or more), and an "edited" glyph. Pressed: 12% white overlay. Selected (multi-select): the oval treatment becomes a rounded outline plus a corner check (the one selection style applied to cells as a soft inner capsule at the badge). Disabled/unavailable: offline or missing source shows a dimmed cell with a cloud-slash glyph.
- Filter chips (Rated, Flagged, Edited, Camera, Lens, Date, File type): ghost; active chips use the single soft oval fill. A trailing "Clear" appears when any filter is active. Active filter count is shown in the filter button.
- Sort: menu (Capture date, Added, Rating, Name; ascending or descending). Current choice marked with the oval.
- Select mode: top bar becomes "N selected" with Rate, Flag, Add to Album, Export, Delete. Delete is disabled with nothing selected.

**Gestures.**
- Tap: open. Long-press: context menu (Rate, Flag, Copy edits, Paste edits, Reset edits, Export, Delete). Drag on a selected cell: system drag and drop to albums.
- Pinch: grid density. Two-finger tap: undo the last library action (rating, flag, delete) with toast. Swipe with two fingers across cells: range select (iPad). Long-press on the "Edited" badge resets that photo's edits after confirm.
- Pencil: tap-selects, hover shows a larger preview peek. Pencil does not draw here.

**Empty/loading/error.**
- Empty library: centred glass card, "No photos yet", primary actions "Import from Files", "Import from Camera Roll", "Connect camera or card reader". Empty after filters: "No photos match these filters" with "Clear filters".
- Loading: cells show a flat 8% placeholder then fade in the thumbnail. Import progress as a determinate bar in the top bar, tappable for details. Grid is scrollable during import.
- Error: unreadable or unsupported RAW shows a "!" cell badge, and tapping gives "Can't decode this file (unsupported camera). Try again or export original." Storage full: banner with "Free up space".

**Accessibility.**
- Cell label: "Photo 12 of 240, IMG_4021, 4 stars, picked, edited, taken 14 March". Actions: Open, Rate, Flag. Filter chips: "Filter: Rated 4 or more, on" with toggle trait.
- Reduce Transparency: sidebar and top bar solid. Dynamic Type: chips wrap onto two rows or become a "Filters" button opening a list at AX3+. Grid keeps at least 2 columns at AX5.
- Rotor: "Flagged photos", "Rated photos".

**Top 3 usability failures to prevent.**
1. Thumbnails with no overlay, then showing too many overlays at small sizes. Mitigation: overlays only appear at 44pt+ cell size, and rating and flag never overlap the image centre.
2. Accidental destructive actions in multi-select (delete next to export). Mitigation: Delete separated and red-glyph with confirm plus undo toast.
3. Pinch density jumps lose the user's scroll position. Mitigation: anchor the cell under the pinch centroid and animate the layout.

---

## 2. Edit panel (Light, Colour, Effects, Detail, Optics, profile, histogram, Auto/Reset)

**Purpose.** Non-destructive tone, colour and detail adjustment of a single RAW image with real-time preview.

**Entry/exit.** Entry: open a photo from the library, or tap Edit in the tool rail. Exit: Back (to library), or switching to another tool. Edits persist automatically. Leaving mid-render is safe.

**Layout.**
- iPad landscape: tool rail (left) with Edit, Masking, Crop, Heal, Presets. Right inspector 320pt: top histogram (96pt tall, collapsible), profile row, then section tabs (Light, Colour, Effects, Detail, Optics) as a segmented row with the single oval. Below: scrolling sliders. Footer pinned: Auto and Reset.
- iPad portrait: bottom sheet. Peek shows the section tab row and the 3 most used sliders; half shows histogram plus 5 sliders; full shows all. Histogram is a small floating glass chip (draggable) when the sheet is at peek.
- iPhone: bottom strip with five section icons (labelled text at AX). One section's sliders appear in a sheet at half height. Histogram is a tappable mini chip at the image top-left, expanding to a full overlay.

**Sections and controls.**
- Profile (top of Light, plus Optics): dropdown for camera/colour profile (Adobe-style Standard, Neutral, Landscape, Portrait, Monochrome; names are placeholders). Selected profile is marked with the oval.
- Light: Exposure, Contrast, Highlights, Shadows, Whites, Blacks; Tone curve (opens a curve editor sheet).
- Colour: White balance (temp, tint, eyedropper), Vibrance, Saturation, HSL (Hue, Sat, Lum by 8 colour bands), Colour grading wheels.
- Effects: Texture, Clarity, Dehaze, Vignette, Grain.
- Detail: Sharpening (amount, radius, detail, masking), Noise reduction (luminance, colour).
- Optics: Lens profile correction toggle, Remove chromatic aberration, Defringe, Distortion and vignetting amount.
- Slider anatomy: label (left), numeric value (right), track. Default: thumb at default marker (small notch), value in 70% white. Pressed/dragging: value enlarges and gets a floating readout above the finger, track highlights, and fine scrubbing slows when the finger moves vertically away from the track (precision mode, 1/10 speed at 100pt away). Modified: label is full white and a 4pt dot sits beside the section tab. Disabled: e.g. Defringe when no lens profile, with the reason in VoiceOver and a caption.
- Auto: applies a computed exposure, contrast, white balance suggestion, highlighted for one second with an undo toast. Pressed: ghost press state. Disabled while rendering the analysis.
- Reset: resets the current section (long-press resets all sections, with a confirm sheet "Reset all edits? Undo available").
- Histogram: luminance plus RGB channels. Tap toggles RGB/luma. Highlight and shadow clipping shown as small triangles; tap toggles clipping overlay on the image. Dragging on the histogram adjusts the nearest tonal zone (optional, off by default, setting).
- Before/After: see Compare.

**Gestures.**
- Pinch: zoom. Two-finger tap: undo; three-finger tap: redo. Long-press on slider: reset to default. Double-tap value: type a number (keyboard sheet).
- Horizontal drag directly on the image with a selected slider (touch-adjust): drag left and right changes the focused slider (opt-in, setting "Direct slider on image").
- Pencil: hover on a slider thumb shows value; Pencil drag gives finer control than finger. Pencil tap on the image with the WB eyedropper samples a 5x5 average; hold Pencil to show the loupe.
- Long-press on image: shows Original.

**Empty/loading/error.**
- Empty: no photo selected shows "Choose a photo" with a button back to Library.
- Loading: embedded preview with a "Developing..." chip at the top, slider values usable immediately (adjustments queue and apply once the full decode is ready). Histogram shows a dim placeholder.
- Error: decode failure shows a banner "Couldn't develop this RAW" with Retry and "Use embedded preview". Out of GPU/memory: automatic fall back to 50% preview resolution with the notice "Preview reduced to keep editing smooth".

**Accessibility.**
- Slider: "Exposure, adjustable, plus 0.5 stops, default 0." Custom actions: Reset, Enter value. Histogram: label "Histogram. Highlights 4% clipped. Shadows 0% clipped." with a summary rather than raw data. Auto: "Auto adjust. Applies suggested exposure and colour. Undo available."
- Section tabs: tab trait, "Light, selected, 1 of 5". Modified dot is also announced ("modified").
- Reduce Transparency: inspector solid. Dynamic Type: slider labels move above the track at large sizes; value text is never truncated. Section tab row becomes a scrolling, two-line control at AX1+.

**Top 3 usability failures to prevent.**
1. Fine-tuning with a finger on a short track is imprecise. Mitigation: precision drag, double-tap numeric entry, and Pencil.
2. Users cannot tell what they changed. Mitigation: modified dots and a per-section reset, plus Before/After.
3. Accidental full reset. Mitigation: long-press reset is section-scoped by default, full reset needs confirmation and always can be undone through two-finger tap.

---

## 3. Masking (Subject, Sky, Brush, Linear, Radial, mask list, invert, intersect)

**Purpose.** Apply local adjustments to selected regions.

**Entry/exit.** Entry: Masking tool in the rail. Exit: Done button, or choose another tool. Selecting a mask in the list enters its adjustment view.

**Layout.**
- iPad landscape: inspector shows "Add mask" row (Subject, Sky, Brush, Linear, Radial) as ghost icons with labels, then the mask list, then the selected mask's options (Invert, Add, Subtract, Intersect, Feather, Density) and its adjustment sliders (same as Edit Light, Colour, Effects, Detail subset).
- iPad portrait: bottom sheet. Peek: add-mask row and the currently selected mask chip. Half: mask options. Full: sliders.
- iPhone: bottom strip with the five mask types, a mask-list button, and an Invert toggle. A sheet at half for options. The mask list opens as a sheet.

**Controls and states.**
- Add buttons: default ghost; pressed highlights; selected (current creation tool) uses the single oval. Subject and Sky show a spinner within the button while analysing (about 1 to 3 s). Disabled if no photo or analysis unavailable (device unsupported) with a reason.
- Mask list rows: thumbnail of mask (white on dark), name ("Subject 1"), eye toggle (visibility), "..." menu (Rename, Duplicate, Delete). Selected row: soft oval. Drag handle to reorder.
- Mask overlay: red tint 50% (toggle "Show overlay", also toggled by an "O" key). Overlay is hidden during slider drags so the user can see true colours, reappearing 600 ms after release.
- Combine ops per mask: Add, Subtract, Intersect (shown as a 3-item segmented control with the oval). Intersect is disabled until a mask has at least two components. Invert: toggle button with a pressed/on state (filled glyph when on).
- Brush options: Size, Feather, Flow, Auto-mask (edge aware), Erase toggle. Brush cursor is a circle showing size and feather ring.
- Linear: two handles and a line. Radial: centre plus ellipse handles, feather handle. Handles are 44pt hit areas with visible 16pt dots.

**Gestures.**
- Pinch zoom and two-finger pan always work, even in brush mode (finger draws only if "Draw with finger" is on). Pencil paints with pressure mapping to flow, tilt to size (off by default). Pencil double-tap swaps brush/eraser.
- Tap on a Subject/Sky mask refines via "Add or subtract" brush. Linear: drag to create, drag handle to rotate, pinch the line to change feather.
- Two-finger tap: undo last stroke or mask step. Long-press on a slider: reset. Long-press a mask row: begin reorder. Swipe left on a row: Delete (with undo toast).

**Empty/loading/error.**
- Empty: "No masks yet. Add a mask to adjust one part of the photo" with the five add buttons enlarged.
- Loading: Subject/Sky analysis shows a shimmering outline plus a "Finding subject..." chip; user can keep editing global sliders.
- Error: "No subject found. Try the brush or a radial mask." Sky: "No sky detected." Model unavailable: "Smart selection isn't available on this device" with the buttons disabled.

**Accessibility.**
- Add buttons: "Add subject mask". Mask rows: "Mask 2 of 3, Sky, visible, selected." Actions: Toggle visibility, Invert, Delete, Move up and down. Handle objects get labels and can be moved with adjustable actions in 5% steps because precise dragging is not VoiceOver-friendly.
- Overlay is accompanied by a text coverage readout ("Mask covers 18% of image").
- Reduce Transparency: overlay stays but with an extra white outline for contrast. Dynamic Type: segmented Add/Subtract/Intersect becomes a vertical list at AX3+.

**Top 3 usability failures to prevent.**
1. Fingers draw when the user intends to pan or zoom. Mitigation: Pencil-only drawing by default if a Pencil is connected, clear mode badge, and "Draw with finger" toggle.
2. Overlay hides the true look of the edit. Mitigation: auto-hide on drag and quick toggle.
3. Add/Subtract/Intersect semantics are unclear. Mitigation: plain-language labels with thumbnails showing the effect, and a live preview of the result before commit.

---

## 4. Crop / Geometry

**Purpose.** Reframe, straighten, rotate, flip and correct perspective.

**Entry/exit.** Entry: Crop tool. Exit: Done (commits) or Cancel (discards; shown when changes exist). Leaving the tool by switching tools commits.

**Layout.**
- iPad landscape: image fills canvas with crop handles; inspector has Aspect (Original, 1:1, 4:5, 3:2, 16:9, Custom), Angle dial, Rotate 90, Flip, Geometry tab (Vertical, Horizontal, Rotate, Scale, Aspect, Auto upright).
- iPad portrait: aspect chips in a horizontally scrolling row below the image; angle dial as a full-width ruler under it.
- iPhone: aspect row and angle ruler in the bottom strip; geometry sliders under a "Geometry" button sheet.

**Controls and states.**
- Aspect chips: ghost, selected one uses the oval. A lock toggle for aspect (locked state shown with a filled glyph). Orientation swap button.
- Handles: 8 handles with 44pt hit areas (corners and edges), visible 20pt L-shaped corners. Pressed handle thickens and the rule-of-thirds grid shows during drag (also the finer grid while rotating).
- Angle dial: tick marks, snaps with haptics at 0 and plus or minus 45, 90. Value shown in a bubble.
- Geometry sliders: same slider spec as Edit. Auto upright button: disabled when not enough lines detected, with caption.
- Reset: resets crop and geometry; long-press the angle dial resets to 0.

**Gestures.**
- Drag inside crop to move image under crop. Pinch zooms the image within the crop (not the canvas) while this tool is active, and a "Fit" button resets view. Two-finger rotate gesture rotates the image. Two-finger tap: undo.
- Pencil: precise handle dragging, hover highlights handle. Pencil drag on the dial for fine angle.
- Long-press on Reset: confirm "Reset crop and geometry".

**Empty/loading/error.**
- Loading: crop UI available immediately over the preview. Heavy perspective changes show a brief low-quality preview then refine.
- Error: "Crop cannot extend beyond image" is communicated through a soft haptic and the edge flashing, and constraint warning chip "Upright correction left no valid crop" with a button "Use auto-fill edges".

**Accessibility.**
- Handles: "Top left crop handle, adjustable." Adjustable actions move by 1% with VoiceOver and a text readout "Crop: 4032 by 3024, ratio 4 to 3, angle 1.2 degrees". Dial: "Straighten angle, 1.2 degrees, adjustable".
- Reduce Transparency: grid lines get stronger contrast. Dynamic Type: aspect chips scroll, and labels stay readable. Provide non-gesture numeric entry for width, height, and angle.

**Top 3 usability failures to prevent.**
1. Pinch moving the whole canvas rather than the image in the crop, which confuses users. Mitigation: a clear mode, with a Fit button.
2. Tiny handles on iPhone. Mitigation: 44pt invisible hit areas, handle priority to nearest edge, and an inset safe region.
3. Aspect lock surprises. Mitigation: visible lock state and a toast when a ratio changes.

---

## 5. Presets

**Purpose.** Apply saved looks and recipes in one tap, with adjustable strength.

**Entry/exit.** Entry: Presets tool in the rail. Exit: choose another tool or Done. Applying a preset keeps the user in the panel.

**Layout.**
- iPad landscape: inspector with search, group list (Mine, Colour, B&W, Portrait, Film, Imported), and a grid of preset thumbnails (rendered from the current photo) 2 columns. Strength slider pinned at the bottom.
- iPad portrait: a horizontal filmstrip of thumbnails in the bottom sheet with groups as chips above; strength slider below.
- iPhone: horizontal strip of thumbnails at the bottom (88pt), group chips above, strength slider in the half sheet.

**Controls and states.**
- Thumbnail: default shows name and render. Pressed: 12% white. Selected (applied): the single soft oval behind the name label plus a thin ring. Loading: thumbnail placeholder until rendered (progressive, nearest first).
- Strength slider (0 to 100, extended to 200 optionally). Disabled when no preset applied. Long-press resets to 100.
- Actions: Save current as preset (+), Rename, Delete, Import, Favourite (star). Delete is disabled for built-ins.
- Apply mode toggle: "Replace edits" vs "Add on top" (segmented with the oval). Default is "Replace" for looks and "Add on top" for partial presets.

**Gestures.**
- Tap: apply and live-preview. Press and hold a thumbnail: previews the preset on the full image for as long as held, release cancels (a quick look). Two-finger tap: undo the preset application. Pinch: zoom the canvas. Long-press on the strength slider: reset to 100.
- Pencil: tap applies, hover shows a name tooltip.

**Empty/loading/error.**
- Empty "Mine": "No presets yet. Save your current edit as a preset" with a button. Empty search: "No presets match".
- Loading: thumbnails render lazily with placeholders. Error: failed import "That file isn't a valid preset (format not recognised)" with the file name; failed thumbnail render shows a generic icon and the preset is still usable.

**Accessibility.**
- Label: "Preset Warm Film, in group Film, applied, strength 80 percent". Custom action: Favourite, Delete. Strength slider adjustable. Presets announce when applied ("Applied Warm Film").
- Reduce Transparency: solid inspector. Dynamic Type: thumbnail names wrap to two lines, grid falls to 1 column at AX3+.

**Top 3 usability failures to prevent.**
1. Applying a preset silently overwrites hand edits. Mitigation: visible Replace/Add toggle, undo toast.
2. Thumbnails that do not represent the user's photo or lag. Mitigation: render from the current image at low res, progressive loading.
3. Users cannot find a preset in a long list. Mitigation: search, favourites, recently used.

---

## 6. Healing / Remove

**Purpose.** Remove spots, blemishes and distracting objects (heal, clone, and generative remove where available).

**Entry/exit.** Entry: Heal tool in the rail. Exit: Done, or switch tool. Spots remain editable (non-destructive) and appear when the tool is active.

**Layout.**
- iPad landscape: inspector with mode (Heal, Clone, Remove), Size, Feather, Opacity, "Show spots" toggle, spot list. A loupe floats near the stroke.
- iPad portrait: bottom sheet peek shows modes and Size slider. iPhone: bottom strip with modes, Size slider in the sheet, and a floating Undo button because two-finger tap conflicts with pinch more easily on a small screen.

**Controls and states.**
- Mode segmented control (selected mode uses the oval). Brush size via slider and by pinch-with-two-fingers-while-holding-Pencil (optional). Eraser to remove part of a stroke. "Show spots" toggle.
- Spot (target + source): target circle and source circle linked by a thin line. Selected spot shows handles. Auto-source versus manual source: drag source to change. Pressed handle enlarges.
- Apply/processing: the target region shows a shimmering outline while Remove computes (about 1 to 4 s). Disabled: Remove mode disabled when the model is unavailable, with a reason.
- Delete spot: a button in the selected spot's contextual bar; Clear all spots with confirmation.

**Gestures.**
- Pencil or one finger (per setting) paints or taps to place a spot. Pinch zooms (zoom is required: starting zoom to 100% is suggested when the tool opens). Two-finger pan. Two-finger tap: undo; this applies to the last spot or stroke. Long-press on a spot: show actions (Delete, Duplicate, Change source). Long-press on Opacity: reset to 100.
- Pencil pressure can map to opacity (off by default).

**Empty/loading/error.**
- Empty: coachmark "Tap or paint over a spot to remove it" shown once, dismissible.
- Loading: shimmering outline and a "Removing..." chip; other panels remain usable. Cancel button while processing.
- Error: "Couldn't fill this area. Try a smaller area or pick a source" with Retry. Source out of bounds: the source circle turns red with a text note "Source outside the image".

**Accessibility.**
- Spots appear as a list of items in the spot list for VoiceOver ("Spot 3, heal, at upper left"), with actions Delete and Move with adjustable steps. Mode control labelled with a selected trait. A summary string "3 spots" is read when the tool opens.
- Reduce Transparency: the loupe and chips solid. Dynamic Type: chips and labels scale, mode control stacks vertically at AX3+.

**Top 3 usability failures to prevent.**
1. Working at fit zoom produces poor placement. Mitigation: auto-zoom to 100% when selecting the tool, and a loupe showing the area under the finger.
2. Finger occludes the target. Mitigation: offset loupe, and Pencil-first with a visible cursor.
3. Auto source picks a bad region and users do not realise they can change it. Mitigation: source circle always visible after placement with a "Move source" hint on first use, and a "Resample" button.

---

## 7. Export / Share

**Purpose.** Output finished images in the required format, size and destination.

**Entry/exit.** Entry: Export button in the top bar (single photo) or from multi-select in Library. Exit: Cancel, or completion (success state with Done).

**Layout.**
- iPad landscape: a centred glass sheet (560pt wide): preview thumbnail, format, quality, size, colour space, metadata, naming, destination. Primary button Export at the bottom.
- iPad portrait: the same sheet, 80% width. iPhone: full-height sheet with a sticky Export button at the bottom, content scrolls.

**Controls and states.**
- Format segmented (JPEG, HEIC, TIFF, DNG (original), PNG), selected using the oval. Quality slider (JPEG, HEIC). Size: Original, Long edge (px) with presets (2048, 4096), Percent. Colour space: sRGB, Display P3, Adobe RGB (placeholders for supported spaces). Metadata: Keep all, Remove location, Remove all. Sharpen for: Screen, Matte paper, Glossy. File name template.
- Destination: Photos, Files, AirDrop and the share sheet, Copy. The estimated file size updates live ("About 6.2 MB").
- Export button: default ghost-prominent (the only filled control in the app: a white 18% pill is acceptable, still no extra colour); pressed state shows scaling; during export becomes a progress pill with Cancel. Disabled: no destination or write permission missing (reason shown beneath).
- Batch: a progress list with per-image state (queued, exporting, done, failed).

**Gestures.**
- Swipe down to dismiss (confirm if a batch is in progress). Long-press the format to show a short explanation. Long-press on a setting resets that setting to default. Two-finger tap has no meaning here and is ignored, with the standard undo reserved for the editor. Pencil: normal taps.

**Empty/loading/error.**
- Empty: no photo selected disables Export with "Select photos to export".
- Loading: rendering with a determinate progress bar and elapsed estimate; the app stays usable and exports continue in the background where iPadOS allows, with a notification on completion.
- Error: per-image failure with reason ("Not enough storage", "Photos access denied: Open Settings"), actions Retry, Skip, Open Settings. Success: "Exported 12 photos" with Show in Files, Share, Done.

**Accessibility.**
- Each setting has a label and a value ("Format, JPEG, button, opens menu"). Progress announced at 25% steps through accessibility announcements, completion and failure announced immediately. Estimated size is a live region.
- Reduce Transparency: solid sheet. Dynamic Type: the sheet becomes a single column list, the sticky Export button stays visible at AX5.

**Top 3 usability failures to prevent.**
1. Hidden privacy risk: location kept by default when sharing. Mitigation: a visible metadata row with a clear summary and a "Remove location" default for Share destinations.
2. Large exports blocked by the sheet or killed on backgrounding. Mitigation: background-capable queue and persistent progress chip.
3. Users do not understand size and quality trade-offs. Mitigation: live estimated size and a pixel-dimension readout.

---

## 8. Rating / flag bar

**Purpose.** Rate (0 to 5) and flag (Pick, Reject, none) quickly, in Library and in Edit, to support culling.

**Entry/exit.** Always available: a persistent slim bar below the image in Edit, and an overlay in Library select mode and in a full-screen cull view. No explicit entry or exit. Hides in distraction-free mode and returns with a tap.

**Layout.**
- iPad landscape: horizontal glass bar centred under the image, 52pt high: Reject (flag X), Unflag, Pick (flag), divider, 5 stars. Keyboard shortcuts displayed in the tooltips.
- iPad portrait: the same bar, full width.
- iPhone: the bar docks above the tool strip in Edit. In Library cull view, a bottom bar with the 5 stars plus Pick and Reject. Optionally, swipe gestures (up = Pick, down = Reject) available behind a setting.

**Controls and states.**
- Stars: ghost outline by default; rated stars show filled stars up to the rating. Tapping the current rating again clears it (to 0). Pressed: scale 0.95 plus haptic. Not using the oval for stars (the oval applies to selection of one item, so the flag segment uses it).
- Flag segment (Reject, None, Pick): selected state gets the soft oval; Reject glyph includes an X, not only colour; the bar dims the image slightly in Library for rejects.
- Disabled: when the photo is read-only (for example, a shared album with no write permission), the controls are dimmed with a reason.

**Gestures.**
- Tap a star to rate. Drag across the stars to set a rating (scrub). Long-press the star row to clear the rating (reset to default). Two-finger tap: undo the last rating or flag change (toast "Undone: rating 4 to 3"). Pinch: not applicable here, passes through to the image canvas.
- Pencil: tap only. Keyboard: 0 to 5, P, X, U; arrow keys move to the next photo (in cull mode, auto-advance after rating is a toggle, default off).

**Empty/loading/error.**
- Empty: no photo, the bar is hidden. Loading: controls are active immediately and changes queue. Error: "Couldn't save rating" with a pending indicator; changes retry automatically and persist locally first.

**Accessibility.**
- Star group is one adjustable element ("Rating, 3 of 5 stars, adjustable") with up and down changing value, and a Clear custom action. Flag group: "Flag, Picked, button group, 3 options" with the selected trait. Announce changes ("Rated 4 stars").
- Reduce Transparency: bar solid. Dynamic Type: icon-only controls get text labels under them at AX1+, and the bar can wrap onto two lines.

**Top 3 usability failures to prevent.**
1. Accidental rating by brushing the bar while panning. Mitigation: 8pt spacing from the canvas edge, touches that begin as drags on the image do not trigger the bar.
2. Tapping the current star unexpectedly clears. Mitigation: show the toast with Undo and apply only on lift.
3. Colour-only distinction for Pick vs Reject. Mitigation: distinct glyphs and labels.

---

## 9. Compare (Before / After)

**Purpose.** Verify the effect of edits against the original or against another version or photo.

**Entry/exit.** Entry: press-and-hold on the image (momentary), the Before/After button in the top bar (toggle), long-press on that button for modes. Exit: tap the button again, or Escape/Done in the persistent modes.

**Layout.**
- iPad landscape: modes are Hold (momentary), Split (draggable vertical wipe), Side by side (2-up, synchronised zoom and pan), and Top/Bottom. Mode picker is a ghost control in the top bar; selected mode uses the oval. The inspector can stay open, but side by side hides it by default for size.
- iPad portrait: Split (vertical or horizontal) and Top/Bottom stacked. Side by side is not the default (images too small) but available.
- iPhone: Hold and Split only by default; a stacked Top/Bottom is allowed in portrait. The inspector collapses.

**Controls and states.**
- Before/After button: default ghost, on state shows the oval and the label "Before" or "After" in the corner chip. Compare against: Original, a snapshot or version, another photo (from the filmstrip). Disabled: "Compare to" is disabled when the photo has no edits (Before equals After), with a reason.
- Split bar: a 44pt-wide draggable band with a 2pt visible line and a grab knob. Pressed: knob enlarges. Corner labels "Before" and "After".
- Sync toggle for zoom and pan (on by default).

**Gestures.**
- Press and hold on the image: show Before, release returns to After (a toggle option in settings). Drag the split bar to wipe; tap anywhere on the image to jump the bar there. Pinch zooms both sides together. Two-finger tap: undo, even in compare, and the preview updates live. Long-press the Before/After button: pick the compare mode.
- Pencil: drag the split bar with high precision; hover shows pixel values in the corner (optional). Double-tap on the image: toggle fit and 100% for both.

**Empty/loading/error.**
- Empty: "Nothing to compare yet. Make an edit to see before and after." Loading: both sides show the preview. The side that is not ready shows a shimmer, not a blank. Error: snapshot missing or deleted, the banner "That version is no longer available" with a switch to Original.

**Accessibility.**
- Button: "Before and after, toggle, showing After". Split position: adjustable ("Split position, 50 percent") in 5% steps. Mode picker labelled with the selected trait. Announce state changes ("Showing original").
- Reduce Transparency: corner labels solid. Dynamic Type: corner labels scale and remain legible; the bar knob keeps 44pt minimum.

**Top 3 usability failures to prevent.**
1. Users cannot tell which side is which. Mitigation: persistent corner labels, with Before always on the left or top.
2. Zoom and pan fall out of sync, so details do not line up. Mitigation: sync on by default, and a "Realign" action when desynchronised.
3. Hold to compare is awkward when both hands are in use, or conflicts with the long-press reset gesture. Mitigation: the long-press-hold behaviour applies only on the image area, with a button toggle alternative.

---

## Appendix: cross-panel conflict resolutions
- Long-press means "reset to default" on controls and "hold to compare original" on the image area; the two never overlap because the image area contains no resettable controls.
- Two-finger tap = undo everywhere in the editor and library; Export and system sheets ignore it.
- Pinch always zooms the canvas, except in Crop, where it zooms the image inside the crop (indicated by a mode badge and a Fit button).
- Exactly one selected oval per control group, so there is never more than one visible per row.
