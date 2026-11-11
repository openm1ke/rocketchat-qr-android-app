import Flutter
import UIKit

class SceneDelegate: FlutterSceneDelegate {
    override func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        for context in connectionOptions.urlContexts {
            PassWidgetBridge.handleWidgetURL(context.url)
        }
        super.scene(scene, willConnectTo: session, options: connectionOptions)
    }

    override func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
        let otherURLs = URLContexts.filter { !PassWidgetBridge.handleWidgetURL($0.url) }
        if !otherURLs.isEmpty {
            super.scene(scene, openURLContexts: otherURLs)
        }
    }
}
