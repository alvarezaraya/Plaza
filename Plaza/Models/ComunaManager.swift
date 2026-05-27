// ComunaManager.swift
// Gestiona la comuna seleccionada por el usuario: auto-detección por GPS y lista de comunas de Chile.

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
        RegionData(id: "Coquimbo", comunas: [
            "La Serena", "Coquimbo", "Andacollo", "La Higuera",
            "Ovalle", "Combarbalá", "Monte Patria", "Punitaqui", "Río Hurtado",
            "Illapel", "Canela", "Los Vilos", "Salamanca",
        ]),
        RegionData(id: "Valparaíso", comunas: [
            "Valparaíso", "Viña del Mar", "Quilpué", "Villa Alemana",
            "Concón", "Quillota", "Calera", "Hijuelas", "La Cruz", "Nogales",
            "San Antonio", "Cartagena", "El Quisco", "El Tabo", "Algarrobo",
            "Los Andes", "San Esteban", "Calle Larga", "Rinconada",
            "San Felipe", "Putaendo", "Santa María", "Panquehue", "Llaillay",
            "Casablanca", "Juan Fernández", "Isla de Pascua",
        ]),
        RegionData(id: "Metropolitana", comunas: [
            "Santiago", "Cerrillos", "Cerro Navia", "Conchalí", "El Bosque",
            "Estación Central", "Huechuraba", "Independencia", "La Cisterna",
            "La Florida", "La Granja", "La Pintana", "La Reina", "Las Condes",
            "Lo Barnechea", "Lo Espejo", "Lo Prado", "Macul", "Maipú",
            "Ñuñoa", "Pedro Aguirre Cerda", "Peñalolén", "Providencia",
            "Pudahuel", "Quilicura", "Quinta Normal", "Recoleta", "Renca",
            "San Joaquín", "San Miguel", "San Ramón", "Vitacura",
            "Puente Alto", "Pirque", "San José de Maipo",
            "Colina", "Lampa", "Tiltil",
            "San Bernardo", "Buin", "Calera de Tango", "Paine",
            "El Monte", "Isla de Maipo", "Melipilla", "Padre Hurtado",
            "Peñaflor", "Talagante", "Alhué", "Curacaví",
        ]),
        RegionData(id: "O'Higgins", comunas: [
            "Rancagua", "Graneros", "Mostazal", "Codegua", "Machalí",
            "Olivar", "Requínoa", "Rengo", "Malloa", "Quinta de Tilcoco",
            "San Vicente", "Pichidegua", "Las Cabras", "Peumo",
            "Pichilemu", "Litueche", "La Estrella", "Marchigüe", "Navidad",
            "Santa Cruz", "Chimbarongo", "Nancagua", "Palmilla", "Peralillo",
            "Placilla", "Lolol", "Pumanque", "San Fernando", "Chépica",
        ]),
        RegionData(id: "Maule", comunas: [
            "Talca", "Constitución", "Curicó", "Linares",
            "Molina", "San Clemente", "Pelarco", "Maule",
            "Curepto", "Sagrada Familia", "Teno", "Romeral", "Río Claro",
            "Retiro", "Colbún", "Longaví", "Parral", "Cauquenes",
            "Pelluhue", "Chanco", "Vichuquén", "Hualañé", "Rauco", "Licantén",
        ]),
        RegionData(id: "Ñuble", comunas: [
            "Chillán", "Chillán Viejo", "San Carlos", "Ñiquén",
            "San Fabián", "San Nicolás", "Bulnes", "Quillón",
            "El Carmen", "Pemuco", "Yungay", "Pinto",
            "Coihueco", "San Ignacio",
        ]),
        RegionData(id: "Biobío", comunas: [
            "Concepción", "Talcahuano", "Penco", "Hualqui",
            "Florida", "Santa Juana", "Coronel", "Lota",
            "Arauco", "Lebu", "Tirúa", "Cañete", "Contulmo", "Curanilahue",
            "Los Álamos", "Los Ángeles", "Santa Bárbara", "Quilaco",
            "Mulchén", "Nacimiento", "Negrete", "Laja", "San Rosendo",
            "Yumbel", "Cabrero", "Tucapel", "Antuco",
            "Chiguayante", "San Pedro de la Paz", "Hualpén",
        ]),
        RegionData(id: "Araucanía", comunas: [
            "Temuco", "Padre Las Casas", "Vilcún", "Cunco",
            "Freire", "Pitrufquén", "Gorbea", "Loncoche",
            "Nueva Imperial", "Teodoro Schmidt", "Carahue",
            "Saavedra", "Toltén",
            "Villarrica", "Pucón", "Curarrehue", "Melipeuco",
            "Angol", "Renaico", "Collipulli", "Ercilla",
            "Lumaco", "Purén", "Los Sauces", "Traiguén",
        ]),
        RegionData(id: "Los Ríos", comunas: [
            "Valdivia", "Mariquina", "Lanco", "Máfil", "Corral",
            "Futrono", "Lago Ranco", "Río Bueno", "La Unión",
            "Panguipulli", "Los Lagos",
        ]),
        RegionData(id: "Los Lagos", comunas: [
            "Puerto Montt", "Puerto Varas", "Llanquihue", "Frutillar",
            "Los Muermos", "Maullín", "Calbuco", "Cochamó",
            "Osorno", "San Pablo", "Puerto Octay", "Purranque",
            "Río Negro", "San Juan de la Costa",
            "Ancud", "Castro", "Chonchi", "Curaco de Vélez", "Dalcahue",
            "Puqueldón", "Queilén", "Quellón", "Quemchi", "Quinchao",
            "Palena", "Futaleufú", "Chaitén",
        ]),
        RegionData(id: "Aysén", comunas: [
            "Coyhaique", "Lago Verde", "Aysén", "Cisnes", "Guaitecas",
            "Cochrane", "O'Higgins", "Tortel",
        ]),
        RegionData(id: "Magallanes", comunas: [
            "Punta Arenas", "Laguna Blanca", "Río Verde", "San Gregorio",
            "Puerto Natales", "Torres del Paine",
            "Porvenir", "Primavera", "Timaukel",
            "Cabo de Hornos",
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
        selectedComuna = UserDefaults.standard.string(forKey: Self.storageKey) ?? "Chile"
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
