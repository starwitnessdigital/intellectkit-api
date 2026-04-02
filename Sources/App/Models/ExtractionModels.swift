import Vapor

// MARK: - Article Extraction

struct ArticleExtractionResponse: Content {
    let url: String
    let title: String?
    let author: String?
    let publishedDate: String?
    let bodyText: String
    let images: [String]
    let wordCount: Int
    let readingTimeMinutes: Int
    let summary: String
    let extractedAt: String
}

// MARK: - Product Extraction

struct ProductExtractionResponse: Content {
    let url: String
    let name: String?
    let price: String?
    let currency: String?
    let description: String?
    let images: [String]
    let brand: String?
    let availability: String?
    let ratingValue: String?
    let reviewCount: String?
    let extractedAt: String
}

// MARK: - Metadata Extraction

struct MetadataExtractionResponse: Content {
    let url: String
    let title: String?
    let description: String?
    let ogTags: [String: String]
    let twitterTags: [String: String]
    let canonicalURL: String?
    let language: String?
    let favicon: String?
    let jsonLD: [String]
    let extractedAt: String
}

// MARK: - Links Extraction

struct ExtractedLink: Content {
    let href: String
    let text: String
    let rel: String?
    let isExternal: Bool
}

struct LinksExtractionResponse: Content {
    let url: String
    let totalLinks: Int
    let internalLinks: Int
    let externalLinks: Int
    let links: [ExtractedLink]
    let extractedAt: String
}

// MARK: - Text Extraction

struct TextExtractionResponse: Content {
    let url: String
    let text: String
    let wordCount: Int
    let characterCount: Int
    let extractedAt: String
}
