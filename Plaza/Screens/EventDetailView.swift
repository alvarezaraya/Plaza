// EventDetailView.swift
// Pantalla de detalle de un evento: imagen, fechas, info del venue, resumen IA, y acciones de agenda y recordatorio.

import SwiftUI
import UIKit
import MapKit

struct EventDetailView: View {
    let event: Event
    @Environment(EventoService.self) private var servicio
    @Environment(LocationManager.self) private var location
    @Environment(ReminderManager.self) private var reminders
    @State private var appleMusicURL: URL?
    @State private var showingFullImage = false
    @State private var aiSummary: EventSummary?
    @State private var showToast = false
    @State private var toastLabel = ""
    @State private var toastIcon = ""
    @State private var mapCamera: MapCameraPosition = .automatic
    @State private var selectedDateIndex = 0

    private var allDates: [(dateText: String, venue: String, ciudad: String)] {
        [(event.dateText, event.venue, event.ciudad)] +
        event.otherDates.map { ($0.dateText, $0.venue, $0.ciudad) }
    }

    private var currentDate: (dateText: String, venue: String, ciudad: String) {
        allDates[min(selectedDateIndex, allDates.count - 1)]
    }

    private var liveCoordinate: CLLocationCoordinate2D {
        servicio.events.first { $0.stableID == event.stableID }?.coordinate ?? event.coordinate
    }

    private func updateMapCamera() {
        let coord = liveCoordinate
        guard coord.latitude != 0 || coord.longitude != 0 else { return }
        mapCamera = .region(MKCoordinateRegion(
            center: coord,
            latitudinalMeters: 600,
            longitudinalMeters: 600
        ))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                AsyncImage(url: event.imageURL) { phase in
                    if let img = phase.image {
                        img.resizable().scaledToFill()
                            .onTapGesture { showingFullImage = true }
                    } else {
                        Rectangle().fill(Color.plSurface)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 320)
                .clipped()

                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        if let fuente = event.fuente {
                            PlTag(text: fuente, color: .plAccent)
                        }
                        Spacer()
                        PlTag(text: event.ciudad)
                    }
                    .padding(.top, 18)

                    Text(event.title)
                        .font(.plDisplay(38))
                        .kerning(-1.2)

                    if !event.subtitle.isEmpty {
                        Text(event.subtitle)
                            .font(.plSerifItalic(22))
                            .foregroundStyle(Color.plMuted)
                    }

                    Divider()

                    HStack(alignment: .center) {
                        dateRow(dateText: currentDate.dateText, venue: currentDate.venue, ciudad: currentDate.ciudad)
                        if allDates.count > 1 {
                            Spacer()
                            Menu {
                                Picker("Fecha", selection: $selectedDateIndex) {
                                    ForEach(allDates.indices, id: \.self) { i in
                                        Text("\(allDates[i].dateText) · \(allDates[i].venue)")
                                            .tag(i)
                                    }
                                }
                            } label: {
                                HStack(spacing: 4) {
                                    Text("\(allDates.count) fechas")
                                    Image(systemName: "chevron.up.chevron.down")
                                        .font(.system(size: 10))
                                }
                                .font(.plSans(13, weight: .medium))
                                .foregroundStyle(Color.plAccent)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(Color.plAccent.opacity(0.1), in: .capsule)
                            }
                        }
                    }

                    Divider()

                    Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 12) {
                        GridRow {
                            infoCell("Venue", event.venue)
                            infoCell("Ciudad", event.ciudad)
                        }
                        GridRow {
                            infoCell("Precio", event.price ?? "Gratuito")
                            infoCell("Fechas", { let n = 1 + event.otherDates.count; return "\(n) disponible\(n == 1 ? "" : "s")" }())
                        }
                        if let dist = location.distanceText(event.coordinate) {
                            GridRow {
                                infoCell("Distancia", dist)
                                Spacer()
                            }
                        }
                    }

                    Divider()

                    Text(event.blurb)
                        .font(.plSans(16))
                        .foregroundStyle(Color.plFg)
                        .lineSpacing(4)

                    if let summary = aiSummary {
                        Divider()
                        PlTag(text: "Sobre el artista")
                        Text(summary.bio)
                            .font(.plSerifItalic(15))
                            .foregroundStyle(Color.plMuted)
                            .lineSpacing(3)
                            .padding(.top, 4)

                        PlTag(text: "Qué esperar")
                        Text(summary.preview)
                            .font(.plSerifItalic(15))
                            .foregroundStyle(Color.plMuted)
                            .lineSpacing(3)
                            .padding(.top, 4)
                    } else if let bio = event.bioArtista, !bio.isEmpty {
                        Divider()
                        PlTag(text: "Sobre el artista")
                        Text(bio)
                            .font(.plSerifItalic(15))
                            .foregroundStyle(Color.plMuted)
                            .lineSpacing(3)
                            .padding(.top, 4)
                    }
                }
                .padding(.horizontal, PlSpace.gutter)

                // Mapa
                if liveCoordinate.latitude != 0 || liveCoordinate.longitude != 0 {
                    Divider()
                    Map(position: $mapCamera, interactionModes: []) {
                        Marker(event.venue, coordinate: liveCoordinate)
                            .tint(Color.plAccent)
                    }
                    .aspectRatio(1, contentMode: .fit)
                    .frame(maxWidth: .infinity)
                    .clipShape(.rect(cornerRadius: PlSpace.cardRadius))
                    .padding(.horizontal, PlSpace.gutter)
                    .padding(.bottom, PlSpace.gutter)
                }
            }
        }
        .background(Color.plBg)
        .ignoresSafeArea(edges: .top)
        .task {
            if event.category == .musica {
                appleMusicURL = await EventoService.fetchAppleMusicURL(artist: event.title)
            }
        }
        .task {
            aiSummary = await EventClassifier.generateSummary(event: event)
        }
        .onAppear { updateMapCamera() }
        .onChange(of: liveCoordinate.latitude) { updateMapCamera() }
        .overlay(alignment: .top) {
            if showToast {
                AddedToast(label: toastLabel, icon: toastIcon)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .padding(.top, 60)
            }
        }
        .animation(.smooth, value: showToast)
        .safeAreaInset(edge: .bottom) {
            ctaBar
        }
        .fullScreenCover(isPresented: $showingFullImage) {
            FullImageView(url: event.imageURL)
        }
    }

    private func dateRow(dateText: String, venue: String, ciudad: String) -> some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(dateText).font(.plSans(16, weight: .medium))
                Text("\(venue) · \(ciudad)")
                    .font(.plSans(13))
                    .foregroundStyle(Color.plMuted)
            }
        } icon: {
            Image(systemName: "calendar")
                .foregroundStyle(Color.plAccent)
        }
        .padding(.vertical, 4)
    }

    private func infoCell(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            PlTag(text: label)
            Text(value).font(.plSans(16, weight: .medium))
        }
    }

    private func presentToast(label: String, icon: String) {
        toastLabel = label
        toastIcon = icon
        showToast = true
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            showToast = false
        }
    }

    private var ctaBar: some View {
        HStack(spacing: 10) {
            if let url = event.url {
                Link(destination: url) {
                    Text("Ver evento")
                        .font(.plSans(16, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.plAccent, in: .capsule)
                        .foregroundStyle(.white)
                }
            }
            if let musicURL = appleMusicURL {
                Link(destination: musicURL) {
                    Image(systemName: "music.note")
                        .frame(width: 48, height: 48)
                }
                .glassEffect(.clear.interactive(), in: .circle)
                .accessibilityLabel("Escuchar en Apple Music")
            }
            Button {
                Task {
                    await reminders.toggleReminder(for: event)
                    let hasReminder = reminders.hasReminder(for: event)
                    presentToast(
                        label: hasReminder ? "Recordatorio activado" : "Recordatorio eliminado",
                        icon: hasReminder ? "bell.fill" : "bell.slash"
                    )
                }
            } label: {
                Image(systemName: reminders.hasReminder(for: event) ? "bell.fill" : "bell")
                    .frame(width: 48, height: 48)
            }
            .glassEffect(.clear.interactive(), in: .circle)
            .accessibilityLabel(reminders.hasReminder(for: event) ? "Quitar recordatorio" : "Recordarme")
            Button {
                if servicio.toggleSaved(event) {
                    presentToast(label: "Agregado", icon: "checkmark")
                }
            } label: {
                Image(systemName: servicio.isSaved(event) ? "calendar.badge.checkmark" : "calendar.badge.plus")
                    .frame(width: 48, height: 48)
            }
            .glassEffect(.clear.interactive(), in: .circle)
            .accessibilityLabel(servicio.isSaved(event) ? "Quitar de agenda" : "Agregar a agenda")
        }
        .padding(.horizontal, PlSpace.gutter)
        .padding(.vertical, 12)
        .background(.bar)
    }
}

// MARK: - Toast de confirmación

struct AddedToast: View {
    var label: String = "Agregado"
    var icon: String = "checkmark"

    var body: some View {
        Label(label, systemImage: icon)
            .font(.plSans(15, weight: .semibold))
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .glassEffect(.clear, in: .capsule)
    }
}

// MARK: - Visor de imagen completa

struct FullImageView: View {
    let url: URL?
    @Environment(\.dismiss) private var dismiss
    @State private var image: UIImage?

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()

            if let image {
                ZoomableImage(image: image)
                    .ignoresSafeArea()
            } else {
                ProgressView().tint(.white)
            }

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .semibold))
                    .frame(width: 36, height: 36)
                    .foregroundStyle(.white)
            }
            .glassEffect(.clear.interactive(), in: .circle)
            .padding(.top, 12)
            .padding(.trailing, 16)
        }
        .statusBarHidden()
        .task {
            guard let url else { return }
            if let (data, _) = try? await URLSession.shared.data(from: url) {
                image = UIImage(data: data)
            }
        }
    }
}

// MARK: - UIScrollView con zoom nativo

struct ZoomableImage: UIViewRepresentable {
    let image: UIImage

    func makeUIView(context: Context) -> UIScrollView {
        let scrollView = UIScrollView()
        scrollView.delegate = context.coordinator
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.bouncesZoom = true
        scrollView.backgroundColor = .clear

        let imageView = UIImageView(image: image)
        imageView.contentMode = .scaleAspectFit
        imageView.isUserInteractionEnabled = true
        scrollView.addSubview(imageView)

        let doubleTap = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleDoubleTap(_:))
        )
        doubleTap.numberOfTapsRequired = 2
        imageView.addGestureRecognizer(doubleTap)

        context.coordinator.imageView = imageView
        context.coordinator.scrollView = scrollView

        return scrollView
    }

    func updateUIView(_ scrollView: UIScrollView, context: Context) {
        context.coordinator.imageView?.image = image
        DispatchQueue.main.async {
            context.coordinator.fitImage()
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    class Coordinator: NSObject, UIScrollViewDelegate {
        weak var imageView: UIImageView?
        weak var scrollView: UIScrollView?

        func viewForZooming(in scrollView: UIScrollView) -> UIView? {
            imageView
        }

        func scrollViewDidZoom(_ scrollView: UIScrollView) {
            centerImage()
        }

        func fitImage() {
            guard let scrollView, let imageView,
                  let image = imageView.image else { return }
            let boundsSize = scrollView.bounds.size
            guard boundsSize.width > 0, boundsSize.height > 0 else { return }

            let imageSize = image.size
            let widthScale = boundsSize.width / imageSize.width
            let heightScale = boundsSize.height / imageSize.height
            let minScale = min(widthScale, heightScale)

            scrollView.minimumZoomScale = minScale
            scrollView.maximumZoomScale = max(minScale * 5, 1)

            imageView.frame = CGRect(origin: .zero, size: imageSize)
            scrollView.contentSize = imageSize
            scrollView.zoomScale = minScale

            centerImage()
        }

        private func centerImage() {
            guard let scrollView, let imageView else { return }
            let boundsSize = scrollView.bounds.size
            var frame = imageView.frame

            frame.origin.x = frame.width < boundsSize.width
                ? (boundsSize.width - frame.width) / 2 : 0
            frame.origin.y = frame.height < boundsSize.height
                ? (boundsSize.height - frame.height) / 2 : 0

            imageView.frame = frame
        }

        @objc func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
            guard let scrollView else { return }
            if scrollView.zoomScale > scrollView.minimumZoomScale {
                scrollView.setZoomScale(scrollView.minimumZoomScale, animated: true)
            } else {
                let point = gesture.location(in: scrollView)
                let targetScale = scrollView.maximumZoomScale / 2
                let size = CGSize(
                    width: scrollView.bounds.width / targetScale,
                    height: scrollView.bounds.height / targetScale
                )
                scrollView.zoom(to: CGRect(
                    origin: CGPoint(x: point.x - size.width / 2, y: point.y - size.height / 2),
                    size: size
                ), animated: true)
            }
        }
    }
}
