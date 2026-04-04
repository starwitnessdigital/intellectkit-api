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

    // MARK: Developer Tools endpoints
    let tools = ToolsController()
    let toolsGroup = v1.grouped("tools")
    toolsGroup.get("validate-email", use: tools.validateEmail)
    toolsGroup.get("dns", use: tools.dns)
    toolsGroup.get("ip-info", use: tools.ipInfo)
    toolsGroup.get("ssl", use: tools.ssl)
    toolsGroup.get("url-info", use: tools.urlInfo)
    toolsGroup.get("hash", use: tools.hash)
    toolsGroup.get("encode", use: tools.encode)
    toolsGroup.get("decode", use: tools.decode)
    toolsGroup.post("json-validate", use: tools.jsonValidate)
}
