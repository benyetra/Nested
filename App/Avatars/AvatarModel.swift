import NestData
import SQLiteData
import SwiftUI

/// The app's one observation of the photos table, with decoded images cached by version so
/// a list of rows doesn't decode JPEGs on every render.
@MainActor
@Observable
final class AvatarModel {
  static let shared = AvatarModel()

  @ObservationIgnored @Fetch(AvatarsRequest()) private var fetched: [Avatar] = []
  @ObservationIgnored private var cache: [String: (version: Date, image: UIImage)] = [:]

  func image(for subject: String) -> UIImage? {
    guard let avatar = fetched.first(where: { $0.subject == subject }) else { return nil }
    if let hit = cache[subject], hit.version == avatar.updatedAt { return hit.image }
    guard let image = UIImage(data: avatar.photo) else { return nil }
    cache[subject] = (avatar.updatedAt, image)
    return image
  }
}

extension AppModel {
  func setAvatar(subject: String, photo: Data?) {
    perform(haptic: .success, undo: .none) {
      try store.setAvatar(subject: subject, photo: photo)
      return nil
    }
  }
}

/// A round photo, or the person's initial on a tinted circle when there isn't one.
struct AvatarView: View {
  let subject: String
  let name: String
  var size: CGFloat = 40
  var tint: Color = .accentColor

  var body: some View {
    Group {
      if let image = AvatarModel.shared.image(for: subject) {
        Image(uiImage: image)
          .resizable()
          .scaledToFill()
      } else {
        ZStack {
          Circle().fill(tint.opacity(0.18))
          Text(DevicePrefs.initial(for: name))
            .font(.system(size: size * 0.42, weight: .bold, design: .rounded))
            .foregroundStyle(tint)
        }
      }
    }
    .frame(width: size, height: size)
    .clipShape(Circle())
  }
}
