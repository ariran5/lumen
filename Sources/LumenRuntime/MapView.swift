import JavaScriptCore
import MapKit
import UIKit

/// MKMapView с JS-bridged props и callback'ами.
/// Паттерн — стандартный overlay: UIView сидит как subview hostView,
/// frame'ом управляет Renderer через flex layout. Те же шаги что у
/// LumenTextField / LumenBlurView / LumenScrollView.
@MainActor
final class LumenMapView: MKMapView, MKMapViewDelegate {

    var onRegionChange: JSValue?
    var onPinTap: JSValue?

    /// Игнорим первый regionDidChange после программного `setRegion(...)`,
    /// иначе zoomToFit от JS → callback в JS → JS пушит region.value → loop.
    private var suppressNextRegionEvent = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        delegate = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) not implemented") }

    func apply(region: MapRegionSpec?,
               pins: [MapPinSpec],
               mapType: MKMapType) {
        if self.mapType != mapType {
            self.mapType = mapType
        }
        if let region {
            let target = MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: region.lat, longitude: region.lon),
                span: MKCoordinateSpan(latitudeDelta: region.latDelta,
                                       longitudeDelta: region.lonDelta))
            if !Self.regionsEqual(self.region, target) {
                suppressNextRegionEvent = true
                setRegion(target, animated: true)
            }
        }

        // Pins: тривиальный diff по id+coord. Для серьёзного маршрута/heat-map
        // лучше keyed-reuse, но для типового UI достаточно.
        let existing = annotations.compactMap { $0 as? LumenPinAnnotation }
        let nextKeys = Set(pins.map { $0.signature })
        let existingKeys = Set(existing.map { $0.signature })

        if existingKeys != nextKeys {
            removeAnnotations(existing)
            for p in pins {
                addAnnotation(LumenPinAnnotation(spec: p))
            }
        }
    }

    private static func regionsEqual(_ a: MKCoordinateRegion, _ b: MKCoordinateRegion) -> Bool {
        let eps = 1e-4
        return abs(a.center.latitude - b.center.latitude) < eps
            && abs(a.center.longitude - b.center.longitude) < eps
            && abs(a.span.latitudeDelta - b.span.latitudeDelta) < eps
            && abs(a.span.longitudeDelta - b.span.longitudeDelta) < eps
    }

    // MARK: - MKMapViewDelegate

    nonisolated func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
        MainActor.assumeIsolated {
            if suppressNextRegionEvent {
                suppressNextRegionEvent = false
                return
            }
            guard let cb = onRegionChange else { return }
            let r = mapView.region
            let payload: [String: Any] = [
                "lat": r.center.latitude,
                "lon": r.center.longitude,
                "latDelta": r.span.latitudeDelta,
                "lonDelta": r.span.longitudeDelta,
            ]
            _ = cb.call(withArguments: [payload])
        }
    }

    nonisolated func mapView(_ mapView: MKMapView, didSelect view: MKAnnotationView) {
        MainActor.assumeIsolated {
            guard let cb = onPinTap,
                  let pin = view.annotation as? LumenPinAnnotation else { return }
            _ = cb.call(withArguments: [pin.spec.id ?? NSNull()])
            mapView.deselectAnnotation(view.annotation, animated: true)
        }
    }
}

// MARK: - data structs (parsed RenderNode → Swift)

struct MapRegionSpec: Equatable {
    let lat: Double
    let lon: Double
    let latDelta: Double
    let lonDelta: Double
}

struct MapPinSpec: Equatable {
    let lat: Double
    let lon: Double
    let title: String?
    let id: String?

    var signature: String {
        "\(id ?? "")|\(lat)|\(lon)|\(title ?? "")"
    }
}

// MKAnnotation — NSObjectProtocol, не MainActor-isolated. Делаем annotation
// без MainActor и с immutable-данными — MapKit гоняет это между потоками.
final class LumenPinAnnotation: NSObject, MKAnnotation, @unchecked Sendable {
    let spec: MapPinSpec
    init(spec: MapPinSpec) { self.spec = spec }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: spec.lat, longitude: spec.lon)
    }
    var title: String? { spec.title }

    var signature: String { spec.signature }
}

extension MapPinSpec: @unchecked Sendable {}
