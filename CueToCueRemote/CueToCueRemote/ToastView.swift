import SwiftUI

/// Bottom confirmation with an Undo action; announces itself to VoiceOver and clears after 5 seconds.
struct ToastView: View {
    @EnvironmentObject var store: RemoteStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if let t = store.toast {
                HStack(spacing: 8) {
                    Text(t.message).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.text)
                    Spacer(minLength: 8)
                    if t.canUndo {
                        Button("Undo") { Task { await store.undo() } }
                            .font(.subheadline.weight(.bold)).foregroundStyle(Theme.accent)
                            .frame(minWidth: 56, minHeight: 44)
                    }
                }
                .padding(.horizontal, 16).padding(.vertical, 2)
                .background(.regularMaterial, in: Capsule())
                .shadow(color: .black.opacity(0.25), radius: 10, y: 4)
                .padding(.horizontal, 16).padding(.bottom, 8)
                .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(reduceMotion ? nil : .snappy, value: store.toast)
    }
}
