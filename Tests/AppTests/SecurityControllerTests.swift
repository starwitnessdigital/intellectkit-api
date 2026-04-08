@testable import App
import XCTVapor

final class SecurityControllerTests: XCTestCase {

    private func makeApp() async throws -> Application {
        let app = try await Application.make(.testing)
        try await configure(app)
        return app
    }

    private var apiKey: HTTPHeaders { ["X-API-Key": "ik_free_demo_key_123"] }

    // MARK: - Hash

    func testHashSha256() async throws {
        let app = try await makeApp()
        defer { Task { try await app.asyncShutdown() } }

        try await app.test(.POST, "v1/security/hash", headers: apiKey, beforeRequest: { req in
            try req.content.encode(HashRequest(text: "hello world", algorithm: "sha256"))
        }) { res async in
            XCTAssertEqual(res.status, .ok)
            let body = try? res.content.decode(HashResponse.self)
            // Known SHA-256 hash of "hello world"
            XCTAssertEqual(body?.hash, "b94d27b9934d3e08a52e52d7da7dabfac484efe37a5380ee9088f7ace2efcde9")
            XCTAssertEqual(body?.algorithm, "sha256")
            XCTAssertEqual(body?.inputLength, 11)
        }
    }

    func testHashMd5() async throws {
        let app = try await makeApp()
        defer { Task { try await app.asyncShutdown() } }

        try await app.test(.POST, "v1/security/hash", headers: apiKey, beforeRequest: { req in
            try req.content.encode(HashRequest(text: "hello world", algorithm: "md5"))
        }) { res async in
            XCTAssertEqual(res.status, .ok)
            let body = try? res.content.decode(HashResponse.self)
            // Known MD5 hash of "hello world"
            XCTAssertEqual(body?.hash, "5eb63bbbe01eeed093cb22bb8f5acdc3")
            XCTAssertEqual(body?.algorithm, "md5")
        }
    }

    func testHashSha512() async throws {
        let app = try await makeApp()
        defer { Task { try await app.asyncShutdown() } }

        try await app.test(.POST, "v1/security/hash", headers: apiKey, beforeRequest: { req in
            try req.content.encode(HashRequest(text: "test", algorithm: "sha512"))
        }) { res async in
            XCTAssertEqual(res.status, .ok)
            let body = try? res.content.decode(HashResponse.self)
            XCTAssertNotNil(body?.hash)
            XCTAssertEqual(body?.hash.count, 128) // SHA-512 = 64 bytes = 128 hex chars
        }
    }

    func testHashInvalidAlgorithmReturns400() async throws {
        let app = try await makeApp()
        defer { Task { try await app.asyncShutdown() } }

        try await app.test(.POST, "v1/security/hash", headers: apiKey, beforeRequest: { req in
            try req.content.encode(HashRequest(text: "hello", algorithm: "bcrypt"))
        }) { res async in
            XCTAssertEqual(res.status, .badRequest)
        }
    }

    func testHashEmptyTextReturns400() async throws {
        let app = try await makeApp()
        defer { Task { try await app.asyncShutdown() } }

        try await app.test(.POST, "v1/security/hash", headers: apiKey, beforeRequest: { req in
            try req.content.encode(HashRequest(text: "", algorithm: "sha256"))
        }) { res async in
            XCTAssertEqual(res.status, .badRequest)
        }
    }

    // MARK: - Password Strength

    func testPasswordStrengthVeryWeak() async throws {
        let app = try await makeApp()
        defer { Task { try await app.asyncShutdown() } }

        try await app.test(.POST, "v1/security/password-strength", headers: apiKey, beforeRequest: { req in
            try req.content.encode(PasswordStrengthRequest(password: "abc"))
        }) { res async in
            XCTAssertEqual(res.status, .ok)
            let body = try? res.content.decode(PasswordStrengthResponse.self)
            XCTAssertLessThanOrEqual(body?.score ?? 4, 1)
            XCTAssertFalse(body?.feedback.isEmpty ?? true)
        }
    }

    func testPasswordStrengthStrong() async throws {
        let app = try await makeApp()
        defer { Task { try await app.asyncShutdown() } }

        try await app.test(.POST, "v1/security/password-strength", headers: apiKey, beforeRequest: { req in
            try req.content.encode(PasswordStrengthRequest(password: "T!g3r$Blu3Moon#99"))
        }) { res async in
            XCTAssertEqual(res.status, .ok)
            let body = try? res.content.decode(PasswordStrengthResponse.self)
            XCTAssertGreaterThanOrEqual(body?.score ?? 0, 3)
            XCTAssertTrue(body?.hasUppercase ?? false)
            XCTAssertTrue(body?.hasLowercase ?? false)
            XCTAssertTrue(body?.hasDigits ?? false)
            XCTAssertTrue(body?.hasSymbols ?? false)
        }
    }

    func testPasswordStrengthCommonPassword() async throws {
        let app = try await makeApp()
        defer { Task { try await app.asyncShutdown() } }

        try await app.test(.POST, "v1/security/password-strength", headers: apiKey, beforeRequest: { req in
            try req.content.encode(PasswordStrengthRequest(password: "password123"))
        }) { res async in
            XCTAssertEqual(res.status, .ok)
            let body = try? res.content.decode(PasswordStrengthResponse.self)
            XCTAssertFalse(body?.noCommonPatterns ?? true)
            XCTAssertFalse(body?.feedback.isEmpty ?? true)
        }
    }

    func testPasswordStrengthEntropyIncreases() async throws {
        let app = try await makeApp()
        defer { Task { try await app.asyncShutdown() } }

        var shortEntropy = 0.0
        var longEntropy = 0.0

        try await app.test(.POST, "v1/security/password-strength", headers: apiKey, beforeRequest: { req in
            try req.content.encode(PasswordStrengthRequest(password: "Ab1!"))
        }) { res async in
            let body = try? res.content.decode(PasswordStrengthResponse.self)
            shortEntropy = body?.entropy ?? 0
        }

        try await app.test(.POST, "v1/security/password-strength", headers: apiKey, beforeRequest: { req in
            try req.content.encode(PasswordStrengthRequest(password: "Ab1!Ab1!Ab1!Ab1!"))
        }) { res async in
            let body = try? res.content.decode(PasswordStrengthResponse.self)
            longEntropy = body?.entropy ?? 0
        }

        XCTAssertGreaterThan(longEntropy, shortEntropy)
    }
}
