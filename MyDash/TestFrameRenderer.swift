import UIKit

/// Draws a test picture for the dash on the CPU (Core Graphics into a bitmap, then a JPEG).
/// This is the same way the real map will be drawn: no GPU, no MapKit view, so it still works with the
/// phone locked in a pocket (docs/how-it-works/background.md).
///
/// Keep text and icons out of the dash's own zones (docs/how-it-works/dash-canvas.md):
/// zoom buttons (0, 68, 56x100) and the road bar (y >= 186).
enum TestFrameRenderer {
    static func jpeg(width: Int, height: Int, counter: Int, quality: CGFloat) -> [UInt8]? {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1               // 1 point = 1 dash pixel
        format.opaque = true
        format.preferredRange = .standard   // plain sRGB: no wide-colour profile inflating the JPEG
        let size = CGSize(width: width, height: height)

        let image = UIGraphicsImageRenderer(size: size, format: format).image { context in
            let g = context.cgContext

            UIColor(red: 0.07, green: 0.07, blue: 0.07, alpha: 1).setFill()
            g.fill(CGRect(origin: .zero, size: size))

            // Fine grid every 10 px, strong grid every 40 px.
            UIColor(white: 0.14, alpha: 1).setStroke()
            g.setLineWidth(1)
            for x in stride(from: 0, through: width, by: 10) { g.move(to: CGPoint(x: x, y: 0)); g.addLine(to: CGPoint(x: x, y: height)) }
            for y in stride(from: 0, through: height, by: 10) { g.move(to: CGPoint(x: 0, y: y)); g.addLine(to: CGPoint(x: width, y: y)) }
            g.strokePath()

            UIColor(white: 0.30, alpha: 1).setStroke()
            g.setLineWidth(2)
            for x in stride(from: 0, through: width, by: 40) { g.move(to: CGPoint(x: x, y: 0)); g.addLine(to: CGPoint(x: x, y: height)) }
            for y in stride(from: 0, through: height, by: 40) { g.move(to: CGPoint(x: 0, y: y)); g.addLine(to: CGPoint(x: width, y: y)) }
            g.strokePath()

            // A route-like line in sodium amber (the template's accent colour), thick enough for 4:2:0 JPEG.
            UIColor(red: 0.95, green: 0.70, blue: 0.24, alpha: 1).setStroke()
            g.setLineWidth(6)
            g.setLineCap(.round)
            g.setLineJoin(.round)
            g.move(to: CGPoint(x: 90, y: 170))
            g.addLine(to: CGPoint(x: 220, y: 120))
            g.addLine(to: CGPoint(x: 330, y: 130))
            g.addLine(to: CGPoint(x: 440, y: 70))
            g.strokePath()

            // A white dot that moves with the counter, so you can see the frames are live.
            UIColor.white.setFill()
            let dotX = 90 + (counter * 7) % 340
            g.fillEllipse(in: CGRect(x: dotX - 8, y: 100, width: 16, height: 16))

            let title: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 26, weight: .semibold),
                .foregroundColor: UIColor.white,
            ]
            ("MyDash  #\(counter)" as NSString).draw(at: CGPoint(x: 72, y: 16), withAttributes: title)
        }

        guard let data = image.jpegData(compressionQuality: quality) else { return nil }
        return [UInt8](data)
    }
}
