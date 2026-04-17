import SwiftUI
import WebKit
import OatsCore

// MARK: - Notes side panel

struct NotesPanelView: View {
    let noteTitle: String
    let markdown: String
    @EnvironmentObject var store: TodoStore

    var body: some View {
        VStack(spacing: 0) {

            // ── Header ────────────────────────────────────────────────────
            HStack(spacing: 8) {
                Image(systemName: "doc.text.fill")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.granolaGreen)

                Text(noteTitle)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer()

                Button {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        store.showingNoteId = nil
                    }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.textSecondary)
                        .frame(width: 20, height: 20)
                        .background(Color.creamHover, in: RoundedRectangle(cornerRadius: 5))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)

            Divider()
                .background(Color.creamDivider)

            // ── Markdown body ─────────────────────────────────────────────
            MarkdownWebView(markdown: markdown)
        }
        .background(Color.cream)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .preferredColorScheme(.light)
    }
}

// MARK: - WKWebView markdown renderer

struct MarkdownWebView: NSViewRepresentable {
    let markdown: String

    func makeNSView(context: Context) -> WKWebView {
        let prefs = WKWebpagePreferences()
        prefs.allowsContentJavaScript = false
        let config = WKWebViewConfiguration()
        config.defaultWebpagePreferences = prefs
        let wv = WKWebView(frame: .zero, configuration: config)
        wv.setValue(false, forKey: "drawsBackground")
        return wv
    }

    func updateNSView(_ wv: WKWebView, context: Context) {
        wv.loadHTMLString(buildHTML(), baseURL: nil)
    }

    // MARK: - HTML

    private func buildHTML() -> String {
        """
        <!DOCTYPE html><html><head><meta charset="UTF-8">
        <style>
        * { box-sizing: border-box; }
        body {
            font-family: -apple-system, BlinkMacSystemFont, sans-serif;
            font-size: 13px; line-height: 1.65;
            color: #28261F; background: #ECE7D9;
            margin: 0; padding: 14px 16px 24px;
        }
        h1 { font-size: 15px; font-weight: 700; margin: 18px 0 6px; }
        h2 { font-size: 13.5px; font-weight: 650; margin: 16px 0 5px; color: #28261F; }
        h3 { font-size: 13px; font-weight: 600; margin: 12px 0 4px; color: #3a3830; }
        p  { margin: 5px 0 8px; }
        ul, ol { padding-left: 18px; margin: 4px 0 8px; }
        li { margin: 3px 0; }
        strong { font-weight: 650; }
        em { font-style: italic; color: #3a3830; }
        code {
            font-family: 'SF Mono', 'Menlo', monospace;
            font-size: 11px;
            background: #D4CDB8; color: #28261F;
            padding: 1px 5px; border-radius: 3px;
        }
        hr { border: none; border-top: 1px solid #D4CDB8; margin: 14px 0; }
        blockquote {
            border-left: 3px solid #507A46;
            margin: 8px 0; padding: 2px 0 2px 12px;
            color: #A8A39A;
        }
        a { color: #507A46; text-decoration: none; }
        a:hover { text-decoration: underline; }
        ::-webkit-scrollbar { width: 6px; }
        ::-webkit-scrollbar-track { background: transparent; }
        ::-webkit-scrollbar-thumb { background: #D4CDB8; border-radius: 3px; }
        </style></head><body>
        \(markdownToHTML(markdown))
        </body></html>
        """
    }

    // MARK: - Markdown → HTML

    private func markdownToHTML(_ md: String) -> String {
        let lines = md.components(separatedBy: "\n")
        var html  = ""
        var inUL  = false
        var inOL  = false

        func closeLists() {
            if inUL { html += "</ul>\n"; inUL = false }
            if inOL { html += "</ol>\n"; inOL = false }
        }

        for line in lines {
            // Headings
            if line.hasPrefix("#### ") {
                closeLists()
                html += "<h3>\(inline(String(line.dropFirst(5))))</h3>\n"
            } else if line.hasPrefix("### ") {
                closeLists()
                html += "<h3>\(inline(String(line.dropFirst(4))))</h3>\n"
            } else if line.hasPrefix("## ") {
                closeLists()
                html += "<h2>\(inline(String(line.dropFirst(3))))</h2>\n"
            } else if line.hasPrefix("# ") {
                closeLists()
                html += "<h1>\(inline(String(line.dropFirst(2))))</h1>\n"
            // Unordered list
            } else if line.hasPrefix("- ") || line.hasPrefix("* ") || line.hasPrefix("• ") {
                if !inUL { closeLists(); html += "<ul>\n"; inUL = true }
                html += "<li>\(inline(String(line.dropFirst(2))))</li>\n"
            // Ordered list
            } else if line.range(of: #"^\d+[\.\)]\s"#, options: .regularExpression) != nil {
                let content = line.replacingOccurrences(of: #"^\d+[\.\)]\s+"#,
                                                        with: "",
                                                        options: .regularExpression)
                if !inOL { closeLists(); html += "<ol>\n"; inOL = true }
                html += "<li>\(inline(content))</li>\n"
            // Blockquote
            } else if line.hasPrefix("> ") {
                closeLists()
                html += "<blockquote>\(inline(String(line.dropFirst(2))))</blockquote>\n"
            // Horizontal rule
            } else if line == "---" || line == "***" || line == "___" {
                closeLists()
                html += "<hr>\n"
            // Blank line
            } else if line.trimmingCharacters(in: .whitespaces).isEmpty {
                closeLists()
                html += "\n"
            // Paragraph
            } else {
                closeLists()
                html += "<p>\(inline(line))</p>\n"
            }
        }
        closeLists()
        return html
    }

    /// Escape HTML special chars then apply inline markdown (bold, italic, code, links).
    private func inline(_ raw: String) -> String {
        var s = raw
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")

        // Inline code (before bold/italic so backticks aren't mangled)
        s = s.replacingOccurrences(of: #"`([^`]+)`"#,
                                   with: "<code>$1</code>",
                                   options: .regularExpression)
        // Bold
        s = s.replacingOccurrences(of: #"\*\*(.+?)\*\*"#,
                                   with: "<strong>$1</strong>",
                                   options: .regularExpression)
        s = s.replacingOccurrences(of: #"__(.+?)__"#,
                                   with: "<strong>$1</strong>",
                                   options: .regularExpression)
        // Italic
        s = s.replacingOccurrences(of: #"\*([^\*]+)\*"#,
                                   with: "<em>$1</em>",
                                   options: .regularExpression)
        s = s.replacingOccurrences(of: #"(?<![_])_([^_]+)_(?![_])"#,
                                   with: "<em>$1</em>",
                                   options: .regularExpression)
        // Links [text](url)
        s = s.replacingOccurrences(of: #"\[([^\]]+)\]\(([^)]+)\)"#,
                                   with: "<a href=\"$2\">$1</a>",
                                   options: .regularExpression)
        return s
    }
}
