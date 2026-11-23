import Flutter
import UIKit
import LocalAuthentication
import Security
import CoreLocation
import CommonCrypto

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate, CLLocationManagerDelegate, UIImagePickerControllerDelegate, UINavigationControllerDelegate, UIDocumentPickerDelegate {
  private let channelName = "com.indetail.office/device"
  private var locationManager: CLLocationManager?
  private var locationResult: FlutterResult?
  private var imagePickerResult: FlutterResult?
  private var documentPickerResult: FlutterResult?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    
    let controller = window?.rootViewController as? FlutterViewController
    let binaryMessenger = controller?.binaryMessenger ?? engineBridge.pluginRegistry.registrar(forPlugin: "DeviceServices")?.messenger()
    
    if let messenger = binaryMessenger {
      let channel = FlutterMethodChannel(name: channelName, binaryMessenger: messenger)
      channel.setMethodCallHandler { [weak self] (call, result) in
        self?.handleMethod(call: call, result: result)
      }
    }
  }

  private func handleMethod(call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "writeSecure":
      guard let args = call.arguments as? [String: Any],
            let key = args["key"] as? String,
            let value = args["value"] as? String else {
        result(FlutterError(code: "invalid_arguments", message: "Missing secure key/value", details: nil))
        return
      }
      saveToKeychain(key: key, value: value)
      result(nil)

    case "readSecure":
      guard let args = call.arguments as? [String: Any],
            let key = args["key"] as? String else {
        result(nil)
        return
      }
      result(readFromKeychain(key: key))

    case "deleteSecure":
      guard let args = call.arguments as? [String: Any],
            let key = args["key"] as? String else {
        result(nil)
        return
      }
      deleteFromKeychain(key: key)
      result(nil)

    case "hasPin":
      result(readFromKeychain(key: "pin_record") != nil)

    case "setPin":
      guard let args = call.arguments as? [String: Any],
            let pin = args["pin"] as? String,
            pin.range(of: "^[0-9]{6}$", options: .regularExpression) != nil else {
        result(FlutterError(code: "invalid_pin", message: "PIN must contain exactly six digits", details: nil))
        return
      }
      var salt = [UInt8](repeating: 0, count: 16)
      _ = SecRandomCopyBytes(kSecRandomDefault, salt.count, &salt)
      let saltData = Data(salt)
      if let hash = derivePinHash(pin: pin, salt: saltData) {
        let combined = saltData + hash
        saveToKeychain(key: "pin_record", value: combined.base64EncodedString())
        saveToKeychain(key: "pin_failures", value: "0")
        saveToKeychain(key: "pin_lockout_until", value: "0")
        result(nil)
      } else {
        result(FlutterError(code: "pin_setup", message: "Failed to derive PIN hash", details: nil))
      }

    case "verifyPin":
      guard let args = call.arguments as? [String: Any],
            let pin = args["pin"] as? String,
            pin.range(of: "^[0-9]{6}$", options: .regularExpression) != nil else {
        result(false)
        return
      }
      let lockoutUntil = Int64(readFromKeychain(key: "pin_lockout_until") ?? "0") ?? 0
      let now = Int64(Date().timeIntervalSince1970 * 1000)
      if now < lockoutUntil {
        result(FlutterError(code: "pin_locked", message: "Too many attempts. Try again in a short while.", details: nil))
        return
      }
      guard let recordB64 = readFromKeychain(key: "pin_record"),
            let recordData = Data(base64Encoded: recordB64),
            recordData.count > 16 else {
        result(FlutterError(code: "pin_missing", message: "Set up a PIN after signing in.", details: nil))
        return
      }
      let salt = recordData.subdata(in: 0..<16)
      let expectedHash = recordData.subdata(in: 16..<recordData.count)
      if let actualHash = derivePinHash(pin: pin, salt: salt), actualHash == expectedHash {
        saveToKeychain(key: "pin_failures", value: "0")
        saveToKeychain(key: "pin_lockout_until", value: "0")
        result(true)
      } else {
        let failures = (Int(readFromKeychain(key: "pin_failures") ?? "0") ?? 0) + 1
        if failures >= 5 {
          saveToKeychain(key: "pin_failures", value: "0")
          saveToKeychain(key: "pin_lockout_until", value: String(now + 30_000))
        } else {
          saveToKeychain(key: "pin_failures", value: String(failures))
        }
        result(false)
      }

    case "biometricAvailable":
      let context = LAContext()
      var error: NSError?
      let canAuth = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
      result(canAuth)

    case "authenticateBiometric":
      let context = LAContext()
      context.localizedFallbackTitle = "Use PIN"
      var error: NSError?
      if context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) {
        context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: "Unlock INDETAIL") { success, _ in
          DispatchQueue.main.async {
            result(success)
          }
        }
      } else {
        result(false)
      }

    case "currentLocation":
      requestLocation(result: result)

    case "chooseImage":
      chooseImage(result: result)

    case "chooseSpreadsheet":
      chooseSpreadsheet(result: result)

    case "saveSpreadsheet":
      saveSpreadsheet(call: call, result: result)

    default:
      result(FlutterMethodNotImplemented)
    }
  }

  // MARK: - Keychain Storage
  private func saveToKeychain(key: String, value: String) {
    guard let data = value.data(using: .utf8) else { return }
    deleteFromKeychain(key: key)
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrAccount as String: key,
      kSecValueData as String: data,
      kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
    ]
    SecItemAdd(query as CFDictionary, nil)
  }

  private func readFromKeychain(key: String) -> String? {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrAccount as String: key,
      kSecReturnData as String: true,
      kSecMatchLimit as String: kSecMatchLimitOne
    ]
    var item: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &item)
    if status == errSecSuccess, let data = item as? Data {
      return String(data: data, encoding: .utf8)
    }
    return nil
  }

  private func deleteFromKeychain(key: String) {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrAccount as String: key
    ]
    SecItemDelete(query as CFDictionary)
  }

  // MARK: - PBKDF2 PIN Hashing
  private func derivePinHash(pin: String, salt: Data) -> Data? {
    let passwordData = pin.data(using: .utf8)!
    var derived = [UInt8](repeating: 0, count: 32)
    let status = salt.withUnsafeBytes { saltPtr in
      passwordData.withUnsafeBytes { passPtr in
        CCKeyDerivationPBKDF(
          CCPBKDFAlgorithm(kCCPBKDF2),
          passPtr.baseAddress?.assumingMemoryBound(to: Int8.self),
          passwordData.count,
          saltPtr.baseAddress?.assumingMemoryBound(to: UInt8.self),
          salt.count,
          CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
          210_000,
          &derived,
          derived.count
        )
      }
    }
    return status == kCCSuccess ? Data(derived) : nil
  }

  // MARK: - Location
  private func requestLocation(result: @escaping FlutterResult) {
    locationResult = result
    locationManager = CLLocationManager()
    locationManager?.delegate = self
    locationManager?.desiredAccuracy = kCLLocationAccuracyBest
    locationManager?.requestWhenInUseAuthorization()
    locationManager?.startUpdatingLocation()
  }

  func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
    guard let location = locations.last else { return }
    manager.stopUpdatingLocation()
    if let res = locationResult {
      locationResult = nil
      res([
        "latitude": location.coordinate.latitude,
        "longitude": location.coordinate.longitude,
        "accuracy": location.horizontalAccuracy,
        "mocked": false
      ])
    }
  }

  func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
    manager.stopUpdatingLocation()
    if let res = locationResult {
      locationResult = nil
      res(FlutterError(code: "location_error", message: error.localizedDescription, details: nil))
    }
  }

  // MARK: - Image Picker
  private func chooseImage(result: @escaping FlutterResult) {
    imagePickerResult = result
    let picker = UIImagePickerController()
    picker.delegate = self
    picker.sourceType = .photoLibrary
    window?.rootViewController?.present(picker, animated: true, completion: nil)
  }

  func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
    picker.dismiss(animated: true, completion: nil)
    guard let image = info[.originalImage] as? UIImage,
          let data = image.jpegData(compressionQuality: 0.8) else {
      imagePickerResult?(nil)
      imagePickerResult = nil
      return
    }
    imagePickerResult?([
      "name": "photo-\(Int(Date().timeIntervalSince1970)).jpg",
      "contentType": "image/jpeg",
      "base64": data.base64EncodedString()
    ])
    imagePickerResult = nil
  }

  func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
    picker.dismiss(animated: true, completion: nil)
    imagePickerResult?(nil)
    imagePickerResult = nil
  }

  // MARK: - Document Picker (Spreadsheets)
  private func chooseSpreadsheet(result: @escaping FlutterResult) {
    documentPickerResult = result
    let types = ["org.openxmlformats.spreadsheetml.sheet", "com.microsoft.excel.xls"]
    let picker = UIDocumentPickerViewController(documentTypes: types, in: .import)
    picker.delegate = self
    window?.rootViewController?.present(picker, animated: true, completion: nil)
  }

  func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
    guard let url = urls.first, let data = try? Data(contentsOf: url) else {
      documentPickerResult?(nil)
      documentPickerResult = nil
      return
    }
    documentPickerResult?([
      "name": url.lastPathComponent,
      "base64": data.base64EncodedString()
    ])
    documentPickerResult = nil
  }

  func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
    documentPickerResult?(nil)
    documentPickerResult = nil
  }

  private func saveSpreadsheet(call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard let args = call.arguments as? [String: Any],
          let b64 = args["base64"] as? String,
          let data = Data(base64Encoded: b64),
          let name = args["name"] as? String else {
      result(FlutterError(code: "invalid_arguments", message: "Missing spreadsheet data", details: nil))
      return
    }
    let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(name)
    try? data.write(to: tempURL)
    let activity = UIActivityViewController(activityItems: [tempURL], applicationActivities: nil)
    window?.rootViewController?.present(activity, animated: true, completion: {
      result(nil)
    })
  }
}
