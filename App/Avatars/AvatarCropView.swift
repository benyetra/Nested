import SwiftUI

/// Pan and pinch a photo under a round window, then save the square that shows.
struct AvatarCropView: View {
  let image: UIImage
  let onCancel: () -> Void
  let onDone: (Data) -> Void

  @State private var offset = CGSize.zero
  @State private var committedOffset = CGSize.zero
  @State private var zoom: CGFloat = 1
  @State private var committedZoom: CGFloat = 1

  private let outputSide: CGFloat = 320
  private let maxZoom: CGFloat = 5

  var body: some View {
    GeometryReader { proxy in
      let side = min(proxy.size.width - 32, 360)
      VStack(spacing: 28) {
        Spacer()
        ZStack {
          Image(uiImage: image)
            .resizable()
            .frame(width: displaySize(side).width, height: displaySize(side).height)
            .offset(offset)
            .frame(width: side, height: side)
            .clipped()
          // Dim everything outside the circle.
          Rectangle()
            .fill(.black.opacity(0.6))
            .mask {
              Rectangle()
                .overlay { Circle().padding(2).blendMode(.destinationOut) }
                .compositingGroup()
            }
            .allowsHitTesting(false)
          Circle().strokeBorder(.white.opacity(0.8), lineWidth: 1.5).padding(2).allowsHitTesting(false)
        }
        .frame(width: side, height: side)
        .contentShape(Rectangle())
        .gesture(gesture(side: side))
        Text("Drag and pinch to fit")
          .font(.subheadline)
          .foregroundStyle(.white.opacity(0.7))
        Spacer()
        HStack {
          Button("Cancel", action: onCancel)
          Spacer()
          Button("Use photo") { finish(side: side) }
            .fontWeight(.semibold)
        }
        .font(.headline)
        .foregroundStyle(.white)
        .padding(.horizontal, 24)
        .padding(.bottom, 12)
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    .background(Color.black.ignoresSafeArea())
    .preferredColorScheme(.dark)
  }

  // MARK: Geometry

  /// The photo's on-screen size: it always covers the square, more so as you zoom.
  private func displaySize(_ side: CGFloat) -> CGSize {
    let base = side / min(image.size.width, image.size.height)
    return CGSize(width: image.size.width * base * zoom, height: image.size.height * base * zoom)
  }

  private func clamped(_ offset: CGSize, side: CGFloat) -> CGSize {
    let size = displaySize(side)
    let maxX = max(0, (size.width - side) / 2)
    let maxY = max(0, (size.height - side) / 2)
    return CGSize(
      width: min(max(offset.width, -maxX), maxX), height: min(max(offset.height, -maxY), maxY))
  }

  private func gesture(side: CGFloat) -> some Gesture {
    SimultaneousGesture(
      DragGesture()
        .onChanged { value in
          offset = clamped(
            CGSize(
              width: committedOffset.width + value.translation.width,
              height: committedOffset.height + value.translation.height), side: side)
        }
        .onEnded { _ in committedOffset = offset },
      MagnifyGesture()
        .onChanged { value in
          zoom = min(max(committedZoom * value.magnification, 1), maxZoom)
          offset = clamped(offset, side: side)
        }
        .onEnded { _ in
          committedZoom = zoom
          committedOffset = offset
        })
  }

  private func finish(side: CGFloat) {
    let size = displaySize(side)
    let k = outputSide / side
    let format = UIGraphicsImageRendererFormat()
    format.scale = 1
    format.opaque = true
    let renderer = UIGraphicsImageRenderer(size: CGSize(width: outputSide, height: outputSide), format: format)
    let data = renderer.jpegData(withCompressionQuality: 0.82) { _ in
      image.draw(
        in: CGRect(
          x: ((side - size.width) / 2 + offset.width) * k,
          y: ((side - size.height) / 2 + offset.height) * k,
          width: size.width * k, height: size.height * k))
    }
    onDone(data)
  }
}

extension UIImage {
  /// Redraws upright at no more than `maxSide`, so crop math ignores EXIF orientation and
  /// huge camera photos don't sit in memory.
  func normalized(maxSide: CGFloat = 2048) -> UIImage {
    let scale = min(1, maxSide / max(size.width, size.height))
    let target = CGSize(width: size.width * scale, height: size.height * scale)
    let format = UIGraphicsImageRendererFormat()
    format.scale = 1
    return UIGraphicsImageRenderer(size: target, format: format).image { _ in
      draw(in: CGRect(origin: .zero, size: target))
    }
  }
}
