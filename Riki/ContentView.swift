//
//  ContentView.swift
//  Riki
//
//  Created by Manik on 5/1/25.
//

import SwiftUI
import Combine
// Import local components

struct ContentView: View {
    @StateObject private var viewModel = WikiViewModel()
    
    var body: some View {
        NavigationView {
            VStack {
                // Content area with fixed height to maintain consistent layout
                ZStack {
                    if viewModel.isLoading {
                        LoadingView()
                    } else if let error = viewModel.error {
                        ErrorView(error: error) {
                            viewModel.fetchRandomArticle()
                        }
                    } else if let article = viewModel.article {
                        ArticleView(article: article)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                
                // Fixed button at bottom
                Button(action: {
                    viewModel.fetchRandomArticle()
                }) {
                    HStack {
                        Image(systemName: "arrow.clockwise")
                        Text("Random Wiki")
                    }
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(8)
                    .padding(.horizontal)
                }
                .padding(.bottom)
            }
            .navigationTitle(viewModel.article?.title ?? "Riki")
        }
        .onAppear {
            viewModel.fetchRandomArticle()
        }
    }
}

// View to display article content
struct ArticleView: View {
    let article: WikiArticle
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Article header with thumbnail if available
                if let thumbnailURL = article.thumbnail {
                    AsyncImage(url: thumbnailURL) { image in
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(maxWidth: .infinity, maxHeight: 200)
                            .clipped()
                    } placeholder: {
                        Rectangle()
                            .fill(Color.gray.opacity(0.3))
                            .frame(maxWidth: .infinity, maxHeight: 200)
                    }
                }
    
                // Article content
                VStack(alignment: .leading, spacing: 12) {
    
                    FormattedTextView(text: article.extract, fontSize: 16, lineSpacing: 6)
                        .padding(.horizontal)
    
                    Divider()
    
                    // Display article sections if available
                    if !article.sections.isEmpty {
                        ForEach(article.sections) { section in
                            VStack(alignment: .leading, spacing: 8) {
                                if !section.title.isEmpty {
                                    Text(section.title)
                                        .font(fontForLevel(section))
                                        .fontWeight(.semibold)
                                        .padding(.top, 8)
                                }
    
                                FormattedTextView(text: section.content, fontSize: 16, lineSpacing: 6)
                            }
                            .padding(.horizontal)
                        }
                    }
    
                    // Source link
                    Link(destination: article.url) {
                        HStack {
                            Image(systemName: "link")
                            Text("View on Wikipedia")
                        }
                        .font(.footnote)
                        .foregroundColor(.blue)
                    }
                    .padding()
                }
            }
        }
        .refreshable {
            // This could be used to refresh the article in the future
        }
    }
    
    // Helper function to determine font based on heading level
    private func fontForLevel(_ section: ArticleSection) -> Font {
        print("Here!")
        switch section.level {
        case 1: return .largeTitle // H1
        case 2: return .title      // H2
        case 3: return .title2     // H3
        case 4: return .title3     // H4
        case 5: return .headline   // H5
        case 6: return .subheadline // H6
        default: return .body       // Default for other levels or 0
        }
    }
}

// Error view
struct ErrorView: View {
    let error: String
    let retryAction: () -> Void
    
    var body: some View {
        VStack {
            Image(systemName: "exclamationmark.triangle")
                .imageScale(.large)
                .foregroundColor(.red)
                .padding()
            Text("Error: \(error)")
                .multilineTextAlignment(.center)
                .padding()
            Button("Try Again") {
                retryAction()
            }
            .padding()
            .background(Color.blue)
            .foregroundColor(.white)
            .cornerRadius(8)
        }
        .padding()
    }
}

// ViewModel to handle data and business logic
class WikiViewModel: ObservableObject {
    @Published var article: WikiArticle? = nil
    @Published var isLoading = false
    @Published var error: String? = nil
    
    private var cancellables = Set<AnyCancellable>()
    
    func fetchRandomArticle() {
        isLoading = true
        error = nil
        article = nil
        
        WikipediaService.shared.fetchRandomArticle()
            .receive(on: DispatchQueue.main)
            .sink(receiveCompletion: { [weak self] completion in
                self?.isLoading = false
                if case .failure(let err) = completion {
                    self?.error = err.localizedDescription
                }
            }, receiveValue: { [weak self] article in
                // Process article content if needed
                self?.processArticleContent(article)
                self?.article = article
            })
            .store(in: &cancellables)
    }
    
    // Process and enhance article content for better display
    private func processArticleContent(_ article: WikiArticle) {
        // This method could be expanded to further process content
        // For example, extracting images, formatting tables, etc.
        
        // If no sections were parsed, try to create some based on paragraphs
        if article.sections.isEmpty && !article.content.isEmpty {
            let paragraphs = article.content.components(separatedBy: "\n\n")
            var processedSections: [ArticleSection] = []
            
            for (index, paragraph) in paragraphs.enumerated() {
                if !paragraph.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    // Create a section for each substantial paragraph
                    processedSections.append(ArticleSection(
                        title: "",
                        level: 0,
                        content: paragraph.trimmingCharacters(in: .whitespacesAndNewlines)
                    ))
                }
            }
            
            // Create a new article with the processed sections
            if !processedSections.isEmpty {
                // Since article is immutable, we need to create a new instance with the updated sections
                let updatedArticle = WikiArticle(
                    id: article.id,
                    title: article.title,
                    extract: article.extract,
                    content: article.content,
                    thumbnail: article.thumbnail,
                    url: article.url,
                    lastModified: article.lastModified,
                    sections: processedSections
                )
                
                // Update the published article property
                self.article = updatedArticle
            }
        }
    }
}

#Preview {
    ContentView()
}
