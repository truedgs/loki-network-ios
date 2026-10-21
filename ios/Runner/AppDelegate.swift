import Flutter
import UIKit
import NetworkExtension
import Security

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var vpnSetupChannel: FlutterMethodChannel?
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    guard let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "LokiIosVpnSetup") else { return }
    let channel = FlutterMethodChannel(name: "com.lokinetwork.mm/ios_vpn_setup", binaryMessenger: registrar.messenger())
    vpnSetupChannel = channel
    channel.setMethodCallHandler { [weak self] call, result in
      guard call.method == "checkVpnSetup" else {
        result(FlutterMethodNotImplemented)
        return
      }
      self?.checkVpnSetup(result: result)
    }
  }

  private func checkVpnSetup(result: @escaping FlutterResult) {
    #if targetEnvironment(simulator)
    result(FlutterError(code: "IOS_VPN_SIMULATOR", message: "VPN tunnel testing requires a signed physical iPhone.", details: nil))
    return
    #else
    guard let bundleId = Bundle.main.bundleIdentifier,
          let group = Bundle.main.object(forInfoDictionaryKey: "FlutterVlessKeychainAccessGroup") as? String,
          !group.isEmpty, !group.contains("$(") else {
      result(FlutterError(code: "IOS_VPN_CONFIGURATION", message: "Missing iOS bundle or shared App Group configuration.", details: nil))
      return
    }
    guard let plugins = Bundle.main.builtInPlugInsURL,
          let tunnel = Bundle(url: plugins.appendingPathComponent("XrayTunnel.appex")),
          tunnel.bundleIdentifier == bundleId + ".XrayTunnel" else {
      result(FlutterError(code: "IOS_VPN_EXTENSION", message: "XrayTunnel is missing or its bundle ID does not match the app. Rebuild and sign both targets together.", details: nil))
      return
    }
    guard FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group) != nil else {
      result(FlutterError(code: "IOS_VPN_APP_GROUP", message: "This installation cannot access the VPN App Group. Sign Runner and XrayTunnel with provisioning profiles that include the registered App Group and Network Extension capability. An unsigned IPA cannot provide these permissions.", details: nil))
      return
    }
    // Probe only our temporary item; never read or alter the user's VPN secrets.
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: "com.lokinetwork.vpn.setup-check",
      kSecAttrAccount as String: UUID().uuidString,
      kSecAttrAccessGroup as String: group,
    ]
    var item = query
    item[kSecValueData as String] = Data([0])
    item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
    let status = SecItemAdd(item as CFDictionary, nil)
    guard status == errSecSuccess else {
      result(FlutterError(code: "IOS_VPN_KEYCHAIN", message: "Shared VPN Keychain is unavailable (OSStatus \(status)). Check both targets' App Group signing profiles, or unlock the iPhone and retry.", details: nil))
      return
    }
    SecItemDelete(query as CFDictionary)
    // A read-only OS check exposes entitlement failures without installing another profile.
    NETunnelProviderManager.loadAllFromPreferences { _, error in
      DispatchQueue.main.async {
        if let error = error as NSError? {
          result(FlutterError(code: "IOS_VPN_PREFERENCES", message: "iOS cannot access VPN profiles (\(error.domain), code \(error.code)). Verify Network Extension signing and device restrictions.", details: nil))
        } else {
          result(["bundleId": bundleId, "groupIdentifier": group, "keychainAccessGroup": group])
        }
      }
    }
    #endif
  }
}
