import Vapor

public func routes(_ app: Application) throws {
    // MARK: - Landing page
    app.get { req async throws -> Response in
        let indexPath = app.directory.publicDirectory + "index.html"
        return req.fileio.streamFile(at: indexPath)
    }

    // MARK: - Health check (no auth required)
    app.get("health") { _ in ["status": "ok", "service": "intellectkit-api"] }

    // MARK: - OpenAPI spec (public, no auth required)
    app.get("v1", "openapi") { req async throws -> Response in
        let path = req.application.directory.publicDirectory + "openapi.yaml"
        let response = req.fileio.streamFile(at: path)
        response.headers.contentType = HTTPMediaType(type: "application", subType: "yaml")
        return response
    }

    // MARK: - API v1 — protected by API key middleware
    let v1 = app.grouped("v1").grouped(APIKeyMiddleware())

    // MARK: Web Data Extraction endpoints
    let extraction = ExtractionController()
    let extractGroup = v1.grouped("extract")
    extractGroup.get("article", use: extraction.article)
    extractGroup.get("product", use: extraction.product)
    extractGroup.get("metadata", use: extraction.metadata)
    extractGroup.get("links", use: extraction.links)
    extractGroup.get("text", use: extraction.text)
    extractGroup.get("structured", use: extraction.structured)

    // MARK: Developer Tools endpoints
    let tools = ToolsController()
    let toolsGroup = v1.grouped("tools")
    toolsGroup.get("validate-email", use: tools.validateEmail)
    toolsGroup.get("dns", use: tools.dns)
    toolsGroup.get("whois", use: tools.whois)
    toolsGroup.get("headers", use: tools.httpHeaders)
    toolsGroup.get("robots", use: tools.robots)
    toolsGroup.get("sitemap", use: tools.sitemap)
    toolsGroup.get("social", use: tools.social)
    toolsGroup.get("tech-stack", use: tools.techStack)
    toolsGroup.post("markdown-to-html", use: tools.markdownToHtml)
    toolsGroup.get("color", use: tools.colorInfo)
    toolsGroup.get("timestamp", use: tools.timestamp)
    toolsGroup.get("random", use: tools.random)
    toolsGroup.post("diff", use: tools.diff)
}
