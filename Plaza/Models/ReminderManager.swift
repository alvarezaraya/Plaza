// ReminderManager.swift
// Notificaciones locales UNUserNotificationCenter: toggleReminder(for:) programa/cancela alertas
// 1 hora antes del evento; hasReminder(for:) refleja el estado en la UI.

import Foundation
import UserNotifications
import Observation

@MainActor
@Observable
class ReminderManager {
    private let center = UNUserNotificationCenter.current()
    private let storageKey = "plaza_reminders"
    private(set) var reminderIDs: Set<String> = []
    private(set) var isAuthorized = false

    init() {
        loadReminders()
        Task { await checkAuthorization() }
    }

    func hasReminder(for event: Event) -> Bool {
        reminderIDs.contains(event.stableID)
    }

    @discardableResult
    func toggleReminder(for event: Event) async -> Bool {
        if hasReminder(for: event) {
            removeReminder(for: event)
            return false
        } else {
            return await scheduleReminder(for: event)
        }
    }

    private func scheduleReminder(for event: Event) async -> Bool {
        if !isAuthorized {
            do {
                let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
                isAuthorized = granted
                guard granted else { return false }
            } catch {
                return false
            }
        }

        let content = UNMutableNotificationContent()
        content.title = event.title
        content.body = "En 1 hora · \(event.venue) · \(event.dateText)"
        content.sound = .default

        let triggerDate = event.date.addingTimeInterval(-3600)
        guard triggerDate > .now else { return false }

        let components = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute], from: triggerDate
        )
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let request = UNNotificationRequest(identifier: event.stableID, content: content, trigger: trigger)

        do {
            try await center.add(request)
            reminderIDs.insert(event.stableID)
            persistReminders()
            return true
        } catch {
            return false
        }
    }

    private func removeReminder(for event: Event) {
        center.removePendingNotificationRequests(withIdentifiers: [event.stableID])
        reminderIDs.remove(event.stableID)
        persistReminders()
    }

    func requestPermission() async {
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            isAuthorized = granted
        } catch {}
    }

    private func checkAuthorization() async {
        let settings = await center.notificationSettings()
        isAuthorized = settings.authorizationStatus == .authorized
    }

    private func persistReminders() {
        if let data = try? JSONEncoder().encode(Array(reminderIDs)) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }

    private func loadReminders() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let ids = try? JSONDecoder().decode([String].self, from: data)
        else { return }
        reminderIDs = Set(ids)
    }
}
