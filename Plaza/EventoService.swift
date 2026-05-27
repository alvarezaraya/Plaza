// EventoService.swift
// Servicio principal de datos: descarga el JSON de eventos, geocodifica venues, clasifica con IA y persiste ediciones.

import Foundation
import Observation

// MARK: - DTO

struct Evento: Identifiable, Codable {
    let nombre: String
    let descripcion: String
    let fecha_iso: String
    let fecha_texto: String
    let ciudad: String
    let fuente: String
    let url: String
    let precio_desde_clp: String
    let imagen_url: String
    let venue: String?
    let descripcion_extendida: String?
    let bio_artista: String?

    var id: String { nombre + url }

    var precioTexto: String {
        guard !precio_desde_clp.isEmpty,
              let num = Int(precio_desde_clp.replacingOccurrences(of: ".", with: ""))
        else { return "Precio no indicado" }
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.groupingSeparator = "."
        return "Desde $\(f.string(from: NSNumber(value: num)) ?? precio_desde_clp)"
    }

    var urlAbierta: URL? { URL(string: url) }
    var imagenURL: URL? { URL(string: imagen_url) }
    var fechaMostrar: String { fecha_texto.isEmpty ? "Fecha por confirmar" : fecha_texto }
    var descripcionMostrar: String { descripcion.isEmpty ? "Sin descripción disponible." : descripcion }
    var venueMostrar: String { if let v = venue, !v.isEmpty { return v }; return ciudad }
}

struct RespuestaJSON: Codable {
    let generado_en: String
    let total_eventos: Int
    let eventos: [Evento]
}

// MARK: - Servicio

@MainActor
@Observable
class EventoService {
    private let jsonURL = URL(string:
        "https://raw.githubusercontent.com/alvarezaraya/plaza/main/eventos.json"
    )!
    private let editsKey  = "plaza_edited_events"
    private let savedKey  = "plaza_saved_events"
    private let etagKey   = "plaza_etag"
    private let cachedKey = "plaza_cached_json"

    var events: [Event] = []
    var cargando = false
    var error: String?
    private(set) var savedIDs: Set<String> = []

    var savedEvents: [Event] {
        events.filter { savedIDs.contains($0.stableID) }
    }

    func isSaved(_ event: Event) -> Bool {
        savedIDs.contains(event.stableID)
    }

    @discardableResult
    func toggleSaved(_ event: Event) -> Bool {
        if savedIDs.contains(event.stableID) {
            savedIDs.remove(event.stableID)
            persistSavedIDs()
            return false
        } else {
            savedIDs.insert(event.stableID)
            persistSavedIDs()
            return true
        }
    }

    private func persistSavedIDs() {
        if let data = try? JSONEncoder().encode(Array(savedIDs)) {
            UserDefaults.standard.set(data, forKey: savedKey)
        }
    }

    private func loadSavedIDs() {
        guard let data = UserDefaults.standard.data(forKey: savedKey),
              let ids = try? JSONDecoder().decode([String].self, from: data)
        else { return }
        savedIDs = Set(ids)
    }

    func cargarEventos() {
        guard !cargando else { return }
        cargando = true
        error = nil
        loadSavedIDs()

        Task {
            do {
                let data = try await fetchWithETag()
                let r = try JSONDecoder().decode(RespuestaJSON.self, from: data)
                var processed = Self.processEvents(r.eventos)
                applyEdits(to: &processed)
                events = processed
                Task { await geocodeEvents() }
                Task { await reclassifyWithAI() }
            } catch {
                // Si hay datos cacheados, mostrarlos en lugar de un error en blanco
                if let cached = UserDefaults.standard.data(forKey: cachedKey),
                   let r = try? JSONDecoder().decode(RespuestaJSON.self, from: cached) {
                    var processed = Self.processEvents(r.eventos)
                    applyEdits(to: &processed)
                    events = processed
                    self.error = "Sin conexión — mostrando datos guardados"
                } else {
                    self.error = "Sin conexión: \(error.localizedDescription)"
                }
            }
            cargando = false
        }
    }

    // Descarga con soporte ETag para evitar re-descargar si no hubo cambios.
    private func fetchWithETag() async throws -> Data {
        var request = URLRequest(url: jsonURL, cachePolicy: .reloadIgnoringLocalCacheData)
        if let storedETag = UserDefaults.standard.string(forKey: etagKey) {
            request.setValue(storedETag, forHTTPHeaderField: "If-None-Match")
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        let http = response as? HTTPURLResponse

        if http?.statusCode == 304,
           let cached = UserDefaults.standard.data(forKey: cachedKey) {
            return cached
        }

        if let etag = http?.value(forHTTPHeaderField: "ETag") {
            UserDefaults.standard.set(etag, forKey: etagKey)
        }
        UserDefaults.standard.set(data, forKey: cachedKey)
        return data
    }

    func updateEvent(_ updated: Event) {
        guard let index = events.firstIndex(where: { $0.id == updated.id }) else { return }
        events[index] = updated
        saveEdit(updated)
    }

    // MARK: - Persistencia local

    private func saveEdit(_ event: Event) {
        var edits = loadEdits()
        edits[event.stableID] = EditedFields(from: event)
        if let data = try? JSONEncoder().encode(edits) {
            UserDefaults.standard.set(data, forKey: editsKey)
        }
    }

    private func loadEdits() -> [String: EditedFields] {
        guard let data = UserDefaults.standard.data(forKey: editsKey) else { return [:] }
        return (try? JSONDecoder().decode([String: EditedFields].self, from: data)) ?? [:]
    }

    private func applyEdits(to events: inout [Event]) {
        let edits = loadEdits()
        for i in events.indices {
            if let edit = edits[events[i].stableID] {
                edit.apply(to: &events[i])
            }
        }
    }

    private static func processEvents(_ eventos: [Evento]) -> [Event] {
        var seen = Set<String>()
        let unique = eventos.filter { seen.insert($0.url).inserted }
        let converted = unique.map { Event.from($0) }

        var groups: [String: [Event]] = [:]
        for event in converted {
            groups[event.groupKey, default: []].append(event)
        }

        return groups.values.compactMap { group in
            let sorted = group.sorted { $0.date < $1.date }
            guard var primary = sorted.first else { return nil }
            if sorted.count > 1 {
                primary.otherDates = sorted.dropFirst().map {
                    Event.DateEntry(date: $0.date, venue: $0.venue, ciudad: $0.ciudad)
                }
            }
            return primary
        }.sorted { $0.date < $1.date }
    }

    // MARK: - Geocodificación

    private func geocodeEvents() async {
        let uniqueVenues = Set(events.map { "\($0.venue)|\($0.ciudad)" })
        for venueKey in uniqueVenues {
            let parts = venueKey.split(separator: "|", maxSplits: 1)
            guard parts.count == 2 else { continue }
            let venue = String(parts[0])
            let ciudad = String(parts[1])
            let coord = await VenueGeocoder.shared.coordinate(venue: venue, ciudad: ciudad)
            for i in events.indices where events[i].venue == venue && events[i].ciudad == ciudad {
                events[i].coordinate = coord
            }
        }
    }

    // MARK: - Clasificación con Apple Intelligence

    private func reclassifyWithAI() async {
        guard EventClassifier.isAvailable else { return }

        for i in events.indices {
            if let category = await EventClassifier.classify(
                title: events[i].title,
                description: events[i].blurb
            ) {
                events[i].category = category
            }
        }
    }

    // MARK: - Apple Music

    static func fetchAppleMusicURL(artist: String) async -> URL? {
        let query = artist
            .replacingOccurrences(of: "\\s*\\(.*\\)", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty,
              let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let searchURL = URL(string: "https://itunes.apple.com/search?term=\(encoded)&entity=musicArtist&limit=1")
        else { return nil }

        do {
            let (data, _) = try await URLSession.shared.data(from: searchURL)
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let results = json["results"] as? [[String: Any]],
                  let first = results.first,
                  let urlString = first["artistLinkUrl"] as? String
            else { return nil }
            return URL(string: urlString)
        } catch {
            return nil
        }
    }
}
