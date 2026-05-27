// EventEditView.swift
// Formulario de edición manual: título, subtítulo, venue, ciudad, fecha, categoría y descripción.
// Persiste cambios en EventoService (plaza_edited_events). Solo accesible desde AgendaView.

import SwiftUI

struct EventEditView: View {
    @Environment(EventoService.self) private var servicio
    @Environment(\.dismiss) private var dismiss

    @State var event: Event

    var body: some View {
        NavigationStack {
            Form {
                Section("Información") {
                    TextField("Título", text: $event.title)
                    TextField("Subtítulo", text: $event.subtitle)
                    TextField("Venue", text: $event.venue)
                    TextField("Ciudad", text: $event.ciudad)
                    DatePicker("Fecha", selection: $event.date, displayedComponents: [.date, .hourAndMinute])
                    TextField("Precio", text: Binding(
                        get: { event.price ?? "" },
                        set: { event.price = $0.isEmpty ? nil : $0 }
                    ))
                }

                Section("Categoría") {
                    Picker("Categoría", selection: $event.category) {
                        ForEach(Event.Category.allCases, id: \.self) { cat in
                            Label(cat.rawValue, systemImage: cat.icon).tag(cat)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }

                Section("Descripción") {
                    TextEditor(text: $event.blurb)
                        .frame(minHeight: 120)
                }
            }
            .navigationTitle("Editar evento")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar") {
                        servicio.updateEvent(event)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }
}
