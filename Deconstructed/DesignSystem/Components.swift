import SwiftUI

struct Tag: View {
    enum Tone {
        case neutral, rose, olive, seagrass, warning

        var color: Color {
            switch self {
            case .neutral: Theme.ink
            case .rose: Theme.rose
            case .olive: Theme.olive
            case .seagrass: Theme.seagrass
            case .warning: Theme.warning
            }
        }
    }

    var text: String
    var symbol: String?
    var tone: Tone = .neutral
    /// Filled with the tone's gradient and white text, for statuses that should stand out.
    var solid = false

    @Environment(\.colorScheme) private var colorScheme

    private var solidFill: AnyShapeStyle {
        // On a coloured panel a same-coloured chip would vanish, so it becomes a frosted one.
        if colorScheme == .dark { return AnyShapeStyle(.white.opacity(0.22)) }
        switch tone {
        case .rose: return AnyShapeStyle(Theme.roseGradient)
        case .olive: return AnyShapeStyle(Theme.oliveGradient)
        case .seagrass: return AnyShapeStyle(Theme.seagrassGradient)
        case .neutral: return AnyShapeStyle(Theme.heroGradient)
        case .warning: return AnyShapeStyle(Theme.roseGradient)
        }
    }

    var body: some View {
        HStack(spacing: 4) {
            if let symbol { Image(systemName: symbol).imageScale(.small) }
            Text(text)
        }
        .font(.caption.weight(.semibold))
        // Text is always jet or alabaster; the palette colour is the chip behind it.
        .foregroundStyle(solid ? AnyShapeStyle(Theme.alabaster) : AnyShapeStyle(Theme.ink))
        .padding(.horizontal, solid ? 10 : 8)
        .padding(.vertical, solid ? 5 : 4)
        .background(solid ? solidFill : AnyShapeStyle(tone.color.opacity(tone == .neutral ? 0.14 : 0.32)), in: Capsule())
        .accessibilityElement(children: .combine)
    }
}

/// Marks anything fictional so demo content can never be mistaken for real results.
struct DemoBadge: View {
    var body: some View {
        Tag(text: "Demo", symbol: "theatermasks", tone: .warning)
            .accessibilityLabel("Demo data, not a real restaurant")
    }
}

struct SectionTitle: View {
    var text: String
    var detail: String?

    init(_ text: String, detail: String? = nil) {
        self.text = text
        self.detail = detail
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Capsule().fill(Theme.spectrum)
                .frame(width: 22, height: 5)
                .padding(.top, 11)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(text)
                    .font(.display(.title3))
                    .foregroundStyle(Theme.ink)
                    .accessibilityAddTraits(.isHeader)
                if let detail {
                    Text(detail).font(.footnote).foregroundStyle(Theme.inkSoft)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct Avatar: View {
    var profile: UserProfile
    var size: CGFloat = 40

    var body: some View {
        Text(profile.initials)
            .font(.display(size: size * 0.40))
            .foregroundStyle(Theme.alabaster)
            .frame(width: size, height: size)
            .background([Theme.rose, Theme.seagrass, Theme.olive][Int(profile.id.uuid.14 ^ profile.id.uuid.15) % 3], in: Circle())
            .overlay { Circle().strokeBorder(.white.opacity(0.85), lineWidth: max(2, size * 0.05)) }
            .shadow(color: Theme.jet.opacity(0.18), radius: 5, y: 2)
            .accessibilityHidden(true)
    }
}

struct ErrorBanner: View {
    var message: String
    var retry: (() -> Void)?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Theme.warning)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 8) {
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(Theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                if let retry {
                    Button("Try again", action: retry)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.rose)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(Theme.warning.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .contain)
    }
}

struct EmptyState: View {
    var symbol: String
    var title: String
    var message: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(Theme.rose)
                .accessibilityHidden(true)
            Text(title).font(.display(.title3)).foregroundStyle(Theme.ink)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(Theme.inkSoft)
                .multilineTextAlignment(.center)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.secondary)
                    .fixedSize()
                    .padding(.top, 4)
            }
        }
        .padding(28)
        .frame(maxWidth: .infinity)
    }
}

struct LabeledRow: View {
    var symbol: String
    var text: String

    var body: some View {
        Label {
            Text(text).foregroundStyle(Theme.ink)
        } icon: {
            Image(systemName: symbol).foregroundStyle(Theme.inkSoft)
        }
        .font(.subheadline)
    }
}

/// A brief message that fades in at the bottom of the screen and clears itself.
struct ToastModifier: ViewModifier {
    @Binding var message: String?

    func body(content: Content) -> some View {
        content.overlay(alignment: .bottom) {
            if let message {
                Text(message)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Theme.canvas)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(Theme.ink, in: Capsule())
                    .padding(.bottom, 64)
                    .padding(.horizontal, 24)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .task(id: message) {
                        UIAccessibility.post(notification: .announcement, argument: message)
                        try? await Task.sleep(for: .seconds(3.2))
                        withAnimation(.snappy) { self.message = nil }
                    }
            }
        }
        .animation(.snappy, value: message)
    }
}

extension View {
    func toast(_ message: Binding<String?>) -> some View {
        modifier(ToastModifier(message: message))
    }
}

/// Runs an async action from a button and reports failure through the app-wide toast.
struct AsyncButton<Label: View>: View {
    @Environment(AppModel.self) private var model
    var role: ButtonRole?
    var action: () async throws -> Void
    @ViewBuilder var label: () -> Label
    @State private var isRunning = false

    var body: some View {
        Button(role: role) {
            guard !isRunning else { return }
            isRunning = true
            Task {
                defer { isRunning = false }
                do {
                    try await action()
                } catch {
                    model.toast = error.localizedDescription
                }
            }
        } label: {
            label().opacity(isRunning ? 0.5 : 1)
        }
        .disabled(isRunning)
    }
}

extension AsyncButton where Label == Text {
    init(_ title: String, role: ButtonRole? = nil, action: @escaping () async throws -> Void) {
        self.init(role: role, action: action) { Text(title) }
    }
}

extension Date {
    var visitFormatted: String {
        formatted(.dateTime.day().month(.abbreviated).year())
    }
}
