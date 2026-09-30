import Foundation
import NestedCore

/// Per-device settings that are never shared: who is holding this phone, which baby it shows,
/// night mode. Stored in the App Group's defaults so widgets and intents read the same values.
public struct DevicePrefs: Sendable {
  public static let appGroup = "group.com.yetra.nest"

  nonisolated(unsafe) public static var defaults: UserDefaults =
    UserDefaults(suiteName: appGroup) ?? .standard

  private enum Key {
    static let ownerName = "ownerName"
    static let deviceID = "deviceID"
    static let babyID = "babyID"
    static let nightMode = "nightMode"
    static let lastLiveActivityPush = "lastLiveActivityPush"
  }

  /// "Bennett" / "Yvette". Recorded on every entry as `loggedBy`.
  public static var ownerName: String {
    get { defaults.string(forKey: Key.ownerName) ?? "" }
    set { defaults.set(newValue, forKey: Key.ownerName) }
  }

  /// Stable per-install identifier, used as this device's `DeviceToken` row id.
  public static var deviceID: UUID {
    if let raw = defaults.string(forKey: Key.deviceID), let id = UUID(uuidString: raw) {
      return id
    }
    let id = UUID()
    defaults.set(id.uuidString, forKey: Key.deviceID)
    return id
  }

  public static var babyID: UUID? {
    get { defaults.string(forKey: Key.babyID).flatMap(UUID.init(uuidString:)) }
    set { defaults.set(newValue?.uuidString, forKey: Key.babyID) }
  }

  public static var nightMode: NightModeSetting {
    get { defaults.string(forKey: Key.nightMode).flatMap(NightModeSetting.init(rawValue:)) ?? .automatic }
    set { defaults.set(newValue.rawValue, forKey: Key.nightMode) }
  }

  /// Initial for the Timeline badge: "B", "Y".
  public static func initial(for name: String) -> String {
    name.first.map { String($0).uppercased() } ?? "?"
  }
}
