// AgendaView.swift
// Lista los eventos guardados por el usuario agrupados por fecha, con acciones de recordatorio y edición.

import SwiftUI

struct AgendaView: View {
    @Environment(EventoService.self) private var servicio
    @Environment(ReminderManager.self) private var reminders
    private var events: [Event] { servicio.savedEvents }

    private static let groupFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "es_CL")
        f.dateFormat = "EEEE d 'de' MMMM"
        return f
    }()

    private var grouped: [(String, [Event])] {
        guard !events.isEmpty else { return [] }
        let dict = Dictionary(grouping: events) { Self.groupFormatter.string(from: $0.date) }
        return dict.sorted { $0.value.first!.date < $1.value.first!.date }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            PlTag(text: "● Mi Agenda", color: .plFg)
                            Spacer()
                            if !events.isEmpty {
                                PlTag(text: "\(events.count) evento\(events.count == 1 ? "" : "s")")
                            }
                        }
                        Text("Eventos guardados")
                            .font(.plSerifItalic(18))
                            .foregroundStyle(Color.plMuted)
                        Text("\(events.count) guardado\(events.count == 1 ? "" : "s")")
                            .font(.plDisplay(40))
                            .kerning(-1.4)
                    }
                    .plainRow()
                    .padding(.horizontal, PlSpace.gutter)
                }

                if servicio.cargando {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.top, 40)
                        .plainRow()
                } else if events.isEmpty {
                    ContentUnavailableView(
                        "Sin eventos guardados",
                        systemImage: "calendar.badge.plus",
                        description: Text("Desliza un evento hacia la derecha o toca el botón de agenda para agregarlo aquí")
                    )
                    .plainRow()
                } else {
                    ForEach(grouped, id: \.0) { label, items in
                        Section {
                            ForEach(items) { event in
                                NavigationLink(value: event) {
                                    HStack {
                                        EventRowContent(event: event)
                                        if reminders.hasReminder(for: event) {
                                            Image(systemName: "bell.fill")
                                                .font(.system(size: 12))
                                                .foregroundStyle(Color.plAccent)
                                        }
                                    }
                                }
                                .swipeActions(edge: .trailing) {
                                    Button(role: .destructive) {
                                        withAnimation { _ = servicio.toggleSaved(event) }
                                    } label: {
                                        Label("Quitar", systemImage: "calendar.badge.minus")
                                    }
                                }
                                .swipeActions(edge: .leading) {
                                    Button {
                                        Task { await reminders.toggleReminder(for: event) }
                                    } label: {
                                        Label(
                                            reminders.hasReminder(for: event) ? "Sin recordatorio" : "Recordar",
                                            systemImage: reminders.hasReminder(for: event) ? "bell.slash" : "bell"
                                        )
                                    }
                                    .tint(reminders.hasReminder(for: event) ? .orange : .blue)
                                }
                                .listRowInsets(EdgeInsets(top: 0, leading: PlSpace.gutter, bottom: 0, trailing: PlSpace.gutter))
                                .listRowBackground(Color.plBg)
                            }
                        } header: {
                            HStack {
                                PlTag(text: label, color: .plFg)
                                Spacer()
                                PlTag(text: "\(items.count) evento\(items.count == 1 ? "" : "s")")
                            }
                        }
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Color.plBg)
            .toolbar(.hidden, for: .navigationBar)
            .toolbarBackground(.hidden, for: .tabBar)
            .navigationDestination(for: Event.self) { EventDetailView(event: $0) }
            .refreshable { servicio.cargarEventos() }
        }
    }
}

#Preview {
    AgendaView()
        .environment(EventoService())
        .tint(.plAccent)
}
