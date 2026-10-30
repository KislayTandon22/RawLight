# Prompt for Figma Make / Lovable: LightCraft for iPad and iPhone

Paste everything below the line into the tool. If it asks for one screen at a time, start with "Edit (iPhone)" and then ask for the others.

---

Design a native-feeling iOS and iPadOS photo editor called **LightCraft**: a fast, RAW-capable editor in the spirit of Lightroom mobile, built for touch. Produce high-fidelity screens, not wireframes: real photos, real labels, real states. Dark theme, iOS 26 "Liquid Glass" look, Inter font. iPad landscape is the primary layout; also iPad portrait and iPhone (390x844 with 59px top and 34px bottom safe insets).

## What the app does
Import RAW and JPEG photos, browse and cull them, edit non-destructively, mask, crop, apply presets, and export. Everything runs on device.

Screens to produce, each for iPhone, iPad portrait and iPad landscape:
1. **Library**: photo grid grouped by day, search with suggestions, multi-select filters (Picked, Rejected, Unflagged, star ratings, Edited), sort, thumbnail-size slider, Select mode, Import button. Photo cells show stars, pick or reject flag, an edited badge, and states for offline, cannot decode, and loading.
2. **Edit**: large photo, histogram, Auto / B&W / HDR quick actions, Profile dropdown, parameter groups Light, Colour, Effects, Detail, Optics (Exposure, Contrast, Highlights, Shadows, Whites, Blacks, Temp, Tint, Vibrance, Saturation, Colour mixer, Colour grading, Texture, Clarity, Dehaze, Sharpening, Noise, Lens correction), Tone curve with RGB channels, Pick / Reject / star flags, before and after, undo and redo, copy and paste edit settings.
3. **Masking**: add Subject, Sky, Brush, Linear, Radial; mask list with eye toggles; Add / Subtract / Invert; per-mask sliders; overlay on / outline / off; on-canvas handles.
4. **Crop and geometry**: aspect chips (Original, Free, 1:1, 4:5, 3:2, 16:9, Custom), straighten ruler, rotate and flip, guides (thirds, golden ratio, grid), Upright (Off, Auto, Level, Vertical, Full), exact size, Cancel and Done.
5. **Presets / Looks**: category dropdown, search, thumbnail grid, strength slider, Replace or Add on top, save current as preset.
6. **Export**: format (JPEG, HEIC, TIFF, PNG), quality, size (original, long edge, percent), colour space (sRGB, Display P3, Adobe RGB), metadata options, save to (Photos, Files, Share, Copy), one Export button, progress state.
7. Also draw: Heal and Remove tool, compare / survey view, settings, import flow, first-run onboarding, and empty and error states.

## Design language (follow strictly)
- **Two materials that follow the device theme.** Liquid Glass when the OS draws it (translucent white about 16 percent, strong background blur, a thin light rim on the top edge only), solid dark greys (#1C1C1C canvas, #282828 and #363636 surfaces) otherwise. Same shapes and sizes in both.
- **Bars:** all top and bottom bars are floating capsules, **60px tall, 8px inset on all four sides, radius 30**. Controls inside are 44px. Symmetric padding everywhere; 16px screen margins; 8px gap inside a group and 16px between groups.
- **Mode selector at the bottom, never a side rail.** One floating glass capsule like the iOS 26 tab bar: every tab is an icon with its label under it; the selected tab is tinted with the accent colour on a soft lighter pill. While dragging, the selected tab lifts into a larger glass lens that magnifies its icon and label and follows the finger. Modes: Library, Edit, Crop, Heal, Mask, Looks, History. The same bar style is used for parameter groups inside the inspector.
- **Buttons:** 44px capsules, 15px bold labels. **One filled blue (#0A84FF) button per screen** (Done, Export, Import). Helpful actions (Auto) use a blue tint at 18 percent; Cancel is neutral (white at 12 percent); destructive is a red tint. Related icon buttons share one capsule. **No outlines, no hairline borders, no divider lines anywhere.**
- **Selected state is one soft oval** (white at 20 percent). No tick marks. Multi-select shows several ovals.
- **Dropdown menus** are a rounded card (radius 28, 8px inset), rows 48px tall with a 20px icon, 16px label and an optional value or count badge on the right, no dividers. Selected row in the soft oval.
- **Search** is a 44px capsule with a search icon, the typed text and a clear button; suggestions drop down in the same menu card with 40px thumbnails, the matched text highlighted, a second line (date, flags) and a count.
- **Sliders** come in six types, each in its own rounded capsule with an optional action button on the right: value slider (thin track, 24px thumb, reset button), gradient slider (Temp, Tint, Hue, with eyedropper), tick-ruler (Straighten), stepped dots, segmented switch, icon segment. On iPhone Edit, use **one ruler slider at a time**: a row of round parameter icons (the selected one with a progress ring and a small label above it), the ruler below with the current value, and a bottom tab bar with a prominent centre Auto pill.
- **Typography:** Inter, text 12px or larger, secondary text white at 62 percent.
- **Less clutter:** progressive disclosure. Show one group of controls at a time, generous spacing, nothing decorative.
- iPad landscape layout: big photo on the left, a docked inspector about 340px wide on the right, a slim top bar (back, undo and redo, file name, filter, share), a filmstrip with a small glass Pick / Reject / stars capsule, and the mode capsule centred at the bottom.
- iPad portrait: slim top bar, large photo, a docked bottom sheet for controls, mode capsule at the very bottom.
- iPhone: full-bleed photo, floating glass controls on top, a glass bottom panel.

## References for the look (visit and match the feel, do not copy)
- Liquid Glass tab bar with icon and label and a magnifying lens: https://dribbble.com/shots/26361614-Liquid-Glass
- iOS 26 glass tab bar: https://dribbble.com/shots/26600476-Tabs
- Minimal segmented tab group: https://dribbble.com/shots/25193731-Tabs-Concept
- Liquid Glass buttons: https://dribbble.com/shots/26231218-iOS-26-Liquid-Glass-Buttons and https://dribbble.com/shots/26151993-Liquid-Glass-Button
- Vertical menu card: https://dribbble.com/shots/24096611-slothUI-World-s-Laziest-Design-System-Vertical-Tab-Component
- Search bar with suggestions: https://dribbble.com/shots/24569120-Search-Input-Bar-Roblox-Trading-Platform-plstrade
- Sliders: https://dribbble.com/shots/25285143-Sliders
- Mobile photo editor with parameter icons and ruler: https://cdn.dribbble.com/userupload/45367309/file/ab73c0377ff68e39ce3a826e39caa743.png

- Our own mockups to match (private link, I will attach screenshots if you cannot open it): https://claude.ai/artifact/WnTHFZF9smZ7X1aGc6mmxp. The boards named "v2 ..." at the bottom are the target look; "Tabs and dropdowns", "Buttons and search" and "Slider families" are the component specs.
- Original app being redesigned: https://github.com/storytold/lightcraft

## Output
Give me an interactive prototype with these flows: Library, open a photo, Edit with the parameter groups, Masking, Crop, Presets, Export. Tapping the bottom capsule switches modes. Provide Figma-style components for: capsule bar, glass and solid button set, dropdown card, search with suggestions, the six slider types, photo cell with all states.
