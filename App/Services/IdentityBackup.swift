import Foundation
import NestedData
import Security

/// Keeps a copy of this phone's identity (its device-row ID and the name of whoever holds it)
/// in the Keychain, which survives deleting and reinstalling the app. Without it a reinstall
/// starts a new identity: a second row for the same person shows up as a "partner" and
/// partner pushes go to the old install.
///
/// The app group's defaults stay the source of truth for widgets and intents; the Keychain
/// copy is only read back when the defaults come up empty. It is device-only, so it is not
/// carried to a different phone.
enum IdentityBackup {
  private static let service = "com.yetra.nest.identity"

  /// Call first thing at launch, before anything reads `DevicePrefs`.
  static func restore() {
    if let raw = read("deviceID"), UUID(uuidString: raw) != nil {
      // The Keychain copy wins: it is the one identity this install has ever had.
      DevicePrefs.defaults.set(raw, forKey: "deviceID")
    }
    if DevicePrefs.ownerName.isEmpty, let name = read("ownerName"), !name.isEmpty {
      DevicePrefs.ownerName = name
    }
  }

  /// Writes the current identity back. Cheap; call after launch and whenever the name changes.
  static func mirror() {
    write("deviceID", DevicePrefs.deviceID.uuidString)
    let name = DevicePrefs.ownerName
    if !name.isEmpty { write("ownerName", name) }
  }

  // MARK: Keychain

  private static func query(_ key: String) -> [String: Any] {
    [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: key,
    ]
  }

  private static func read(_ key: String) -> String? {
    var query = query(key)
    query[kSecReturnData as String] = true
    query[kSecMatchLimit as String] = kSecMatchLimitOne
    var item: CFTypeRef?
    guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
      let data = item as? Data
    else { return nil }
    return String(data: data, encoding: .utf8)
  }

  private static func write(_ key: String, _ value: String) {
    let data = Data(value.utf8)
    let status = SecItemUpdate(query(key) as CFDictionary, [kSecValueData as String: data] as CFDictionary)
    if status == errSecItemNotFound {
      var add = query(key)
      add[kSecValueData as String] = data
      // Readable after the first unlock, never leaves this device.
      add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
      SecItemAdd(add as CFDictionary, nil)
    }
  }
}
