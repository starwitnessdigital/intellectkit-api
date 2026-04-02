import Vapor

public func configure(_ app: Application) async throws {
    // MARK: - Middleware

    // CORS — allow all origins for API consumption
    let corsConfig = CORSMiddleware.Configuration(
        allowedOrigin: .all,
        allowedMethods: [.GET, .POST, .OPTIONS],
        allowedHeaders: [
            .accept,
            .authorization,
            .contentType,
            .origin,
            .xRequestedWith,
            HTTPHeaders.Name("X-API-Key"),
        ]
    )
    app.middleware.use(CORSMiddleware(configuration: corsConfig), at: .beginning)
    app.middleware.use(ErrorMiddleware.default(environment: app.environment))

    // MARK: - File Middleware (serves Public/ directory)
    app.middleware.use(FileMiddleware(publicDirectory: app.directory.publicDirectory))

    // MARK: - Routes
    try routes(app)
}
