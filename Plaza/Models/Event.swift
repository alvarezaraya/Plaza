// Event.swift
// Modelo central del evento cultural: datos, categorías, conversión desde DTO y datos de muestra.

import Foundation
import CoreLocation

private let eventDateFormatter: DateFormatter = {
    let f = DateFormatter()
    f.locale = Locale(identifier: "es_CL")
    f.dateFormat = "d 'de' MMMM"
    return f
}()

struct Event: Identifiable, Hashable {
    let id: UUID
    var stableID: String
    var title: String
    var subtitle: String
    var venue: String
    var ciudad: String
    var category: Category
    var date: Date
    var coordinate: CLLocationCoordinate2D
    var blurb: String
    var bioArtista: String?
    var price: String?
    var url: URL?
    var fuente: String?
    var imageURL: URL?
    var otherDates: [DateEntry] = []

    var dateText: String {
        eventDateFormatter.string(from: date)
    }

    struct DateEntry: Identifiable, Hashable {
        let id = UUID()
        var date: Date
        var venue: String
        var ciudad: String

        var dateText: String {
            eventDateFormatter.string(from: date)
        }
    }

    enum Category: String, CaseIterable, Hashable {
        case musica   = "Música"
        case humor    = "Humor"
        case teatro   = "Teatro"
        case deporte  = "Deporte"
        case familiar = "Familiar"
        case cine     = "Cine"
        case otros    = "Otros"

        var icon: String {
            switch self {
            case .musica:   return "music.note"
            case .humor:    return "face.smiling"
            case .teatro:   return "theatermasks"
            case .deporte:  return "sportscourt"
            case .familiar: return "figure.2.and.child.holdinghands"
            case .cine:     return "film"
            case .otros:    return "sparkles"
            }
        }
    }

    var groupKey: String { title.lowercased() }

    static func == (lhs: Event, rhs: Event) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

// MARK: - Coordenadas

extension Event {
    // Centro geográfico aproximado de Chile continental
    static let defaultCoordinate = CLLocationCoordinate2D(latitude: -35.6751, longitude: -71.5430)
}

// MARK: - Conversión Evento → Event

extension Event {
    static func from(_ evento: Evento) -> Event {
        let (rawTitle, cleanSubtitle) = parseName(evento.nombre)
        let cleanTitle = rawTitle.uppercased()
        let parsedDate = parseDate(evento.fecha_iso)
        let venueStr = evento.venueMostrar
        let category = classify(title: cleanTitle, subtitle: cleanSubtitle, description: evento.descripcion, venue: venueStr)

        let descExtendida = evento.descripcion_extendida ?? ""
        let blurbFinal = stripHTML(descExtendida.isEmpty ? evento.descripcionMostrar : descExtendida)

        let coordinate: CLLocationCoordinate2D
        if let lat = evento.lat, let lon = evento.lon {
            coordinate = CLLocationCoordinate2D(latitude: lat, longitude: lon)
        } else {
            coordinate = Event.defaultCoordinate
        }

        return Event(
            id: UUID(),
            stableID: evento.url,
            title: cleanTitle,
            subtitle: cleanSubtitle,
            venue: venueStr,
            ciudad: evento.ciudad,
            category: category,
            date: parsedDate,
            coordinate: coordinate,
            blurb: blurbFinal,
            bioArtista: evento.bio_artista.map { stripHTML($0) },
            price: evento.precio_desde_clp.isEmpty ? nil : evento.precioTexto,
            url: evento.urlAbierta,
            fuente: evento.fuente,
            imageURL: evento.imagenURL
        )
    }

    private static func parseName(_ raw: String) -> (title: String, subtitle: String) {
        var name = raw
        let ticketeras = "Ticketplus|PuntoTicket|Ticketpro|Ticketmaster|Passline|ComediaTicket"

        // Limpiar prefijos y sufijos de ticketera / "Entradas"
        name = name.replacingOccurrences(of: "^Entradas\\s+(?:para\\s+)?", with: "", options: [.regularExpression, .caseInsensitive])
        name = name.replacingOccurrences(of: "^(?:\(ticketeras))\\s*[-–:]\\s*", with: "", options: [.regularExpression, .caseInsensitive])
        name = name.replacingOccurrences(of: "\\s*[-–]\\s*(?:\(ticketeras))\\s*$", with: "", options: [.regularExpression, .caseInsensitive])
        // Quitar coma o punto y coma al final
        name = name.replacingOccurrences(of: "[,;]\\s*$", with: "", options: .regularExpression)
        name = name.trimmingCharacters(in: .whitespacesAndNewlines)

        var title = name
        var subtitle = ""

        // 1. Separador " - ": tomar solo los dos primeros segmentos;
        //    el tercero en adelante suele ser venue/fecha.
        let dashParts = name.components(separatedBy: " - ")
        if dashParts.count >= 2 {
            title    = dashParts[0].trimmingCharacters(in: .whitespacesAndNewlines)
            subtitle = dashParts[1].trimmingCharacters(in: .whitespacesAndNewlines)

        // 2. "Artist presenta Show" o "Artist presenta: Show"
        } else if let r = name.range(of: "\\s+presenta[:\\s]+", options: [.regularExpression, .caseInsensitive]) {
            title = String(name[..<r.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            var show = String(name[r.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
            // Quitar comillas decorativas circundantes (" " « » ¡ ¿ ' ")
            show = show.replacingOccurrences(of: "^[\"'\\u00A1\\u00BF\\u201C\\u00AB]+|[\"'!?\\u201D\\u00BB]+$", with: "", options: .regularExpression)
            subtitle = show.trimmingCharacters(in: .whitespacesAndNewlines)

        // 3. "Artist en: Show"
        } else if let r = name.range(of: "\\s+en:\\s+", options: [.regularExpression, .caseInsensitive]) {
            title    = String(name[..<r.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            subtitle = String(name[r.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)

        // 4. "Artist Gira/Tour nombre" sin guion
        } else if let r = name.range(of: "\\s+(Gira|Tour)\\s+", options: [.regularExpression, .caseInsensitive]) {
            title    = String(name[..<r.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            subtitle = String(name[r.lowerBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        // Limpiar título: quitar año suelto al final ("Los Jaivas 2026" → "Los Jaivas")
        title = title
            .replacingOccurrences(of: "\\s+\\d{4}\\s*$", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        // Limpiar subtítulo: quitar info de venue que queda pegada
        // "Lo que no se vio en Viña Hotel Antay de" → "Lo que no se vio en Viña"
        subtitle = subtitle
            .replacingOccurrences(of: "\\s+Hotel\\b.*$", with: "", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: "\\s+Casa\\s+del\\b.*$", with: "", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: "\\s+\\bde\\b\\s*$", with: "", options: [.regularExpression, .caseInsensitive])
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return (title, subtitle)
    }

    private static func classify(title: String, subtitle: String, description: String, venue: String) -> Category {
        if venue.lowercased().contains("esquina retornable") { return .cine }

        let text = "\(title) \(subtitle) \(description)".lowercased()

        let rules: [(Category, [String])] = [
            (.cine, ["película", "pelicula", "film", "cine ", "proyección", "proyeccion", "screening", "largometraje", "documental"]),
            (.humor, ["stand up", "stand-up", "standup", "comedia", "comedy", "humor", "humorista", "monólogo", "comedian"]),
            (.teatro, ["teatro", "obra", "musical", "dramaturgia", "escénic", "teatral", "ópera", "opera", "ballet", "danza"]),
            (.deporte, ["boxeo", "mma", "ufc", "pelea", "lucha", "fútbol", "futbol", "running", "maratón", "maraton", "deporte", "deportiv", "wrestling", "kick"]),
            (.familiar, ["circo", "circus", "infantil", "niños", "familia", "familiar", "kids", "títere", "titere", "magia", "payaso"]),
            (.musica, ["concierto", "concert", "festival", "música", "musica", "recital", "gira", "tour", "dj", "reggaeton", "cumbia", "rock", "hip hop", "rap", "trap", "metal", "punk", "jazz", "blues", "folk", "electrónica", "electronica", "sinfónic", "sinfonic", "orquesta", "banda", "cantante", "singer", "live", "show en vivo"]),
        ]

        for (category, keywords) in rules {
            for keyword in keywords {
                if text.contains(keyword) { return category }
            }
        }
        return .otros
    }

    private static func stripHTML(_ text: String) -> String {
        var s = text
        s = s.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
        s = s.replacingOccurrences(of: "&nbsp;",  with: " ")
        s = s.replacingOccurrences(of: "&amp;",   with: "&")
        s = s.replacingOccurrences(of: "&lt;",    with: "<")
        s = s.replacingOccurrences(of: "&gt;",    with: ">")
        s = s.replacingOccurrences(of: "&quot;",  with: "\"")
        s = s.replacingOccurrences(of: "&#39;",   with: "'")
        s = s.replacingOccurrences(of: "&apos;",  with: "'")
        s = s.replacingOccurrences(of: "\\s{2,}", with: " ", options: .regularExpression)
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func parseDate(_ string: String) -> Date {
        let formats = ["yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd", "dd-MM-yyyy"]
        for fmt in formats {
            let df = DateFormatter()
            df.locale = Locale(identifier: "es_CL")
            df.dateFormat = fmt
            if let d = df.date(from: string) { return d }
        }
        return .now
    }
}

// MARK: - Edición persistente

struct EditedFields: Codable {
    var title: String
    var subtitle: String
    var venue: String
    var ciudad: String
    var date: Date
    var price: String?
    var categoryRaw: String
    var blurb: String

    init(from event: Event) {
        title = event.title
        subtitle = event.subtitle
        venue = event.venue
        ciudad = event.ciudad
        date = event.date
        price = event.price
        categoryRaw = event.category.rawValue
        blurb = event.blurb
    }

    func apply(to event: inout Event) {
        event.title = title
        event.subtitle = subtitle
        event.venue = venue
        event.ciudad = ciudad
        event.date = date
        event.price = price
        event.category = Event.Category(rawValue: categoryRaw) ?? event.category
        event.blurb = blurb
    }
}

// MARK: - Filtering helpers

extension Array where Element == Event {
    func byComune(_ key: String) -> [Event] {
        // "Chile" y "" son sentinelas de "mostrar todo"
        let k = key.lowercased().trimmingCharacters(in: .whitespaces)
        guard k != "chile", !k.isEmpty else { return self }
        let byCiudad = filter {
            $0.ciudad.lowercased().contains(k) || k.contains($0.ciudad.lowercased())
        }
        return byCiudad.isEmpty ? self : byCiudad
    }

    func byMaxDistance(_ maxKm: Double, from userLocation: CLLocation?) -> [Event] {
        guard maxKm > 0, let loc = userLocation else { return self }
        return filter { event in
            let point = CLLocation(latitude: event.coordinate.latitude, longitude: event.coordinate.longitude)
            return point.distance(from: loc) / 1000 <= maxKm
        }
    }
}

// MARK: - Sample data

extension Event {
    static let samples: [Event] = [
        .init(id: UUID(), stableID: "sample-1", title: "CUARTETO LATINOAMERICANO", subtitle: "Concierto de cámara",
              venue: "Teatro Municipal", ciudad: "Antofagasta", category: .musica,
              date: Date().addingTimeInterval(60*60*4),
              coordinate: .init(latitude: -23.6509, longitude: -70.3975),
              blurb: "Programa con obras de Villa-Lobos, Piazzolla y Revueltas.", price: "$8.000"),
    ]
}
