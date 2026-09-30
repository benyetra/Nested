import PhotosUI
import SwiftUI

private struct CropSource: Identifiable {
  let id = UUID()
  let image: UIImage
}

/// A tappable avatar: choose a photo from the library, crop it, or remove it.
struct AvatarEditor: View {
  @Environment(AppModel.self) private var model
  let subject: String
  let name: String
  var size: CGFloat = 64
  var tint: Color = .accentColor

  @State private var showPicker = false
  @State private var item: PhotosPickerItem?
  @State private var cropping: CropSource?

  private var hasPhoto: Bool { AvatarModel.shared.image(for: subject) != nil }

  var body: some View {
    Menu {
      Button("Choose photo", systemImage: "photo.on.rectangle") { showPicker = true }
      if hasPhoto {
        Button("Remove photo", systemImage: "trash", role: .destructive) {
          model.setAvatar(subject: subject, photo: nil)
        }
      }
    } label: {
      AvatarView(subject: subject, name: name, size: size, tint: tint)
        .overlay(alignment: .bottomTrailing) {
          Image(systemName: "camera.fill")
            .font(.system(size: size * 0.2, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size * 0.36, height: size * 0.36)
            .background(Circle().fill(tint))
            .overlay(Circle().strokeBorder(Palette.card, lineWidth: 2))
        }
        .frame(minWidth: 44, minHeight: 44)
    }
    .accessibilityLabel(hasPhoto ? "Change photo" : "Add photo")
    .photosPicker(isPresented: $showPicker, selection: $item, matching: .images)
    .onChange(of: item) { _, picked in
      guard let picked else { return }
      Task {
        if let data = try? await picked.loadTransferable(type: Data.self), let image = UIImage(data: data) {
          cropping = CropSource(image: image.normalized())
        }
        item = nil
      }
    }
    .fullScreenCover(item: $cropping) { source in
      AvatarCropView(
        image: source.image,
        onCancel: { cropping = nil },
        onDone: { data in
          model.setAvatar(subject: subject, photo: data)
          cropping = nil
        })
    }
  }
}
