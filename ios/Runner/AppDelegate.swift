import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {

  private var fileSaverChannel: FlutterMethodChannel?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // Set up the file saver channel for the main engine
    setupFileSaverChannel(for: self.window?.rootViewController)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  override func application(
    _ application: UIApplication,
    willConnectTo session: UISceneSession,
    options connectionOptions: UIScene.ConnectionOptions
  ) -> Bool {
    // The FlutterViewController may not be available yet at this point,
    // so we defer channel setup to didInitializeImplicitFlutterEngine.
    return super.application(application, willConnectTo: session, options: connectionOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

    // Set up file saver channel for implicit (background) engine
    fileSaverChannel = FlutterMethodChannel(
      name: "com.clanai.clan_ai/file_saver",
      binaryMessenger: engineBridge.binaryMessenger
    )
    fileSaverChannel?.setMethodCallHandler(handleMethodCall)
  }

  private func setupFileSaverChannel(for viewController: UIResponder?) {
    if let flutterVC = viewController as? FlutterViewController {
      fileSaverChannel = FlutterMethodChannel(
        name: "com.clanai.clan_ai/file_saver",
        binaryMessenger: flutterVC.engine
      )
      fileSaverChannel?.setMethodCallHandler(handleMethodCall)
    }
  }

  // MARK: - Method channel handler

  private func handleMethodCall(_ call: FlutterMethodCall, result: FlutterResult) {
    switch call.method {
    case "saveFile":
      handleSaveFile(call, result: result)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  // MARK: - Save file logic

  private func handleSaveFile(_ call: FlutterMethodCall, result: FlutterResult) {
    guard let args = call.arguments as? [String: Any],
          let filename = args["filename"] as? String,
          let base64Content = args["content"] as? String else {
      result(FlutterError(code: "INVALID_ARGS", message: "Missing filename or content", details: nil))
      return
    }

    // Decode base64 content
    guard let data = Data(base64Encoded: base64Content, options: .ignoreUnknownCharacters) else {
      result(FlutterError(code: "DECODE_ERROR", message: "Failed to decode content", details: nil))
      return
    }

    // Write to a temp file in the app's caches directory
    let cachesURL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
    let fileExtension = (filename as NSString).pathExtension
    let fileBase = (filename as NSString).deletingPathExtension
    let tempFileName: String
    if fileExtension.isEmpty {
      tempFileName = "clan_ai_export_\(UUID().uuidString)"
    } else {
      tempFileName = "clan_ai_export_\(fileBase)_\(UUID().uuidString).\(fileExtension)"
    }
    let tempFile = cachesURL.appendingPathComponent(tempFileName)

    do {
      try data.write(to: tempFile, options: .atomic)

      // Present document picker for export
      let picker = UIDocumentPickerViewController(forExporting: [tempFile], asCopy: true)
      picker.delegate = self
      picker.allowsMultipleSelection = false

      // Present from the Flutter view controller
      if let flutterVC = getFlutterViewController() {
        flutterVC.present(picker, animated: true)
      } else if let rootVC = getRootViewController() {
        rootVC.present(picker, animated: true)
      } else {
        result(FlutterError(code: "UI_ERROR", message: "Cannot present save dialog", details: nil))
        try? FileManager.default.removeItem(at: tempFile)
        return
      }

      // Store temp file URL for delegate callback
      self.pendingTempFile = tempFile
      self.pendingResult = result

    } catch {
      result(FlutterError(code: "TEMP_FILE_ERROR", message: "Failed to create temp file: \(error.localizedDescription)", details: nil))
    }
  }

  // MARK: - UIDocumentPickerDelegate

  private var pendingTempFile: URL?
  private var pendingResult: FlutterResult?

  func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
    defer { cleanup() }

    guard let tempURL = pendingTempFile,
          let exportURL = urls.first else {
      return
    }

    do {
      if FileManager.default.fileExists(atPath: exportURL.path) {
        try FileManager.default.removeItem(at: exportURL)
      }
      try FileManager.default.moveItem(at: tempURL, to: exportURL)
      pendingResult?(exportURL.path)
    } catch {
      pendingResult?(FlutterError(code: "EXPORT_ERROR", message: error.localizedDescription, details: nil))
    }
  }

  func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
    cleanup()
    pendingResult?(nil)
  }

  private func cleanup() {
    if let url = pendingTempFile, FileManager.default.fileExists(atPath: url.path) {
      try? FileManager.default.removeItem(at: url)
    }
    pendingTempFile = nil
    pendingResult = nil
  }

  // MARK: - View controller helpers

  private func getFlutterViewController() -> FlutterViewController? {
    // Check the root view controller first, then walk the responder chain
    let root = UIApplication.shared.keyWindow?.rootViewController
    var current: UIResponder? = root
    while let next = current?.next {
      current = next
      if let flutterVC = current as? FlutterViewController {
        return flutterVC
      }
    }
    return nil
  }

  private func getRootViewController() -> UIViewController? {
    return UIApplication.shared.keyWindow?.rootViewController
  }
}

private extension UIWindow {
    static var keyWindow: UIWindow? {
        return UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow }
    }
}
