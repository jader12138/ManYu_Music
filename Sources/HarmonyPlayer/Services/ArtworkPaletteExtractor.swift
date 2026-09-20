import AppKit

struct ArtworkPalette {
    let primary: NSColor
    let secondary: NSColor
    let accent: NSColor

    static let fallback = ArtworkPalette(
        primary: NSColor(srgbRed: 0.18, green: 0.48, blue: 0.96, alpha: 1),
        secondary: NSColor(srgbRed: 0.30, green: 0.72, blue: 1.00, alpha: 1),
        accent: NSColor(srgbRed: 0.53, green: 0.56, blue: 0.98, alpha: 1)
    )
}

enum ArtworkPaletteExtractor {
    /// 抽色逻辑：把封面缩成 32×32 像素，按 3×3 网格分块，每块独立做
    /// 「饱和度加权 + 中调加权」平均得到一个区域代表色。
    /// `primary` 仍是整体加权平均（保持与旧版本一致的色味基线）。
    /// `secondary`/`accent` 从九宫格区域代表色中按色相距离挑选——
    /// 这样多采样的真正意义是：secondary 不再只是 primary 旋转色相，
    /// 而是封面里另一块色调不同的真实颜色，渐变里能看到两种或以上
    /// 来源不同的颜色带。当九宫格里色相都接近（单色封面）时，
    /// 回退到 hueShift 派生保持兼容。
    static func palette(from image: NSImage) -> ArtworkPalette {
        var proposedRect = NSRect(origin: .zero, size: image.size)
        guard let cgImage = image.cgImage(forProposedRect: &proposedRect, context: nil, hints: nil) else {
            return .fallback
        }

        let width = 32
        let height = 32
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        guard let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return .fallback
        }

        context.interpolationQuality = .medium
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        // 整体加权平均（保留旧逻辑作为 primary 基线）
        var weighted = (r: 0.0, g: 0.0, b: 0.0, weight: 0.0)
        var fallbackAverage = (r: 0.0, g: 0.0, b: 0.0, count: 0.0)

        for index in stride(from: 0, to: pixels.count, by: 4) {
            let alpha = Double(pixels[index + 3]) / 255
            guard alpha > 0.15 else { continue }

            let red = Double(pixels[index]) / 255
            let green = Double(pixels[index + 1]) / 255
            let blue = Double(pixels[index + 2]) / 255

            fallbackAverage.r += red
            fallbackAverage.g += green
            fallbackAverage.b += blue
            fallbackAverage.count += 1

            let maximum = max(red, green, blue)
            let minimum = min(red, green, blue)
            let saturation = maximum == 0 ? 0 : (maximum - minimum) / maximum
            let brightness = maximum
            let midtone = 1 - abs(brightness - 0.55)
            let weight = (0.18 + saturation * 0.82) * (0.35 + midtone * 0.65)

            weighted.r += red * weight
            weighted.g += green * weight
            weighted.b += blue * weight
            weighted.weight += weight
        }

        let primary: NSColor
        if weighted.weight > 0 {
            primary = NSColor(
                srgbRed: weighted.r / weighted.weight,
                green: weighted.g / weighted.weight,
                blue: weighted.b / weighted.weight,
                alpha: 1
            )
        } else if fallbackAverage.count > 0 {
            primary = NSColor(
                srgbRed: fallbackAverage.r / fallbackAverage.count,
                green: fallbackAverage.g / fallbackAverage.count,
                blue: fallbackAverage.b / fallbackAverage.count,
                alpha: 1
            )
        } else {
            return .fallback
        }

        // 九宫格区域代表色（多采样点）：把 32×32 缩略图按 3×3 网格分块，
        // 每块内同样按饱和度加权平均得到一个区域颜色。
        let regionColors = regionSamples(pixels: pixels, width: width, height: height)

        let secondary = pickSecondary(from: primary, in: regionColors)
        let accent = pickAccent(from: primary, secondary: secondary, in: regionColors)

        return ArtworkPalette(primary: primary, secondary: secondary, accent: accent)
    }

    /// 把 32×32 缩略图按 3×3 网格分块，每块返回饱和度加权平均色。
    /// 中间格的色相分布往往能反映封面的次主色调（背景/天空/服饰等）。
    private static func regionSamples(pixels: [UInt8], width: Int, height: Int) -> [NSColor] {
        let cellsX = 3
        let cellsY = 3
        let cellW = width / cellsX
        let cellH = height / cellsY
        var samples: [NSColor] = []
        samples.reserveCapacity(cellsX * cellsY)

        for cy in 0..<cellsY {
            for cx in 0..<cellsX {
                var w = (r: 0.0, g: 0.0, b: 0.0, weight: 0.0)
                var plain = (r: 0.0, g: 0.0, b: 0.0, count: 0.0)
                let xStart = cx * cellW
                let yStart = cy * cellH
                let xEnd = (cx == cellsX - 1) ? width : (cx + 1) * cellW
                let yEnd = (cy == cellsY - 1) ? height : (cy + 1) * cellH

                for y in yStart..<yEnd {
                    for x in xStart..<xEnd {
                        let index = (y * width + x) * 4
                        let alpha = Double(pixels[index + 3]) / 255
                        guard alpha > 0.15 else { continue }

                        let red = Double(pixels[index]) / 255
                        let green = Double(pixels[index + 1]) / 255
                        let blue = Double(pixels[index + 2]) / 255

                        plain.r += red
                        plain.g += green
                        plain.b += blue
                        plain.count += 1

                        let maximum = max(red, green, blue)
                        let minimum = min(red, green, blue)
                        let saturation = maximum == 0 ? 0 : (maximum - minimum) / maximum
                        let brightness = maximum
                        let midtone = 1 - abs(brightness - 0.55)
                        let weight = (0.18 + saturation * 0.82) * (0.35 + midtone * 0.65)

                        w.r += red * weight
                        w.g += green * weight
                        w.b += blue * weight
                        w.weight += weight
                    }
                }

                if w.weight > 0 {
                    samples.append(NSColor(
                        srgbRed: w.r / w.weight,
                        green: w.g / w.weight,
                        blue: w.b / w.weight,
                        alpha: 1
                    ))
                } else if plain.count > 0 {
                    samples.append(NSColor(
                        srgbRed: plain.r / plain.count,
                        green: plain.g / plain.count,
                        blue: plain.b / plain.count,
                        alpha: 1
                    ))
                }
            }
        }

        return samples
    }

    /// 在九宫格区域颜色里挑选与 primary 色相距离最大且饱和度合理的代表色，
    /// 作为 secondary。这是真正的"多采样"——secondary 不再只是 primary
    /// 转色相的派生，而是封面里另一块区域的真实颜色。
    /// 没有合理候选（单色封面）时回退 hueShift 派生。
    private static func pickSecondary(from primary: NSColor, in regionColors: [NSColor]) -> NSColor {
        guard let primaryHue = hue(of: primary) else {
            return adjusted(primary, hueShift: 0.075, saturationScale: 1.08, brightnessScale: 1.18)
        }

        var best: NSColor?
        var bestDistance: Double = 0.10 // 阈值：色相距离至少 0.10 才认作「不同区域」
        for candidate in regionColors {
            guard let candidateHue = hue(of: candidate) else { continue }
            let distance = hueDistance(primaryHue, candidateHue)
            let saturation = saturation(of: candidate)
            // 排除低饱和度（接近灰白）的网格，避免选中白边/黑底
            guard saturation > 0.18 else { continue }
            // 排除过暗的网格（避免选中纯黑底色）
            let brightness = brightness(of: candidate)
            guard brightness > 0.18 else { continue }

            if distance > bestDistance {
                bestDistance = distance
                best = candidate
            }
        }

        if let chosen = best {
            return adjusted(chosen, hueShift: 0.04, saturationScale: 1.10, brightnessScale: 1.14)
        }
        return adjusted(primary, hueShift: 0.075, saturationScale: 1.08, brightnessScale: 1.18)
    }

    /// accent 在剩下的区域色里挑一个与 primary、secondary 都不同色调的，
    /// 让背景渐变至少能呈现三种来源不同的颜色带。回退用 primary 反向 hueShift。
    private static func pickAccent(from primary: NSColor, secondary: NSColor, in regionColors: [NSColor]) -> NSColor {
        guard let primaryHue = hue(of: primary),
              let secondaryHue = hue(of: secondary) else {
            return adjusted(primary, hueShift: -0.065, saturationScale: 0.92, brightnessScale: 0.78)
        }

        var best: NSColor?
        var bestDistance: Double = 0.12
        for candidate in regionColors {
            guard let candidateHue = hue(of: candidate) else { continue }
            let dPrimary = hueDistance(primaryHue, candidateHue)
            let dSecondary = hueDistance(secondaryHue, candidateHue)
            // 要求 accent 与 primary 和 secondary 都有距离，保证它是「第三种」颜色
            let distance = min(dPrimary, dSecondary)
            let saturation = saturation(of: candidate)
            guard saturation > 0.15 else { continue }
            let brightness = brightness(of: candidate)
            guard brightness > 0.15 else { continue }

            if distance > bestDistance {
                bestDistance = distance
                best = candidate
            }
        }

        if let chosen = best {
            return adjusted(chosen, hueShift: -0.03, saturationScale: 0.95, brightnessScale: 0.86)
        }
        return adjusted(primary, hueShift: -0.065, saturationScale: 0.92, brightnessScale: 0.78)
    }

    private static func hue(of color: NSColor) -> Double? {
        guard let converted = color.usingColorSpace(.deviceRGB) else { return nil }
        var hue: CGFloat = 0
        var saturation: CGFloat = 0
        var brightness: CGFloat = 0
        var alpha: CGFloat = 0
        converted.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
        return Double(hue)
    }

    private static func saturation(of color: NSColor) -> Double {
        guard let converted = color.usingColorSpace(.deviceRGB) else { return 0 }
        var hue: CGFloat = 0
        var saturation: CGFloat = 0
        var brightness: CGFloat = 0
        var alpha: CGFloat = 0
        converted.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
        return Double(saturation)
    }

    private static func brightness(of color: NSColor) -> Double {
        guard let converted = color.usingColorSpace(.deviceRGB) else { return 0 }
        var hue: CGFloat = 0
        var saturation: CGFloat = 0
        var brightness: CGFloat = 0
        var alpha: CGFloat = 0
        converted.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
        return Double(brightness)
    }

    /// 两个色相的最短距离（0~0.5）。
    private static func hueDistance(_ a: Double, _ b: Double) -> Double {
        let d = abs(a - b)
        return min(d, 1 - d)
    }

    private static func adjusted(
        _ color: NSColor,
        hueShift: CGFloat,
        saturationScale: CGFloat,
        brightnessScale: CGFloat
    ) -> NSColor {
        guard let converted = color.usingColorSpace(.deviceRGB) else { return color }
        var hue: CGFloat = 0
        var saturation: CGFloat = 0
        var brightness: CGFloat = 0
        var alpha: CGFloat = 0
        converted.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)

        let shiftedHue = (hue + hueShift).truncatingRemainder(dividingBy: 1)
        return NSColor(
            hue: shiftedHue < 0 ? shiftedHue + 1 : shiftedHue,
            saturation: min(1, max(0.16, saturation * saturationScale)),
            brightness: min(1, max(0.18, brightness * brightnessScale)),
            alpha: 1
        )
    }
}
