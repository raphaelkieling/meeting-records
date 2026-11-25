import SwiftUI

struct ChatMarkdownView: View, Equatable {
    let markdown: String

    private enum Block {
        case body(String), heading(String), item(String, String), code(String)
    }

    private var blocks: [Block] {
        var blocks: [Block] = []
        var code: [String]?
        for raw in markdown.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("```") {
                if let lines = code {
                    blocks.append(.code(lines.joined(separator: "\n")))
                    code = nil
                } else {
                    code = []
                }
            } else if code != nil {
                code?.append(raw)
            } else if line.hasPrefix("#"), let space = line.firstIndex(of: " "),
                      line[..<space].allSatisfy({ $0 == "#" }) {
                blocks.append(.heading(String(line[line.index(after: space)...])))
            } else if line.hasPrefix("- ") || line.hasPrefix("* ") || line.hasPrefix("+ ") {
                blocks.append(.item("•", String(line.dropFirst(2))))
            } else if let marker = line.range(of: #"^\d+\. "#, options: .regularExpression) {
                blocks.append(.item(String(line[marker]).trimmingCharacters(in: .whitespaces),
                                    String(line[marker.upperBound...])))
            } else if !line.isEmpty {
                blocks.append(.body(line))
            }
        }
        if let code, !code.isEmpty { blocks.append(.code(code.joined(separator: "\n"))) }
        return blocks
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                switch block {
                case .body(let line): formatted(line)
                case .heading(let line):
                    formatted(line).font(.headline).accessibilityAddTraits(.isHeader)
                case .item(let marker, let line):
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(marker).foregroundStyle(.secondary)
                        formatted(line)
                    }
                case .code(let code):
                    Text(verbatim: code)
                        .font(.system(.callout, design: .monospaced))
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
                }
            }
        }
        .textSelection(.enabled)
    }

    private func formatted(_ text: String) -> Text {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        guard var value = try? AttributedString(markdown: text, options: options) else { return Text(verbatim: text) }
        let links = value.runs.filter { $0.link != nil }.map(\.range)
        for range in links { value[range].link = nil }
        return Text(value)
    }
}
