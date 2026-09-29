import CloudKit
import NestCore
import NestData
import SQLiteData
import SwiftUI
import UIKit

@main
struct NestApp: App {
  @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
  @Environment(\.scenePhase) private var scenePhase
  @State private var model: AppModel

  init() {
    @Dependency(\.context) var context
    if context == .live {
      try! prepareDependencies {
        try $0.bootstrapNest(sync: .live, delegate: NestSyncDelegate.shared)
      }
    } else {
      prepareDependencies { $0.defaultDatabase = try! NestDatabase.openInMemory() }
    }
    @Dependency(\.defaultDatabase) var database
    let store = LiveEventStore(database: database, onChange: { change in
      Task { @MainActor in SideEffects.shared.handle(change) }
    })
    SharedStore.configure(store)
    _model = State(initialValue: AppModel(store: store))
    SideEffects.shared.start(store: store)
    SyncCoordinator.shared.observeExtensionWrites()
  }

  var body: some Scene {
    WindowGroup {
      RootView()
        .environment(model)
        .onOpenURL { model.handle(url: $0) }
    }
    .onChange(of: scenePhase) { _, phase in
      switch phase {
      case .active:
        // Pick up anything widgets or intents wrote out of process, and refresh tokens.
        SyncCoordinator.shared.restartSync()
        SideEffects.shared.refresh()
        try? model.store.updateDevice { _ in }
      default:
        break
      }
    }
  }
}

/// Signs the sync engine back up after out-of-process writes, so their pending changes upload.
@MainActor
final class SyncCoordinator {
  static let shared = SyncCoordinator()
  @Dependency(\.defaultSyncEngine) private var syncEngine
  private var restarting = false

  func restartSync() {
    guard !restarting else { return }
    restarting = true
    let engine = syncEngine
    Task {
      defer { restarting = false }
      engine.stop()
      try? await engine.start()
      try? await engine.syncChanges()
    }
  }

  func fetch() async {
    try? await syncEngine.fetchChanges()
  }

  func observeExtensionWrites() {
    CFNotificationCenterAddObserver(
      CFNotificationCenterGetDarwinNotifyCenter(),
      nil,
      { _, _, _, _, _ in
        Task { @MainActor in SyncCoordinator.shared.restartSync() }
      },
      NestDatabase.externalWriteNotification as CFString,
      nil,
      .deliverImmediately)
  }
}

/// Resets local data if the iCloud account changes, so one family's data never shows in
/// another account.
final class NestSyncDelegate: SyncEngineDelegate, Sendable {
  static let shared = NestSyncDelegate()

  func syncEngine(
    _ syncEngine: SQLiteData.SyncEngine,
    accountChanged changeType: CKSyncEngine.Event.AccountChange.ChangeType
  ) async {
    switch changeType {
    case .signOut, .switchAccounts:
      try? await syncEngine.deleteLocalData()
    case .signIn:
      break
    @unknown default:
      break
    }
  }
}

final class AppDelegate: NSObject, UIApplicationDelegate {
  func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
  ) -> Bool {
    NotificationService.shared.configure()
    application.registerForRemoteNotifications()
    return true
  }

  func application(
    _ application: UIApplication,
    configurationForConnecting connectingSceneSession: UISceneSession,
    options: UIScene.ConnectionOptions
  ) -> UISceneConfiguration {
    let configuration = UISceneConfiguration(name: "Default", sessionRole: connectingSceneSession.role)
    configuration.delegateClass = SceneDelegate.self
    return configuration
  }

  func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
    let token = deviceToken.hexString
    try? SharedStore.store.updateDevice { $0.apnsToken = token }
  }

  /// CloudKit's silent pushes and the Worker's alarm pushes both land here.
  func application(
    _ application: UIApplication,
    didReceiveRemoteNotification userInfo: [AnyHashable: Any]
  ) async -> UIBackgroundFetchResult {
    await SyncCoordinator.shared.fetch()
    SideEffects.shared.refresh()
    return .newData
  }
}

/// Accepts the partner's iCloud share invite.
final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
  @Dependency(\.defaultSyncEngine) private var syncEngine
  var window: UIWindow?

  func windowScene(_ windowScene: UIWindowScene, userDidAcceptCloudKitShareWith cloudKitShareMetadata: CKShare.Metadata) {
    accept(cloudKitShareMetadata)
  }

  func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
    guard let metadata = connectionOptions.cloudKitShareMetadata else { return }
    accept(metadata)
  }

  private func accept(_ metadata: CKShare.Metadata) {
    let engine = syncEngine
    // Record names are "<id>:<table>"; show the shared baby from now on.
    let sharedBabyID = metadata.hierarchicalRootRecordID
      .flatMap { $0.recordName.split(separator: ":").first }
      .flatMap { UUID(uuidString: String($0)) }
    Task {
      try? await engine.acceptShare(metadata: metadata)
      if let sharedBabyID { DevicePrefs.babyID = sharedBabyID }
    }
  }
}
