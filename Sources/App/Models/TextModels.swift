import Vapor

// MARK: - Sentiment

struct SentimentRequest: Content {
    let text: String
}

struct SentimentResponse: Content {
    let sentiment: String      // "positive", "negative", "neutral"
    let score: Double          // -1.0 to 1.0
    let confidence: Double     // 0.0 to 1.0
    let positive: Int          // count of positive signals
    let negative: Int          // count of negative signals
    let wordCount: Int
}

// MARK: - Readability

struct ReadabilityRequest: Content {
    let text: String
}

struct ReadabilityResponse: Content {
    let fleschReadingEase: Double
    let fleschKincaidGrade: Double
    let automatedReadabilityIndex: Double
    let level: String          // "5th grade", "college", etc.
    let sentences: Int
    let words: Int
    let syllables: Int
    let avgWordsPerSentence: Double
    let avgSyllablesPerWord: Double
}

// MARK: - Keywords

struct KeywordsRequest: Content {
    let text: String
    let limit: Int?
}

struct KeywordsResponse: Content {
    let keywords: [KeywordResult]
    let totalWords: Int
    let uniqueWords: Int
}

struct KeywordResult: Content {
    let keyword: String
    let frequency: Int
    let score: Double          // relative frequency 0.0–1.0
}

// MARK: - Language

struct LanguageRequest: Content {
    let text: String
}

struct LanguageResponse: Content {
    let language: String       // "English"
    let code: String           // "en"
    let script: String         // "Latin", "Cyrillic", "Arabic", etc.
    let confidence: Double     // 0.0 to 1.0
}
