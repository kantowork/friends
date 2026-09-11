// MARK: - LegalMarkdownView
import SwiftUI

/// A high-quality SwiftUI view that parses and renders Markdown legal documents
/// into structured native blocks with proper spacing, headings, and line breaks.
public struct LegalMarkdownView: View {
    private let fileName: String
    @State private var blocks: [MarkdownBlock] = []
    @State private var loadError: Bool = false
    @State private var isLoading: Bool = true

    public init(fileName: String) {
        self.fileName = fileName
    }

    public var body: some View {
        Group {
            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if loadError {
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 44))
                        .foregroundColor(.orange)
                    Text("法的ドキュメントを読み込めませんでした。")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    Text("ファイル: \(fileName).md")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding()
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(blocks) { block in
                            renderBlock(block)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
                }
            }
        }
        .onAppear {
            loadAndParseMarkdown()
        }
    }

    // MARK: - Block Rendering

    @ViewBuilder
    private func renderBlock(_ block: MarkdownBlock) -> some View {
        switch block.type {
        case .h1(let text):
            Text(attributedString(from: text))
                .font(.title2.bold())
                .foregroundColor(.primary)
                .padding(.top, 8)
                .padding(.bottom, 12)
                .frame(maxWidth: .infinity, alignment: .leading)

        case .h2(let text):
            Text(attributedString(from: text))
                .font(.title3.bold())
                .foregroundColor(.primary)
                .padding(.top, 24)
                .padding(.bottom, 8)
                .frame(maxWidth: .infinity, alignment: .leading)

        case .h3(let text):
            Text(attributedString(from: text))
                .font(.headline)
                .foregroundColor(.primary)
                .padding(.top, 16)
                .padding(.bottom, 6)
                .frame(maxWidth: .infinity, alignment: .leading)

        case .divider:
            Divider()
                .padding(.vertical, 16)

        case .numberedItem(let number, let content):
            HStack(alignment: .top, spacing: 10) {
                Text(number)
                    .font(.body.monospacedDigit())
                    .bold()
                    .foregroundColor(.secondary)
                    .frame(width: 26, alignment: .trailing)
                Text(attributedString(from: content))
                    .font(.body)
                    .lineSpacing(5)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.vertical, 4)

        case .bulletItem(let content, let indentLevel):
            HStack(alignment: .top, spacing: 8) {
                Circle()
                    .fill(Color.secondary)
                    .frame(width: 5, height: 5)
                    .padding(.top, 8)
                Text(attributedString(from: content))
                    .font(.body)
                    .lineSpacing(5)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.leading, CGFloat(indentLevel * 16 + 8))
            .padding(.vertical, 4)

        case .codeBlock(let code):
            ScrollView(.horizontal, showsIndicators: false) {
                Text(code)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(.primary)
                    .lineSpacing(3)
                    .textSelection(.enabled)
                    .padding(12)
            }
            .background(Color(uiColor: .secondarySystemBackground))
            .cornerRadius(8)
            .padding(.vertical, 6)

        case .quote(let text):
            HStack(spacing: 12) {
                Rectangle()
                    .fill(Color.accentColor.opacity(0.6))
                    .frame(width: 4)
                Text(attributedString(from: text))
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .lineSpacing(4)
            }
            .padding(.vertical, 6)

        case .paragraph(let text):
            Text(attributedString(from: text))
                .font(.body)
                .lineSpacing(5)
                .padding(.vertical, 4)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func attributedString(from text: String) -> AttributedString {
        var options = AttributedString.MarkdownParsingOptions()
        options.interpretedSyntax = .full
        return (try? AttributedString(markdown: text, options: options)) ?? AttributedString(text)
    }

    // MARK: - Loading & Parsing

    private func loadAndParseMarkdown() {
        guard blocks.isEmpty else { return }

        let candidates: [URL?] = [
            Bundle.main.url(forResource: fileName, withExtension: "md"),
            Bundle.main.url(forResource: fileName, withExtension: "md", subdirectory: "legal"),
            Bundle.main.url(forResource: fileName, withExtension: "md", subdirectory: "Resources/legal")
        ]

        guard let targetURL = candidates.compactMap({ $0 }).first else {
            loadError = true
            isLoading = false
            return
        }

        do {
            let markdownString = try String(contentsOf: targetURL, encoding: .utf8)
            self.blocks = parseMarkdown(markdownString)
            self.isLoading = false
        } catch {
            loadError = true
            isLoading = false
        }
    }

    private func parseMarkdown(_ markdown: String) -> [MarkdownBlock] {
        var result: [MarkdownBlock] = []
        let rawLines = markdown.components(separatedBy: .newlines)
        
        var currentParagraphLines: [String] = []
        var isInCodeBlock = false
        var currentCodeLines: [String] = []

        func flushParagraph() {
            guard !currentParagraphLines.isEmpty else { return }
            let text = currentParagraphLines.joined(separator: "\n")
            result.append(MarkdownBlock(type: .paragraph(text)))
            currentParagraphLines.removeAll()
        }

        for rawLine in rawLines {
            let trimmed = rawLine.trimmingCharacters(in: .whitespaces)

            // Code block delimiter
            if trimmed.hasPrefix("```") {
                if isInCodeBlock {
                    // Close code block
                    let code = currentCodeLines.joined(separator: "\n")
                    result.append(MarkdownBlock(type: .codeBlock(code)))
                    currentCodeLines.removeAll()
                    isInCodeBlock = false
                } else {
                    // Start code block
                    flushParagraph()
                    isInCodeBlock = true
                }
                continue
            }

            if isInCodeBlock {
                currentCodeLines.append(rawLine)
                continue
            }

            if trimmed.isEmpty {
                flushParagraph()
                continue
            }

            // 1. Horizontal Rule (---, ***, ___)
            if trimmed == "---" || trimmed == "***" || trimmed == "___" {
                flushParagraph()
                result.append(MarkdownBlock(type: .divider))
                continue
            }

            // 2. Headings (#, ##, ###)
            if trimmed.hasPrefix("### ") {
                flushParagraph()
                let title = String(trimmed.dropFirst(4)).trimmingCharacters(in: .whitespaces)
                result.append(MarkdownBlock(type: .h3(title)))
                continue
            }
            if trimmed.hasPrefix("## ") {
                flushParagraph()
                let title = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                result.append(MarkdownBlock(type: .h2(title)))
                continue
            }
            if trimmed.hasPrefix("# ") {
                flushParagraph()
                let title = String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespaces)
                result.append(MarkdownBlock(type: .h1(title)))
                continue
            }

            // 3. Blockquote (> ...)
            if trimmed.hasPrefix("> ") {
                flushParagraph()
                let quoteText = String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespaces)
                result.append(MarkdownBlock(type: .quote(quoteText)))
                continue
            }

            // 4. Numbered List items (e.g. "1. ", "12. ")
            if let match = trimmed.range(of: #"^(\d+[\.\)])\s+(.*)$"#, options: .regularExpression) {
                flushParagraph()
                let fullString = String(trimmed[match])
                // Extract number and content
                if let dotIndex = fullString.firstIndex(of: ".") ?? fullString.firstIndex(of: ")") {
                    let number = String(fullString[..<fullString.index(after: dotIndex)])
                    let content = String(fullString[fullString.index(after: dotIndex)...]).trimmingCharacters(in: .whitespaces)
                    result.append(MarkdownBlock(type: .numberedItem(number: number, content: content)))
                    continue
                }
            }

            // 5. Bullet List items (e.g. "- ", "* ")
            if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") {
                flushParagraph()
                let leadingSpaces = rawLine.prefix(while: { $0 == " " || $0 == "\t" }).count
                let indentLevel = leadingSpaces / 2
                let content = String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespaces)
                result.append(MarkdownBlock(type: .bulletItem(content: content, indentLevel: indentLevel)))
                continue
            }

            // Regular paragraph line
            currentParagraphLines.append(trimmed)
        }

        if isInCodeBlock {
            let code = currentCodeLines.joined(separator: "\n")
            result.append(MarkdownBlock(type: .codeBlock(code)))
        }

        flushParagraph()
        return result
    }
}

// MARK: - Internal Types

private enum BlockType: Hashable {
    case h1(String)
    case h2(String)
    case h3(String)
    case divider
    case quote(String)
    case codeBlock(String)
    case numberedItem(number: String, content: String)
    case bulletItem(content: String, indentLevel: Int)
    case paragraph(String)
}

private struct MarkdownBlock: Identifiable {
    let id = UUID()
    let type: BlockType
}
