import Foundation

/// Click-to-select for things Vision does not call a foreground subject (a wall, a car behind the
/// subject, a log pile): grows from the tapped pixel over similar colour, and stops at edges.
/// Works on the same `side × side` stretch of the photo the engine's soft mask uses.
enum RegionGrow {
    /// Coverage 0...1 per cell of `side × side` for a click at normalized `(x, y)`.
    static func select(rgb: UnsafePointer<UInt8>, w: Int, h: Int, side: Int, x: Float, y: Float) -> [Float] {
        guard w > 0, h > 0, side > 2 else { return [] }
        let n = side * side
        // box-downsample to the grid, as opponent colour (luma, red-green, blue-yellow) in 0...1
        var l = [Float](repeating: 0, count: n), a = l, b = l
        for gy in 0..<side {
            let y0 = gy * h / side, y1 = max(y0 + 1, (gy + 1) * h / side)
            for gx in 0..<side {
                let x0 = gx * w / side, x1 = max(x0 + 1, (gx + 1) * w / side)
                var r: Float = 0, g: Float = 0, bl: Float = 0, c: Float = 0
                var yy = y0
                while yy < y1 {
                    var xx = x0
                    while xx < x1 {
                        let i = (yy * w + xx) * 3
                        r += Float(rgb[i]); g += Float(rgb[i + 1]); bl += Float(rgb[i + 2]); c += 1
                        xx += 1
                    }
                    yy += 1
                }
                r /= c * 255; g /= c * 255; bl /= c * 255
                let i = gy * side + gx
                l[i] = 0.3 * r + 0.59 * g + 0.11 * bl
                a[i] = (r - g) * 0.8
                b[i] = (bl - (r + g) / 2) * 0.8
            }
        }
        func edge(_ i: Int) -> Float {
            let x = i % side, y = i / side
            let xl = max(0, x - 1), xr = min(side - 1, x + 1), yu = max(0, y - 1), yd = min(side - 1, y + 1)
            let dx = l[y * side + xr] - l[y * side + xl], dy = l[yd * side + x] - l[yu * side + x]
            return (dx * dx + dy * dy).squareRoot()
        }
        let sx = min(side - 1, max(0, Int(x * Float(side)))), sy = min(side - 1, max(0, Int(y * Float(side))))
        // seed statistics over a small patch
        var mean: (Float, Float, Float) = (0, 0, 0), count: Float = 0
        for dy in -2...2 { for dx in -2...2 {
            let px = min(side - 1, max(0, sx + dx)), py = min(side - 1, max(0, sy + dy)), i = py * side + px
            mean.0 += l[i]; mean.1 += a[i]; mean.2 += b[i]; count += 1
        } }
        mean = (mean.0 / count, mean.1 / count, mean.2 / count)
        var spread: Float = 0
        for dy in -2...2 { for dx in -2...2 {
            let px = min(side - 1, max(0, sx + dx)), py = min(side - 1, max(0, sy + dy)), i = py * side + px
            spread += dist(l[i], a[i], b[i], mean)
        } }
        spread /= count
        let tolerance = min(0.34, 0.11 + spread * 2.2)
        let step = min(0.12, 0.045 + spread)
        let edgeLimit: Float = 0.16
        var seen = [Bool](repeating: false, count: n)
        var out = [Float](repeating: 0, count: n)
        var queue = [Int](); queue.reserveCapacity(4096)
        let start = sy * side + sx
        seen[start] = true; queue.append(start)
        var head = 0, area = 0
        let limit = Int(Float(n) * 0.75)
        while head < queue.count, area < limit {
            let p = queue[head]; head += 1
            out[p] = 1; area += 1
            let px = p % side, py = p / side
            for (nx, ny) in [(px - 1, py), (px + 1, py), (px, py - 1), (px, py + 1)] {
                if nx < 0 || ny < 0 || nx >= side || ny >= side { continue }
                let q = ny * side + nx
                if seen[q] { continue }
                seen[q] = true
                let toSeed = dist(l[q], a[q], b[q], mean)
                let toParent = dist(l[q], a[q], b[q], (l[p], a[p], b[p]))
                if toSeed < tolerance, toParent < step, edge(q) < edgeLimit { queue.append(q) }
            }
        }
        return fill(out, side: side)
    }

    private static func dist(_ l: Float, _ a: Float, _ b: Float, _ m: (Float, Float, Float)) -> Float {
        let dl = l - m.0, da = a - m.1, db = b - m.2
        return (dl * dl * 0.6 + da * da + db * db).squareRoot()
    }

    /// Closes pin-holes and speckle: two rounds of a 3×3 majority vote.
    private static func fill(_ m: [Float], side: Int) -> [Float] {
        var cur = m
        for _ in 0..<2 {
            var next = cur
            for y in 1..<(side - 1) { for x in 1..<(side - 1) {
                var s: Float = 0
                for dy in -1...1 { for dx in -1...1 { s += cur[(y + dy) * side + x + dx] } }
                next[y * side + x] = s >= 5 ? 1 : 0
            } }
            cur = next
        }
        return cur
    }
}
