import SwiftUI

/// Assigns colors to nodes. Each top-level child gets a distinct hue (spread
/// around the wheel with the golden ratio so neighbors never clash); deeper
/// rings keep the family hue but shift brightness/saturation so levels read
/// apart. This mirrors the "one color family per top folder" look people know
/// from disk visualizers.
enum Palette {

    /// A well-separated hue for the child at `index` among a top-level ring.
    static func hue(forIndex index: Int) -> Double {
        (Double(index) * 0.6180339887498949).truncatingRemainder(dividingBy: 1.0)
    }

    static func color(hue: Double, depth: Int) -> Color {
        var h = hue.truncatingRemainder(dividingBy: 1.0)
        if h < 0 { h += 1 }
        let saturation = max(0.30, 0.62 - Double(depth) * 0.05)
        let brightness = max(0.55, 0.97 - Double(depth) * 0.07)
        return Color(hue: h, saturation: saturation, brightness: brightness)
    }
}
