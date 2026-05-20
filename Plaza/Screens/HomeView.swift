// HomeView.swift
// Feed principal de eventos con filtro por categoría, tarjeta destacada y acciones de guardado.

import SwiftUI

struct HomeView: View {
    @Environment(EventoService.self) private var servicio
    @Environment(LocationManager.self) private var location
    @Environment(ComunaManager.self) private var comunaManager
    @Environment(ReminderManager.self) private var reminders
    @Environment(\.openURL) private var openURL
    @State private var selectedCategory: Event.Category?
    @State private var showAddedToast = false
    @State private var showProfile = false
    @State private var showComunaPicker = false
    @State private var navPath = NavigationPath()
    @AppStorage("plaza_max_distance_km") private var maxDistanceKm: Double = 0

    private var events: [Event] { servicio.events }

    private var filteredEvents: [Event] {
        var result = events
            .byComune(comunaManager.selectedComuna)
            .byMaxDistance(maxDistanceKm, from: location.userLocation)
        if let cat = selectedCategory {
            result = result.filter { $0.category == cat }
        }
        return result
    }

    var body: some View {
        NavigationStack(path: $navPath) {
            listContent
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .background(Color.plBg)
                .toolbar(.hidden, for: .navigationBar)
                .toolbarBackground(.hidden, for: .tabBar)
                .navigationDestination(for: Event.self) { EventDetailView(event: $0) }
                .sheet(isPresented: $showProfile) { ProfileView() }
                .sheet(isPresented: $showComunaPicker) { ComunaPickerView() }
                .refreshable { servicio.cargarEventos() }
                .overlay(alignment: .top) {
                    if showAddedToast {
                        AddedToast()
                            .transition(.move(edge: .top).combined(with: .opacity))
                            .padding(.top, 60)
                    }
                }
                .animation(.smooth, value: showAddedToast)
                .safeAreaInset(edge: .top, spacing: 0) { headerBlock }
        }
        .onAppear {
            if events.isEmpty { servicio.cargarEventos() }
            location.requestPermission()
            if let loc = location.userLocation {
                comunaManager.autoDetectar(desde: loc)
            }
        }
        .onChange(of: location.userLocation) { _, newLoc in
            if let loc = newLoc { comunaManager.autoDetectar(desde: loc) }
        }
    }

    private var listContent: some View {
        List {
            if servicio.cargando {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(.top, 120)
                    .plainRow()
            } else if let error = servicio.error {
                ContentUnavailableView {
                    Label("Sin conexión", systemImage: "wifi.slash")
                } description: {
                    Text(error)
                } actions: {
                    Button("Reintentar") { servicio.cargarEventos() }
                        .buttonStyle(.borderedProminent)
                        .tint(Color.plAccent)
                }
                .padding(.top, 120)
                .plainRow()
            } else {
                if filteredEvents.isEmpty {
                    ContentUnavailableView(
                        "Sin eventos",
                        systemImage: "calendar.badge.exclamationmark",
                        description: Text("No hay eventos en esta categoría")
                    )
                    .padding(.top, 120)
                    .plainRow()
                } else {
                    EventImageStack(events: Array(filteredEvents.prefix(3))) { event in
                        navPath.append(event)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 28)
                    .plainRow()

                    ForEach(filteredEvents) { event in
                        NavigationLink(value: event) {
                            EventRowContent(event: event)
                        }
                        .contextMenu { eventContextMenu(for: event) }
                        .swipeActions(edge: .leading) {
                            Button {
                                let added = servicio.toggleSaved(event)
                                if added {
                                    showAddedToast = true
                                    Task {
                                        try? await Task.sleep(for: .seconds(1.5))
                                        showAddedToast = false
                                    }
                                }
                            } label: {
                                Label(
                                    servicio.isSaved(event) ? "Quitar" : "Agenda",
                                    systemImage: servicio.isSaved(event) ? "calendar.badge.minus" : "calendar.badge.plus"
                                )
                            }
                            .tint(servicio.isSaved(event) ? .red : .green)
                        }
                        .listRowInsets(EdgeInsets(top: 0, leading: PlSpace.gutter, bottom: 0, trailing: PlSpace.gutter))
                        .listRowBackground(Color.plBg)
                    }
                }
            }
        }
    }

    // MARK: - Header (sticky, Liquid Glass)

    private static let distanceOptions: [(String, Double)] = [
        ("Sin límite", 0), ("100 km", 100), ("200 km", 200), ("300 km", 300),
    ]

    private static let mainCities = ["Arica", "Iquique", "Antofagasta", "Calama", "Copiapó"]

    private var headerBlock: some View {
        HStack(spacing: 10) {
            // Píldora: muestra comuna + radio. Al tocar abre menú con ambas secciones.
            Menu {
                Section("Ubicación") {
                    Button {
                        comunaManager.resetearAAutoDeteccion()
                    } label: {
                        Label("Detectar automáticamente", systemImage: "location.circle")
                    }
                    ForEach(Self.mainCities, id: \.self) { city in
                        Button {
                            comunaManager.seleccionar(city)
                        } label: {
                            if comunaManager.selectedComuna == city {
                                Label(city, systemImage: "checkmark")
                            } else {
                                Text(city)
                            }
                        }
                    }
                    Button {
                        showComunaPicker = true
                    } label: {
                        Label("Más comunas…", systemImage: "list.bullet")
                    }
                }
                Section("Radio") {
                    Picker("Distancia", selection: $maxDistanceKm) {
                        ForEach(Self.distanceOptions, id: \.1) { label, km in
                            Text(label).tag(km)
                        }
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: comunaManager.isDetecting ? "location.slash" : "location.fill")
                        .font(.system(size: 13))
                    Text(comunaManager.selectedComuna)
                        .font(.plSans(15, weight: .semibold))
                    if maxDistanceKm > 0 {
                        Text("·")
                            .font(.plSans(13))
                            .foregroundStyle(Color.plMuted)
                        Text("\(Int(maxDistanceKm)) km")
                            .font(.plSans(13, weight: .medium))
                            .foregroundStyle(Color.plAccent)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .foregroundStyle(Color.plFg)
            }
            .glassEffect(.clear, in: .capsule)
            .accessibilityLabel("Ubicación: \(comunaManager.selectedComuna)\(maxDistanceKm > 0 ? ", radio \(Int(maxDistanceKm)) km" : ""). Toca para cambiar.")

            Spacer()

            // Menú desplegable de categorías
            Menu {
                Picker("Categoría", selection: $selectedCategory) {
                    Text("Todos").tag(Optional<Event.Category>.none)
                    ForEach(Event.Category.allCases, id: \.self) { cat in
                        Label(cat.rawValue, systemImage: cat.icon)
                            .tag(Optional(cat))
                    }
                }
            } label: {
                Image(systemName: selectedCategory != nil
                      ? "line.3.horizontal.decrease.circle.fill"
                      : "line.3.horizontal.decrease.circle")
                    .font(.system(size: 22))
                    .frame(width: 50, height: 50)
                    .foregroundStyle(selectedCategory != nil ? Color.plAccent : Color.plFg)
            }
            .glassEffect(.clear.interactive(), in: .circle)
            .accessibilityLabel("Filtrar por categoría\(selectedCategory != nil ? " (activo)" : "")")

            // Botón de perfil
            Button {
                showProfile = true
            } label: {
                Image(systemName: "person.crop.circle")
                    .font(.system(size: 22))
                    .frame(width: 50, height: 50)
                    .foregroundStyle(Color.plFg)
            }
            .glassEffect(.clear.interactive(), in: .circle)
            .accessibilityLabel("Perfil")
        }
        .padding(.horizontal, PlSpace.gutter)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private func eventContextMenu(for event: Event) -> some View {
        if let url = event.url {
            Button { openURL(url) } label: {
                Label("Ver evento", systemImage: "arrow.up.right")
            }
        }
        Button {
            servicio.toggleSaved(event)
        } label: {
            Label(
                servicio.isSaved(event) ? "Quitar de agenda" : "Agregar a agenda",
                systemImage: servicio.isSaved(event) ? "calendar.badge.minus" : "calendar.badge.plus"
            )
        }
        Button {
            Task { await reminders.toggleReminder(for: event) }
        } label: {
            Label(
                reminders.hasReminder(for: event) ? "Quitar recordatorio" : "Recordarme",
                systemImage: reminders.hasReminder(for: event) ? "bell.slash" : "bell"
            )
        }
        if let url = event.url {
            ShareLink(item: url) {
                Label("Compartir", systemImage: "square.and.arrow.up")
            }
        }
    }
}

// MARK: - List row modifier

extension View {
    func plainRow() -> some View {
        self
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.plBg)
    }
}

// MARK: - Event Row

struct EventRowContent: View {
    @Environment(LocationManager.self) private var location
    let event: Event

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: event.category.icon)
                .font(.system(size: 22))
                .foregroundStyle(Color.plAccent)
                .frame(width: 54, height: 54)
                .background(Color.plSurface, in: .rect(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 4) {
                Text(event.title)
                    .font(.plSans(17, weight: .medium))
                    .foregroundStyle(Color.plFg)
                    .lineLimit(2)
                if !event.subtitle.isEmpty {
                    Text(event.subtitle)
                        .font(.plSerifItalic(14))
                        .foregroundStyle(Color.plMuted)
                        .lineLimit(1)
                }
                HStack(spacing: 8) {
                    PlTag(text: event.dateText)
                    PlTag(text: event.venue)
                    if let dist = location.distanceText(event.coordinate) {
                        PlTag(text: dist, color: .plAccent)
                    }
                }
                .padding(.top, 2)
                HStack(spacing: 8) {
                    PlTag(text: event.price ?? "gratis")
                    if !event.otherDates.isEmpty {
                        PlTag(text: "+\(event.otherDates.count) fechas", color: .plAccent)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 14)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Event Image Stack

struct EventImageStack: View {
    let events: [Event]
    let onSelect: (Event) -> Void

    var body: some View {
        ZStack {
            if events.count > 1 {
                card(events[1])
                    .frame(width: 168, height: 196)
                    .rotationEffect(.degrees(-13))
                    .offset(x: -60, y: 12)
            }
            if events.count > 2 {
                card(events[2])
                    .frame(width: 168, height: 196)
                    .rotationEffect(.degrees(13))
                    .offset(x: 60, y: 12)
            }
            if let first = events.first {
                card(first)
                    .frame(width: 196, height: 228)
            }
        }
        .frame(height: 264)
    }

    private func card(_ event: Event) -> some View {
        Button { onSelect(event) } label: {
            AsyncImage(url: event.imageURL) { phase in
                if let img = phase.image {
                    img.resizable().scaledToFill()
                } else {
                    Rectangle().fill(Color.plSurface)
                        .overlay {
                            Image(systemName: event.category.icon)
                                .font(.system(size: 32))
                                .foregroundStyle(Color.plMuted)
                        }
                }
            }
            .clipShape(.rect(cornerRadius: 22))
        }
        .buttonStyle(.plain)
        .shadow(color: .black.opacity(0.22), radius: 12, x: 0, y: 6)
    }
}

// MARK: - Category Chip

struct CategoryChip: View {
    let label: String
    let icon: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon).font(.system(size: 12))
                Text(label).font(.plSans(13, weight: .medium))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(isSelected ? Color.plFg : Color.plSurface, in: .capsule)
            .foregroundStyle(isSelected ? Color.plBg : Color.plMuted)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - Comuna Picker

struct ComunaPickerView: View {
    @Environment(ComunaManager.self) private var comunaManager
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        comunaManager.resetearAAutoDeteccion()
                        dismiss()
                    } label: {
                        Label("Detectar automáticamente", systemImage: "location.circle")
                            .foregroundStyle(Color.plAccent)
                    }
                }

                ForEach(ComunaManager.regiones) { region in
                    Section(region.id) {
                        ForEach(region.comunas, id: \.self) { comuna in
                            Button {
                                comunaManager.seleccionar(comuna)
                                dismiss()
                            } label: {
                                HStack {
                                    Text(comuna)
                                        .foregroundStyle(Color.plFg)
                                    Spacer()
                                    if comunaManager.selectedComuna == comuna {
                                        Image(systemName: "checkmark")
                                            .foregroundStyle(Color.plAccent)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Ubicación")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Listo") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Filter Sheet

struct FilterSheetView: View {
    @Binding var selectedCategory: Event.Category?
    @Binding var maxDistanceKm: Double
    @Environment(\.dismiss) private var dismiss

    private static let distanceOptions: [(String, Double)] = [
        ("Sin límite", 0), ("100 km", 100), ("200 km", 200), ("300 km", 300),
    ]

    private var hasFilters: Bool { selectedCategory != nil || maxDistanceKm > 0 }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 28) {
                filterSection("Categoría") {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            CategoryChip(label: "Todos", icon: "square.grid.2x2", isSelected: selectedCategory == nil) {
                                withAnimation { selectedCategory = nil }
                            }
                            ForEach(Event.Category.allCases, id: \.self) { cat in
                                CategoryChip(label: cat.rawValue, icon: cat.icon, isSelected: selectedCategory == cat) {
                                    withAnimation { selectedCategory = cat }
                                }
                            }
                        }
                        .padding(.horizontal, PlSpace.gutter)
                        .padding(.vertical, 4)
                    }
                }

                filterSection("Distancia máxima") {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(Self.distanceOptions, id: \.1) { label, km in
                                CategoryChip(
                                    label: label,
                                    icon: km == 0 ? "xmark.circle" : "location",
                                    isSelected: maxDistanceKm == km
                                ) {
                                    withAnimation { maxDistanceKm = km }
                                }
                            }
                        }
                        .padding(.horizontal, PlSpace.gutter)
                        .padding(.vertical, 4)
                    }
                }

                Spacer()
            }
            .padding(.top, 20)
            .background(Color.plBg)
            .navigationTitle("Filtros")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Listo") { dismiss() }
                }
                if hasFilters {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Limpiar") {
                            withAnimation { selectedCategory = nil; maxDistanceKm = 0 }
                        }
                        .foregroundStyle(Color.plAccent)
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }

    private func filterSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.plSans(13, weight: .semibold))
                .foregroundStyle(Color.plMuted)
                .padding(.horizontal, PlSpace.gutter)
            content()
        }
    }
}

#Preview {
    HomeView()
        .environment(EventoService())
        .environment(LocationManager())
        .tint(.plAccent)
}
