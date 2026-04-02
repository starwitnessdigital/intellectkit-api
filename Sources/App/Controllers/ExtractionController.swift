import Vapor

/// Structured web data extraction endpoints.
///
/// GET /v1/extract/article?url=https://example.com/post
/// GET /v1/extract/product?url=https://example.com/product
/// GET /v1/extract/metadata?url=https://example.com
/// GET /v1/extract/links?url=https://example.com
/// GET /v1/extract/text?url=https://example.com
struct ExtractionController {

    func article(req: Request) async throws -> ArticleExtractionResponse {
        let url = try validatedURL(req)
        let service = try await WebExtractionService.fetch(url: url, client: req.client)
        return try service.extractArticle()
    }

    func product(req: Request) async throws -> ProductExtractionResponse {
        let url = try validatedURL(req)
        let service = try await WebExtractionService.fetch(url: url, client: req.client)
        return try service.extractProduct()
    }

    func metadata(req: Request) async throws -> MetadataExtractionResponse {
        let url = try validatedURL(req)
        let service = try await WebExtractionService.fetch(url: url, client: req.client)
        return try service.extractMetadata()
    }

    func links(req: Request) async throws -> LinksExtractionResponse {
        let url = try validatedURL(req)
        let service = try await WebExtractionService.fetch(url: url, client: req.client)
        return try service.extractLinks()
    }

    func text(req: Request) async throws -> TextExtractionResponse {
        let url = try validatedURL(req)
        let service = try await WebExtractionService.fetch(url: url, client: req.client)
        return try service.extractText()
    }

    // MARK: - Helpers

    private func validatedURL(_ req: Request) throws -> String {
        guard let url = req.query[String.self, at: "url"], !url.isEmpty else {
            throw Abort(.badRequest,
                        reason: "Missing required query parameter: url. Example: ?url=https://example.com/article")
        }
        guard url.hasPrefix("http://") || url.hasPrefix("https://") else {
            throw Abort(.badRequest,
                        reason: "url must begin with http:// or https://")
        }
        return url
    }
}
