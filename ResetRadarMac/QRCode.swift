import AppKit
import CoreImage.CIFilterBuiltins
import Foundation

enum QRCode {
    static func image(for value: String) -> NSImage {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(value.utf8)
        filter.correctionLevel = "M"
        let context = CIContext()
        guard let output = filter.outputImage?.transformed(by: .init(scaleX: 8, y: 8)),
            let image = context.createCGImage(output, from: output.extent)
        else { return NSImage(size: NSSize(width: 1, height: 1)) }
        return NSImage(cgImage: image, size: .zero)
    }
}
