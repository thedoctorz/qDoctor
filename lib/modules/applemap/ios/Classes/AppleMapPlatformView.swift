import Flutter
import MapKit
import UIKit

/// An `MKMapView` behind a Flutter widget.
///
/// Deliberately thin. The map draws the basemap, the system location dot and a
/// set of image annotations; everything above it — controls, sheets, the pick
/// crosshair — stays a Flutter widget, so the surrounding page does not have to
/// be written twice.
class AppleMapPlatformView: NSObject, FlutterPlatformView, MKMapViewDelegate {
    private let mapView: LayoutReportingMapView
    private let channel: FlutterMethodChannel

    /// Annotation artwork, by the key the Dart side refers to it with. Sent
    /// once and reused: the pins are a handful of images, and putting bytes in
    /// every annotation update would make selecting a pin a kilobyte of channel
    /// traffic instead of a string.
    private var images: [String: UIImage] = [:]
    private var annotations: [String: KeyedAnnotation] = [:]

    /// Applied once the view has a width. A region means nothing before then,
    /// and the first camera always arrives before the first layout.
    private var pendingCamera: (coordinate: CLLocationCoordinate2D, zoom: Double)?
    private var laidOut = false

    /// Set while `moveCamera` is driving the map, so the region change it
    /// causes is not reported back as the user having moved the map.
    private var programmaticMoves = 0

    init(
        frame: CGRect,
        viewId: Int64,
        arguments: [String: Any],
        messenger: FlutterBinaryMessenger
    ) {
        mapView = LayoutReportingMapView(frame: frame)
        channel = FlutterMethodChannel(
            name: "applemap/view/\(viewId)",
            binaryMessenger: messenger
        )
        super.init()

        mapView.delegate = self
        mapView.isRotateEnabled = false
        mapView.isPitchEnabled = false
        mapView.showsCompass = false
        mapView.showsScale = false
        // Points of interest are left on: they are a large part of why the
        // system map reads as the system map. The muted basemap is the option
        // for when the pins need to carry the screen instead.
        mapView.onLayout = { [weak self] in self?.handleLayout() }

        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        tap.cancelsTouchesInView = false
        mapView.addGestureRecognizer(tap)

        apply(style: arguments["style"] as? String, dark: arguments["dark"] as? Bool ?? false)
        mapView.showsUserLocation = arguments["showsUserLocation"] as? Bool ?? false
        if let camera = arguments["camera"] as? [String: Any] {
            setCamera(camera, animated: false)
        }

        channel.setMethodCallHandler { [weak self] call, result in
            self?.handle(call, result: result)
        }
    }

    func view() -> UIView { mapView }

    deinit {
        mapView.delegate = nil
        mapView.onLayout = nil
        channel.setMethodCallHandler(nil)
    }

    // MARK: - Channel

    private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        let args = call.arguments as? [String: Any] ?? [:]
        switch call.method {
        case "setImages":
            setImages(args["images"] as? [String: FlutterStandardTypedData] ?? [:])
            result(nil)
        case "setAnnotations":
            setAnnotations(args["annotations"] as? [[String: Any]] ?? [])
            result(nil)
        case "moveCamera":
            setCamera(args, animated: args["animated"] as? Bool ?? true)
            result(nil)
        case "camera":
            result(currentCamera())
        case "setStyle":
            apply(style: args["style"] as? String, dark: args["dark"] as? Bool ?? false)
            result(nil)
        case "setShowsUserLocation":
            mapView.showsUserLocation = args["value"] as? Bool ?? false
            result(nil)
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    // MARK: - Style

    private func apply(style: String?, dark: Bool) {
        switch style {
        case "muted": mapView.mapType = .mutedStandard
        case "satellite": mapView.mapType = .satellite
        case "hybrid": mapView.mapType = .hybrid
        default: mapView.mapType = .standard
        }
        // The map follows the app's own light/dark choice rather than the
        // system's: the page already lets that be overridden per map.
        mapView.overrideUserInterfaceStyle = dark ? .dark : .light
    }

    // MARK: - Camera

    /// Width of one tile in the web-mercator scheme every zoom level in this
    /// app is expressed in. MapKit works in spans, so the two are converted
    /// here and nowhere else.
    private static let tileSize: Double = 256

    private func setCamera(_ args: [String: Any], animated: Bool) {
        guard
            let latitude = args["latitude"] as? Double,
            let longitude = args["longitude"] as? Double,
            let zoom = args["zoom"] as? Double
        else { return }

        let coordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        guard CLLocationCoordinate2DIsValid(coordinate) else { return }

        guard laidOut, mapView.bounds.width > 0 else {
            pendingCamera = (coordinate, zoom)
            return
        }

        let width = Double(mapView.bounds.width)
        let height = Double(mapView.bounds.height)
        let longitudeDelta = 360 / pow(2, zoom) * (width / Self.tileSize)
        // A degree of longitude covers cos(latitude) as much ground as a
        // degree of latitude, so the vertical span is the horizontal one
        // scaled by that and by the view's shape. Handing MapKit a zero
        // latitude delta and letting regionThatFits guess is the usual trick
        // and it is not documented to work.
        let aspect = width > 0 ? height / width : 1
        let latitudeDelta =
            longitudeDelta * aspect * cos(latitude * .pi / 180)
        let span = MKCoordinateSpan(
            latitudeDelta: min(max(latitudeDelta, 1e-8), 180),
            longitudeDelta: min(max(longitudeDelta, 1e-8), 360)
        )

        programmaticMoves += 1
        mapView.setRegion(
            mapView.regionThatFits(MKCoordinateRegion(center: coordinate, span: span)),
            animated: animated
        )
        if !animated { programmaticMoves = max(0, programmaticMoves - 1) }
    }

    private func currentCamera() -> [String: Any] {
        let region = mapView.region
        return [
            "latitude": region.center.latitude,
            "longitude": region.center.longitude,
            "zoom": currentZoom(),
        ]
    }

    private func currentZoom() -> Double {
        let width = Double(mapView.bounds.width)
        let longitudeDelta = mapView.region.span.longitudeDelta
        guard width > 0, longitudeDelta > 0 else { return 2 }
        return log2(360 * (width / Self.tileSize) / longitudeDelta)
    }

    private func handleLayout() {
        guard mapView.bounds.width > 0 else { return }
        laidOut = true
        guard let pending = pendingCamera else { return }
        pendingCamera = nil
        setCamera(
            [
                "latitude": pending.coordinate.latitude,
                "longitude": pending.coordinate.longitude,
                "zoom": pending.zoom,
            ],
            animated: false
        )
    }

    // MARK: - Annotations

    private func setImages(_ incoming: [String: FlutterStandardTypedData]) {
        for (key, data) in incoming {
            guard let image = UIImage(data: data.data, scale: UIScreen.main.scale) else { continue }
            images[key] = image
        }
        // Anything already on the map that this refreshed has to be redrawn.
        for (_, annotation) in annotations {
            guard let view = mapView.view(for: annotation) else { continue }
            view.image = images[annotation.imageKey]
            view.centerOffset = Self.centerOffset(for: view.image)
        }
    }

    /// Reconciles the map's annotations with [incoming] by id.
    ///
    /// A diff rather than a clear-and-refill: replacing the set makes every pin
    /// blink each time one of them is selected, because selection is just a
    /// different image for the same id.
    private func setAnnotations(_ incoming: [[String: Any]]) {
        var seen = Set<String>()

        for entry in incoming {
            guard
                let id = entry["id"] as? String,
                let latitude = entry["latitude"] as? Double,
                let longitude = entry["longitude"] as? Double,
                let key = entry["imageKey"] as? String
            else { continue }
            let coordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
            guard CLLocationCoordinate2DIsValid(coordinate) else { continue }
            seen.insert(id)

            if let existing = annotations[id] {
                if existing.coordinate.latitude != latitude
                    || existing.coordinate.longitude != longitude {
                    existing.coordinate = coordinate
                }
                if existing.imageKey != key {
                    existing.imageKey = key
                    if let view = mapView.view(for: existing) {
                        view.image = images[key]
                        view.centerOffset = Self.centerOffset(for: view.image)
                    }
                }
                existing.zIndex = entry["zIndex"] as? Int ?? 0
                continue
            }

            let annotation = KeyedAnnotation(
                id: id,
                coordinate: coordinate,
                imageKey: key,
                zIndex: entry["zIndex"] as? Int ?? 0
            )
            annotations[id] = annotation
            mapView.addAnnotation(annotation)
        }

        let gone = annotations.keys.filter { !seen.contains($0) }
        guard !gone.isEmpty else { return }
        mapView.removeAnnotations(gone.compactMap { annotations.removeValue(forKey: $0) })
    }

    /// Pins are drawn anchored at their bottom point, the way a map pin sits on
    /// the place it marks.
    private static func centerOffset(for image: UIImage?) -> CGPoint {
        guard let image else { return .zero }
        return CGPoint(x: 0, y: -image.size.height / 2)
    }

    func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
        // The system's own blue dot, which is the point of being here.
        if annotation is MKUserLocation { return nil }
        guard let keyed = annotation as? KeyedAnnotation else { return nil }

        let identifier = "applemap.keyed"
        let view = mapView.dequeueReusableAnnotationView(withIdentifier: identifier)
            ?? MKAnnotationView(annotation: keyed, reuseIdentifier: identifier)
        view.annotation = keyed
        view.image = images[keyed.imageKey]
        view.centerOffset = Self.centerOffset(for: view.image)
        view.canShowCallout = false
        // Stacking order: the selected pin belongs on top of whatever it
        // overlaps. Only from iOS 14; below that MapKit orders them itself and
        // a pin under another is still reachable by moving the map.
        if #available(iOS 14.0, *) {
            view.zPriority = MKAnnotationViewZPriority(
                rawValue: Float(500 + keyed.zIndex)
            )
        }
        return view
    }

    func mapView(_ mapView: MKMapView, didSelect view: MKAnnotationView) {
        guard let keyed = view.annotation as? KeyedAnnotation else { return }
        // Deselected straight away: selection is the Dart side's to own, and
        // leaving MapKit's own selection in place means tapping the same pin
        // twice only reports once.
        mapView.deselectAnnotation(keyed, animated: false)
        channel.invokeMethod("onAnnotationTap", arguments: ["id": keyed.id])
    }

    // MARK: - Gestures

    @objc private func handleTap(_ recognizer: UITapGestureRecognizer) {
        // An annotation tap arrives through didSelect instead; this is the
        // basemap, which the page uses to clear the selection.
        let point = recognizer.location(in: mapView)
        for annotation in annotations.values {
            guard let view = mapView.view(for: annotation) else { continue }
            if view.frame.insetBy(dx: -8, dy: -8).contains(point) { return }
        }
        let coordinate = mapView.convert(point, toCoordinateFrom: mapView)
        channel.invokeMethod(
            "onMapTap",
            arguments: ["latitude": coordinate.latitude, "longitude": coordinate.longitude]
        )
    }

    func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
        var byGesture = false
        if programmaticMoves > 0 {
            programmaticMoves -= 1
        } else {
            byGesture = regionChangeWasGesture()
        }
        var payload = currentCamera()
        payload["gesture"] = byGesture
        channel.invokeMethod("onCameraMoved", arguments: payload)
    }

    /// MapKit does not say who moved the map, so ask its own gesture
    /// recognizers. A pan or a pinch that has just ended is the user.
    private func regionChangeWasGesture() -> Bool {
        guard let recognizers = mapView.subviews.first?.gestureRecognizers else { return false }
        for recognizer in recognizers {
            switch recognizer.state {
            case .began, .changed, .ended:
                return true
            default:
                continue
            }
        }
        return false
    }
}

/// An annotation that remembers which Dart-side object it is and which image
/// to draw for it.
class KeyedAnnotation: NSObject, MKAnnotation {
    let id: String
    @objc dynamic var coordinate: CLLocationCoordinate2D
    var imageKey: String
    var zIndex: Int

    init(id: String, coordinate: CLLocationCoordinate2D, imageKey: String, zIndex: Int) {
        self.id = id
        self.coordinate = coordinate
        self.imageKey = imageKey
        self.zIndex = zIndex
        super.init()
    }
}

/// MapKit has no "the view now has a size" callback, and a region set before
/// the first layout is meaningless — the span is computed from the width.
class LayoutReportingMapView: MKMapView {
    var onLayout: (() -> Void)?

    override func layoutSubviews() {
        super.layoutSubviews()
        onLayout?()
    }
}
