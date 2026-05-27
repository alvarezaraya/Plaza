// OnboardingView.swift
// Bienvenida en dos pasos: presentación de funciones (carrusel) + solicitud de permisos
// de ubicación y notificaciones. Controlado por plaza_onboarding_done en UserDefaults.

import SwiftUI
import CoreLocation

struct OnboardingView: View {
    @Environment(LocationManager.self) private var location
    @Environment(ReminderManager.self) private var reminders
    var onFinish: () -> Void

    @State private var page = 0

    var body: some View {
        TabView(selection: $page) {
            welcomePage.tag(0)
            permissionsPage.tag(1)
        }
        .tabViewStyle(.page(indexDisplayMode: .always))
        .background(Color.plBg)
    }

    // MARK: - Bienvenida

    private var welcomePage: some View {
        VStack(spacing: 0) {
            Spacer()

            Image(systemName: "binoculars.fill")
                .font(.system(size: 64))
                .foregroundStyle(Color.plAccent)
                .padding(.bottom, 16)

            Text("Bienvenido a")
                .font(.plSerifItalic(20))
                .foregroundStyle(Color.plMuted)

            Text("Plaza")
                .font(.plDisplay(48))
                .kerning(-2)

            Text("Tu guía de eventos culturales")
                .font(.plSans(16))
                .foregroundStyle(Color.plDim)
                .padding(.top, 4)

            Spacer().frame(height: 40)

            VStack(spacing: 20) {
                FeatureRow(
                    icon: "square.grid.2x2",
                    color: .plAccent,
                    title: "Descubre eventos",
                    subtitle: "Conciertos, teatro, humor y más cerca de ti"
                )
                FeatureRow(
                    icon: "map",
                    color: .blue,
                    title: "Explora en el mapa",
                    subtitle: "Encuentra venues y eventos por ubicación"
                )
                FeatureRow(
                    icon: "calendar.badge.plus",
                    color: .green,
                    title: "Arma tu agenda",
                    subtitle: "Guarda eventos y recibe recordatorios"
                )
                FeatureRow(
                    icon: "sparkles",
                    color: .purple,
                    title: "Resúmenes con IA",
                    subtitle: "Conoce al artista antes de ir al show"
                )
            }
            .padding(.horizontal, 32)

            Spacer()

            Button {
                withAnimation(.smooth) { page = 1 }
            } label: {
                Text("Continuar")
                    .font(.plSans(17, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color.plAccent, in: .capsule)
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 40)
        }
    }

    // MARK: - Permisos

    private var locationGranted: Bool {
        location.authorizationStatus == .authorizedWhenInUse || location.authorizationStatus == .authorizedAlways
    }

    private var permissionsPage: some View {
        VStack(spacing: 0) {
            Spacer()

            Image(systemName: "location.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(Color.blue)
                .padding(.bottom, 16)

            Text("Permisos")
                .font(.plDisplay(38))
                .kerning(-1.2)

            Text("Para la mejor experiencia")
                .font(.plSerifItalic(18))
                .foregroundStyle(Color.plMuted)
                .padding(.top, 4)

            Spacer().frame(height: 40)

            VStack(spacing: 0) {
                Toggle(isOn: Binding(
                    get: { locationGranted },
                    set: { if $0 { location.requestPermission() } }
                )) {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Ubicación")
                                .font(.plSans(16, weight: .semibold))
                            Text("Ver eventos cercanos y distancias")
                                .font(.plSans(13))
                                .foregroundStyle(Color.plMuted)
                        }
                    } icon: {
                        Image(systemName: "location.fill")
                            .foregroundStyle(.blue)
                    }
                }
                .padding(.vertical, 12)

                Divider()

                Toggle(isOn: Binding(
                    get: { reminders.isAuthorized },
                    set: { if $0 { Task { await reminders.requestPermission() } } }
                )) {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Notificaciones")
                                .font(.plSans(16, weight: .semibold))
                            Text("Recordatorios antes del evento")
                                .font(.plSans(13))
                                .foregroundStyle(Color.plMuted)
                        }
                    } icon: {
                        Image(systemName: "bell.fill")
                            .foregroundStyle(.orange)
                    }
                }
                .padding(.vertical, 12)
            }
            .padding(.horizontal, 16)
            .background(Color.plSurface, in: .rect(cornerRadius: PlSpace.cardRadius))
            .padding(.horizontal, 32)

            Spacer()

            Button {
                onFinish()
            } label: {
                Text("Empezar")
                    .font(.plSans(17, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color.plFg, in: .capsule)
                    .foregroundStyle(Color.plBg)
            }
            .padding(.horizontal, 32)

            Button {
                onFinish()
            } label: {
                Text("Ahora no")
                    .font(.plSans(15))
                    .foregroundStyle(Color.plMuted)
            }
            .padding(.top, 12)
            .padding(.bottom, 40)
        }
    }
}

// MARK: - Feature Row

private struct FeatureRow: View {
    let icon: String
    let color: Color
    let title: String
    let subtitle: String

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 22))
                .foregroundStyle(color)
                .frame(width: 44, height: 44)
                .background(color.opacity(0.12), in: .rect(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.plSans(16, weight: .semibold))
                    .foregroundStyle(Color.plFg)
                Text(subtitle)
                    .font(.plSans(14))
                    .foregroundStyle(Color.plMuted)
            }
            Spacer(minLength: 0)
        }
    }
}

