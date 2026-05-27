// VenueGeocoder.swift
// Fallback geocoder: venue+ciudad → GPS vía MKGeocodingRequest; caché en UserDefaults (plaza_geocode_cache).
// Solo se invoca para eventos que llegan sin coordenadas del JSON.

import Foundation
import CoreLocation
import MapKit

// Coordenadas fijas para venues locales que MapKit no resuelve correctamente.
// Clave: nombre del venue en minúsculas.
private let VENUES_FIJOS: [String: CLLocationCoordinate2D] = [
    "rock and soccer":               .init(latitude: -23.699305, longitude: -70.422728),
    "teatro municipal de antofagasta": .init(latitude: -23.646360, longitude: -70.396306),
    "teatro municipal":              .init(latitude: -23.646360, longitude: -70.396306),
    "enjoy antofagasta":             .init(latitude: -23.685324, longitude: -70.414614),
    "estadio sokol":                 .init(latitude: -23.655882, longitude: -70.397059),
    "esquina retornable":            .init(latitude: -23.673621, longitude: -70.409617),
]

@MainActor
final class VenueGeocoder {
    static let shared = VenueGeocoder()

    private let cacheKey = "plaza_geocode_cache"
    private var cache: [String: CachedCoordinate] = [:]

    private init() {
        loadCache()
    }

    func coordinate(venue: String, ciudad: String) async -> CLLocationCoordinate2D {
        // Consultar primero el diccionario de venues conocidos
        let venueKey = venue.lowercased().trimmingCharacters(in: .whitespaces)
        if let fixed = VENUES_FIJOS[venueKey] {
            return fixed
        }

        let key = "\(venue)|\(ciudad)".lowercased()

        if let cached = cache[key] {
            return cached.coordinate
        }

        if let coord = await geocode("\(venue), \(ciudad), Chile") {
            cache[key] = CachedCoordinate(latitude: coord.latitude, longitude: coord.longitude)
            saveCache()
            return coord
        }

        let cityKey = "|\(ciudad)".lowercased()
        if let cached = cache[cityKey] {
            return cached.coordinate
        }

        if let coord = await geocode("\(ciudad), Chile") {
            cache[cityKey] = CachedCoordinate(latitude: coord.latitude, longitude: coord.longitude)
            saveCache()
            return coord
        }

        return Event.defaultCoordinate
    }

    private func geocode(_ address: String) async -> CLLocationCoordinate2D? {
        guard let request = MKGeocodingRequest(addressString: address) else { return nil }
        return await withCheckedContinuation { (continuation: CheckedContinuation<CLLocationCoordinate2D?, Never>) in
            request.getMapItems { items, _ in
                continuation.resume(returning: items?.first?.location.coordinate)
            }
        }
    }

    private func loadCache() {
        guard let data = UserDefaults.standard.data(forKey: cacheKey),
              let decoded = try? JSONDecoder().decode([String: CachedCoordinate].self, from: data)
        else { return }
        cache = decoded
    }

    private func saveCache() {
        if let data = try? JSONEncoder().encode(cache) {
            UserDefaults.standard.set(data, forKey: cacheKey)
        }
    }
}

private struct CachedCoordinate: Codable {
    let latitude: Double
    let longitude: Double

    var coordinate: CLLocationCoordinate2D {
        .init(latitude: latitude, longitude: longitude)
    }
}
