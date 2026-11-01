//! Portable watermark files: a watermark's settings plus its graphic, in one `.json` that another
//! person can import. The graphic travels inside the file (base64), so nothing points at a path on
//! the sender's machine.

use crate::export::{Watermark, watermark_logo};
use serde::{Deserialize, Serialize};
use std::path::Path;

/// `kind` of every watermark file; anything else is not one.
pub const KIND: &str = "lightcraft-watermark";
/// The file layout this build writes and reads.
pub const VERSION: u32 = 1;
/// A graphic larger than this is refused, on export and on import.
pub const MAX_LOGO_BYTES: usize = 6 * 1024 * 1024;

#[derive(Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
struct Pack {
    kind: String,
    version: u32,
    name: String,
    watermark: serde_json::Value,
    /// The graphic's file, base64, when the watermark draws one.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    logo: Option<String>,
}

/// The watermark as the text of a `.json` file named `name`. A graphic is read from disk and
/// embedded; its path is not written.
pub fn export_json(wm: &Watermark, name: &str) -> Result<String, String> {
    let logo = if wm.image.trim().is_empty() {
        None
    } else {
        let bytes = std::fs::read(wm.image.trim()).map_err(|e| format!("can't read the graphic: {e}"))?;
        if bytes.len() > MAX_LOGO_BYTES {
            return Err(format!("the graphic is larger than {} MB", MAX_LOGO_BYTES / 1024 / 1024));
        }
        if logo_extension(&bytes).is_none() {
            return Err("the graphic is not a PNG or JPEG".into());
        }
        Some(encode(&bytes))
    };
    let mut value = serde_json::to_value(wm).map_err(|e| e.to_string())?;
    if let Some(o) = value.as_object_mut() {
        o.remove("image");
    }
    let pack = Pack { kind: KIND.into(), version: VERSION, name: name.trim().to_string(), watermark: value, logo };
    serde_json::to_string_pretty(&pack).map_err(|e| e.to_string())
}

/// The name and watermark in `json`. A graphic is written into `assets_dir` (created if needed)
/// under a name made from its content, so importing the same file twice stores it once.
pub fn import_json(json: &str, assets_dir: &Path) -> Result<(String, Watermark), String> {
    let pack: Pack = serde_json::from_str(json).map_err(|e| format!("not a watermark file: {e}"))?;
    if pack.kind != KIND {
        return Err("not a LightCraft watermark file".into());
    }
    if pack.version > VERSION {
        return Err("this watermark file was made by a newer version".into());
    }
    let mut value = pack.watermark;
    if let Some(o) = value.as_object_mut() {
        o.retain(|k, _| crate::export::WATERMARK_PARAMS.contains(&k.as_str()));
        o.remove("image");
    }
    let mut wm: Watermark = serde_json::from_value(value).map_err(|e| format!("bad watermark settings: {e}"))?;
    wm.size = wm.size.clamp(crate::export::WATERMARK_SIZE_RANGE.0, crate::export::WATERMARK_SIZE_RANGE.1);
    wm.inset_x = wm.inset_x.clamp(crate::export::WATERMARK_INSET_RANGE.0, crate::export::WATERMARK_INSET_RANGE.1);
    wm.inset_y = wm.inset_y.clamp(crate::export::WATERMARK_INSET_RANGE.0, crate::export::WATERMARK_INSET_RANGE.1);
    wm.opacity = wm.opacity.clamp(0.0, 1.0);
    wm.border_width = wm.border_width.clamp(crate::export::WATERMARK_BORDER_RANGE.0, crate::export::WATERMARK_BORDER_RANGE.1);
    wm.padding = wm.padding.clamp(crate::export::WATERMARK_PADDING_RANGE.0, crate::export::WATERMARK_PADDING_RANGE.1);
    wm.radius = wm.radius.clamp(crate::export::WATERMARK_RADIUS_RANGE.0, crate::export::WATERMARK_RADIUS_RANGE.1);
    wm.background_opacity = wm.background_opacity.clamp(0.0, 1.0);
    wm.image_width = wm.image_width.clamp(crate::export::WATERMARK_IMAGE_WIDTH_RANGE.0, crate::export::WATERMARK_IMAGE_WIDTH_RANGE.1);
    if let Some(b64) = pack.logo {
        let bytes = decode(&b64).ok_or("the graphic in this file is damaged")?;
        if bytes.len() > MAX_LOGO_BYTES {
            return Err(format!("the graphic is larger than {} MB", MAX_LOGO_BYTES / 1024 / 1024));
        }
        let ext = logo_extension(&bytes).ok_or("the graphic is not a PNG or JPEG")?;
        std::fs::create_dir_all(assets_dir).map_err(|e| format!("can't create {}: {e}", assets_dir.display()))?;
        let path = assets_dir.join(format!("{:016x}.{ext}", fnv1a(&bytes)));
        if !path.exists() {
            std::fs::write(&path, &bytes).map_err(|e| format!("can't save the graphic: {e}"))?;
        }
        let path = path.to_string_lossy().into_owned();
        if watermark_logo(&path).is_none() {
            let _ = std::fs::remove_file(&path);
            return Err("the graphic in this file can't be read".into());
        }
        wm.image = path;
    }
    Ok((pack.name, wm))
}

/// `png` or `jpg` by the file's first bytes, `None` for anything else.
fn logo_extension(b: &[u8]) -> Option<&'static str> {
    if b.starts_with(&[0x89, b'P', b'N', b'G', 0x0D, 0x0A, 0x1A, 0x0A]) {
        Some("png")
    } else if b.starts_with(&[0xFF, 0xD8, 0xFF]) {
        Some("jpg")
    } else {
        None
    }
}

fn fnv1a(bytes: &[u8]) -> u64 {
    bytes.iter().fold(0xcbf2_9ce4_8422_2325, |h, b| (h ^ u64::from(*b)).wrapping_mul(0x0000_0100_0000_01b3))
}

const ALPHABET: &[u8; 64] = b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";

fn encode(bytes: &[u8]) -> String {
    let mut out = String::with_capacity(bytes.len().div_ceil(3) * 4);
    for chunk in bytes.chunks(3) {
        let b = [chunk.first().copied().unwrap_or(0), chunk.get(1).copied().unwrap_or(0), chunk.get(2).copied().unwrap_or(0)];
        let n = (u32::from(b[0]) << 16) | (u32::from(b[1]) << 8) | u32::from(b[2]);
        for i in 0..4 {
            if i <= chunk.len() {
                let idx = ((n >> (18 - 6 * i)) & 63) as usize;
                out.push(ALPHABET.get(idx).copied().map_or('=', char::from));
            } else {
                out.push('=');
            }
        }
    }
    out
}

fn decode(s: &str) -> Option<Vec<u8>> {
    let mut out = Vec::with_capacity(s.len() / 4 * 3);
    let (mut acc, mut bits) = (0u32, 0u32);
    for c in s.bytes().filter(|c| !c.is_ascii_whitespace() && *c != b'=') {
        let v = ALPHABET.iter().position(|a| *a == c)? as u32;
        acc = (acc << 6) | v;
        bits += 6;
        if bits >= 8 {
            bits -= 8;
            out.push(((acc >> bits) & 0xFF) as u8);
        }
    }
    Some(out)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::export::Anchor;

    fn tmp(name: &str) -> std::path::PathBuf {
        let d = std::env::temp_dir().join(format!("lc-wm-{name}-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&d);
        std::fs::create_dir_all(&d).expect("tmp dir");
        d
    }

    /// A 2×2 RGBA PNG.
    fn png() -> Vec<u8> {
        let rgba = [255, 0, 0, 255, 0, 255, 0, 128, 0, 0, 255, 255, 255, 255, 255, 0];
        lightcraft_codecs::encode_png(
            &lightcraft_codecs::EncodeImage::new(2, 2, 4, lightcraft_codecs::Samples::U8(&rgba)),
            &lightcraft_codecs::EncodeMeta::default(),
        )
        .expect("png")
    }

    #[test]
    fn base64_round_trips_every_length() {
        for n in 0..40u8 {
            let bytes: Vec<u8> = (0..n).map(|i| i.wrapping_mul(37).wrapping_add(11)).collect();
            assert_eq!(decode(&encode(&bytes)).as_deref(), Some(bytes.as_slice()), "{n}");
        }
        assert_eq!(encode(b"Man"), "TWFu");
        assert_eq!(encode(b"Ma"), "TWE=");
        assert!(decode("@@@@").is_none());
    }

    #[test]
    fn text_watermark_round_trips_without_a_graphic() {
        let wm = Watermark { text: "© Sam".into(), anchor: Anchor::TopLeft, rotation: 90, opacity: 0.4, ..Default::default() };
        let json = export_json(&wm, " Studio ").expect("export");
        let dir = tmp("text");
        let (name, back) = import_json(&json, &dir).expect("import");
        assert_eq!(name, "Studio");
        assert_eq!((back.text.as_str(), back.anchor, back.rotation), ("© Sam", Anchor::TopLeft, 90));
        assert!(back.image.is_empty());
        assert!(!dir.join("x").exists());
    }

    #[test]
    fn graphic_travels_inside_the_file_and_is_stored_once() {
        let dir = tmp("graphic");
        let src = dir.join("logo.png");
        std::fs::write(&src, png()).expect("write logo");
        let wm = Watermark { image: src.to_string_lossy().into_owned(), image_width: 0.3, ..Default::default() };
        let json = export_json(&wm, "Logo").expect("export");
        assert!(!json.contains("logo.png"), "no path on the sender's machine");
        let assets = dir.join("assets");
        let (_, a) = import_json(&json, &assets).expect("import");
        let (_, b) = import_json(&json, &assets).expect("import again");
        assert_eq!(a.image, b.image);
        assert!(std::path::Path::new(&a.image).starts_with(&assets));
        assert_eq!(std::fs::read_dir(&assets).expect("dir").count(), 1);
        assert!((a.image_width - 0.3).abs() < 1e-6);
    }

    #[test]
    fn rejects_other_files_newer_versions_and_bad_graphics() {
        let dir = tmp("bad");
        assert!(import_json("not json", &dir).is_err());
        assert!(import_json(r#"{"kind":"other","version":1,"name":"x","watermark":{}}"#, &dir).is_err());
        assert!(import_json(r#"{"kind":"lightcraft-watermark","version":99,"name":"x","watermark":{}}"#, &dir).is_err());
        let not_image = encode(b"just some text, not a picture");
        let j = format!(r#"{{"kind":"lightcraft-watermark","version":1,"name":"x","watermark":{{}},"logo":"{not_image}"}}"#);
        assert!(import_json(&j, &dir).is_err());
        assert!(import_json(r#"{"kind":"lightcraft-watermark","version":1,"name":"x","watermark":{},"logo":"@@@"}"#, &dir).is_err());
        assert!(export_json(&Watermark { image: dir.join("missing.png").to_string_lossy().into_owned(), ..Default::default() }, "x").is_err());
    }

    #[test]
    fn imported_numbers_are_clamped_and_unknown_keys_ignored() {
        let dir = tmp("clamp");
        let j = r#"{"kind":"lightcraft-watermark","version":1,"name":"x","watermark":{"size":9.0,"opacity":-3,"insetX":5,"future":true}}"#;
        let (_, wm) = import_json(j, &dir).expect("import");
        assert_eq!(wm.size, crate::export::WATERMARK_SIZE_RANGE.1);
        assert_eq!(wm.opacity, 0.0);
        assert_eq!(wm.inset_x, crate::export::WATERMARK_INSET_RANGE.1);
    }
}
