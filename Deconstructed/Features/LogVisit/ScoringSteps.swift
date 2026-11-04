import SwiftUI

/// One position in the Log a visit progress row.
struct StepDot: Identifiable {
    var id: Int
    /// A criterion's colour. Other steps show `symbol` instead of a dot.
    var color: Color?
    var symbol: String = "circle.fill"
    var isDone: Bool
}

/// Where the user is in Log a visit: a title, a dot per step (tap to jump), back and forward
/// arrows, and the running total while scoring.
struct StepProgressHeader: View {
    var title: String
    var dots: [StepDot]
    var current: Int
    var total: Int?
    var go: (Int) -> Void

    var body: some View {
        HStack(spacing: 6) {
            Button { go(current - 1) } label: {
                Image(systemName: "chevron.left").font(.subheadline.weight(.semibold))
                    .frame(width: 30, height: 30)
            }
            .disabled(current == 0)
            .accessibilityLabel("Previous step")

            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(.footnote.weight(.semibold).monospacedDigit())
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                dotRow
            }
            .layoutPriority(1)
            Spacer(minLength: 8)
            if let total { runningTotal(total) }

            Button { go(current + 1) } label: {
                Image(systemName: "chevron.right").font(.subheadline.weight(.semibold))
                    .frame(width: 30, height: 30)
            }
            .disabled(current >= dots.count - 1)
            .accessibilityLabel("Next step")
        }
        .foregroundStyle(Theme.ink)
    }

    private func runningTotal(_ total: Int) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            Text("\(total)")
                .font(.display(.title3, weight: .bold).monospacedDigit())
                .foregroundStyle(Theme.ink)
                .contentTransition(.numericText())
            Text("/\(RankingRules.totalPoints)")
                .font(.display(.subheadline))
                .foregroundStyle(Theme.inkSoft)
        }
        .animation(.snappy, value: total)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Running total \(total) out of \(RankingRules.totalPoints)")
    }

    private var dotRow: some View {
        HStack(spacing: 6) {
            ForEach(dots) { dot in
                let isCurrent = dot.id == current
                Group {
                    if let color = dot.color {
                        Capsule()
                            .fill(dot.isDone ? AnyShapeStyle(color) : AnyShapeStyle(Theme.fill))
                            .overlay { Capsule().strokeBorder(color.opacity(isCurrent ? 1 : 0.5), lineWidth: 1) }
                            .frame(width: isCurrent ? 20 : 8, height: 8)
                    } else {
                        Image(systemName: dot.symbol)
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(isCurrent ? Theme.ink : Theme.inkSoft)
                            .frame(width: isCurrent ? 16 : 10, height: 8)
                    }
                }
                .contentShape(Rectangle().inset(by: -6))
                .onTapGesture { go(dot.id) }
            }
        }
        .animation(.snappy(duration: 0.25), value: current)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Step \(current + 1) of \(dots.count)")
    }
}

/// One criterion: every selectable score with its label and what it means. Nothing is
/// selected until the user chooses. Laid out to fit on screen without scrolling.
struct CriterionScorePicker: View {
    var criterion: Criterion
    var color: Color
    @Binding var selection: Int?
    var onPick: () -> Void = {}

    /// Rubrics with more levels than this switch to a grid of numbers, with the chosen
    /// level's description below, so the page still fits on a small phone.
    private static let tileLimit = 6

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Rectangle().fill(color).frame(width: 10, height: 10).accessibilityHidden(true)
                Text(criterion.name).font(.display(.title3)).foregroundStyle(Theme.ink)
                Spacer()
                Text(selection.map { "\($0)/\(criterion.maxPoints)" } ?? "up to \(criterion.maxPoints)")
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .foregroundStyle(selection == nil ? Theme.inkSoft : Theme.ink)
                    .contentTransition(.numericText())
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)

            if !criterion.guidance.isBlank {
                Text(criterion.guidance)
                    .font(.footnote)
                    .foregroundStyle(Theme.inkSoft)
                    .lineLimit(4)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if levels.count > Self.tileLimit {
                gridLayout
            } else {
                // Two columns, best first, reading left to right like a rubric sheet.
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 8, alignment: .top),
                                    GridItem(.flexible(), spacing: 8, alignment: .top)],
                          spacing: 8) {
                    ForEach(levels) { level in
                        ScoreChoiceTile(level: level, maxPoints: criterion.maxPoints, color: color,
                                        isSelected: selection == level.points) { pick(level) }
                    }
                }
            }
        }
        .card(padding: 12)
    }

    // Highest first, so the best outcome reads at the top like a rubric sheet.
    private var levels: [ScoreLevel] { criterion.levels.sorted { $0.points > $1.points } }

    private func pick(_ level: ScoreLevel) {
        withAnimation(.snappy(duration: 0.2)) { selection = level.points }
        onPick()
    }

    private var gridLayout: some View {
        VStack(alignment: .leading, spacing: 12) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 48), spacing: 8)], spacing: 8) {
                ForEach(levels.reversed()) { level in
                    let isSelected = selection == level.points
                    Button { pick(level) } label: {
                        Text("\(level.points)")
                            .font(.display(.title3, weight: .bold).monospacedDigit())
                            .foregroundStyle(isSelected ? Theme.text(on: color) : Theme.ink)
                            .frame(maxWidth: .infinity, minHeight: 48)
                            .background(isSelected ? AnyShapeStyle(color) : AnyShapeStyle(Theme.plate),
                                        in: RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                                    .strokeBorder(isSelected ? color : Theme.hairline, lineWidth: isSelected ? 2 : 1)
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(level.points) of \(criterion.maxPoints), \(level.displayLabel)")
                    .accessibilityValue(level.detail)
                    .accessibilityAddTraits(isSelected ? [.isSelected] : [])
                }
            }
            VStack(alignment: .leading, spacing: 3) {
                if let chosen = selection.flatMap(criterion.level(for:)) {
                    Text("\(chosen.points) · \(chosen.displayLabel)")
                        .font(.subheadline.weight(.semibold)).foregroundStyle(Theme.ink)
                    Text(chosen.detail).font(.footnote).foregroundStyle(Theme.inkSoft)
                        .lineLimit(3)
                } else {
                    Text("Pick a score to see what it means.")
                        .font(.footnote).foregroundStyle(Theme.inkSoft)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 60, alignment: .topLeading)
            .accessibilityHidden(true)
        }
    }
}

/// One selectable score: its number, label and what it means, as a tile in a two-column grid.
struct ScoreChoiceTile: View {
    var level: ScoreLevel
    var maxPoints: Int
    var color: Color
    var isSelected: Bool
    var select: () -> Void

    var body: some View {
        Button(action: select) {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Text("\(level.points)")
                        .font(.display(.headline, weight: .heavy).monospacedDigit())
                        .foregroundStyle(isSelected ? Theme.text(on: color) : Theme.ink)
                        .frame(minWidth: 28, minHeight: 28)
                        .background(isSelected ? color : Theme.plate, in: Rectangle())
                        .overlay { Rectangle().strokeBorder(color, lineWidth: 2) }
                    Text(level.displayLabel)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Spacer(minLength: 0)
                }
                Text(level.detail)
                    .font(.caption2)
                    .foregroundStyle(Theme.inkSoft)
                    .multilineTextAlignment(.leading)
                    .lineLimit(6)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(9)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(isSelected ? color.opacity(0.12) : Theme.plate, in: Rectangle())
            .overlay { Rectangle().strokeBorder(isSelected ? color : Theme.rule, lineWidth: isSelected ? 2.5 : 1.5) }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(level.points) of \(maxPoints), \(level.displayLabel)")
        .accessibilityValue(level.detail)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}
