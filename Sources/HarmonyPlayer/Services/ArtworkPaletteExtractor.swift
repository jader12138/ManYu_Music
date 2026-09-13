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

        let secondary = adjusted(primary, hueShift: 0.075, saturationScale: 1.08, brightnessScale: 1.18)
        let accent = adjusted(primary, hueShift: -0.065, saturationScale: 0.92, brightnessScale: 0.78)
        return ArtworkPalette(primary: primary, secondary: secondary, accent: accent)
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
