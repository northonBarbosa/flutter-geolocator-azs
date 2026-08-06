import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // Registro eager (não a versão lazy via didInitializeImplicitFlutterEngine):
    // um relaunch em background disparado só por localização não conecta
    // nenhuma scene, então o engine implícito nunca seria criado e nosso
    // plugin nunca receberia application(_:didFinishLaunchingWithOptions:).
    GeneratedPluginRegistrant.register(with: self)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    // No-op: plugins já registrados eagerly acima. Mantido só para
    // conformar ao protocolo exigido pelo template de scene.
  }
}
