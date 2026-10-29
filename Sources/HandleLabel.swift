import Apus
import Cadova
import Foundation

/// Engraved handle lettering, right-aligned against its area and centered across it.
///
/// Layout uses font metrics rather than glyph outlines, so the size and position don't depend on
/// which characters the text happens to contain. The font size shrinks only if the text doesn't fit,
/// and never below the smallest size that engraves legibly; text that still doesn't fit is left out.
struct HandleLabel: Geometry2D {
    static let fontURL = Bundle.module.url(forResource: "Fredoka", withExtension: "ttf")!
    static let fontWeight = 550.0
    static let minimumFontSize = 7.0

    let text: String
    let fontSize: Double
    let anchor: Vector2D

    init?(text: String, requestedSize: Double, area: BoundingBox2D) {
        let text = Self.normalized(text)
        guard let unitWidth = Self.advanceWidth(of: text, fontSize: 1), unitWidth > 0 else { return nil }

        let fontSize = min(requestedSize, area.size.y, area.size.x / unitWidth)
        guard fontSize >= Self.minimumFontSize else { return nil }

        self.text = text
        self.fontSize = fontSize
        anchor = [area.maximum.x, area.center.y]
    }

    var body: any Geometry2D {
        Text(text)
            .withFont("Fredoka", size: fontSize, from: Self.fontURL)
            .withFontVariations([.weight(Self.fontWeight)])
            .withTextAlignment(horizontal: .right, vertical: .center)
            .translated(anchor)
    }

    /// The text on a single line, with runs of whitespace collapsed to single spaces.
    static func normalized(_ text: String) -> String {
        text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    /// The shaped line's advance width, as Cadova's Text measures it for alignment.
    static func advanceWidth(of text: String, fontSize: Double) -> Double? {
        guard let data = try? Data(contentsOf: fontURL),
              let font = try? Apus.Font(data: data, family: "Fredoka",
                                        variations: [.weight(fontWeight)]),
              let last = font.glyphs(for: text).last
        else { return nil }

        // Apus shapes at 1000 units per font size.
        return (last.position.x + last.advance.x) * fontSize / 1000
    }
}
