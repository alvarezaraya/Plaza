// MapView.swift
// Mapa interactivo MKMapView: marcadores por venue agrupados por ciudad, tarjeta emergente
// con info del evento y navegación a EventDetailView.

import SwiftUI
import MapKit
import CoreLocation

struct MapView: View {
    @Environment(EventoService.self) private var servicio
    @Environment(LocationManager.self) private var location
    @Environment(\.horizontalSizeClass) private var hSizeClass
    @State private var selectedVenue: String?
    @State private var venueGroups: [VenueGroup] = []
    @State private var camera: MapCameraPosition = .automatic

    // En iPad el sidebar cubre 387pt desde el borde izquierdo (12 padding + 375 frame).
    // Se añaden 16pt de margen mínimo para que el contenido no quede pegado al borde visible.
    private var sidebarInset: CGFloat { hSizeClass == .regular ? 403 : 0 }

    private var selectedEvents: [Event] {
        guard let venue = selectedVenue else { return [] }
        return venueGroups.first { $0.id == venue }?.events ?? []
    }

    var body: some View {
        Map(position: $camera, selection: $selectedVenue) {
            UserAnnotation()
            ForEach(venueGroups) { group in
                Marker(
                    group.name,
                    systemImage: group.events.count > 1 ? "\(min(group.events.count, 50)).circle.fill" : "music.note",
                    coordinate: group.coordinate
                )
                .tint(Color.plAccent)
                .tag(group.id)
            }
        }
        .mapStyle(.standard(elevation: .flat))
        .mapControls {
            MapCompass()
        }
        .ignoresSafeArea()
        .overlay(alignment: sidebarInset > 0 ? .topTrailing : .topLeading) {
            Button {
                if let coord = location.userLocation?.coordinate {
                    withAnimation {
                        camera = .region(MKCoordinateRegion(
                            center: coord,
                            span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)
                        ))
                    }
                }
            } label: {
                Image(systemName: "location.fill")
                    .font(.system(size: 18))
                    .frame(width: 44, height: 44)
                    .foregroundStyle(Color.plAccent)
            }
            .glassEffect(.clear.interactive(), in: .circle)
            .safeAreaPadding(.top)
            .padding(sidebarInset > 0 ? .trailing : .leading, 16)
            .padding(.top, 10)
        }
        .safeAreaInset(edge: .bottom) {
            if !selectedEvents.isEmpty {
                eventCards
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.smooth, value: selectedVenue)
        .onAppear {
            location.requestPermission()
            recomputeGroups()
        }
        .onChange(of: servicio.events) { recomputeGroups() }
        .onChange(of: location.userLocation) { recomputeGroups() }
    }

    private func recomputeGroups() {
        let allEvents = servicio.events
        var dict: [String: VenueGroup] = [:]
        for event in allEvents {
            let key = event.venue.lowercased()
            if dict[key] == nil {
                dict[key] = VenueGroup(
                    name: event.venue,
                    coordinate: event.coordinate,
                    events: []
                )
            }
            dict[key]?.events.append(event)
        }
        venueGroups = Array(dict.values).sorted { $0.name < $1.name }
        updateCameraToFitEvents()
    }

    private func updateCameraToFitEvents() {
        guard !venueGroups.isEmpty else { return }

        let userCoord = location.userLocation?.coordinate

        // Sort venues by distance to user (or keep as-is if no location)
        let sorted: [VenueGroup]
        if let origin = userCoord {
            let originLoc = CLLocation(latitude: origin.latitude, longitude: origin.longitude)
            sorted = venueGroups.sorted {
                CLLocation(latitude: $0.coordinate.latitude, longitude: $0.coordinate.longitude)
                    .distance(from: originLoc) <
                CLLocation(latitude: $1.coordinate.latitude, longitude: $1.coordinate.longitude)
                    .distance(from: originLoc)
            }
        } else {
            sorted = venueGroups
        }

        // Collect user + 2 nearest venues to compute bounding region
        var coords: [CLLocationCoordinate2D] = Array(sorted.prefix(2)).map { $0.coordinate }
        if let u = userCoord { coords.append(u) }
        guard !coords.isEmpty else { return }

        let lats = coords.map { $0.latitude }
        let lons = coords.map { $0.longitude }
        let minLat = lats.min()!, maxLat = lats.max()!
        let minLon = lons.min()!, maxLon = lons.max()!

        // pad = 0.08 ≈ 8.9 km por lado; garantiza ≥1 pulgada (132 pt) de margen
        // en un iPad Pro 12,9" (132 pt/inch) con venues hasta ~50 km de distancia.
        let pad = 0.08
        let center = CLLocationCoordinate2D(
            latitude: (minLat + maxLat) / 2,
            longitude: (minLon + maxLon) / 2
        )
        let span = MKCoordinateSpan(
            latitudeDelta: max(maxLat - minLat + pad * 2, 0.16),
            longitudeDelta: max(maxLon - minLon + pad * 2, 0.16)
        )
        camera = .region(MKCoordinateRegion(center: center, span: span))
    }

    private func selectVenue(for event: Event) {
        let venueID = event.venue.lowercased()
        withAnimation(.smooth) {
            selectedVenue = venueID
            camera = .region(.init(
                center: event.coordinate,
                span: .init(latitudeDelta: 0.02, longitudeDelta: 0.02)
            ))
        }
    }

    // MARK: - Tarjetas horizontales

    private var eventCards: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(selectedEvents) { event in
                    EventGlassCard(event: event)
                        .frame(width: 280)
                }
            }
            .padding(.leading, sidebarInset > 0 ? sidebarInset : 14)
            .padding(.trailing, 16)
        }
        .padding(.vertical, 10)
    }
}

// MARK: - Modelos auxiliares

struct VenueGroup: Identifiable, Hashable {
    var id: String { name.lowercased() }
    var name: String
    var coordinate: CLLocationCoordinate2D
    var events: [Event]

    static func == (lhs: VenueGroup, rhs: VenueGroup) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

// MARK: - Tarjeta glass

struct EventGlassCard: View {
    @Environment(EventoService.self) private var servicio
    @Environment(LocationManager.self) private var location
    let event: Event
    @State private var showAddedToast = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                PlTag(text: event.venue, color: .plAccent)
                Spacer()
                if let precio = event.price {
                    PlTag(text: precio)
                }
            }
            Text(event.title)
                .font(.plDisplay(20))
                .kerning(-0.6)
            if !event.subtitle.isEmpty {
                Text(event.subtitle)
                    .font(.plSerifItalic(14))
                    .foregroundStyle(Color.plMuted)
            }
            HStack(spacing: 8) {
                PlTag(text: event.dateText)
                if let dist = location.distanceText(event.coordinate) {
                    PlTag(text: dist, color: .plAccent)
                }
            }

            HStack(spacing: 8) {
                if let url = event.url {
                    Link(destination: url) {
                        Text("Ver evento")
                            .font(.plSans(14, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(Color.plFg, in: .capsule)
                            .foregroundStyle(Color.plBg)
                    }
                }
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
                    Image(systemName: servicio.isSaved(event) ? "calendar.badge.checkmark" : "calendar.badge.plus")
                        .font(.system(size: 16))
                        .frame(width: 40, height: 40)
                }
                .glassEffect(.clear.interactive(), in: .circle)
            }
        }
        .padding(14)
        .glassEffect(.clear, in: .rect(cornerRadius: PlSpace.cardRadius))
        .overlay(alignment: .top) {
            if showAddedToast {
                AddedToast()
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .padding(.top, -40)
            }
        }
        .animation(.smooth, value: showAddedToast)
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    MapView()
        .environment(EventoService())
        .environment(LocationManager())
}
