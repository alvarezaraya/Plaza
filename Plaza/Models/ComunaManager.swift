// ComunaManager.swift
// Filtro de ubicación: auto-detección GPS → comuna más cercana, selección manual por comuna.
// La app cubre SOLO la Región de Antofagasta; "Chile" es el sentinel que muestra
// todos los eventos (= toda la región) sin filtro por comuna.

import Foundation
import MapKit
import Observation

@MainActor
@Observable
final class ComunaManager {

    // MARK: - Datos estáticos

    struct RegionData: Identifiable {
        let id: String          // nombre de la región
        let comunas: [String]
    }

    static let regiones: [RegionData] = [
        RegionData(id: "Antofagasta", comunas: [
            "Antofagasta", "Mejillones", "Sierra Gorda", "Taltal",
            "Calama", "Ollagüe", "San Pedro de Atacama",
            "Tocopilla", "María Elena",
        ]),
    ]

    static var todasLasComunas: [String] {
        regiones.flatMap { $0.comunas }
    }

    // MARK: - Estado

    private(set) var selectedComuna: String
    private(set) var hasManualSelection = false  // Solo en memoria: siempre false al lanzar

    // Nombre para UI: el sentinel "Chile" (sin filtro) se muestra como toda la región.
    var displayComuna: String {
        selectedComuna == "Chile" ? "Toda la región" : selectedComuna
    }
    var isDetecting = false

    private static let storageKey = "plaza_selected_comuna"

    init() {
        let stored = UserDefaults.standard.string(forKey: Self.storageKey) ?? "Chile"
        // Migración: una comuna guardada antes del recorte a la Región de
        // Antofagasta (p. ej. "Santiago") ya no existe en el picker ni tiene
        // eventos — se resetea al sentinel "toda la región".
        if stored == "Chile" || Self.todasLasComunas.contains(where: { $0 == stored }) {
            selectedComuna = stored
        } else {
            selectedComuna = "Chile"
            UserDefaults.standard.removeObject(forKey: Self.storageKey)
        }
    }

    // MARK: - Selección manual

    func seleccionar(_ comuna: String) {
        selectedComuna     = comuna
        hasManualSelection = true
        UserDefaults.standard.set(comuna, forKey: Self.storageKey)
    }

    func resetearAAutoDeteccion() {
        hasManualSelection = false
        UserDefaults.standard.removeObject(forKey: Self.storageKey)
        selectedComuna = "Chile"
    }

    // MARK: - Auto-detección

    func autoDetectar(desde location: CLLocation) {
        guard !hasManualSelection, !isDetecting else { return }
        isDetecting = true
        Task {
            defer { isDetecting = false }
            guard let request = MKReverseGeocodingRequest(location: location),
                  let mapItems = try? await request.mapItems,
                  let item = mapItems.first
            else { return }

            let city = item.addressRepresentations?.cityName ?? ""
            guard !city.isEmpty else { return }

            let all = Self.todasLasComunas
            if let match = all.first(where: { $0.lowercased() == city.lowercased() }) {
                selectedComuna = match
                UserDefaults.standard.set(match, forKey: Self.storageKey)
                return
            }
            if let match = all.first(where: {
                city.lowercased().contains($0.lowercased()) ||
                $0.lowercased().contains(city.lowercased())
            }) {
                selectedComuna = match
                UserDefaults.standard.set(match, forKey: Self.storageKey)
            }
        }
    }
}
