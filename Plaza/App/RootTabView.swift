// RootTabView.swift
// Contenedor principal con tab bar Liquid Glass: Inicio, Agenda, Mapa y Buscar.
// En iPad: sidebar de 390pt con las tabs de iPhone + MapView persistente a la derecha.

import SwiftUI

enum AppTab: Hashable {
    case home, agenda, map, search
}

struct RootTabView: View {
    @Environment(\.horizontalSizeClass) private var hSizeClass
    @State private var selection: AppTab = .home

    var body: some View {
        if hSizeClass == .regular {
            iPadLayout
        } else {
            iPhoneTabView(includeMap: true)
                .tabBarMinimizeBehavior(.onScrollDown)
        }
    }

    // MARK: - iPhone

    private func iPhoneTabView(includeMap: Bool) -> some View {
        TabView(selection: $selection) {
            Tab("Inicio", systemImage: "house", value: AppTab.home) {
                HomeView()
            }
            Tab("Agenda", systemImage: "calendar", value: AppTab.agenda) {
                AgendaView()
            }
            if includeMap {
                Tab("Mapa", systemImage: "map", value: AppTab.map) {
                    NavigationStack {
                        MapView()
                            .navigationBarTitleDisplayMode(.inline)
                    }
                }
            }
            Tab(value: AppTab.search, role: .search) {
                SearchView()
            }
        }
    }

    // MARK: - iPad

    private var iPadLayout: some View {
        HStack(spacing: 0) {
            // Sidebar: estructura de iPhone sin la tab de Mapa
            iPhoneTabView(includeMap: false)
                .frame(width: 390)

            // Detalle: Mapa permanente
            MapView()
                .ignoresSafeArea()
        }
        .ignoresSafeArea()
    }
}

// MARK: - Búsqueda

enum SearchScope: String, CaseIterable {
    case todos = "Todos"
    case agenda = "Agenda"
}

struct SearchView: View {
    @Environment(EventoService.self) private var servicio
    @Environment(LocationManager.self) private var location
    @Environment(ComunaManager.self) private var comunaManager
    @State private var searchText = ""
    @State private var scope: SearchScope = .todos
    @AppStorage("plaza_max_distance_km") private var maxDistanceKm: Double = 0

    private var baseEvents: [Event] {
        let pool = scope == .agenda ? servicio.savedEvents : servicio.events
        return pool
            .byComune(comunaManager.selectedComuna)
            .byMaxDistance(maxDistanceKm, from: location.userLocation)
    }

    private var results: [Event] {
        guard !searchText.isEmpty else { return baseEvents }
        let q = searchText.lowercased()
        return baseEvents.filter {
            $0.title.lowercased().contains(q) ||
            $0.venue.lowercased().contains(q) ||
            $0.ciudad.lowercased().contains(q) ||
            $0.category.rawValue.lowercased().contains(q)
        }
    }

    var body: some View {
        NavigationStack {
            List(results) { event in
                NavigationLink(value: event) {
                    HStack(spacing: 12) {
                        Image(systemName: event.category.icon)
                            .foregroundStyle(Color.plAccent)
                            .frame(width: 28)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(event.title)
                                .font(.plSans(15, weight: .medium))
                                .foregroundStyle(Color.plFg)
                                .lineLimit(1)
                            Text("\(event.venue) · \(event.ciudad)")
                                .font(.plMono(11))
                                .foregroundStyle(Color.plMuted)
                        }
                        Spacer()
                        PlTag(text: event.dateText)
                    }
                }
                .listRowBackground(Color.plBg)
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Color.plBg)
            .navigationDestination(for: Event.self) { EventDetailView(event: $0) }
            .navigationTitle("Buscar")
            .searchable(text: $searchText, prompt: "Eventos, venue, ciudad…")
            .searchScopes($scope) {
                ForEach(SearchScope.allCases, id: \.self) { s in
                    Text(s.rawValue).tag(s)
                }
            }
            .overlay {
                if results.isEmpty {
                    ContentUnavailableView.search(text: searchText.isEmpty ? scope.rawValue : searchText)
                }
            }
        }
    }
}

// MARK: - Perfil

struct ProfileView: View {
    @Environment(EventoService.self) private var servicio

    private var events: [Event] { servicio.events }

    private var categoryCounts: [(Event.Category, Int)] {
        var counts: [Event.Category: Int] = [:]
        for event in events { counts[event.category, default: 0] += 1 }
        return Event.Category.allCases.compactMap { cat in
            let c = counts[cat] ?? 0
            return c > 0 ? (cat, c) : nil
        }
    }

    private var ciudadCounts: [(String, Int)] {
        Dictionary(grouping: events, by: \.ciudad)
            .map { ($0.key, $0.value.count) }
            .sorted { $0.1 > $1.1 }
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Resumen") {
                    Label {
                        HStack {
                            Text("Eventos disponibles")
                            Spacer()
                            Text("\(events.count)")
                                .foregroundStyle(Color.plAccent)
                                .fontWeight(.semibold)
                        }
                    } icon: {
                        Image(systemName: "calendar")
                            .foregroundStyle(Color.plAccent)
                    }
                    .accessibilityLabel("\(events.count) eventos disponibles")
                }

                if !categoryCounts.isEmpty {
                    Section("Por categoría") {
                        ForEach(categoryCounts, id: \.0) { category, count in
                            Label {
                                HStack {
                                    Text(category.rawValue)
                                    Spacer()
                                    Text("\(count)")
                                        .foregroundStyle(Color.plMuted)
                                }
                            } icon: {
                                Image(systemName: category.icon)
                                    .foregroundStyle(Color.plAccent)
                            }
                            .accessibilityLabel("\(count) eventos de \(category.rawValue)")
                        }
                    }
                }

                if !ciudadCounts.isEmpty {
                    Section("Por ciudad") {
                        ForEach(ciudadCounts, id: \.0) { ciudad, count in
                            Label {
                                HStack {
                                    Text(ciudad)
                                    Spacer()
                                    Text("\(count)")
                                        .foregroundStyle(Color.plMuted)
                                }
                            } icon: {
                                Image(systemName: "mappin.circle")
                                    .foregroundStyle(Color.plAccent)
                            }
                            .accessibilityLabel("\(count) eventos en \(ciudad)")
                        }
                    }
                }

                Section("Preferencias") {
                    NavigationLink {
                        Text("Próximamente")
                    } label: {
                        Label("Categorías favoritas", systemImage: "heart")
                    }
                    NavigationLink {
                        Text("Próximamente")
                    } label: {
                        Label("Recordatorios", systemImage: "bell")
                    }
                    NavigationLink {
                        Text("Próximamente")
                    } label: {
                        Label("Ubicación", systemImage: "location")
                    }
                }
            }
            .navigationTitle("Perfil")
        }
    }
}

#Preview {
    RootTabView()
        .environment(EventoService())
        .tint(.plAccent)
}
