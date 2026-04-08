@testable import App
import XCTVapor

final class TextControllerTests: XCTestCase {

    // MARK: - Helpers

    private func makeApp() async throws -> Application {
        let app = try await Application.make(.testing)
        try await configure(app)
        return app
    }

    private var apiKey: HTTPHeaders { ["X-API-Key": "ik_free_demo_key_123"] }

    // MARK: - Sentiment

    func testSentimentPositive() async throws {
        let app = try await makeApp()
        defer { Task { try await app.asyncShutdown() } }

        try await app.test(.POST, "v1/text/sentiment", headers: apiKey, beforeRequest: { req in
            try req.content.encode(SentimentRequest(text: "This product is absolutely amazing and excellent! I love it."))
        }) { res async in
            XCTAssertEqual(res.status, .ok)
            let body = try? res.content.decode(SentimentResponse.self)
            XCTAssertEqual(body?.sentiment, "positive")
            XCTAssertGreaterThan(body?.score ?? 0, 0.0)
        }
    }

    func testSentimentNegative() async throws {
        let app = try await makeApp()
        defer { Task { try await app.asyncShutdown() } }

        try await app.test(.POST, "v1/text/sentiment", headers: apiKey, beforeRequest: { req in
            try req.content.encode(SentimentRequest(text: "This is terrible and awful. I hate it. Worst experience ever."))
        }) { res async in
            XCTAssertEqual(res.status, .ok)
            let body = try? res.content.decode(SentimentResponse.self)
            XCTAssertEqual(body?.sentiment, "negative")
            XCTAssertLessThan(body?.score ?? 0, 0.0)
        }
    }

    func testSentimentEmptyTextReturns400() async throws {
        let app = try await makeApp()
        defer { Task { try await app.asyncShutdown() } }

        try await app.test(.POST, "v1/text/sentiment", headers: apiKey, beforeRequest: { req in
            try req.content.encode(SentimentRequest(text: "   "))
        }) { res async in
            XCTAssertEqual(res.status, .badRequest)
        }
    }

    // MARK: - Readability

    func testReadabilitySimpleText() async throws {
        let app = try await makeApp()
        defer { Task { try await app.asyncShutdown() } }

        let simpleText = "The cat sat on the mat. The dog ran fast. It was fun."
        try await app.test(.POST, "v1/text/readability", headers: apiKey, beforeRequest: { req in
            try req.content.encode(ReadabilityRequest(text: simpleText))
        }) { res async in
            XCTAssertEqual(res.status, .ok)
            let body = try? res.content.decode(ReadabilityResponse.self)
            XCTAssertNotNil(body)
            XCTAssertGreaterThan(body?.fleschReadingEase ?? 0, 60.0)
            XCTAssertEqual(body?.sentences, 3)
            XCTAssertGreaterThan(body?.words ?? 0, 0)
        }
    }

    func testReadabilityComplexText() async throws {
        let app = try await makeApp()
        defer { Task { try await app.asyncShutdown() } }

        let complexText = "The epistemological implications of postmodern deconstruction fundamentally challenge the ontological presuppositions underlying contemporary philosophical discourse. Hegemonic institutional frameworks perpetuate socioeconomic stratification through systematic disenfranchisement."
        try await app.test(.POST, "v1/text/readability", headers: apiKey, beforeRequest: { req in
            try req.content.encode(ReadabilityRequest(text: complexText))
        }) { res async in
            XCTAssertEqual(res.status, .ok)
            let body = try? res.content.decode(ReadabilityResponse.self)
            XCTAssertNotNil(body)
            // Complex text should have lower Flesch reading ease
            XCTAssertLessThan(body?.fleschReadingEase ?? 100, 50.0)
        }
    }

    // MARK: - Keywords

    func testKeywordsExtraction() async throws {
        let app = try await makeApp()
        defer { Task { try await app.asyncShutdown() } }

        let text = "Swift programming language is great. Swift is fast and reliable. Programming in Swift is fun."
        try await app.test(.POST, "v1/text/keywords", headers: apiKey, beforeRequest: { req in
            try req.content.encode(KeywordsRequest(text: text, limit: 5))
        }) { res async in
            XCTAssertEqual(res.status, .ok)
            let body = try? res.content.decode(KeywordsResponse.self)
            XCTAssertNotNil(body)
            XCTAssertGreaterThan(body?.keywords.count ?? 0, 0)
            // "swift" should be the top keyword
            XCTAssertEqual(body?.keywords.first?.keyword, "swift")
            XCTAssertGreaterThanOrEqual(body?.keywords.first?.frequency ?? 0, 3)
        }
    }

    func testKeywordsDefaultLimit() async throws {
        let app = try await makeApp()
        defer { Task { try await app.asyncShutdown() } }

        let text = Array(repeating: "apple banana cherry date elderberry fig grape honeydew kiwi lemon", count: 3).joined(separator: " ")
        try await app.test(.POST, "v1/text/keywords", headers: apiKey, beforeRequest: { req in
            try req.content.encode(KeywordsRequest(text: text, limit: nil))
        }) { res async in
            XCTAssertEqual(res.status, .ok)
            let body = try? res.content.decode(KeywordsResponse.self)
            XCTAssertNotNil(body)
            XCTAssertLessThanOrEqual(body?.keywords.count ?? 11, 10)
        }
    }

    // MARK: - Language Detection

    func testLanguageEnglish() async throws {
        let app = try await makeApp()
        defer { Task { try await app.asyncShutdown() } }

        let text = "The quick brown fox jumps over the lazy dog. It was a bright cold day in April and the clocks were striking thirteen."
        try await app.test(.POST, "v1/text/language", headers: apiKey, beforeRequest: { req in
            try req.content.encode(LanguageRequest(text: text))
        }) { res async in
            XCTAssertEqual(res.status, .ok)
            let body = try? res.content.decode(LanguageResponse.self)
            XCTAssertEqual(body?.code, "en")
            XCTAssertEqual(body?.script, "Latin")
        }
    }

    func testLanguageChinese() async throws {
        let app = try await makeApp()
        defer { Task { try await app.asyncShutdown() } }

        try await app.test(.POST, "v1/text/language", headers: apiKey, beforeRequest: { req in
            try req.content.encode(LanguageRequest(text: "你好世界。这是一个测试文本，用于检测中文语言。"))
        }) { res async in
            XCTAssertEqual(res.status, .ok)
            let body = try? res.content.decode(LanguageResponse.self)
            XCTAssertEqual(body?.code, "zh")
        }
    }

    func testLanguageSpanish() async throws {
        let app = try await makeApp()
        defer { Task { try await app.asyncShutdown() } }

        let text = "Hola, ¿cómo estás? El sol brilla en el cielo azul. Los niños juegan en el parque con sus amigos."
        try await app.test(.POST, "v1/text/language", headers: apiKey, beforeRequest: { req in
            try req.content.encode(LanguageRequest(text: text))
        }) { res async in
            XCTAssertEqual(res.status, .ok)
            let body = try? res.content.decode(LanguageResponse.self)
            XCTAssertEqual(body?.code, "es")
        }
    }
}
