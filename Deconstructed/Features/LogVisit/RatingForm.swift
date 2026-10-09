import SwiftUI

/// The scoring form, generated entirely from a system version. Any system — standard,
/// edited or custom, with any number of criteria — renders through this one view.
struct RatingForm: View {
    var version: SystemVersion
    @Binding var scores: [UUID: Int]

    var body: some View {
        VStack(spacing: Theme.spacing) {
            ForEach(Array(version.criteria.enumerated()), id: \.element.id) { index, criterion in
                CriterionScorePicker(
                    criterion: criterion,
                    color: Theme.criterionColor(index),
                    selection: Binding(
                        get: { scores[criterion.id] },
                        set: { scores[criterion.id] = $0 }))
            }
        }
    }
}

/// One criterion: every selectable score with its label and what it means. Nothing is
/// selected until the user chooses.
struct CriterionScorePicker: View {
    var criterion: Criterion
    var color: Color
    @Binding var selection: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Circle().fill(color).frame(width: 10, height: 10).accessibilityHidden(true)
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
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(spacing: 8) {
                // Highest first, so the best outcome reads at the top like a rubric sheet.
                ForEach(criterion.levels.sorted { $0.points > $1.points }) { level in
                    ScoreChoiceRow(level: level, maxPoints: criterion.maxPoints, color: color,
                                   isSelected: selection == level.points) {
                        withAnimation(.snappy(duration: 0.2)) { selection = level.points }
                    }
                }
            }
        }
        .card()
    }
}

struct ScoreChoiceRow: View {
    var level: ScoreLevel
    var maxPoints: Int
    var color: Color
    var isSelected: Bool
    var select: () -> Void

    var body: some View {
        Button(action: select) {
            HStack(alignment: .top, spacing: 12) {
                Text("\(level.points)")
                    .font(.display(.title3, weight: .bold).monospacedDigit())
                    .foregroundStyle(isSelected ? Theme.alabaster : Theme.ink)
                    .frame(minWidth: 38, minHeight: 38)
                    .background(isSelected ? AnyShapeStyle(color.gradient) : AnyShapeStyle(Theme.fill),
                                in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .shadow(color: color.opacity(isSelected ? 0.45 : 0), radius: 6, y: 3)
                    .scaleEffect(isSelected ? 1.06 : 1)

                VStack(alignment: .leading, spacing: 3) {
                    Text(level.displayLabel)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.ink)
                    Text(level.detail)
                        .font(.footnote)
                        .foregroundStyle(Theme.inkSoft)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 4)
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? color : Theme.hairline)
                    .accessibilityHidden(true)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isSelected ? color.opacity(0.14) : Color.clear,
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(isSelected ? color : Theme.hairline, lineWidth: isSelected ? 2 : 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(level.points) of \(maxPoints), \(level.displayLabel)")
        .accessibilityValue(level.detail)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

/// Running total pinned under the form: what is scored so far and what is still missing.
struct LiveTotalBar: View {
    var version: SystemVersion
    var scores: [UUID: Int]
    var systemName: String

    private var answered: Int { RatingEngine.answeredCount(scores: scores, version: version) }
    private var isComplete: Bool { answered == version.criteria.count }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                ScoreBadge(total: RatingEngine.runningTotal(scores: scores, version: version),
                           systemName: systemName, size: .regular)
                Spacer()
                Text(isComplete ? "All scored" : "\(answered) of \(version.criteria.count) scored")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(isComplete ? Theme.seagrass : Theme.inkSoft)
            }
            ScoreBar(version: version, scores: scores, height: 10)
        }
        .padding(.horizontal, Theme.spacing)
        .padding(.vertical, 12)
        .background(.regularMaterial)
        .overlay(alignment: .top) { Divider() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Running total \(RatingEngine.runningTotal(scores: scores, version: version)) out of 10 in \(systemName). \(isComplete ? "All criteria scored." : "\(answered) of \(version.criteria.count) criteria scored.")")
    }
}
