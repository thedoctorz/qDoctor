import Flutter
import UIKit

/// Registers the MapKit platform view. There is nothing else to this plugin:
/// every call goes to a per-view channel owned by `AppleMapPlatformView`.
public class AppleMapPlugin: NSObject, FlutterPlugin {
    public static func register(with registrar: FlutterPluginRegistrar) {
        registrar.register(
            AppleMapViewFactory(messenger: registrar.messenger()),
            withId: AppleMapViewFactory.viewType
        )
    }
}

class AppleMapViewFactory: NSObject, FlutterPlatformViewFactory {
    /// Must match the `viewType` the Dart side passes to `UiKitView`.
    static let viewType = "applemap/view"

    private let messenger: FlutterBinaryMessenger

    init(messenger: FlutterBinaryMessenger) {
        self.messenger = messenger
        super.init()
    }

    func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol {
        FlutterStandardMessageCodec.sharedInstance()
    }

    func create(
        withFrame frame: CGRect,
        viewIdentifier viewId: Int64,
        arguments args: Any?
    ) -> FlutterPlatformView {
        AppleMapPlatformView(
            frame: frame,
            viewId: viewId,
            arguments: args as? [String: Any] ?? [:],
            messenger: messenger
        )
    }
}
