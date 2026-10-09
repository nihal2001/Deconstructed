import SwiftUI
import UIKit

/// Choose where searches and the map are centred: the device's location, or an area typed
/// by hand. The manual route means nothing depends on granting location access.
struct AreaPickerSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var text = ""
    @State private var isLooking = false
    @State private var errorMessage: String?

    private var location: LocationService { model.location }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.spacing) {
                    deviceSection
                    manualSection
                    if model.isDemo { demoSection }
                }
                .padding(Theme.spacing)
            }
            .screenBackground()
            .navigationTitle("Search area")
            .modalSurface()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var deviceSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle("Your location")
            switch location.access {
            case .granted:
                Button {
                    location.useDeviceLocation()
                    dismiss()
                } label: {
                    Label(location.manualArea == nil ? "Using current location" : "Use current location", systemImage: "location.fill")
                }
                .buttonStyle(.secondary(tint: Theme.seagrass))
            case .notDetermined:
                Text("Allow location to centre the map and searches on where you are.")
                    .font(.subheadline).foregroundStyle(Theme.inkSoft)
                Button {
                    location.useDeviceLocation()
                } label: {
                    Label("Allow location access", systemImage: "location")
                }
                .buttonStyle(.secondary)
            case .denied:
                Text("Location access is off for Deconstructed. You can set an area by hand below, or turn access on in Settings.")
                    .font(.subheadline).foregroundStyle(Theme.inkSoft)
                Button {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                } label: {
                    Label("Open Settings", systemImage: "gear")
                }
                .buttonStyle(.secondary)
            }
        }
        .card()
    }

    private var manualSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle("Set an area", detail: "A neighbourhood, city or postcode")
            HStack {
                TextField("e.g. Hayes Valley, San Francisco", text: $text)
                    .textFieldStyle(.roundedBorder)
                    .submitLabel(.search)
                    .onSubmit(lookUp)
                    .accessibilityLabel("Area to search")
                if isLooking { ProgressView() }
            }
            if let manual = location.manualArea {
                LabeledRow(symbol: "mappin.and.ellipse", text: "Currently: \(manual.name)")
            }
            if let errorMessage {
                Text(errorMessage).font(.footnote).foregroundStyle(Theme.warning)
            }
            Button("Set area", action: lookUp)
                .buttonStyle(.primary)
                .disabled(text.isBlank || isLooking)
        }
        .card()
    }

    private var demoSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle("Demo neighbourhoods", detail: "Where the invented restaurants are")
            FlowLayout(spacing: 8) {
                ForEach(DemoCatalog.areas, id: \.name) { area in
                    Button(area.name) {
                        location.manualArea = NamedArea(name: area.name, coordinate: area.coordinate)
                        dismiss()
                    }
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Theme.fill, in: Capsule())
                    .foregroundStyle(Theme.ink)
                }
            }
        }
        .card()
    }

    private func lookUp() {
        guard !text.isBlank, !isLooking else { return }
        isLooking = true
        errorMessage = nil
        Task {
            defer { isLooking = false }
            do {
                try await location.setManualArea(matching: text)
                dismiss()
            } catch {
                errorMessage = "Couldn't find that area. Check the spelling or try a nearby city."
            }
        }
    }
}

extension ButtonStyle where Self == SecondaryButtonStyle {
    static func secondary(tint: Color) -> SecondaryButtonStyle { SecondaryButtonStyle(tint: tint) }
}
