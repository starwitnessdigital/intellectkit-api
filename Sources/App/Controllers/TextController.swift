import Vapor

/// Text analysis endpoints.
///
/// POST /v1/text/sentiment   – sentiment scoring via lexicon
/// POST /v1/text/readability – Flesch-Kincaid + ARI readability metrics
/// POST /v1/text/keywords    – top-N keyword extraction
/// POST /v1/text/language    – script and language detection
struct TextController {

    func sentiment(req: Request) async throws -> SentimentResponse {
        let body = try req.content.decode(SentimentRequest.self)
        guard !body.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw Abort(.badRequest, reason: "text must not be empty")
        }
        return analyzeSentiment(body.text)
    }

    func readability(req: Request) async throws -> ReadabilityResponse {
        let body = try req.content.decode(ReadabilityRequest.self)
        guard !body.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw Abort(.badRequest, reason: "text must not be empty")
        }
        return computeReadability(body.text)
    }

    func keywords(req: Request) async throws -> KeywordsResponse {
        let body = try req.content.decode(KeywordsRequest.self)
        guard !body.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw Abort(.badRequest, reason: "text must not be empty")
        }
        let limit = max(1, min(body.limit ?? 10, 100))
        return extractKeywords(body.text, limit: limit)
    }

    func language(req: Request) async throws -> LanguageResponse {
        let body = try req.content.decode(LanguageRequest.self)
        guard !body.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw Abort(.badRequest, reason: "text must not be empty")
        }
        return detectLanguage(body.text)
    }
}

// MARK: - Sentiment Analysis

private extension TextController {

    // Scores: +2 strongly positive, +1 positive, -1 negative, -2 strongly negative
    static let positiveStrong: Set<String> = [
        "excellent", "amazing", "outstanding", "brilliant", "fantastic",
        "perfect", "superb", "extraordinary", "magnificent", "phenomenal",
        "exceptional", "incredible", "remarkable", "wonderful", "delightful",
        "awesome", "marvelous", "splendid", "glorious", "spectacular"
    ]

    static let positiveWeak: Set<String> = [
        "good", "great", "nice", "helpful", "useful", "enjoy", "enjoyed",
        "happy", "pleased", "love", "liked", "positive", "quality", "clean",
        "fast", "reliable", "comfortable", "easy", "effective", "efficient",
        "smart", "beautiful", "friendly", "warm", "cheerful", "inspiring",
        "motivated", "safe", "secure", "improved", "best", "fun", "exciting",
        "creative", "honest", "fair", "kind", "generous", "successful",
        "valuable", "innovative", "elegant", "fresh", "grateful", "thankful",
        "recommend", "recommended", "approved", "praiseworthy", "satisfying",
        "rewarding", "engaging", "interesting", "capable", "skilled",
        "professional", "premium", "superior", "advanced", "modern",
        "smooth", "stable", "consistent", "clear", "intuitive", "polished"
    ]

    static let negativeWeak: Set<String> = [
        "bad", "poor", "slow", "difficult", "disappointing", "negative",
        "boring", "dull", "unclear", "confused", "expensive", "waste",
        "problem", "issue", "concern", "trouble", "uncomfortable",
        "mediocre", "unreliable", "weak", "inconsistent", "cold", "harsh",
        "rude", "spam", "fake", "lacking", "limited", "confusing",
        "frustrating", "annoying", "clunky", "outdated", "messy"
    ]

    static let negativeStrong: Set<String> = [
        "terrible", "awful", "horrible", "dreadful", "disgusting",
        "hate", "loathe", "despise", "worst", "useless", "worthless",
        "dangerous", "harmful", "toxic", "painful", "suffering",
        "fraud", "scam", "failure", "failed", "defective", "broken",
        "destroyed", "attacked", "miserable", "furious", "rage",
        "abysmal", "atrocious", "catastrophic", "disastrous"
    ]

    func analyzeSentiment(_ text: String) -> SentimentResponse {
        let words = tokenize(text)
        var positiveCount = 0
        var negativeCount = 0
        var scoreSum = 0

        for word in words {
            if Self.positiveStrong.contains(word) {
                positiveCount += 1; scoreSum += 2
            } else if Self.positiveWeak.contains(word) {
                positiveCount += 1; scoreSum += 1
            } else if Self.negativeStrong.contains(word) {
                negativeCount += 1; scoreSum -= 2
            } else if Self.negativeWeak.contains(word) {
                negativeCount += 1; scoreSum -= 1
            }
        }

        let total = positiveCount + negativeCount
        let maxPossibleScore = max(total * 2, 1)
        let normalizedScore = Double(scoreSum) / Double(maxPossibleScore)
        let clampedScore = max(-1.0, min(1.0, normalizedScore))

        let sentiment: String
        if clampedScore > 0.1 { sentiment = "positive" }
        else if clampedScore < -0.1 { sentiment = "negative" }
        else { sentiment = "neutral" }

        let confidence: Double
        if words.isEmpty {
            confidence = 0
        } else {
            let coverage = Double(total) / Double(words.count)
            let polarityStrength = abs(clampedScore)
            confidence = min(1.0, (coverage * 0.5 + polarityStrength * 0.5))
        }

        return SentimentResponse(
            sentiment: sentiment,
            score: (clampedScore * 100).rounded() / 100,
            confidence: (confidence * 100).rounded() / 100,
            positive: positiveCount,
            negative: negativeCount,
            wordCount: words.count
        )
    }
}

// MARK: - Readability

private extension TextController {

    func computeReadability(_ text: String) -> ReadabilityResponse {
        let sentences = countSentences(text)
        let words = tokenize(text)
        let wordCount = words.count
        let syllableTotal = words.map { syllableCount($0) }.reduce(0, +)
        let charCount = words.joined().count

        guard wordCount > 0 && sentences > 0 else {
            return ReadabilityResponse(
                fleschReadingEase: 0, fleschKincaidGrade: 0,
                automatedReadabilityIndex: 0, level: "insufficient text",
                sentences: sentences, words: wordCount, syllables: syllableTotal,
                avgWordsPerSentence: 0, avgSyllablesPerWord: 0
            )
        }

        let wpS = Double(wordCount) / Double(sentences)
        let spW = Double(syllableTotal) / Double(wordCount)
        let cpW = Double(charCount) / Double(wordCount)

        let fre = 206.835 - 1.015 * wpS - 84.6 * spW
        let fkg = 0.39 * wpS + 11.8 * spW - 15.59
        let ari = 4.71 * cpW + 0.5 * wpS - 21.43

        let clampedFRE = max(0, min(100, fre))
        let level = readabilityLevel(fre: clampedFRE)

        return ReadabilityResponse(
            fleschReadingEase: (clampedFRE * 10).rounded() / 10,
            fleschKincaidGrade: (fkg * 10).rounded() / 10,
            automatedReadabilityIndex: (ari * 10).rounded() / 10,
            level: level,
            sentences: sentences,
            words: wordCount,
            syllables: syllableTotal,
            avgWordsPerSentence: (wpS * 10).rounded() / 10,
            avgSyllablesPerWord: (spW * 100).rounded() / 100
        )
    }

    func countSentences(_ text: String) -> Int {
        let terminators = CharacterSet(charactersIn: ".!?")
        let count = text.unicodeScalars.filter { terminators.contains($0) }.count
        return max(1, count)
    }

    func syllableCount(_ word: String) -> Int {
        let lower = word.lowercased().filter { "aeiouy".contains($0) || $0.isLetter }
        guard !lower.isEmpty else { return 1 }
        let vowels = CharacterSet(charactersIn: "aeiouy")
        var count = 0
        var prevWasVowel = false
        for scalar in lower.unicodeScalars {
            let isVowel = vowels.contains(scalar)
            if isVowel && !prevWasVowel { count += 1 }
            prevWasVowel = isVowel
        }
        // Drop silent trailing 'e'
        if lower.hasSuffix("e") && lower.count > 2 && count > 1 { count -= 1 }
        return max(1, count)
    }

    func readabilityLevel(fre: Double) -> String {
        switch fre {
        case 90...:       return "5th grade"
        case 80..<90:     return "6th grade"
        case 70..<80:     return "7th grade"
        case 60..<70:     return "8th–9th grade"
        case 50..<60:     return "10th–12th grade"
        case 30..<50:     return "college"
        default:          return "professional"
        }
    }
}

// MARK: - Keywords

private extension TextController {

    static let englishStopwords: Set<String> = [
        "a", "an", "the", "and", "or", "but", "in", "on", "at", "to", "for",
        "of", "with", "by", "from", "up", "about", "into", "through", "during",
        "is", "are", "was", "were", "be", "been", "being", "have", "has", "had",
        "do", "does", "did", "will", "would", "shall", "should", "may", "might",
        "must", "can", "could", "not", "no", "nor", "so", "yet", "both",
        "either", "neither", "each", "few", "more", "most", "other", "some",
        "such", "than", "too", "very", "just", "this", "that", "these", "those",
        "i", "me", "my", "myself", "we", "our", "you", "your", "he", "she",
        "it", "its", "they", "them", "their", "what", "which", "who", "whom",
        "when", "where", "why", "how", "all", "any", "both", "if", "then",
        "as", "also", "well", "even", "like", "get", "got", "let", "us",
        "there", "here", "only", "over", "after", "before", "between",
        "while", "because", "though", "although", "however", "therefore"
    ]

    func extractKeywords(_ text: String, limit: Int) -> KeywordsResponse {
        let words = tokenize(text)
        let filtered = words.filter {
            $0.count >= 3 && !Self.englishStopwords.contains($0)
        }

        var freq: [String: Int] = [:]
        for word in filtered { freq[word, default: 0] += 1 }

        let maxFreq = Double(freq.values.max() ?? 1)
        let sorted = freq.sorted { $0.value > $1.value }.prefix(limit)

        let results = sorted.map { (word, count) in
            KeywordResult(
                keyword: word,
                frequency: count,
                score: (Double(count) / maxFreq * 100).rounded() / 100
            )
        }

        return KeywordsResponse(
            keywords: results,
            totalWords: words.count,
            uniqueWords: freq.count
        )
    }
}

// MARK: - Language Detection

private extension TextController {

    struct LanguageProfile {
        let name: String
        let code: String
        let stopwords: Set<String>
    }

    static let languageProfiles: [LanguageProfile] = [
        LanguageProfile(name: "English", code: "en", stopwords: [
            "the", "and", "is", "in", "to", "of", "a", "that", "it", "was",
            "for", "on", "are", "as", "with", "his", "they", "at", "be",
            "this", "have", "from", "or", "had", "by", "not", "but", "what",
            "all", "were", "we", "when", "your", "can", "said", "there",
            "use", "an", "each", "which", "she", "do", "how", "their", "if"
        ]),
        LanguageProfile(name: "Spanish", code: "es", stopwords: [
            "de", "la", "que", "el", "en", "y", "a", "los", "del", "se",
            "las", "un", "por", "con", "no", "una", "su", "para", "es", "al",
            "lo", "como", "más", "pero", "sus", "le", "ya", "o", "este",
            "porque", "cuando", "muy", "sin", "sobre", "también", "hasta",
            "hay", "donde", "quien", "desde", "todo", "nos", "durante"
        ]),
        LanguageProfile(name: "French", code: "fr", stopwords: [
            "de", "la", "le", "les", "et", "en", "un", "une", "du", "des",
            "est", "que", "il", "se", "qui", "pas", "sur", "au", "ce", "par",
            "ne", "je", "son", "ou", "mais", "nous", "vous", "si", "leur",
            "elle", "très", "tout", "bien", "aussi", "dans", "avec", "plus",
            "même", "ainsi", "puis", "après", "avant", "sous", "entre"
        ]),
        LanguageProfile(name: "German", code: "de", stopwords: [
            "der", "die", "und", "in", "den", "von", "zu", "das", "mit",
            "sich", "des", "auf", "für", "ist", "im", "dem", "nicht", "ein",
            "eine", "als", "auch", "es", "an", "werden", "aus", "er", "hat",
            "dass", "sie", "nach", "bei", "noch", "bis", "war", "aber",
            "oder", "sein", "wenn", "schon", "mehr", "durch", "wie", "über"
        ]),
        LanguageProfile(name: "Italian", code: "it", stopwords: [
            "di", "che", "e", "in", "la", "il", "un", "a", "per", "si",
            "del", "una", "i", "non", "con", "le", "da", "sono", "come",
            "ha", "lo", "ma", "al", "ci", "o", "anche", "se", "questo",
            "più", "tutto", "quando", "loro", "dopo", "ancora", "poi",
            "però", "sempre", "così", "tra", "suo", "sulla", "quello"
        ]),
        LanguageProfile(name: "Portuguese", code: "pt", stopwords: [
            "de", "a", "que", "e", "do", "da", "em", "um", "para", "com",
            "uma", "os", "no", "se", "na", "por", "mais", "as", "dos",
            "como", "mas", "ao", "ele", "das", "seu", "sua", "ou", "ser",
            "quando", "muito", "nos", "já", "também", "só", "mesmo", "isso"
        ]),
        LanguageProfile(name: "Dutch", code: "nl", stopwords: [
            "de", "en", "van", "ik", "te", "dat", "die", "in", "een", "hij",
            "het", "niet", "zijn", "is", "was", "op", "aan", "met", "als",
            "voor", "had", "er", "maar", "om", "hem", "dan", "zou", "of",
            "wat", "mijn", "men", "dit", "zo", "door", "over", "ze", "bij"
        ]),
    ]

    func detectLanguage(_ text: String) -> LanguageResponse {
        let scalars = Array(text.unicodeScalars)
        let total = scalars.count
        guard total > 0 else {
            return LanguageResponse(language: "Unknown", code: "und", script: "Unknown", confidence: 0)
        }

        // Script detection via Unicode ranges
        func fraction(_ range: ClosedRange<UInt32>) -> Double {
            Double(scalars.filter { range.contains($0.value) }.count) / Double(total)
        }

        if fraction(0x4E00...0x9FFF) + fraction(0x3400...0x4DBF) > 0.15 {
            return LanguageResponse(language: "Chinese", code: "zh", script: "Han", confidence: 0.90)
        }
        if fraction(0x3040...0x30FF) > 0.10 {
            return LanguageResponse(language: "Japanese", code: "ja", script: "Japanese", confidence: 0.90)
        }
        if fraction(0xAC00...0xD7AF) > 0.10 {
            return LanguageResponse(language: "Korean", code: "ko", script: "Hangul", confidence: 0.90)
        }
        if fraction(0x0600...0x06FF) > 0.10 {
            return LanguageResponse(language: "Arabic", code: "ar", script: "Arabic", confidence: 0.90)
        }
        if fraction(0x0400...0x04FF) > 0.10 {
            return LanguageResponse(language: "Russian", code: "ru", script: "Cyrillic", confidence: 0.85)
        }
        if fraction(0x0900...0x097F) > 0.10 {
            return LanguageResponse(language: "Hindi", code: "hi", script: "Devanagari", confidence: 0.85)
        }
        if fraction(0x0590...0x05FF) > 0.10 {
            return LanguageResponse(language: "Hebrew", code: "he", script: "Hebrew", confidence: 0.85)
        }
        if fraction(0x0E00...0x0E7F) > 0.10 {
            return LanguageResponse(language: "Thai", code: "th", script: "Thai", confidence: 0.90)
        }

        // Latin-script: score by stopword frequency
        let words = Set(tokenize(text))
        var scores: [(profile: LanguageProfile, hits: Int)] = Self.languageProfiles.map { profile in
            let hits = words.intersection(profile.stopwords).count
            return (profile, hits)
        }
        scores.sort { $0.hits > $1.hits }

        let top = scores[0]
        let second = scores.count > 1 ? scores[1].hits : 0

        guard top.hits > 0 else {
            return LanguageResponse(language: "Unknown", code: "und", script: "Latin", confidence: 0.1)
        }

        let confidence: Double
        if second == 0 {
            confidence = min(0.99, 0.5 + Double(top.hits) * 0.05)
        } else {
            let ratio = Double(top.hits) / Double(top.hits + second)
            confidence = min(0.99, ratio * 0.9)
        }

        return LanguageResponse(
            language: top.profile.name,
            code: top.profile.code,
            script: "Latin",
            confidence: (confidence * 100).rounded() / 100
        )
    }
}

// MARK: - Shared Tokenizer

private extension TextController {
    func tokenize(_ text: String) -> [String] {
        text.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
    }
}
