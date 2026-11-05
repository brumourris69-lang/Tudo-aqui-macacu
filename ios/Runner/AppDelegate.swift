import Flutter
import UIKit
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var contentLinksChannel: FlutterMethodChannel?
  private var pendingContentLinks: [String] = []

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    let messenger = engineBridge.applicationRegistrar.messenger()
    registerShareChannel(messenger)
    registerReminderChannel(messenger)
    registerContentLinksChannel(messenger)
  }

  func receiveContentURL(_ url: URL) {
    guard url.scheme?.lowercased() == "tudoaqui" else { return }
    DispatchQueue.main.async {
      let value = url.absoluteString
      if !self.pendingContentLinks.contains(value) {
        if self.pendingContentLinks.count >= 16 { self.pendingContentLinks.removeFirst() }
        self.pendingContentLinks.append(value)
      }
      self.contentLinksChannel?.invokeMethod("pendingContentLinks", arguments: nil)
    }
  }

  private func registerShareChannel(_ messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: "macacu/public-share", binaryMessenger: messenger)
    channel.setMethodCallHandler { [weak self] call, result in
      guard call.method == "share" else {
        result(FlutterMethodNotImplemented)
        return
      }
      guard let arguments = call.arguments as? [String: Any],
            let title = (arguments["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
            let text = (arguments["text"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
            !title.isEmpty, !text.isEmpty else {
        result(FlutterError(code: "INVALID_SHARE_CONTENT", message: "Conteúdo público inválido.", details: nil))
        return
      }
      DispatchQueue.main.async {
        guard let presenter = self?.topViewController(),
              presenter.presentedViewController == nil else {
          result(false)
          return
        }
        let activity = UIActivityViewController(activityItems: [text], applicationActivities: nil)
        activity.title = title
        if let popover = activity.popoverPresentationController {
          popover.sourceView = presenter.view
          popover.sourceRect = CGRect(x: presenter.view.bounds.midX, y: presenter.view.bounds.midY, width: 0, height: 0)
          popover.permittedArrowDirections = []
        }
        presenter.present(activity, animated: true) { result(true) }
      }
    }
  }

  private func registerReminderChannel(_ messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: "macacu/event-reminders", binaryMessenger: messenger)
    channel.setMethodCallHandler { call, result in
      let center = UNUserNotificationCenter.current()
      switch call.method {
      case "requestPermission":
        center.requestAuthorization(options: [.alert, .sound]) { granted, error in
          DispatchQueue.main.async { result(error == nil && granted) }
        }
      case "notificationsEnabled":
        center.getNotificationSettings { settings in
          let status = settings.authorizationStatus
          let enabled = status == .authorized || status == .provisional || status == .ephemeral
          DispatchQueue.main.async { result(enabled) }
        }
      case "openNotificationSettings":
        DispatchQueue.main.async {
          guard let settingsURL = URL(string: UIApplication.openSettingsURLString) else {
            result(false)
            return
          }
          UIApplication.shared.open(settingsURL, options: [:]) { result($0) }
        }
      case "schedule":
        self.scheduleReminder(call, result: result, center: center)
      case "cancel":
        guard let arguments = call.arguments as? [String: Any],
              let rawId = arguments["notificationId"] as? NSNumber,
              rawId.intValue > 0 else {
          result(FlutterError(code: "INVALID_REMINDER", message: "Lembrete inválido.", details: nil))
          return
        }
        let identifier = "macacu-event-reminder-\(rawId.intValue)"
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
        center.removeDeliveredNotifications(withIdentifiers: [identifier])
        result(true)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private func scheduleReminder(
    _ call: FlutterMethodCall,
    result: @escaping FlutterResult,
    center: UNUserNotificationCenter
  ) {
    guard let arguments = call.arguments as? [String: Any],
          let rawId = arguments["notificationId"] as? NSNumber,
          let eventId = arguments["eventId"] as? String,
          let title = arguments["title"] as? String,
          let body = arguments["body"] as? String,
          let rawMillis = arguments["triggerAtMillis"] as? NSNumber else {
      result(FlutterError(code: "INVALID_REMINDER", message: "Dados do lembrete inválidos.", details: nil))
      return
    }
    let notificationId = rawId.intValue
    let safeEventId = eventId.trimmingCharacters(in: .whitespacesAndNewlines)
    let safeTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
    let safeBody = body.trimmingCharacters(in: .whitespacesAndNewlines)
    let triggerDate = Date(timeIntervalSince1970: Double(rawMillis.int64Value) / 1000.0)
    let interval = triggerDate.timeIntervalSinceNow
    guard notificationId > 0, !safeEventId.isEmpty, safeEventId.count <= 180,
          !safeTitle.isEmpty, safeTitle.count <= 120,
          !safeBody.isEmpty, safeBody.count <= 180, interval > 0 else {
      result(FlutterError(code: "INVALID_REMINDER", message: "Dados do lembrete inválidos ou horário passado.", details: nil))
      return
    }

    let content = UNMutableNotificationContent()
    content.title = safeTitle
    content.body = safeBody
    content.sound = .default
    let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(interval, 1), repeats: false)
    let request = UNNotificationRequest(
      identifier: "macacu-event-reminder-\(notificationId)",
      content: content,
      trigger: trigger
    )
    center.add(request) { error in
      DispatchQueue.main.async { result(error == nil) }
    }
  }

  private func registerContentLinksChannel(_ messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: "macacu/content-links", binaryMessenger: messenger)
    contentLinksChannel = channel
    channel.setMethodCallHandler { [weak self] call, result in
      guard call.method == "takePendingLinks" else {
        result(FlutterMethodNotImplemented)
        return
      }
      let pending = self?.pendingContentLinks ?? []
      self?.pendingContentLinks.removeAll()
      result(pending)
    }
  }

  private func topViewController() -> UIViewController? {
    let scene = UIApplication.shared.connectedScenes
      .compactMap { $0 as? UIWindowScene }
      .first(where: { $0.activationState == .foregroundActive })
    return topViewController(from: scene?.windows.first(where: \.isKeyWindow)?.rootViewController)
  }

  private func topViewController(from controller: UIViewController?) -> UIViewController? {
    if let navigation = controller as? UINavigationController {
      return topViewController(from: navigation.visibleViewController)
    }
    if let tabs = controller as? UITabBarController {
      return topViewController(from: tabs.selectedViewController)
    }
    if let presented = controller?.presentedViewController {
      return topViewController(from: presented)
    }
    return controller
  }
}
