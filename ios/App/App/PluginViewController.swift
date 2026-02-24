import UIKit
import Capacitor

/// Custom bridge view controller that registers native plugins for Capacitor 7
@objc(PluginViewController)
class PluginViewController: CAPBridgeViewController {

    override func capacitorDidLoad() {
        super.capacitorDidLoad()

        print("✅ PluginViewController.capacitorDidLoad – registering native plugins")

        // Register your Swift plugins with the Capacitor bridge
        bridge?.registerPluginInstance(VoiceCommandsPlugin())
        bridge?.registerPluginInstance(IAPPlugin())

        print("✅ Finished registering VoiceCommandsPlugin + NativeAudioPlayerPlugin")
    }
}
