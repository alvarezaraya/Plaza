// HomeView.swift
// Feed principal de eventos con filtro por categoría, tarjeta destacada y acciones de guardado.

import SwiftUI

struct HomeView: View {
    @Environment(EventoService.self) private var servicio
    @Environment(LocationManager.self) private var location
    @Environment(ComunaManager.self) private var comunaManager
    @Environment(ReminderManager.self) private var reminders
    @Environment(\.openURL) private var openURL
    @Environment(\.isIPadSidebar) private var isIPadSidebar
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
                .background(isIPadSidebar ? Color.clear : Color.plBg)
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
                        .listRowBackground(isIPadSidebar ? Color.plSurface.opacity(0.4) : Color.plBg)
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

// MARK: - Event Image Stack (Playbill, physics swipe, float)

struct EventImageStack: View {
    let events: [Event]
    let onSelect: (Event) -> Void

    @State private var frontIndex: Int = 0
    @State private var dragOffset: CGFloat = 0

    private var count: Int { events.count }

    private func idx(_ offset: Int) -> Int {
        guard count > 0 else { return 0 }
        return ((frontIndex + offset) % count + count) % count
    }

    private var leftLerp: CGFloat  { max(0, min(1, dragOffset / 120)) }
    private var rightLerp: CGFloat { max(0, min(1, -dragOffset / 120)) }

    // La flotación se amortigua cuando el usuario arrastra
    private var floatDamp: Double { max(0, 1 - abs(Double(dragOffset)) / 140) }

    var body: some View {
        // TimelineView proporciona tiempo continuo para la animación de seno nativa
        TimelineView(.animation) { tl in
            let t = tl.date.timeIntervalSinceReferenceDate
            cardStack(t: t)
        }
        .frame(height: 278)
    }

    @ViewBuilder
    private func cardStack(t: Double) -> some View {
        ZStack {
            // Tarjeta izquierda — roja
            if count > 1 {
                PlaybillCard(event: events[idx(-1)], cardColor: .plCardLeft) {
                    withAnimation(.spring(response: 0.38, dampingFraction: 0.72)) {
                        frontIndex = idx(-1); dragOffset = 0
                    }
                }
                .frame(width: 182, height: 214)
                .rotationEffect(.degrees(-9 * (1 - leftLerp)))
                .offset(
                    x: -52 + 52 * leftLerp,
                    y: 10 * (1 - leftLerp) + sin(t * 1.1 + .pi * 0.85) * 6 * floatDamp
                )
                .scaleEffect(0.91 + 0.09 * leftLerp)
                .zIndex(leftLerp > 0.6 ? 3 : 1)
            }

            // Tarjeta derecha — amarilla
            if count > 2 {
                PlaybillCard(event: events[idx(1)], cardColor: .plCardRight) {
                    withAnimation(.spring(response: 0.38, dampingFraction: 0.72)) {
                        frontIndex = idx(1); dragOffset = 0
                    }
                }
                .frame(width: 182, height: 214)
                .rotationEffect(.degrees(9 * (1 - rightLerp)))
                .offset(
                    x: 52 - 52 * rightLerp,
                    y: 10 * (1 - rightLerp) + sin(t * 1.25 + .pi * 0.35) * 6 * floatDamp
                )
                .scaleEffect(0.91 + 0.09 * rightLerp)
                .zIndex(rightLerp > 0.6 ? 3 : 1)
            }

            // Tarjeta central — cyan, arrastrable
            if count > 0 {
                PlaybillCard(event: events[idx(0)], cardColor: .plCardCenter) {
                    onSelect(events[frontIndex])
                }
                .frame(width: 200, height: 234)
                .rotationEffect(.degrees(dragOffset / 22))
                .offset(
                    x: dragOffset,
                    y: abs(dragOffset) * 0.04 + sin(t * 1.38) * 8 * floatDamp
                )
                .zIndex(leftLerp > 0.7 || rightLerp > 0.7 ? 0 : 2)
                .gesture(
                    DragGesture(minimumDistance: 10)
                        .onChanged { dragOffset = $0.translation.width }
                        .onEnded { value in
                            let v = value.predictedEndTranslation.width
                            if dragOffset < -70 || v < -220 {
                                withAnimation(.spring(response: 0.4, dampingFraction: 0.72)) {
                                    frontIndex = idx(1); dragOffset = 0
                                }
                            } else if dragOffset > 70 || v > 220 {
                                withAnimation(.spring(response: 0.4, dampingFraction: 0.72)) {
                                    frontIndex = idx(-1); dragOffset = 0
                                }
                            } else {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.62)) {
                                    dragOffset = 0
                                }
                            }
                        }
                )
            }
        }
    }
}

// MARK: - Playbill Card

struct PlaybillCard: View {
    let event: Event
    let cardColor: Color
    let onTap: () -> Void

    private var timeLabel: String {
        let cal = Calendar.current
        let now = Date()
        guard event.date >= now else { return "PRÓXIMAMENTE" }
        if cal.isDateInToday(event.date) { return "HOY" }
        let days = cal.dateComponents([.day], from: now, to: event.date).day ?? 999
        return days <= 7 ? "ESTA SEMANA" : "PRÓXIMAMENTE"
    }

    private let ink = Color(hex: 0x100800, alpha: 1)

    var body: some View {
        Button(action: onTap) {
            ZStack {
                // Fondo sólido
                RoundedRectangle(cornerRadius: 14)
                    .fill(cardColor)

                // Contenido recortado al borde de la tarjeta
                VStack(spacing: 0) {
                    headerBanner
                    imageArea
                }
                .clipShape(RoundedRectangle(cornerRadius: 14))

                // Borde exterior delgado (todo el contorno)
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(ink.opacity(0.55), lineWidth: 1)

                // Marco interior inset decorativo
                RoundedRectangle(cornerRadius: 11)
                    .strokeBorder(ink.opacity(0.28), lineWidth: 0.75)
                    .padding(5)
            }
        }
        .buttonStyle(.plain)
        .shadow(color: .black.opacity(0.22), radius: 10, x: 0, y: 5)
        .shadow(color: .black.opacity(0.12), radius: 24, x: 0, y: 14)
    }

    private var headerBanner: some View {
        VStack(spacing: 0) {
            Spacer().frame(height: 9)
            ruleLine
            VStack(spacing: 2) {
                ornamentRow
                Text(timeLabel)
                    .font(.plPlaybill(16))
                    .foregroundStyle(ink)
                    .fixedSize()
                ornamentRow
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 10)
            ruleLine
            Spacer().frame(height: 7)
        }
        .background(cardColor)
    }

    private var ruleLine: some View {
        Rectangle()
            .fill(ink.opacity(0.6))
            .frame(height: 1)
            .padding(.horizontal, 9)
    }

    private var ornamentRow: some View {
        HStack(spacing: 0) {
            Rectangle().fill(ink.opacity(0.25)).frame(height: 0.6)
            Text("  ✦  ")
                .font(.system(size: 6))
                .foregroundStyle(ink.opacity(0.3))
            Rectangle().fill(ink.opacity(0.25)).frame(height: 0.6)
        }
        .padding(.horizontal, 14)
    }

    private var imageArea: some View {
        AsyncImage(url: event.imageURL) { phase in
            if let img = phase.image {
                img.resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
            } else {
                Rectangle()
                    .fill(cardColor.opacity(0.65))
                    .overlay {
                        Image(systemName: event.category.icon)
                            .font(.system(size: 26))
                            .foregroundStyle(ink.opacity(0.4))
                    }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
