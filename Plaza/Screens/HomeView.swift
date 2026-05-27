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
    @State private var showSettings = false
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

    /// Pool para el carrusel: hasta 15 eventos con imagen, ya ordenados por fecha.
    /// Si hay menos de 3 con imagen, rellena con eventos sin imagen para garantizar
    /// que siempre haya tarjetas visibles.
    private var featuredEvents: [Event] {
        let withImages = filteredEvents.filter { $0.imageURL != nil }
        if withImages.count >= 3 { return Array(withImages.prefix(15)) }
        return Array(filteredEvents.prefix(max(3, withImages.count)))
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
                .refreshable { servicio.cargarEventos() }
                .sheet(isPresented: $showSettings) { SettingsView() }
                .sheet(isPresented: $showComunaPicker) { ComunaPickerView() }
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
        .background(isIPadSidebar ? .clear : Color.plBg)
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
                    .plainRow(background: isIPadSidebar ? .clear : .plBg)
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
                .plainRow(background: isIPadSidebar ? .clear : .plBg)
            } else {
                if filteredEvents.isEmpty {
                    ContentUnavailableView(
                        "Sin eventos",
                        systemImage: "calendar.badge.exclamationmark",
                        description: Text("No hay eventos en esta categoría")
                    )
                    .padding(.top, 120)
                    .plainRow(background: isIPadSidebar ? .clear : .plBg)
                } else {
                    EventImageStack(events: featuredEvents) { event in
                        navPath.append(event)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 28)
                    .plainRow(background: isIPadSidebar ? .clear : .plBg)

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
                        .listRowBackground(isIPadSidebar ? Color.clear : Color.plBg)
                    }
                }
            }
        }
    }

    // MARK: - Header (sticky, Liquid Glass)

    private static let distanceOptions: [(String, Double)] = [
        ("Sin límite", 0), ("100 km", 100), ("200 km", 200), ("300 km", 300),
    ]

    private static let mainCities = [
        "Santiago", "Valparaíso", "Viña del Mar",
        "Concepción", "Temuco", "Antofagasta",
        "La Serena", "Iquique", "Arica",
        "Puerto Montt", "Calama", "Copiapó",
    ]

    private var headerBlock: some View {
        HStack(spacing: 10) {
            // Píldora: muestra comuna + radio. Al tocar abre menú con ambas secciones.
            Menu {
                Menu {
                    Button {
                        comunaManager.resetearAAutoDeteccion()
                    } label: {
                        Label("Detectar automáticamente", systemImage: "location.circle")
                    }
                    Button {
                        comunaManager.seleccionar("Chile")
                    } label: {
                        if comunaManager.selectedComuna == "Chile" {
                            Label("Todo Chile", systemImage: "checkmark")
                        } else {
                            Label("Todo Chile", systemImage: "flag.fill")
                        }
                    }
                    Divider()
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
                    Divider()
                    Button {
                        showComunaPicker = true
                    } label: {
                        Label("Más comunas…", systemImage: "list.bullet")
                    }
                } label: {
                    Label("Ubicación · \(comunaManager.selectedComuna)", systemImage: "location.fill")
                }

                Menu {
                    Picker("Radio", selection: $maxDistanceKm) {
                        ForEach(Self.distanceOptions, id: \.1) { label, km in
                            Text(label).tag(km)
                        }
                    }
                } label: {
                    Label("Radio · \(maxDistanceKm == 0 ? "Sin límite" : "\(Int(maxDistanceKm)) km")", systemImage: "circle.dashed")
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
            .glassEffect(.clear.interactive(), in: .capsule)
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
                Image(systemName: "line.3.horizontal.decrease")
                    .font(.system(size: 22))
                    .frame(width: 50, height: 50)
                    .foregroundStyle(selectedCategory != nil ? Color.plAccent : Color.plFg)
            }
            .glassEffect(.clear.interactive(), in: .circle)
            .accessibilityLabel("Filtrar por categoría\(selectedCategory != nil ? " (activo)" : "")")

            // Botón de ajustes
            Button {
                showSettings = true
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 22))
                    .frame(width: 50, height: 50)
                    .foregroundStyle(Color.plFg)
            }
            .glassEffect(.clear.interactive(), in: .circle)
            .accessibilityLabel("Ajustes")
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
    func plainRow(background: Color = .plBg) -> some View {
        self
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets())
            .listRowBackground(background)
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
                if !event.otherDates.isEmpty {
                    PlTag(text: "+\(event.otherDates.count) fechas", color: .plAccent)
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

    @State private var frontIndex = 0
    @State private var dragOffsets: [Int: CGSize] = [:]

    private var count: Int { events.count }

    // Configuración visual por slot (0=frente, 1=atrás-izq, 2=atrás-der)
    private struct SlotCfg {
        let baseX: CGFloat, baseY: CGFloat
        let rot: Double, scale: CGFloat
        let freq: Double, phase: Double, amp: Double
        let zIndex: Double
    }

    private let slotCfgs: [SlotCfg] = [
        SlotCfg(baseX: 0,   baseY: 0,  rot: 0,  scale: 1.00, freq: 1.38, phase: 0,          amp: 8, zIndex: 2),
        SlotCfg(baseX: -52, baseY: 10, rot: -9, scale: 0.91, freq: 1.10, phase: .pi * 0.85, amp: 6, zIndex: 1),
        SlotCfg(baseX: 52,  baseY: 10, rot: 9,  scale: 0.91, freq: 1.25, phase: .pi * 0.35, amp: 6, zIndex: 1),
    ]

    // Color fijo por índice de evento: independiente del slot/posición
    // Propiedad computada (no `let`) para que se re-evalúe al cambiar de tema.
    private static var cardColors: [Color] { [.plCardCenter, .plCardLeft, .plCardRight] }
    private func colorFor(_ ei: Int) -> Color { Self.cardColors[ei % 3] }

    // Índices de los 3 eventos activos, en orden [frente, izq, der]
    private var activeIndices: [Int] {
        guard count > 0 else { return [] }
        var r = [frontIndex]
        if count > 1 { r.append((frontIndex - 1 + count) % count) }
        if count > 2 { r.append((frontIndex + 1) % count) }
        return r
    }

    // Slot actual de un eventIndex dado el frontIndex en ese momento
    private func slotOf(_ ei: Int) -> Int {
        if ei == frontIndex { return 0 }
        if count > 1 && ei == (frontIndex - 1 + count) % count { return 1 }
        return 2
    }

    var body: some View {
        TimelineView(.animation) { tl in
            let t = tl.date.timeIntervalSinceReferenceDate
            ZStack {
                // ForEach con ID = eventIndex: SwiftUI rastrea la misma tarjeta
                // al moverse entre slots e interpola todos sus modificadores.
                ForEach(activeIndices, id: \.self) { ei in
                    let slot = slotOf(ei)
                    let cfg  = slotCfgs[slot]
                    let drag = dragOffsets[ei, default: .zero]
                    let damp = max(0.0, 1.0 - Double(drag.width * drag.width + drag.height * drag.height).squareRoot() / 130)

                    PlaybillCard(event: events[ei], cardColor: colorFor(ei)) {
                        onSelect(events[ei])
                    }
                    .frame(width: 200, height: 300)
                    .scaleEffect(cfg.scale)
                    .rotationEffect(.degrees(cfg.rot + Double(drag.width) / 18))
                    .offset(
                        x: cfg.baseX + drag.width,
                        y: cfg.baseY + drag.height + sin(t * cfg.freq + cfg.phase) * cfg.amp * damp
                    )
                    .zIndex(cfg.zIndex)
                    .highPriorityGesture(
                        DragGesture(minimumDistance: 8)
                            .onChanged { dragOffsets[ei] = $0.translation }
                            .onEnded { value in
                                let dx = value.translation.width
                                let vx = value.predictedEndTranslation.width
                                if slot == 0 && (dx < -70 || vx < -210) {
                                    rotate(to: (frontIndex + 1) % count, fling: -1, key: ei)
                                } else if slot == 0 && (dx > 70 || vx > 210) {
                                    rotate(to: (frontIndex - 1 + count) % count, fling: +1, key: ei)
                                } else {
                                    withAnimation(.spring(response: 0.55, dampingFraction: 0.58)) {
                                        dragOffsets[ei] = .zero
                                    }
                                }
                            }
                    )
                }
            }
        }
        .frame(height: 350)
        .task(id: events.map(\.stableID).joined()) { prefetchImages() }
    }

    private func prefetchImages() {
        for event in events {
            guard let url = event.imageURL,
                  ImageCache.shared[url] == nil else { continue }
            Task.detached(priority: .utility) {
                guard let (data, _) = try? await URLSession.shared.data(from: url),
                      let img = UIImage(data: data) else { return }
                ImageCache.shared[url] = img
            }
        }
    }

    // Lanza primero la tarjeta en la dirección del swipe y luego rota el carrusel.
    // Garantiza que la animación sea visible incluso en gestos cortos o rápidos.
    private func rotate(to newFront: Int, fling: CGFloat, key: Int) {
        withAnimation(.easeIn(duration: 0.14)) {
            dragOffsets[key] = CGSize(width: fling * 280, height: 14)
        }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(110))
            withAnimation(.spring(response: 0.52, dampingFraction: 0.72)) {
                frontIndex = newFront
                dragOffsets = [:]
            }
        }
    }
}

// MARK: - Playbill Card

struct PlaybillCard: View {
    let event: Event
    let cardColor: Color
    let onTap: () -> Void
    @State private var loadedImage: UIImage?

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

                // Marco interior inset decorativo
                RoundedRectangle(cornerRadius: 11)
                    .strokeBorder(ink.opacity(0.28), lineWidth: 0.75)
                    .padding(5)
            }
        }
        .buttonStyle(.plain)
        .shadow(color: .black.opacity(0.22), radius: 10, x: 0, y: 5)
        .shadow(color: .black.opacity(0.12), radius: 24, x: 0, y: 14)
        .task(id: event.stableID) { await loadImage() }
    }

    private func loadImage() async {
        guard let url = event.imageURL else { return }
        if let cached = ImageCache.shared[url] { loadedImage = cached; return }
        guard let (data, _) = try? await URLSession.shared.data(from: url),
              let img = UIImage(data: data) else { return }
        ImageCache.shared[url] = img
        loadedImage = img
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
        Group {
            if let img = loadedImage {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
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
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .padding(.top, 6)
        .padding(.horizontal, 8)
        .padding(.bottom, 8)
        .background(cardColor)
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
            .background(isSelected ? Color.plAccent : Color.plSurface, in: .capsule)
            .foregroundStyle(isSelected ? Color.white : Color.plMuted)
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
                    Button {
                        comunaManager.seleccionar("Chile")
                        dismiss()
                    } label: {
                        Label("Todo Chile", systemImage: "flag.fill")
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

// MARK: - Image Cache

/// Thread-safe NSCache wrapper. Shared between EventImageStack (prefetch) and PlaybillCard (display).
final class ImageCache: @unchecked Sendable {
    static let shared = ImageCache()
    private init() { cache.countLimit = 60 }
    private let cache = NSCache<NSString, UIImage>()

    subscript(url: URL) -> UIImage? {
        get { cache.object(forKey: url.absoluteString as NSString) }
        set {
            if let img = newValue {
                cache.setObject(img, forKey: url.absoluteString as NSString)
            }
        }
    }
}

#Preview {
    HomeView()
        .environment(EventoService())
        .environment(LocationManager())
        .tint(.plAccent)
}
