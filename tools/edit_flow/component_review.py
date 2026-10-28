#!/usr/bin/env python3
"""Bottom-up UI review: one component at a time (atoms -> molecules -> panels -> screens), several models per component.

Usage:
  component_review.py [--level atoms|molecules|panels|all] [--only NAME,NAME] [--size 1180x820] [--out DIR]
                      [--reviewers gemini,deepseek] [--no-models] [--cli PATH]

For every component in COMPONENTS the pipeline
  1. renders its screen headlessly (touch layout) and reads the registered widget rectangles (`ui.widgets`)
  2. FACTS   measures what a reviewer cannot see in a PNG: sizes, gaps between neighbours, side margins to the container,
             rows that do not line up, text/background contrast sampled from the crop
  3. CROP    writes DIR/crops/<name>.png (2x, with a margin) so a person or a vision model can look at the part
  4. CODE    pulls the source lines that draw it (files + patterns below)
  5. REVIEW  asks each reviewer (gemini = `agy`, deepseek = `opencode run`) for findings as JSON, from the facts, the
             Apple HIG checklist and the code. Neither CLI reads images headless, so they work from facts + code.
  6. REPORT  DIR/report.md and findings.json. Every finding starts as UNVERIFIED: a person (or Claude) confirms it on the crop
             or in the code before anything is changed; reviewers over-claim.
Add a component by adding a dict to COMPONENTS (screen state + widget id regex + source files). Nothing is downloaded.
"""
import argparse, json, os, re, statistics, subprocess, sys
from PIL import Image

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
SRC = os.path.join(ROOT, "crates", "ui-egui", "src")

ap = argparse.ArgumentParser()
ap.add_argument("--level", default="all")
ap.add_argument("--only", default="")
ap.add_argument("--size", default="1180x820")
ap.add_argument("--out", default="/tmp/lc_component_review")
ap.add_argument("--reviewers", default="gemini,deepseek")
ap.add_argument("--no-models", action="store_true", help="facts, crops and code only")
ap.add_argument("--cli", default=os.path.join(ROOT, "target/debug/lightcraft-cli"))
a = ap.parse_args()
W, H = (int(v) for v in a.size.split("x"))
os.makedirs(os.path.join(a.out, "crops"), exist_ok=True)

DETAIL_EDIT = {"view": "detail", "right": "edit"}
GRID = {"view": "photoGrid", "right": "none"}
# level, screen state, widget id regex, optional container id regex (for margins), source files (relative to ui-egui/src) + patterns
COMPONENTS = {
    "button-pill": dict(level="atoms", state=DETAIL_EDIT, ids=r"^button:(auto|bw|hdr|reset)$", container=r"^panel:right_panel$",
                        code=[("panels/edit.rs", r"Auto|B&W"), ("widgets.rs", r"fn chip|fn pill|fn text_button")]),
    "tool-rail-icon": dict(level="atoms", state=DETAIL_EDIT, ids=r"^icon:(presets|edit|crop|remove|masking|redeye|versions|activity|more|keywords|info)$",
                           code=[("panels/right_touch.rs", r"icon|rail")]),
    "star": dict(level="atoms", state=GRID, ids=r"^star:bottom:\d$", code=[("panels/bottombar_touch.rs", r"star|rating")]),
    "flag": dict(level="atoms", state=GRID, ids=r"^flag:", code=[("panels/bottombar_touch.rs", r"flag")]),
    "slider": dict(level="atoms", state=DETAIL_EDIT, ids=r"^slider:light\.", container=r"^panel:right_panel$",
                   code=[("widgets.rs", r"fn paint_track|fn slider|hit")]),
    "dropdown": dict(level="atoms", state=DETAIL_EDIT, ids=r"^dropdown:profile$", container=r"^panel:right_panel$",
                     code=[("widgets.rs", r"fn dropdown")]),
    "section-header": dict(level="atoms", state=DETAIL_EDIT, ids=r"^section:", container=r"^panel:right_panel$",
                           code=[("panels/edit.rs", r"section")]),
    "topbar-icon": dict(level="atoms", state=DETAIL_EDIT, ids=r"^(icon:(sidebar|back|forward|undo|redo|filter|appearance|bell|share|cloud)|button:multiSelect|menu:all)$",
                        code=[("panels/topbar_touch.rs", r"icon|button")]),
    "rating-bar": dict(level="molecules", state=GRID, ids=r"^(star:bottom:\d|flag:.*)$",
                       code=[("panels/bottombar_touch.rs", r"rating|star|flag|pill")]),
    "bottom-bar": dict(level="molecules", state=GRID, ids=r"^(star:bottom:\d|flag:.*|icon:viewOptions|icon:viewMore|dropdown:zoom|button:copy.*|button:.*gear.*)$",
                       code=[("panels/bottombar_touch.rs", r"fn ")]),
    "top-bar": dict(level="molecules", state=DETAIL_EDIT, ids=r"^(icon:(sidebar|back|forward|undo|redo|filter|appearance|bell|share|cloud)|button:multiSelect|menu:all|field:search)$",
                    code=[("panels/topbar_touch.rs", r"fn ")]),
    "edit-panel": dict(level="panels", state=DETAIL_EDIT, ids=r"^(button:(auto|bw|hdr|reset|rightPanelClose)|dropdown:profile|histogram|section:.*|slider:.*)$",
                       container=r"^panel:right_panel$", code=[("panels/edit.rs", r"fn |glass")]),
    "tool-rail": dict(level="panels", state=DETAIL_EDIT, ids=r"^icon:(presets|edit|crop|remove|masking|redeye|versions|activity|more|keywords|info)$",
                      code=[("panels/right_touch.rs", r"fn ")]),
}
ORDER = ["atoms", "molecules", "panels"]

CHECKLIST = """Apple HIG (iPadOS, touch) checklist you must judge against:
- Hit targets >= 44x44pt (36 acceptable only with 8pt spacing); >= 8pt between neighbours; text >= 12pt, body 14-17pt.
- Controls in a bar are symbols without borders; a bar groups at most three sets; text buttons are kept apart from symbol buttons; one filled primary action per bar.
- Group with whitespace and containers, not lines. Same side margin everywhere (16pt). Concentric corner radii (inner = outer - padding).
- Contrast: text 4.5:1, icons/borders 3:1; state is not shown by colour alone. Selected = highlight, not a heavier border.
- Labels: verb phrases in Title Case; ellipsis when more input follows. Names spoken by VoiceOver.
- Glass only for the functional layer (bars, rail, panels), not for content; Reduce Transparency / Dynamic Type must not clip text.

Craft rules from ui-skills.com (better-ui, improve-ui; third-party guidance, apply only when the facts or code show it):
- Concentric radii: outer radius = inner radius + padding (+ border). A control in a capsule bar: bar radius = control radius + inset; the inset on the left equals the inset above and below.
- Optical alignment: where geometric centring looks off (icon + chevron, play-like glyphs, text in a pill) nudge by eye; a lone chevron or icon in a capsule is not centred on the capsule.
- Icons: stroke weight matches the adjacent text; outline for the default state, filled for the active state; colour, not separate assets, carries hover / selected / disabled.
- Borders only for structure (dividers, inputs, selected states); where a border only adds depth use a soft shadow. No hairline outlines on glass cards.
- Press feedback: a pressed control shows a state change within 150ms (scale about 0.96 or a fill); a disabled one never does. High-frequency actions (taps on stars, row hovers, tab switches) are instant, not animated. Every animated change also has a static cue.
- Motion respects Reduce Motion (fade instead of move/scale).

Reporting rules (improve-ui): a finding must pass three proofs: (1) contract: a stated rule above or a contradiction between sibling controls; (2) runtime: the cited value or line really reaches the screen (use the measured facts); (3) correction: ONE specific change naming existing constants/tokens. Drop anything with several possible fixes or that needs invented product intent. Report at most 6, strongest first."""

# ---------------------------------------------------------------------------------------------------------- render
def render(name, comp):
    script = os.path.join(a.out, f"{name}.jsonl")
    lines = [
        {"id": 1, "method": "engine.execute", "params": {"command": "library.select", "params": {"ids": [3]}}},
        {"id": 2, "method": "ui.set", "params": {**comp["state"], "leftPanel": False}},
        {"id": 3, "method": "ui.settle", "params": {"timeoutMs": 4000}},
        {"id": 4, "method": "ui.widgets", "params": {}},
        {"id": 5, "method": "ui.screenshot", "params": {"path": os.path.join(a.out, f"{name}_full.png"), "headless": True}},
    ]
    open(script, "w").write("\n".join(json.dumps(l) for l in lines) + "\n")
    p = subprocess.run([a.cli, "snapshot", "--touch", "--demo", "--script", script, "-o", os.path.join(a.out, f"{name}_end.png"), "--size", a.size],
                       capture_output=True, text=True)
    for l in p.stdout.splitlines():
        if l.startswith("{"):
            x = json.loads(l)
            if x.get("id") == 4 and x.get("ok"):
                return x["result"]
    raise SystemExit(f"{name}: ui.widgets failed\n{p.stderr[-400:]}")

# ---------------------------------------------------------------------------------------------------------- facts
def lum(c):
    f = lambda v: (v / 255) / 12.92 if v / 255 <= 0.03928 else (((v / 255) + 0.055) / 1.055) ** 2.4
    return 0.2126 * f(c[0]) + 0.7152 * f(c[1]) + 0.0722 * f(c[2])

def ratio(c1, c2):
    a1, a2 = sorted((lum(c1), lum(c2)), reverse=True)
    return (a1 + 0.05) / (a2 + 0.05)

def contrast(img, r):
    """Background = the commonest colour in the crop, foreground = the pixel furthest from it in luminance."""
    x, y, w, h = (int(round(v)) for v in r)
    if x >= img.width or y >= img.height or x + w <= 0 or y + h <= 0:
        return None  # off screen (below the fold)
    box = img.crop((max(0, x), max(0, y), min(img.width, x + w), min(img.height, y + h))).convert("RGB")
    px = list(box.getdata())
    if not px:
        return None
    bg = max(set(px), key=px.count)
    fg = max(px, key=lambda c: abs(lum(c) - lum(bg)))
    return round(ratio(fg, bg), 2), "#%02x%02x%02x" % bg, "#%02x%02x%02x" % fg

def facts(comp, widgets, full):
    ws = [w for w in widgets if re.search(comp["ids"], w["id"]) and len(w["rect"]) == 4 and w["rect"][2] > 0]
    out = {"count": len(ws), "widgets": []}
    if not ws:
        return out, ws
    img = Image.open(full) if os.path.exists(full) else None
    for w in sorted(ws, key=lambda w: (round(w["rect"][1] / 20), w["rect"][0])):
        x, y, ww, hh = w["rect"]
        d = {"id": w["id"], "x": round(x), "y": round(y), "w": round(ww), "h": round(hh)}
        if img and ww * hh < 150000:
            c = contrast(img, w["rect"])
            if c:
                d["contrast"], d["bg"], d["fg"] = c
        out["widgets"].append(d)
    sizes = [(w["rect"][2], w["rect"][3]) for w in ws]
    out["min_size"] = [round(min(s[0] for s in sizes)), round(min(s[1] for s in sizes))]
    out["max_size"] = [round(max(s[0] for s in sizes)), round(max(s[1] for s in sizes))]
    out["under_44"] = [w["id"] for w in ws if min(w["rect"][2], w["rect"][3]) < 44]
    # rows: widgets whose vertical centres are within 12pt share a row; report gaps along the row
    rows = {}
    for w in ws:
        rows.setdefault(round((w["rect"][1] + w["rect"][3] / 2) / 24), []).append(w)
    gaps, misaligned = [], []
    for k, row in rows.items():
        row.sort(key=lambda w: w["rect"][0])
        for p, q in zip(row, row[1:]):
            gaps.append(round(q["rect"][0] - (p["rect"][0] + p["rect"][2]), 1))
        if len(row) > 1:
            cs = [w["rect"][1] + w["rect"][3] / 2 for w in row]
            if max(cs) - min(cs) > 1.5:
                misaligned.append([w["id"] for w in row])
    out["gaps_in_rows"] = gaps
    out["gap_spread"] = round(max(gaps) - min(gaps), 1) if gaps else 0
    out["vertical_centre_misaligned"] = misaligned
    cols = {}
    for w in ws:
        cols.setdefault(round(w["rect"][0]), []).append(w)
    vgaps = []
    for col in cols.values():
        col.sort(key=lambda w: w["rect"][1])
        vgaps += [round(q["rect"][1] - (p["rect"][1] + p["rect"][3]), 1) for p, q in zip(col, col[1:])]
    out["gaps_in_columns"] = vgaps
    if comp.get("container"):
        cont = next((w for w in widgets if re.search(comp["container"], w["id"])), None)
        if cont:
            cx, cy, cw, ch = cont["rect"]
            out["left_margin_to_container"] = round(min(w["rect"][0] for w in ws) - cx, 1)
            out["right_margin_to_container"] = round(cx + cw - max(w["rect"][0] + w["rect"][2] for w in ws), 1)
    out["inside_window"] = all(w["rect"][0] >= 0 and w["rect"][1] >= 0 and w["rect"][0] + w["rect"][2] <= W and w["rect"][1] + w["rect"][3] <= H for w in ws)
    return out, ws

def crop(name, ws, full):
    if not ws or not os.path.exists(full):
        return None
    x0 = min(w["rect"][0] for w in ws); y0 = min(w["rect"][1] for w in ws)
    x1 = max(w["rect"][0] + w["rect"][2] for w in ws); y1 = max(w["rect"][1] + w["rect"][3] for w in ws)
    m = 14
    box = (max(0, x0 - m), max(0, y0 - m), min(W, x1 + m), min(H, y1 + m))
    if box[2] <= box[0] or box[3] <= box[1]:
        return None  # the widgets are off screen (below the fold)
    im = Image.open(full).convert("RGB").crop(tuple(int(v) for v in box))
    if im.width > 900 or im.height > 900:
        im.thumbnail((900, 900))
    elif im.width < 700:
        im = im.resize((im.width * 2, im.height * 2), Image.LANCZOS)
    p = os.path.join(a.out, "crops", f"{name}.png")
    im.save(p)
    return p

def code(comp):
    chunks = []
    for rel, pat in comp.get("code", []):
        path = os.path.join(SRC, rel)
        if not os.path.exists(path):
            continue
        lines = open(path, encoding="utf-8", errors="ignore").read().splitlines()
        hits = [i for i, l in enumerate(lines) if re.search(pat, l)][:6]
        for i in hits:
            chunks.append(f"// {rel}:{i + 1}\n" + "\n".join(lines[max(0, i - 3): i + 22]))
    return "\n\n".join(chunks)[:7000]

# ---------------------------------------------------------------------------------------------------------- reviewers
def prompt(name, comp, f, src):
    return f"""You are a senior iPad UI engineer reviewing ONE component of LightCraft, a photo editor (Rust/egui) in its iPad touch layout
({W}x{H} landscape, dark glass look). Component: {name} (level: {comp['level']}).
{CHECKLIST}

MEASURED FACTS (points; from the real layout, trust these):
{json.dumps({k: v for k, v in f.items() if k != 'widgets'}, indent=1)}
Per widget: {json.dumps(f.get('widgets', [])[:24])}

SOURCE (touch paths are behind crate::theme::touch_ui / glass::active; desktop must not change):
{src}

Reply with ONLY a JSON array (max 6 items), each: {{"severity":"P0|P1|P2|P3","rule":"which checklist rule","evidence":"the exact number or code line","fix":"touch-only change, file + constant","confidence":0-1}}.
Only report what the facts or code prove; do not invent. If the component is fine, return []."""

def ask(reviewer, text):
    try:
        if reviewer == "gemini":
            argv = [os.path.expanduser("~/.local/bin/agy"), "--model", "gemini-3.8-flash-high", "--mode", "plan", "-p", text]
        elif reviewer == "deepseek":
            argv = [os.path.expanduser("~/.opencode/bin/opencode"), "run", "-m", "opencode/deepseek-v4.1-flash-free", text]
        else:
            return None, f"unknown reviewer {reviewer}"
        out = subprocess.run(argv, capture_output=True, text=True, timeout=300).stdout
    except Exception as e:
        return None, f"failed: {e}"
    m = re.search(r"\[.*\]", out, re.S)
    if not m:
        return None, out.strip()[-300:]
    try:
        return json.loads(m.group(0)), ""
    except Exception:
        return None, "unparsable: " + out.strip()[-300:]

# ---------------------------------------------------------------------------------------------------------- run
names = [n for n, c in COMPONENTS.items() if (a.level == "all" or c["level"] == a.level) and (not a.only or n in a.only.split(","))]
names.sort(key=lambda n: ORDER.index(COMPONENTS[n]["level"]))
results = []
for n in names:
    comp = COMPONENTS[n]
    widgets = render(n, comp)
    full = os.path.join(a.out, f"{n}_full.png")
    f, ws = facts(comp, widgets, full)
    r = {"component": n, "level": comp["level"], "facts": f, "crop": crop(n, ws, full), "findings": {}}
    if f["count"] and not a.no_models:
        text = prompt(n, comp, f, code(comp))
        for rv in a.reviewers.split(","):
            items, err = ask(rv, text)
            r["findings"][rv] = {"items": items or [], "error": err}
    print(f"{n}: {f['count']} widgets, under44={len(f.get('under_44', []))}, gaps={sorted(set(f.get('gaps_in_rows', [])))[:6]}")
    results.append(r)
json.dump(results, open(os.path.join(a.out, "findings.json"), "w"), indent=1)

md = ["# Component review (bottom-up)", "", f"size {a.size}, reviewers: {a.reviewers}. Every finding is UNVERIFIED until confirmed on the crop or in the code.", ""]
for r in results:
    f = r["facts"]
    md += [f"## {r['level']} / {r['component']}", ""]
    if r["crop"]:
        md.append(f"![{r['component']}](crops/{os.path.basename(r['crop'])})")
    md += ["", f"- widgets: {f['count']}; smallest {f.get('min_size')}; under 44pt: {len(f.get('under_44', []))}",
           f"- gaps in rows: {sorted(set(f.get('gaps_in_rows', [])))}; spread {f.get('gap_spread')}; in columns: {sorted(set(f.get('gaps_in_columns', [])))}",
           f"- margins to container (left/right): {f.get('left_margin_to_container')} / {f.get('right_margin_to_container')}",
           f"- centre-misaligned rows: {len(f.get('vertical_centre_misaligned', []))}; lowest contrast: "
           f"{min((w['contrast'] for w in f.get('widgets', []) if 'contrast' in w), default='n/a')}", ""]
    seen = {}
    for rv, x in r["findings"].items():
        for it in x["items"]:
            key = (it.get("rule", "")[:30]).lower()
            seen.setdefault(key, []).append((rv, it))
        if x["error"]:
            md.append(f"- {rv}: {x['error']}")
    if seen:
        md += ["| sev | rule | evidence | fix | by | status |", "|---|---|---|---|---|---|"]
        for key, lst in sorted(seen.items(), key=lambda kv: min(i[1].get("severity", "P9") for i in kv[1])):
            it = lst[0][1]
            by = "+".join(sorted({rv for rv, _ in lst}))
            md.append(f"| {it.get('severity')} | {it.get('rule')} | {str(it.get('evidence'))[:140]} | {str(it.get('fix'))[:140]} | {by} | UNVERIFIED |")
    md.append("")
open(os.path.join(a.out, "report.md"), "w").write("\n".join(md))
print("report:", os.path.join(a.out, "report.md"))
