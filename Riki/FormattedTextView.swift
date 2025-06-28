//
//  FormattedTextView.swift
//  Riki
//
//  Created by Manik on 5/1/25.
//

import SwiftUI

struct TableView: View {
    let rows: [[String]]
    
    var body: some View {
        ScrollView(.horizontal) {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(rows.indices, id: \.self) { rowIndex in
                    HStack(spacing: 16) {
                        ForEach(rows[rowIndex].indices, id: \.self) { colIndex in
                            Text(rows[rowIndex][colIndex])
                                .padding(8)
                                .frame(minWidth: 100, alignment: .leading)
                                .background(rowIndex == 0 ? Color.gray.opacity(0.2) : Color.clear)
                                .border(Color.gray.opacity(0.3))
                        }
                    }
                }
            }
            .padding()
        }
    }
}

struct FormattedTextView: View {
    let text: String
    let fontSize: CGFloat
    let lineSpacing: CGFloat
    
    init(text: String, fontSize: CGFloat = 16, lineSpacing: CGFloat = 5) {
        self.text = text
        self.fontSize = fontSize
        self.lineSpacing = lineSpacing
    }
    
    var body: some View {
        let components = parseComponents(text)
        VStack(alignment: .leading, spacing: lineSpacing) {
            ForEach(components.indices, id: \.self) { index in
                switch components[index] {
                case .text(let content):
                    Text(formatText(content))
                        .font(.system(size: fontSize))
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                        .multilineTextAlignment(.leading)
                case .table(let rows):
                    TableView(rows: rows)
                }
            }
        }
    }
    
    // Component types for mixed content rendering
    enum Component {
        case text(String)
        case table([[String]])
    }
    
    // Parse text into components (regular text and tables)
    private func parseComponents(_ input: String) -> [Component] {
        var components: [Component] = []
        let parts = input.components(separatedBy: "<table>")
        
        for (index, part) in parts.enumerated() {
            if index == 0 && !part.isEmpty {
                components.append(.text(part))
                continue
            }
            
            if let tableEndIndex = part.range(of: "</table>")?.lowerBound {
                let tableContent = String(part[..<tableEndIndex])
                let rows = tableContent.components(separatedBy: .newlines)
                    .filter { !$0.isEmpty }
                    .map { $0.components(separatedBy: "\t") }
                
                if !rows.isEmpty {
                    components.append(.table(rows))
                }
                
                let remainingText = String(part[part.index(after: tableEndIndex)...])
                if !remainingText.isEmpty {
                    components.append(.text(remainingText))
                }
            } else {
                components.append(.text(part))
            }
        }
        
        return components
    }
    
    // Format text by removing any remaining HTML tags and normalizing whitespace
    private func formatText(_ input: String) -> String {
        let formatted = input
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        
        return formatted.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// Extension to handle attributed text if needed in the future
extension FormattedTextView {
    func attributedText(_ input: String) -> AttributedString {
        let attributedString = AttributedString(input)
        return attributedString
    }
}

#Preview {
    FormattedTextView(text: "This is a sample Wikipedia article with some **bold** and *italic* text.")
        .padding()
}
