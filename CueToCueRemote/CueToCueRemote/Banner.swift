import SwiftUI

// MARK: - Outbox banner and conflicts

/// Shows edits that are waiting for the Mac, and any that need a decision.
struct OutboxBanner: View {
    @EnvironmentObject var store: RemoteStore
    @Binding var showConflicts: Bool

    var body: some View {
        VStack(spacing: 0) {
            if !store.conflicts.isEmpty {
                Button { showConflicts = true } label: {
                    row(icon: "exclamationmark.triangle.fill", color: Theme.danger,
                        text: "\(store.conflicts.count) edit\(store.conflicts.count == 1 ? "" : "s") conflict with changes on the Mac — tap to review",
                        chevron: true)
                }
                .buttonStyle(.plain)
            }
            if !store.unsent.isEmpty {
                row(icon: store.live ? "arrow.triangle.2.circlepath" : "wifi.slash", color: .orange,
                    text: store.live
                        ? "Sending \(store.unsent.count) edit\(store.unsent.count == 1 ? "" : "s")…"
                        : "Offline — \(store.unsent.count) edit\(store.unsent.count == 1 ? "" : "s") saved on this phone, will send when connected",
                    chevron: false)
            }
        }
    }

    private func row(icon: String, color: Color, text: String, chevron: Bool) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
            Text(text).font(.footnote.weight(.semibold)).multilineTextAlignment(.leading)
            Spacer(minLength: 0)
            if chevron { Image(systemName: "chevron.right") }
        }
        .foregroundStyle(color)
        .padding(.horizontal, 14).padding(.vertical, 10)
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .background(color.opacity(0.15))
        .accessibilityElement(children: .combine)
    }
}

struct ConflictsView: View {
    @EnvironmentObject var store: RemoteStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    Text("Someone changed these on the Mac while you were editing. Choose which version to keep.")
                        .font(.subheadline).foregroundStyle(Theme.textMuted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    ForEach(store.conflicts) { c in
                        VStack(alignment: .leading, spacing: 10) {
                            Text("\(c.cueLabel) — \(c.columnName)").font(.headline).foregroundStyle(Theme.text)
                            versionBox(title: "ON THE MAC", text: c.conflictRemote ?? "")
                            versionBox(title: "YOUR EDIT", text: c.newValue, highlight: true)
                            HStack(spacing: 10) {
                                choice("Use Mac's", filled: false) { await store.resolve(c.id, keepMine: false) }
                                choice("Keep mine", filled: true) { await store.resolve(c.id, keepMine: true) }
                            }
                        }
                        .padding(14)
                        .background(Theme.card, in: RoundedRectangle(cornerRadius: 16))
                    }
                    if store.conflicts.isEmpty {
                        Text("All resolved.").foregroundStyle(Theme.textMuted).padding(.top, 40)
                    }
                }
                .padding(12)
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("Review conflicts")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Theme.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() }.frame(minHeight: 44) } }
            .onChange(of: store.conflicts.isEmpty) { _, empty in if empty { dismiss() } }
        }
        
    }

    private func versionBox(title: String, text: String, highlight: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption2.weight(.heavy)).foregroundStyle(highlight ? Theme.accent : Theme.textMuted)
            Text(text.isEmpty ? "(empty)" : text).font(.body).foregroundStyle(Theme.text)
        }
        .padding(10).frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.cardRaised, in: RoundedRectangle(cornerRadius: 10))
    }

    private func choice(_ title: String, filled: Bool, action: @escaping () async -> Void) -> some View {
        Button { Task { await action() } } label: {
            Text(title).font(.body.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: Theme.minTarget)
                .background(filled ? Theme.accentFill : Theme.cardRaised, in: Capsule())
                .foregroundStyle(filled ? Theme.onAccent : Theme.text)
        }
        .buttonStyle(PressStyle())
    }
}
