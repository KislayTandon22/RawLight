# LightCraft iPad design spec (from Apple HIG, fetched 2026-10-28)

Sources (Apple text): HIG `materials`, `layout`, `toolbars` (developer.apple.com/design/human-interface-guidelines).

## Rules taken from Apple
1. Liquid Glass is for the functional layer (bars, rail, sidebars, popovers, sheets) floating above content. Content (photo grid,
   canvas, filmstrip thumbnails) is not glass. Use the Regular variant for anything with text; Clear only over photos.
2. Controls inside a bar are symbols without borders or outlined circles; the bar is the container and hover/selection is a
   highlight. Text buttons are kept apart from symbol buttons so they do not read as one control. One prominent (filled) action per bar.
3. A toolbar has at most three groups: leading (navigation), centre (common tools), trailing (essential + primary). Rare actions go in More.
4. Group with negative space and containers, not separator lines. Align related items; indent subordinate ones.
5. Content extends under bars (scroll-edge effect) instead of a solid slab behind controls.
6. Corner radii are concentric: inner radius = outer radius - padding.
7. Layout follows size classes, not orientation; test the largest and smallest first; support Dynamic Type (rows grow, never clip).
8. Respect Reduce Transparency / Increase Contrast: glass falls back to an opaque fill.

## Tokens (touch only, `theme::touch_ui`)
- Side margin 16 (grid, headers, filter strip, panel rows, dialogs).
- Gap between neighbours 8; between groups 16; row height 44; pill height 36-44.
- Bar radius 22 (SHELL_RADIUS); card inner controls 14 = 22 - 8.
- Text 14-17 body, 12.5 minimum secondary.

## Done in this pass
- Grid side margin 16, headers aligned with photos (`TOUCH_GRID_INSET`).
- Filter strip: no slab, 16 margin.
- Histogram: rounded tile inset 10 from the card edge.
- Dialogs: centred heading in the card instead of egui's title band; overlay scroll bars so nothing is narrower than the window.

## Still to do (ranked)
1. Top bar: 13 controls in one row; regroup into leading / centre / trailing, Menu + Select as the only text buttons, bell/cloud into More.
2. Bottom bar: rater, flags, Copy Edit Settings, gear and zoom in one pill; split into a left view switcher and a centred rating group.
3. Edit panel: empty gaps under Auto/B&W/HDR/Reset and under Profile; section headers as one list style; dash artifacts at the top of panels.
4. Highlight-only buttons: remove filled capsules from tool rows, keep fill for the selected state and for the single primary action.
5. Reduce Transparency / Increase Contrast / Dynamic Type honoured from the iOS host.
6. Scroll-edge fade where a scroll area is cut by a bar or dialog button row (Export shows a half-cut row).
