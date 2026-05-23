import SwiftUI
import CoreImage.CIFilterBuiltins

struct QRCodeView: View {
    let url: String
    var size: CGFloat = 180

    @State private var qrImage: UIImage? = nil

    var body: some View {
        Group {
            if let img = qrImage {
                Image(uiImage: img)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
                    .frame(width: size, height: size)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            } else {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(.systemGray5))
                    .frame(width: size, height: size)
                    .overlay(ProgressView().tint(.secondary))
            }
        }
        .onAppear { qrImage = generateQR(from: url) }
        .onChange(of: url) { newURL in qrImage = generateQR(from: newURL) }
    }

    private func generateQR(from string: String) -> UIImage? {
        guard !string.isEmpty else { return nil }

        let context = CIContext()
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)
        filter.correctionLevel = "M"

        guard let ciImage = filter.outputImage else { return nil }

        let scale = size / ciImage.extent.width
        let scaledImage = ciImage.transformed(by: CGAffineTransform(scaleX: scale, y: scale))

        guard let cgImage = context.createCGImage(scaledImage, from: scaledImage.extent) else { return nil }

        let raw = UIImage(cgImage: cgImage)
        return addQuietZone(to: raw)
    }

    private func addQuietZone(to image: UIImage) -> UIImage {
        let margin: CGFloat = 10
        let newSize = CGSize(width: image.size.width + margin * 2,
                             height: image.size.height + margin * 2)

        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(origin: .zero, size: newSize))
            image.draw(at: CGPoint(x: margin, y: margin))
        }
    }
}
