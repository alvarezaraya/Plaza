// ComunaManager.swift
// Gestiona la comuna seleccionada por el usuario: auto-detección por GPS y lista de comunas del norte de Chile.

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
        RegionData(id: "Arica y Parinacota", comunas: [
            "Arica", "Camarones", "Putre", "General Lagos",
        ]),
        RegionData(id: "Tarapacá", comunas: [
            "Iquique", "Alto Hospicio", "Pozo Almonte",
            "Camiña", "Colchane", "Huara", "Pica",
        ]),
        RegionData(id: "Antofagasta", comunas: [
            "Antofagasta", "Mejillones", "Sierra Gorda", "Taltal",
            "Calama", "Ollagüe", "San Pedro de Atacama",
            "Tocopilla", "María Elena",
        ]),
        RegionData(id: "Atacama", comunas: [
            "Copiapó", "Caldera", "Tierra Amarilla",
            "Chañaral", "Diego de Almagro",
            "Vallenar", "Alto del Carmen", "Freirina", "Huasco",
        ]),
    ]

    static var todasLasComunas: [String] {
        regiones.flatMap { $0.comunas }
    }

    // MARK: - Estado

    private(set) var selectedComuna: String
    private(set) var hasManualSelection = false  // Solo en memoria: siempre false al lanzar
    var isDetecting = false

    private static let storageKey = "plaza_selected_comuna"

    init() {
        // Muestra la última comuna detectada mientras el GPS carga, pero no bloquea la auto-detección
        selectedComuna = UserDefaults.standard.string(forKey: Self.storageKey) ?? "Antofagasta"
    }

    // MARK: - Selección manual

    func seleccionar(_ comuna: String) {
        selectedComuna     = comuna
        hasManualSelection = true  // Pausa auto-detección durante esta sesión
        UserDefaults.standard.set(comuna, forKey: Self.storageKey)
    }

    func resetearAAutoDeteccion() {
        hasManualSelection = false
        UserDefaults.standard.removeObject(forKey: Self.storageKey)
    }

    // MARK: - Auto-detección

    /// Intenta detectar la comuna del usuario a partir de su ubicación GPS.
    /// Solo actúa si no hay selección manual previa.
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
