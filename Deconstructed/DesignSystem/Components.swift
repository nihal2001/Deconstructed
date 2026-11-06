import SwiftUI

struct Tag: View {
    enum Tone {
        case neutral, accent, saved, positive, warning

        var color: Color {
            switch self {
            case .neutral: Theme.inkSoft
            case .accent: Theme.tint
            case .saved: Theme.saved
            case .positive: Theme.positive
            case .warning: Theme.warning
            }
        }
    }

    var text: String
    var symbol: String?
    var tone: Tone = .neutral
    /// Filled with the tone's colour, for statuses that should stand out.
    var solid = false

    var body: some View {
        HStack(spacing: 4) {
            if let symbol { Image(systemName: symbol).imageScale(.small) }
            Text(text)
        }
        .font(.system(.caption, design: .rounded, weight: .semibold))
        .foregroundStyle(solid ? Color.white : (tone == .neutral ? Theme.ink : tone.color))
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        // A soft scoop of the tone's colour; solid tags get the glossy fill.
        .background { if solid { Gloss(shape: Capsule(), strength: 0.35) } }
        .background(solid ? tone.color : tone.color.opacity(tone == .neutral ? 0.10 : 0.13), in: Capsule())
        .accessibilityElement(children: .combine)
    }
}

/// A row of glass chips standing in for a segmented control: the chosen one is glossy cobalt with
/// white text, the rest are glass. Wraps at large Dynamic Type sizes.
struct SegmentedChips<Value: Hashable>: View {
    var title: String
    var options: [Value]
    @Binding var selection: Value
    var label: (Value) -> String

    var body: some View {
        FlowLayout(spacing: 8) {
            ForEach(options, id: \.self) { option in
                let isOn = option == selection
                Button {
                    withAnimation(Motion.pop) { selection = option }
                } label: {
                    Text(label(option))
                        .font(.system(.subheadline, design: .rounded, weight: .semibold))
                        .foregroundStyle(isOn ? Theme.onTint : Theme.ink)
                        .padding(.horizontal, 16)
                        .frame(minHeight: 38)
                        .background { Gloss(shape: Capsule(), strength: isOn ? 0.35 : 0.5) }
                        .background { Capsule().fill(isOn ? AnyShapeStyle(Theme.keyGradient) : AnyShapeStyle(Theme.plate)) }
                        .overlay { Capsule().strokeBorder(Theme.rule, lineWidth: 1) }
                        .shadow(color: (isOn ? Theme.cobalt : Theme.shadowInk).opacity(isOn ? 0.3 : 0.08), radius: 10, y: 5)
                        .contentShape(Capsule())
                }
                .buttonStyle(.squish)
                .sensoryFeedback(.selection, trigger: isOn)
                .accessibilityAddTraits(isOn ? [.isSelected] : [])
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title)
    }
}

/// Marks anything fictional so demo content can never be mistaken for real results.
struct DemoBadge: View {
    var body: some View {
        // Quiet on purpose: it sits beside every name, so it must not outshout ranks and scores.
        // Opaque in both schemes, so it stays legible on the key panel too.
        Text("Demo")
            .font(.system(.caption2, design: .rounded, weight: .semibold))
            .foregroundStyle(Color(hex: Theme.inkSoftHex))
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(Color(hex: 0xE3E8EF), in: Capsule())
            .fixedSize()
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
        VStack(alignment: .leading, spacing: 2) {
            Text(text)
                .font(.display(.title3))
                .foregroundStyle(Theme.ink)
                .accessibilityAddTraits(.isHeader)
            if let detail {
                Text(detail).font(.footnote).foregroundStyle(Theme.inkSoft)
            }
        }
        .padding(.top, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct Avatar: View {
    var profile: UserProfile
    var size: CGFloat = 40

    private var color: Color {
        let colors = [Theme.coral, Theme.cobalt, Theme.violet, Theme.aqua, Theme.amber, Theme.pink]
        return colors[Int(profile.id.uuid.14 ^ profile.id.uuid.15) % colors.count]
    }

    var body: some View {
        Text(profile.initials)
            .font(.display(size: size * 0.40))
            .foregroundStyle(Theme.text(on: color))
            .frame(width: size, height: size)
            .background { Gloss(shape: Circle(), strength: 0.4) }
            .background(color, in: Circle())
            .overlay { Circle().strokeBorder(.white, lineWidth: max(1.5, size * 0.05)) }
            .shadow(color: color.opacity(0.35), radius: 8, y: 4)
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
                        .foregroundStyle(Theme.tint)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(Theme.warning.opacity(0.08), in: RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
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
                .foregroundStyle(Theme.tint)
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
                    .foregroundStyle(Theme.ink)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .liquidGlass(Capsule())
                    .padding(.bottom, 124) // clear of the floating tab bar and its accessory
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
                } catch is CancellationError {
                    // The person backed out, so there's nothing to report.
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
