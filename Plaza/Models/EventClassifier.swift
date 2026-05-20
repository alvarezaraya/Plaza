// EventClassifier.swift
// Clasifica eventos y genera resúmenes en español usando Apple Intelligence (FoundationModels).

import Foundation
import FoundationModels

@Generable(description: "Category for a cultural event")
enum EventTag {
    case musica
    case humor
    case teatro
    case deporte
    case familiar
    case otros

    var category: Event.Category {
        switch self {
        case .musica: .musica
        case .humor: .humor
        case .teatro: .teatro
        case .deporte: .deporte
        case .familiar: .familiar
        case .otros: .otros
        }
    }
}

@Generable(description: "Summary about a cultural event and its artist or performer")
struct EventSummary {
    @Guide(description: "Brief bio strictly about the exact artist or band named in the event (2-3 sentences in Spanish). Only state facts you are confident about for THIS specific artist. If uncertain, describe only what is mentioned in the event description — do not invent details or confuse with other artists.")
    var bio: String

    @Guide(description: "What attendees can expect at this specific event in Spanish (1-2 sentences), based on the event details provided.")
    var preview: String
}

enum EventClassifier {
    private static let classifyInstructions = """
        Classify the cultural event into exactly one category based on its title and description.
        - musica: concerts, music festivals, recitals, DJs, live music, bands, singers, tours
        - humor: stand-up comedy, comedy shows, monologues, humorists, comedians
        - teatro: theater plays, musicals, opera, ballet, dance performances, drama
        - deporte: boxing, MMA, soccer, running, marathons, wrestling, sports events
        - familiar: circus, children's shows, magic shows, puppets, family events
        - otros: events that don't clearly fit any category above
        """

    private static let summaryInstructions = """
        Genera un resumen sobre el evento cultural y el artista EXACTO indicado. \
        IMPORTANTE: Escribe únicamente sobre el artista nombrado en el evento. \
        No confundas con otros artistas de nombre similar o de la misma categoría. \
        Si no tienes información confiable sobre ese artista específico, limítate a lo que dice la descripción del evento; no inventes datos biográficos. \
        Sé conciso y factual. Responde siempre en español.
        """

    static var isAvailable: Bool {
        SystemLanguageModel(useCase: .general).isAvailable
    }

    static func classify(title: String, description: String) async -> Event.Category? {
        let model = SystemLanguageModel(useCase: .general)
        guard model.isAvailable else { return nil }

        let session = LanguageModelSession(model: model, instructions: classifyInstructions)

        do {
            let response = try await session.respond(
                to: "Event: \(title). \(description)",
                generating: EventTag.self
            )
            return response.content.category
        } catch {
            return nil
        }
    }

    static func generateSummary(event: Event) async -> EventSummary? {
        let model = SystemLanguageModel(useCase: .general)
        guard model.isAvailable else { return nil }

        let session = LanguageModelSession(model: model, instructions: summaryInstructions)

        let prompt = """
            Artista/Evento: \(event.title). \
            \(event.subtitle). \
            Categoría: \(event.category.rawValue). \
            Venue: \(event.venue), \(event.ciudad). \
            Descripción: \(event.blurb)
            """

        do {
            let response = try await session.respond(to: prompt, generating: EventSummary.self)
            return response.content
        } catch {
            return nil
        }
    }
}
