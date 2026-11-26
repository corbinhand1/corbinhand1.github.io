import SwiftUI

/// Stacks on the left (a plain list on iPhone, a sidebar on iPad), cues on the right.
struct RootView: View {
    @EnvironmentObject var store: RemoteStore
    @State private var visibility: NavigationSplitViewVisibility = .automatic
    @State private var compact: NavigationSplitViewColumn = .detail

    var body: some View {
        NavigationSplitView(columnVisibility: $visibility, preferredCompactColumn: $compact) {
            StackListView()
        } detail: {
            if store.selectedStackID != nil {
                CueListView()
            } else {
                ContentUnavailableView("Choose a cue stack", systemImage: "rectangle.stack")
            }
        }
        .alert("Problem", isPresented: Binding(get: { store.error != nil }, set: { if !$0 { store.error = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(store.error ?? "") }
    }
}

struct StackListView: View {
    @EnvironmentObject var store: RemoteStore
    @State private var showSettings = false

    var body: some View {
        List(selection: Binding(get: { store.selectedStackID },
                                set: { id in if let id { Task { await store.selectStack(id) } } })) {
            Section {
                ForEach(store.sheet?.availableCueStacks ?? []) { s in
                    NavigationLink(value: s.id) {
                        HStack {
                            Text(s.name).foregroundStyle(Theme.text)
                            Spacer()
                            Text("\(s.cueCount)").monospacedDigit().foregroundStyle(Theme.textMuted)
                                .accessibilityLabel("\(s.cueCount) cues")
                        }
                        .frame(minHeight: 44)
                    }
                    .listRowBackground(Theme.card)
                }
            } header: { Text("Cue Stacks") }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle("Cue Remote")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showSettings = true } label: { Image(systemName: "gearshape").frame(minWidth: 44, minHeight: 44) }
                    .accessibilityLabel("Settings")
            }
        }
        .refreshable { await store.refresh() }
        .sheet(isPresented: $showSettings) { SettingsView().environmentObject(store) }
    }
}
