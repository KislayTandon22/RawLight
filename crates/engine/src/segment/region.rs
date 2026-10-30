//! Click-seeded region growing: the fallback when a platform segmenter (Apple Vision) finds no
//! salient subject under a tap, as with sky, foliage, water or a background object.
//!
//! The photo is reduced to a `side × side` grid. From each include click the region spreads to
//! neighbours whose colour stays close to the region's running mean, and stops at strong edges, so
//! the selection follows the object's outline. Exclude clicks cut their own region back out.

use super::platform::PlatformMask;

/// Largest share of the photo a grown region may cover before it is treated as "leaked".
const MAX_COVER: f32 = 0.85;
const LOGIT: f32 = 6.0;

/// Grow regions from `clicks` (`[x, y, 1 include | 0 exclude]`, normalized). `None` when nothing
/// sensible was found (no include click, or the region leaked over the whole photo).
pub fn region_grow(rgb: &[u8], w: usize, h: usize, clicks: &[[f32; 3]], side: usize) -> Option<PlatformMask> {
    if w == 0 || h == 0 || side < 8 || rgb.len() < w * h * 3 || !clicks.iter().any(|c| c[2] > 0.5) {
        return None;
    }
    let grid = reduce(rgb, w, h, side);
    let edges = edge_strength(&grid, side);
    let mut selected = vec![false; side * side];
    for c in clicks.iter().filter(|c| c[2] > 0.5) {
        let region = grow(&grid, &edges, side, seed_of(c, side))?;
        for (s, r) in selected.iter_mut().zip(&region) {
            *s |= *r;
        }
    }
    for c in clicks.iter().filter(|c| c[2] <= 0.5) {
        if let Some(region) = grow(&grid, &edges, side, seed_of(c, side)) {
            for (s, r) in selected.iter_mut().zip(&region) {
                *s &= !*r;
            }
        }
    }
    let covered = selected.iter().filter(|s| **s).count() as f32 / (side * side) as f32;
    if !(0.0005..=MAX_COVER).contains(&covered) {
        return None;
    }
    close_holes(&mut selected, side);
    Some(PlatformMask { side, logits: soften(&selected, side) })
}

fn seed_of(c: &[f32; 3], side: usize) -> (usize, usize) {
    let max = (side - 1) as f32;
    ((c[0].clamp(0.0, 1.0) * max) as usize, (c[1].clamp(0.0, 1.0) * max) as usize)
}

/// Box-average the photo into a `side × side` grid of f32 RGB.
fn reduce(rgb: &[u8], w: usize, h: usize, side: usize) -> Vec<[f32; 3]> {
    let mut out = vec![[0f32; 3]; side * side];
    for gy in 0..side {
        let y0 = gy * h / side;
        let y1 = (((gy + 1) * h / side).max(y0 + 1)).min(h);
        for gx in 0..side {
            let x0 = gx * w / side;
            let x1 = (((gx + 1) * w / side).max(x0 + 1)).min(w);
            let mut acc = [0f32; 3];
            let mut n = 0f32;
            // sample at most ~8×8 pixels per cell
            let sy = ((y1 - y0) / 8).max(1);
            let sx = ((x1 - x0) / 8).max(1);
            let mut y = y0;
            while y < y1 {
                let mut x = x0;
                while x < x1 {
                    let i = (y * w + x) * 3;
                    acc[0] += f32::from(rgb[i]);
                    acc[1] += f32::from(rgb[i + 1]);
                    acc[2] += f32::from(rgb[i + 2]);
                    n += 1.0;
                    x += sx;
                }
                y += sy;
            }
            out[gy * side + gx] = [acc[0] / n, acc[1] / n, acc[2] / n];
        }
    }
    out
}

fn dist(a: &[f32; 3], b: &[f32; 3]) -> f32 {
    // luma-weighted so brightness steps count a little more than hue noise
    let (dr, dg, db) = (a[0] - b[0], a[1] - b[1], a[2] - b[2]);
    (0.35 * dr * dr + 0.5 * dg * dg + 0.15 * db * db).sqrt()
}

/// Colour step to the right/bottom neighbour, the larger of the two, per cell.
fn edge_strength(grid: &[[f32; 3]], side: usize) -> Vec<f32> {
    let mut e = vec![0f32; side * side];
    for y in 0..side {
        for x in 0..side {
            let i = y * side + x;
            let r = if x + 1 < side { dist(&grid[i], &grid[i + 1]) } else { 0.0 };
            let d = if y + 1 < side { dist(&grid[i], &grid[i + side]) } else { 0.0 };
            e[i] = r.max(d);
        }
    }
    e
}

fn grow(grid: &[[f32; 3]], edges: &[f32], side: usize, seed: (usize, usize)) -> Option<Vec<bool>> {
    let at = |x: usize, y: usize| y * side + x;
    // seed colour: mean of the 3×3 around the tap, so one noisy pixel does not decide it
    let mut mean = [0f32; 3];
    let mut n = 0f32;
    for y in seed.1.saturating_sub(1)..=(seed.1 + 1).min(side - 1) {
        for x in seed.0.saturating_sub(1)..=(seed.0 + 1).min(side - 1) {
            for k in 0..3 {
                mean[k] += grid[at(x, y)][k];
            }
            n += 1.0;
        }
    }
    for m in &mut mean {
        *m /= n;
    }
    // tolerance from the neighbourhood's own variation: textured surfaces (foliage) accept more
    let mut spread = 0f32;
    for y in seed.1.saturating_sub(3)..=(seed.1 + 3).min(side - 1) {
        for x in seed.0.saturating_sub(3)..=(seed.0 + 3).min(side - 1) {
            spread += dist(&grid[at(x, y)], &mean);
        }
    }
    let cells = (7 * 7) as f32;
    let tol = (18.0 + 1.6 * spread / cells).clamp(18.0, 46.0);
    let edge_stop = (tol * 0.9).max(14.0);

    let mut inside = vec![false; side * side];
    let mut stack = vec![seed];
    inside[at(seed.0, seed.1)] = true;
    let (mut sum, mut count) = (mean, 1f32);
    let limit = (side * side) as f32 * (MAX_COVER + 0.05);
    while let Some((x, y)) = stack.pop() {
        for (dx, dy) in [(1i32, 0i32), (-1, 0), (0, 1), (0, -1)] {
            let (nx, ny) = (x as i32 + dx, y as i32 + dy);
            if nx < 0 || ny < 0 || nx >= side as i32 || ny >= side as i32 {
                continue;
            }
            let (nx, ny) = (nx as usize, ny as usize);
            let j = at(nx, ny);
            if inside[j] {
                continue;
            }
            // the step that was crossed to reach j, and how far j is from the running mean
            let crossed = if dx == 1 {
                edges[at(x, y)]
            } else if dx == -1 {
                edges[j]
            } else if dy == 1 {
                edges[at(x, y)]
            } else {
                edges[j]
            };
            let running = [sum[0] / count, sum[1] / count, sum[2] / count];
            if crossed > edge_stop || dist(&grid[j], &running) > tol {
                continue;
            }
            inside[j] = true;
            for k in 0..3 {
                sum[k] += grid[j][k];
            }
            count += 1.0;
            if count > limit {
                return None;
            }
            stack.push((nx, ny));
        }
    }
    Some(inside)
}

/// Fill small background pockets fully enclosed by the selection (specks of a different colour
/// inside an object are part of it). A large enclosed area is another object, not a speck.
fn close_holes(sel: &mut [bool], side: usize) {
    let max_pocket = side * side / 50;
    let mut seen = vec![false; side * side];
    for start in 0..side * side {
        if sel[start] || seen[start] {
            continue;
        }
        let mut cells = vec![start];
        let mut stack = vec![start];
        seen[start] = true;
        let mut touches_border = false;
        while let Some(i) = stack.pop() {
            let (x, y) = (i % side, i / side);
            if x == 0 || y == 0 || x + 1 == side || y + 1 == side {
                touches_border = true;
            }
            for (dx, dy) in [(1i32, 0i32), (-1, 0), (0, 1), (0, -1)] {
                let (nx, ny) = (x as i32 + dx, y as i32 + dy);
                if nx < 0 || ny < 0 || nx >= side as i32 || ny >= side as i32 {
                    continue;
                }
                let j = ny as usize * side + nx as usize;
                if !sel[j] && !seen[j] {
                    seen[j] = true;
                    cells.push(j);
                    stack.push(j);
                }
            }
        }
        if !touches_border && cells.len() <= max_pocket {
            for i in cells {
                sel[i] = true;
            }
        }
    }
}

/// Binary selection → logits with a soft, ~2-cell edge (two passes of a 3×3 blur).
fn soften(sel: &[bool], side: usize) -> Vec<f32> {
    let mut a: Vec<f32> = sel.iter().map(|s| if *s { LOGIT } else { -LOGIT }).collect();
    for _ in 0..2 {
        let mut b = a.clone();
        for y in 0..side {
            for x in 0..side {
                let mut acc = 0f32;
                let mut n = 0f32;
                for yy in y.saturating_sub(1)..=(y + 1).min(side - 1) {
                    for xx in x.saturating_sub(1)..=(x + 1).min(side - 1) {
                        acc += a[yy * side + xx];
                        n += 1.0;
                    }
                }
                b[y * side + x] = acc / n;
            }
        }
        a = b;
    }
    a
}

#[cfg(test)]
mod tests {
    use super::*;

    /// A 200×200 photo: a red square on a blue-grey sky.
    fn scene() -> Vec<u8> {
        let (w, h) = (200, 200);
        let mut rgb = vec![0u8; w * h * 3];
        for y in 0..h {
            for x in 0..w {
                let i = (y * w + x) * 3;
                let in_box = (60..140).contains(&x) && (60..140).contains(&y);
                let c = if in_box { [200, 40, 40] } else { [90, 110, 150] };
                rgb[i..i + 3].copy_from_slice(&c);
            }
        }
        rgb
    }

    fn inside(m: &PlatformMask, nx: f32, ny: f32) -> bool {
        let max = (m.side - 1) as f32;
        m.logits[(ny * max) as usize * m.side + (nx * max) as usize] > 0.0
    }

    #[test]
    fn tap_on_object_selects_it_and_stops_at_its_edge() {
        let m = region_grow(&scene(), 200, 200, &[[0.5, 0.5, 1.0]], 64).expect("mask");
        assert!(inside(&m, 0.5, 0.5));
        assert!(inside(&m, 0.4, 0.6));
        assert!(!inside(&m, 0.1, 0.1));
        assert!(!inside(&m, 0.9, 0.5));
    }

    #[test]
    fn tap_on_background_selects_it_but_not_the_object() {
        let m = region_grow(&scene(), 200, 200, &[[0.1, 0.1, 1.0]], 64).expect("mask");
        assert!(inside(&m, 0.1, 0.1));
        assert!(inside(&m, 0.9, 0.9));
        assert!(!inside(&m, 0.5, 0.5));
    }

    #[test]
    fn exclude_click_removes_its_region() {
        let m = region_grow(&scene(), 200, 200, &[[0.1, 0.1, 1.0], [0.5, 0.5, 1.0], [0.5, 0.5, 0.0]], 64).expect("mask");
        assert!(inside(&m, 0.1, 0.1));
        assert!(!inside(&m, 0.5, 0.5));
    }

    #[test]
    fn needs_an_include_click_and_a_real_image() {
        assert!(region_grow(&scene(), 200, 200, &[], 64).is_none());
        assert!(region_grow(&scene(), 200, 200, &[[0.5, 0.5, 0.0]], 64).is_none());
        assert!(region_grow(&[0u8; 12], 200, 200, &[[0.5, 0.5, 1.0]], 64).is_none());
    }

    #[test]
    fn a_flat_photo_is_not_one_giant_selection() {
        let flat = vec![128u8; 200 * 200 * 3];
        assert!(region_grow(&flat, 200, 200, &[[0.5, 0.5, 1.0]], 64).is_none());
    }
}
