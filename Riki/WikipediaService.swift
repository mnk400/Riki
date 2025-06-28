//
//  WikipediaService.swift
//  Riki
//
//  Created by Manik on 5/1/25.
//

import Foundation
import Combine
import SwiftSoup

class WikipediaService {
    static let shared = WikipediaService()
    
    private init() {}
    
    func fetchRandomArticle() -> AnyPublisher<WikiArticle, Error> {
        return fetchRandomArticleSummary()
            .flatMap { summaryResponse -> AnyPublisher<WikiArticle, Error> in
                self.fetchFullArticleContent(for: summaryResponse)
                    .map { sections -> WikiArticle in
                        self.createArticleFromSummary(summaryResponse, sections: sections)
                    }
                    .catch { error -> AnyPublisher<WikiArticle, Error> in
                        // If fetching full content fails, return an article with just the summary
                        print("Error fetching full article content: \(error). Falling back to summary.")
                        return Just(self.createArticleFromSummary(summaryResponse, sections: []))
                            .setFailureType(to: Error.self)
                            .eraseToAnyPublisher()
                    }
                    .eraseToAnyPublisher()
            }
            .eraseToAnyPublisher()
    }

    private func fetchRandomArticleSummary() -> AnyPublisher<WikipediaDetailResponse, Error> {
        let randomSummaryURL = "https://en.wikipedia.org/api/rest_v1/page/random/summary"
        
        guard let url = URL(string: randomSummaryURL) else {
            return Fail(error: URLError(.badURL)).eraseToAnyPublisher()
        }
        
        return URLSession.shared.dataTaskPublisher(for: url)
            .tryMap { data, response -> Data in
                guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                    throw URLError(.badServerResponse)
                }
                return data
            }
            .decode(type: WikipediaDetailResponse.self, decoder: JSONDecoder())
            .eraseToAnyPublisher()
    }

    private func fetchFullArticleContent(for summaryResponse: WikipediaDetailResponse) -> AnyPublisher<[ArticleSection], Error> {
        let title = summaryResponse.title
        let parseAPIURLString = "https://en.wikipedia.org/w/api.php?action=parse&page=\(title.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")&prop=text&format=json&origin=*"
        
        guard let fullContentURL = URL(string: parseAPIURLString) else {
            return Fail(error: URLError(.badURL)).eraseToAnyPublisher()
        }
        
        return URLSession.shared.dataTaskPublisher(for: fullContentURL)
            .tryMap { data, response -> Data in
                guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                    throw URLError(.badServerResponse)
                }
                return data
            }
            .tryMap { data -> [ArticleSection] in
                return try self.parseArticleContentResponse(data: data)
            }
            .eraseToAnyPublisher()
    }

    private func parseArticleContentResponse(data: Data) throws -> [ArticleSection] {
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        
        guard let parseData = json?["parse"] as? [String: Any],
              let textData = parseData["text"] as? [String: Any],
              let htmlContent = textData["*"] as? String else {
            // If parsing fails, return empty sections, the caller will handle fallback.
            return [] 
        }
        
        return self.parseHTMLContent(htmlContent)
    }
    
    // Helper method to create a WikiArticle from a summary response
    private func createArticleFromSummary(_ response: WikipediaDetailResponse, sections: [ArticleSection]) -> WikiArticle {
        let dateFormatter = ISO8601DateFormatter()
        let lastModified = response.lastmodified != nil ? dateFormatter.date(from: response.lastmodified!) : nil
        
        let finalSections = sections.isEmpty ? [ArticleSection(title: "", level: 0, content: response.extract)] : sections
        
        return WikiArticle(
            id: response.id,
            title: response.title,
            extract: response.extract,
            content: "",
            thumbnail: response.thumbnail?.source,
            url: response.content_urls.mobile.page,
            lastModified: lastModified,
            sections: finalSections
        )
    }
    
    private func parseHTMLContent(_ htmlString: String) -> [ArticleSection] {
        var sections: [ArticleSection] = []
        do {
            let doc = try SwiftSoup.parse(htmlString)

            let unwantedSelectors = [
            ".infobox", ".thumb", ".toc", ".mw-editsection",
            ".navbox", ".metadata", "table:not(.wikitable)", ".mw-empty-elt",
            ".mw-jump-link", ".mw-parser-output > style",
            "img", ".image", ".mbox", ".ambox", ".tmbox",
            ".vertical-navbox", ".sistersitebox"
            ]
            for selector in unwantedSelectors {
                try doc.select(selector).remove()
            }
            
            guard let content = try doc.select(".mw-parser-output").first() ?? doc.body() else {
                return [ArticleSection(title: "Error", level: 0, content: "Could not find main content area.")]
            }
            
            if let introSection = try extractIntroduction(from: content) {
                sections.append(introSection)
            }
            
            sections.append(contentsOf: try extractSectionsFromHeadings(in: content))
            
            // if sections.isEmpty {
            //     let bodyText = try doc.body()?.text() ?? ""
            //     if !bodyText.isEmpty {
            //         sections.append(ArticleSection(title: "", level: 0, content: bodyText))
            //     }
            // }
        } catch {
            print("Error parsing HTML: \(error)")
            sections.append(ArticleSection(title: "Error", level: 0, content: "Could not parse article content."))
        }
        return sections
    }

    private func extractIntroduction(from content: Element) throws -> ArticleSection? {
        var introText = ""
        // Iterate through the direct children of the main content element
        for element in try content.children() {
            let tagName = try element.tagName().lowercased()
            var isSectionHeading = false

            // Check if the element itself is a heading (h1-h6)
            if tagName.starts(with: "h") && tagName.count == 2 && Int(String(tagName.dropFirst())) != nil {
                isSectionHeading = true
            }
            // Check if the element is a common wrapper for a heading (e.g., <div class="mw-heading"><h2>...</h2></div>)
            else if let hTag = try element.select("h1, h2, h3, h4, h5, h6").first() {
                 let hTagName = try hTag.tagName().lowercased()
                 if hTagName.starts(with: "h") && hTagName.count == 2 && Int(String(hTagName.dropFirst())) != nil {
                    isSectionHeading = true
                 }
            }

            if isSectionHeading {
                break // Stop accumulating intro text when the first section heading is encountered
            }

            // Append the text of the current element to the introText
            // Filter out some common non-content elements that might appear before the first heading
            if try !element.hasClass("shortdescription") && 
               !element.hasClass("hatnote") && 
               !element.hasClass("mw-jump-link") && 
               element.tagName().lowercased() != "meta" && 
               element.tagName().lowercased() != "style" &&
               !element.hasClass("toc") && // Table of contents
               !element.className().contains("infobox") && // Infoboxes
               !element.className().contains("navbox") // Navigation boxes
            {
                let elementText = try formatElementContent(element)
                if !elementText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    introText += elementText + "\n"
                }
            }
        }

        let trimmedIntro = introText.trimmingCharacters(in: .whitespacesAndNewlines)
        // Return an ArticleSection for the introduction with level 0 and an empty title
        return trimmedIntro.isEmpty ? nil : ArticleSection(title: "", level: 0, content: trimmedIntro)
    }

    private func formatElementContent(_ element: Element) throws -> String {
        let tagName = try element.tagName().lowercased()
        
        // Handle unordered lists
        if tagName == "ul" {
            var formattedList = ""
            for listItem in try element.select("li") {
                formattedList += "• " + (try listItem.text()) + "\n"
            }
            return formattedList
        }
        
        // Handle ordered lists
        if tagName == "ol" {
            var formattedList = ""
            let listItems = try element.select("li")
            for (index, listItem) in listItems.enumerated() {
                formattedList += "\(index + 1). " + (try listItem.text()) + "\n"
            }
            return formattedList
        }
        
        // Handle tables
        if tagName == "table" && (try element.hasClass("wikitable")) {
            var tableData: [[String]] = []
            
            // Process header row
            if let headerRow = try element.select("tr").first() {
                var headers: [String] = []
                for header in try headerRow.select("th") {
                    headers.append(try header.text().trimmingCharacters(in: .whitespacesAndNewlines))
                }
                if !headers.isEmpty {
                    tableData.append(headers)
                }
            }
            
            // Process data rows
            for row in try element.select("tr").dropFirst() {
                var rowData: [String] = []
                for cell in try row.select("td") {
                    rowData.append(try cell.text().trimmingCharacters(in: .whitespacesAndNewlines))
                }
                if !rowData.isEmpty {
                    tableData.append(rowData)
                }
            }
            
            // Convert table data to string representation
            if !tableData.isEmpty {
                return "<table>" + tableData.map { row in row.joined(separator: "\t") }.joined(separator: "\n") + "</table>"
            }
        }
        
        // Handle paragraphs and other elements
        return try element.text()
    }

    private func extractSectionsFromHeadings(in content: Element) throws -> [ArticleSection] {
        var sections: [ArticleSection] = []
        var currentSectionTitle: String? = nil
        var currentSectionLevel: Int? = nil
        var currentSectionContent = ""
        var pastIntroPhase = false // Becomes true after the first actual section heading is processed

        // Helper to finalize the current section
        func finalizeCurrentSection() {
            if let title = currentSectionTitle, let level = currentSectionLevel {
                let trimmedContent = currentSectionContent.trimmingCharacters(in: .whitespacesAndNewlines)
                if !title.isEmpty || !trimmedContent.isEmpty { // Add section if it has a non-empty title or content
                    sections.append(ArticleSection(title: title, level: level, content: trimmedContent))
                }
            }
            currentSectionTitle = nil
            currentSectionLevel = nil
            currentSectionContent = ""
        }

        for element in try content.children() {
            var isPotentialHeadingContainer = false
            var actualHeadingTag: Element? = nil
            var identifiedLevel = 0
            var identifiedTitle = ""

            let tagName = try element.tagName().lowercased()

            // Check if the element itself is h1-h6
            if tagName.starts(with: "h") && tagName.count == 2, let level = Int(String(tagName.dropFirst())) {
                isPotentialHeadingContainer = true
                actualHeadingTag = element
                identifiedLevel = level
                identifiedTitle = try element.text()
            } 
            // Check if element contains a h1-h6 (e.g. <div class="mw-heading"><h2>...</h2></div>)
            else if let hTag = try element.select("h1, h2, h3, h4, h5, h6").first() {
                // Ensure this hTag is a primary heading for this element, not deeply nested.
                // A simple check: if the element's direct children include this hTag or its parent.
                var isPrimaryHeading = false
                if element == hTag.parent() || element == hTag { // hTag is direct child or element itself
                    isPrimaryHeading = true
                } else if let hTagParent = hTag.parent(), element == hTagParent.parent() && hTagParent.hasClass("mw-headline") { // Common pattern: div > span.mw-headline > hX
                    isPrimaryHeading = true
                }
                // More specific check for structures like <div class="mw-heading mw-heading2"><h2>Title</h2></div>
                if try element.hasClass("mw-heading") && hTag.parent() == element {
                    isPrimaryHeading = true
                }

                if isPrimaryHeading {
                    let hTagName = try hTag.tagName().lowercased()
                    if let level = Int(String(hTagName.dropFirst())) {
                        isPotentialHeadingContainer = true
                        actualHeadingTag = hTag
                        identifiedLevel = level
                        identifiedTitle = try hTag.text()
                    }
                }
            }

            if isPotentialHeadingContainer {
                // This is the first heading encountered by this function after intro extraction.
                // Or, it's a subsequent heading.
                if !pastIntroPhase {
                    pastIntroPhase = true // We are now processing actual sections
                }
                
                // Finalize the previous section before starting a new one
                finalizeCurrentSection()
                
                currentSectionTitle = identifiedTitle
                currentSectionLevel = identifiedLevel
                // Content will be added from subsequent non-heading elements

            } else {
                // If it's not a heading, and we are past the intro phase (first heading processed)
                // and a section is currently being built (currentSectionTitle != nil)
                if pastIntroPhase, currentSectionTitle != nil {
                    // Filter out some common non-content elements that might appear between sections
                    if try !element.hasClass("shortdescription") && 
                   !element.hasClass("hatnote") && 
                   !element.hasClass("mw-jump-link") && 
                   element.tagName().lowercased() != "meta" && 
                   element.tagName().lowercased() != "style" &&
                   !element.hasClass("toc") &&
                   !element.className().contains("infobox") &&
                   !element.className().contains("navbox")
                {
                    let elementText = try formatElementContent(element)
                    if !elementText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        currentSectionContent += elementText + "\n"
                    }
                }
                }
            }
        }

        // Finalize the last section after the loop
        finalizeCurrentSection()

        return sections
    }
}

struct ContentURLs: Codable {
    let mobile: MobileURL
}

struct MobileURL: Codable {
    let page: URL
}
