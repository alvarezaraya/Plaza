// PlazaApp.swift
// Entry point: registra fuentes Bricolage Grotesque, inyecta servicios en el entorno,
// controla puerta de onboarding y hot-swaps el tema vía WindowGroup.id(themeRaw).

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
    @AppStorage("plaza_theme") private var themeRaw: String = AppTheme.plaza.rawValue

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
                    .id(themeRaw)
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
            "BricolageGrotesque-VariableFont_opsz,wdth,wght"
        ]
        for name in fonts {
            guard let url = Bundle.main.url(forResource: name, withExtension: "ttf") else { continue }
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }
}
