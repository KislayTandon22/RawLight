//! Saved watermarks (Pro Export dialog): one portable `<name>.json` per watermark in
//! `<config dir>/watermarks/`, written and read with [`lightcraft_engine::watermark_pack`], so a
//! file there can be copied to another machine as it is. A graphic travels inside its file; on
//! load it is unpacked next to the files under a content-derived name.

use lightcraft_engine::export::{Anchor, Watermark};
use lightcraft_engine::watermark_pack;
use std::path::{Path, PathBuf};

/// A watermark on disk.
#[derive(Clone, Debug, PartialEq)]
pub struct Saved {
    /// The name shown in the list (the file's name without `.json`).
    pub name: String,
    pub path: PathBuf,
    pub watermark: Watermark,
}

/// The folder saved watermarks live in (`None` when the host has no config folder).
pub fn dir() -> Option<PathBuf> {
    lightcraft_engine::config::config_dir().map(|d| d.join("watermarks"))
}

/// A file name for `name`: path separators and characters Windows refuses become `-`.
pub fn file_stem(name: &str) -> String {
    let s: String = name.trim().chars().map(|c| if c.is_control() || "<>:\"/\\|?*".contains(c) { '-' } else { c }).collect();
    s.trim_matches(['.', ' ']).chars().take(80).collect()
}

/// Every watermark file in `dir`, by name. A file that doesn't read as a watermark is skipped.
pub fn list_in(dir: &Path) -> Vec<Saved> {
    let Ok(read) = std::fs::read_dir(dir) else { return Vec::new() };
    let mut out: Vec<Saved> = read
        .flatten()
        .filter_map(|e| {
            let path = e.path();
            if path.extension().and_then(|x| x.to_str()) != Some("json") {
                return None;
            }
            let name = path.file_stem()?.to_string_lossy().into_owned();
            let json = std::fs::read_to_string(&path).ok()?;
            let (_, watermark) = watermark_pack::import_json(&json, dir).ok()?;
            Some(Saved { name, path, watermark })
        })
        .collect();
    out.sort_by_key(|s| s.name.to_lowercase());
    out
}

/// Write `wm` as `<name>.json` in `dir` (created if needed), replacing a file of that name.
pub fn save_in(dir: &Path, name: &str, wm: &Watermark) -> Result<PathBuf, String> {
    let stem = file_stem(name);
    if stem.is_empty() {
        return Err("Give the watermark a name".into());
    }
    let json = watermark_pack::export_json(wm, &stem)?;
    std::fs::create_dir_all(dir).map_err(|e| format!("can't create {}: {e}", dir.display()))?;
    let path = dir.join(format!("{stem}.json"));
    std::fs::write(&path, json).map_err(|e| format!("can't save {}: {e}", path.display()))?;
    Ok(path)
}

/// Remove the saved watermark `name` from `dir`. A name that isn't there is not an error.
pub fn delete_in(dir: &Path, name: &str) -> Result<(), String> {
    let path = dir.join(format!("{}.json", file_stem(name)));
    match std::fs::remove_file(&path) {
        Ok(()) => Ok(()),
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => Ok(()),
        Err(e) => Err(format!("can't delete {}: {e}", path.display())),
    }
}

/// A name for a copy of `name` that `taken` doesn't have (`Name copy`, `Name copy 2`, …).
pub fn copy_name(name: &str, taken: &[String]) -> String {
    let mut candidate = format!("{name} copy");
    let mut n = 2;
    while taken.iter().any(|t| t.eq_ignore_ascii_case(&candidate)) && n < 1000 {
        candidate = format!("{name} copy {n}");
        n += 1;
    }
    candidate
}

/// `text · bottomRight · framed`, as in the list row's second line.
pub fn summary(wm: &Watermark) -> String {
    let kind = if wm.image.trim().is_empty() { "text" } else { "graphic" };
    let anchor = match wm.anchor {
        Anchor::TopLeft => "topLeft",
        Anchor::Top => "top",
        Anchor::TopRight => "topRight",
        Anchor::Left => "left",
        Anchor::Center => "center",
        Anchor::Right => "right",
        Anchor::BottomLeft => "bottomLeft",
        Anchor::Bottom => "bottom",
        Anchor::BottomRight => "bottomRight",
    };
    let mut s = format!("{kind} · {anchor}");
    if wm.rotation != 0 {
        s.push_str(&format!(" · rotation {}", wm.rotation));
    }
    if wm.border_width > 0.0 {
        s.push_str(" · framed");
    }
    if wm.background_opacity > 0.0 {
        s.push_str(&format!(" · box {:.0}%", wm.background_opacity * 100.0));
    }
    s
}

#[cfg(test)]
mod tests {
    use super::*;

    fn tmp(name: &str) -> PathBuf {
        let d = std::env::temp_dir().join(format!("lc-wm-store-{name}-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&d);
        std::fs::create_dir_all(&d).expect("tmp dir");
        d
    }

    #[test]
    fn saved_watermark_round_trips_through_the_folder() {
        let dir = tmp("round");
        let wm = Watermark {
            text: "© Aanya Rao".into(),
            anchor: Anchor::TopLeft,
            rotation: 90,
            border_width: 0.003,
            border_color: [245, 194, 107],
            padding: 0.012,
            background_opacity: 0.35,
            radius: 0.01,
            ..Default::default()
        };
        save_in(&dir, "Signature / corner", &wm).expect("save");
        save_in(&dir, "Another", &Watermark::default()).expect("save second");
        let list = list_in(&dir);
        assert_eq!(list.iter().map(|s| s.name.as_str()).collect::<Vec<_>>(), ["Another", "Signature - corner"]);
        let back = &list[1].watermark;
        assert_eq!(back, &wm);
        assert!(summary(back).contains("framed"));
        delete_in(&dir, "Signature - corner").expect("delete");
        delete_in(&dir, "never saved").expect("deleting nothing is fine");
        assert_eq!(list_in(&dir).len(), 1);
    }

    #[test]
    fn unreadable_files_are_skipped_and_empty_names_refused() {
        let dir = tmp("junk");
        std::fs::write(dir.join("junk.json"), "not json").expect("write");
        std::fs::write(dir.join("notes.txt"), "x").expect("write");
        assert!(list_in(&dir).is_empty());
        assert!(save_in(&dir, "  ", &Watermark::default()).is_err());
        assert!(list_in(&dir.join("missing")).is_empty());
        assert_eq!(copy_name("A", &["a copy".into()]), "A copy 2");
    }
}
