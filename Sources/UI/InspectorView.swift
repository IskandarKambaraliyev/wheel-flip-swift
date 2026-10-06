import SwiftUI

/// Raw fields of the last scroll event and how it was classified. Fed by AppState's
/// inspector timer, which only runs while the disclosure group is expanded.
struct InspectorView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        let sample = state.sample

        if !state.enabled || !state.tapRunning {
            hint("The inspector needs WheelFlip enabled and running.")
        } else if sample == InspectorSample() {
            hint("Scroll with the device you want to inspect.")
        } else {
            field("isContinuous", sample.continuous)
            field("phase", sample.phase)
            field("momentum", sample.momentum)
            field("Line delta", sample.line)
            field("Point delta", sample.point)
            LabeledContent("Classification",
                           value: sample.wasMouse ? "Mouse wheel → inverted" : "Trackpad → passed through")
        }
    }

    private func field(_ name: String, _ value: Int64) -> some View {
        LabeledContent(name) {
            Text(String(value)).monospacedDigit()
        }
    }

    private func hint(_ text: String) -> some View {
        Text(text).foregroundStyle(.secondary)
    }
}
