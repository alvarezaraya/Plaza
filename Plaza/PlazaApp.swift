// PlazaApp.swift
// Punto de entrada de la app: inicializa servicios, registra fuentes y controla la puerta de onboarding.

import SwiftUI
import CoreText
import MapKit

@main
struct PlazaApp: App {
    @State private var servicio = EventoService()
    @State private var locationManager = LocationManager()
    @State private var reminderManager = ReminderManager()
    @State private var comunaManager = ComunaManager()
    @AppStorage("plaza_onboarding_done") private var onboardingDone = false

    init() {
        Self.registerFonts()
        Self.prewarmMapKit()
    }

    var body: some Scene {
        WindowGroup {
            if onboardingDone {
                RootTabView()
                    .environment(servicio)
                    .environment(locationManager)
                    .environment(reminderManager)
                    .environment(comunaManager)
                    .tint(.plAccent)
            } else {
                OnboardingView {
                    withAnimation(.smooth) { onboardingDone = true }
                }
                .environment(locationManager)
                .environment(reminderManager)
                .tint(.plAccent)
            }
        }
    }

    private static func prewarmMapKit() {
        // Fuerza la compilación de shaders Metal de MapKit en el lanzamiento,
        // eliminando el delay visual al mostrar el primer Map view.
        _ = MKMapView()
    }

    private static func registerFonts() {
        let fonts = [
            "BricolageGrotesque-VariableFont_opsz,wdth,wght",
            "InstrumentSerif-Regular",
            "InstrumentSerif-Italic",
            "JetBrainsMono-VariableFont_wght",
            "JetBrainsMono-Italic-VariableFont_wght"
        ]
        for name in fonts {
            guard let url = Bundle.main.url(forResource: name, withExtension: "ttf") else { continue }
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }
}
