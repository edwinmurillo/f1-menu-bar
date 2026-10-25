import F1Core
import SwiftUI

struct SettingsView: View {
    @Bindable var preferences: AppPreferences
    let store: SeasonStore
    let loginItem: LoginItemController

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            SectionHeader(title: "Settings", subtitle: "A quiet companion for race weekends")
                .padding(.horizontal, 26).padding(.top, 26)
            Form {
                Section("General") {
                    Toggle("Launch at login", isOn: Binding(get: { loginItem.enabled }, set: { loginItem.setEnabled($0) }))
                    if loginItem.status == .requiresApproval {
                        Button("Allow in Login Items settings") { loginItem.openSystemSettings() }
                    }
                    if let error = loginItem.error { Text(error).font(.caption).foregroundStyle(.secondary) }
                    Toggle("Menu bar countdown", isOn: $preferences.showCountdown)
                }
                Section("Display") {
                    Picker("Timezone", selection: $preferences.useUTC) {
                        Text("System · \(TimeZone.autoupdatingCurrent.identifier)").tag(false)
                        Text("UTC").tag(true)
                    }
                    Picker("Appearance", selection: $preferences.appearance) {
                        Text("System").tag("system")
                        Text("Light").tag("light")
                        Text("Dark").tag("dark")
                    }
                }
                Section("Data") {
                    LabeledContent("Current source") {
                        Link(Presentation.providerName(store.snapshot.provider), destination: Presentation.providerURL(store.snapshot.provider))
                    }
                    Text("Schedules, published race results and championship points. Cached data stays available when a connection fails.")
                        .font(.callout).foregroundStyle(.secondary)
                    Text("OpenF1 is the primary source. Jolpica supplies a backup when OpenF1 is unavailable, including during live sessions. Both are independent services; this app does not provide live timing.")
                        .font(.caption).foregroundStyle(.secondary)
                    Link("Jolpica data · CC BY-NC-SA 4.0", destination: URL(string: "https://github.com/jolpica/jolpica-f1/blob/main/TERMS.md")!)
                        .font(.caption)
                    HStack {
                        Text("Last update")
                        Spacer()
                        Text(store.snapshot.latestUpdate.map { Presentation.date($0, format: "d MMM jmm", zone: preferences.timeZone) } ?? "Not yet downloaded")
                            .foregroundStyle(.secondary)
                    }
                    Button(store.isRefreshing ? "Refreshing…" : "Refresh data") { Task { await store.refresh(force: true) } }
                        .disabled(store.isRefreshing)
                }
                Section {
                    Text("F1 Menu Bar · 0.1.0").font(.callout)
                    Text("An independent app. Not affiliated with Formula 1, the FIA, or any team.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }.formStyle(.grouped)
        }
    }
}
