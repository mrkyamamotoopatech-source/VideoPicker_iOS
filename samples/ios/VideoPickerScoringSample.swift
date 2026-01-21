import SwiftUI

struct VideoPickerScoringSampleView: View {
    @State private var output: String = ""
    @State private var selectedMode: VideoSceneMode = .person

    var body: some View {
        VStack(spacing: 16) {
            Text("VideoPicker Scoring")
                .font(.headline)
            Picker("Scene", selection: $selectedMode) {
                Text("人物").tag(VideoSceneMode.person)
                Text("景色").tag(VideoSceneMode.landscape)
            }
            .pickerStyle(.segmented)
            Button("Analyze Sample Video") {
                analyzeSample()
            }
            ScrollView {
                Text(output)
                    .font(.system(.footnote, design: .monospaced))
            }
        }
        .padding()
    }

    private func analyzeSample() {
        guard let sampleURL = Bundle.main.url(forResource: "sample", withExtension: "mp4") else {
            output = "Sample video not found."
            return
        }
        do {
            let scorer = try VideoPickerScoring()
            let result = try scorer.analyze(url: sampleURL, mode: selectedMode)
            var lines: [String] = []
            lines.append("Mode: \(selectedMode.rawValue)")
            lines.append("Mean:")
            for item in result.mean {
                lines.append("  \(item.id): score=\(String(format: "%.3f", item.score)) raw=\(String(format: "%.5f", item.raw))")
            }
            lines.append("Worst:")
            for item in result.worst {
                lines.append("  \(item.id): score=\(String(format: "%.3f", item.score)) raw=\(String(format: "%.5f", item.raw))")
            }
            output = lines.joined(separator: "\n")
        } catch {
            output = "Analyze failed: \(error)"
        }
    }
}
