import SwiftUI

/// Paste a second JSON document here (e.g. appsecrets.json) to deep-merge
/// into Input (e.g. appsettings.json). Matching keys recurse and the
/// pasted JSON wins on conflicts; everything else is kept from both sides.
struct MergeSheetView: View {
    @Binding var overlayText: String
    let onMerge: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Merge into Input")
                .font(.title3).bold()
            Text("Paste a second JSON below (e.g. appsecrets.json). Its values fill in or override matching keys in Input (e.g. appsettings.json); everything else from both sides is kept.")
                .font(.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            CodeEditor(text: $overlayText)
                .frame(minHeight: 320)
                .border(Color.gray.opacity(0.3))

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Merge → Output") {
                    onMerge(overlayText)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(overlayText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding()
        .frame(minWidth: 560, minHeight: 440)
    }
}
