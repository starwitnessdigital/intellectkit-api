@testable import App
import XCTVapor

final class TransformControllerTests: XCTestCase {

    private func makeApp() async throws -> Application {
        let app = try await Application.make(.testing)
        try await configure(app)
        return app
    }

    private var apiKey: HTTPHeaders { ["X-API-Key": "ik_free_demo_key_123"] }

    // MARK: - JSON to CSV

    func testJsonToCsvBasic() async throws {
        let app = try await makeApp()
        defer { Task { try await app.asyncShutdown() } }

        let json = #"[{"name":"Alice","age":30},{"name":"Bob","age":25}]"#
        try await app.test(.POST, "v1/transform/json-to-csv", headers: apiKey, beforeRequest: { req in
            try req.content.encode(JsonToCsvRequest(json: json, delimiter: nil))
        }) { res async in
            XCTAssertEqual(res.status, .ok)
            let body = try? res.content.decode(JsonToCsvResponse.self)
            XCTAssertEqual(body?.rows, 2)
            XCTAssertEqual(body?.columns, 2)
            XCTAssertEqual(Set(body?.headers ?? []), Set(["name", "age"]))
            XCTAssertTrue(body?.csv.contains("Alice") ?? false)
            XCTAssertTrue(body?.csv.contains("Bob") ?? false)
        }
    }

    func testJsonToCsvEmptyArray() async throws {
        let app = try await makeApp()
        defer { Task { try await app.asyncShutdown() } }

        try await app.test(.POST, "v1/transform/json-to-csv", headers: apiKey, beforeRequest: { req in
            try req.content.encode(JsonToCsvRequest(json: "[]", delimiter: nil))
        }) { res async in
            XCTAssertEqual(res.status, .ok)
            let body = try? res.content.decode(JsonToCsvResponse.self)
            XCTAssertEqual(body?.rows, 0)
        }
    }

    func testJsonToCsvInvalidJsonReturns400() async throws {
        let app = try await makeApp()
        defer { Task { try await app.asyncShutdown() } }

        try await app.test(.POST, "v1/transform/json-to-csv", headers: apiKey, beforeRequest: { req in
            try req.content.encode(JsonToCsvRequest(json: "not valid json", delimiter: nil))
        }) { res async in
            XCTAssertEqual(res.status, .badRequest)
        }
    }

    func testJsonToCsvNotArrayReturns400() async throws {
        let app = try await makeApp()
        defer { Task { try await app.asyncShutdown() } }

        try await app.test(.POST, "v1/transform/json-to-csv", headers: apiKey, beforeRequest: { req in
            try req.content.encode(JsonToCsvRequest(json: #"{"key":"value"}"#, delimiter: nil))
        }) { res async in
            XCTAssertEqual(res.status, .badRequest)
        }
    }

    func testJsonToCsvCustomDelimiter() async throws {
        let app = try await makeApp()
        defer { Task { try await app.asyncShutdown() } }

        let json = #"[{"name":"Alice","city":"New York"},{"name":"Bob","city":"LA"}]"#
        try await app.test(.POST, "v1/transform/json-to-csv", headers: apiKey, beforeRequest: { req in
            try req.content.encode(JsonToCsvRequest(json: json, delimiter: ";"))
        }) { res async in
            XCTAssertEqual(res.status, .ok)
            let body = try? res.content.decode(JsonToCsvResponse.self)
            XCTAssertTrue(body?.csv.contains(";") ?? false)
        }
    }

    func testJsonToCsvEscapesCommasInValues() async throws {
        let app = try await makeApp()
        defer { Task { try await app.asyncShutdown() } }

        let json = #"[{"name":"Smith, John","role":"developer"}]"#
        try await app.test(.POST, "v1/transform/json-to-csv", headers: apiKey, beforeRequest: { req in
            try req.content.encode(JsonToCsvRequest(json: json, delimiter: nil))
        }) { res async in
            XCTAssertEqual(res.status, .ok)
            let body = try? res.content.decode(JsonToCsvResponse.self)
            // Value with comma should be quoted
            XCTAssertTrue(body?.csv.contains("\"Smith, John\"") ?? false)
        }
    }

    // MARK: - CSV to JSON

    func testCsvToJsonBasic() async throws {
        let app = try await makeApp()
        defer { Task { try await app.asyncShutdown() } }

        let csv = "name,age\nAlice,30\nBob,25"
        try await app.test(.POST, "v1/transform/csv-to-json", headers: apiKey, beforeRequest: { req in
            try req.content.encode(CsvToJsonRequest(csv: csv, delimiter: nil, hasHeader: nil))
        }) { res async in
            XCTAssertEqual(res.status, .ok)
            let body = try? res.content.decode(CsvToJsonResponse.self)
            XCTAssertEqual(body?.rows, 2)
            XCTAssertEqual(body?.columns, 2)
            XCTAssertEqual(Set(body?.headers ?? []), Set(["name", "age"]))
            XCTAssertTrue(body?.json.contains("Alice") ?? false)
        }
    }

    func testCsvToJsonNoHeader() async throws {
        let app = try await makeApp()
        defer { Task { try await app.asyncShutdown() } }

        let csv = "Alice,30\nBob,25"
        try await app.test(.POST, "v1/transform/csv-to-json", headers: apiKey, beforeRequest: { req in
            try req.content.encode(CsvToJsonRequest(csv: csv, delimiter: nil, hasHeader: false))
        }) { res async in
            XCTAssertEqual(res.status, .ok)
            let body = try? res.content.decode(CsvToJsonResponse.self)
            XCTAssertEqual(body?.rows, 2)
            XCTAssertEqual(body?.headers, ["column1", "column2"])
        }
    }

    func testCsvToJsonRoundTrip() async throws {
        let app = try await makeApp()
        defer { Task { try await app.asyncShutdown() } }

        // JSON → CSV → verify structure
        let originalCsv = "id,name,score\n1,Alice,95\n2,Bob,87\n3,Carol,92"
        try await app.test(.POST, "v1/transform/csv-to-json", headers: apiKey, beforeRequest: { req in
            try req.content.encode(CsvToJsonRequest(csv: originalCsv, delimiter: nil, hasHeader: nil))
        }) { res async in
            XCTAssertEqual(res.status, .ok)
            let body = try? res.content.decode(CsvToJsonResponse.self)
            XCTAssertEqual(body?.rows, 3)
            XCTAssertEqual(body?.columns, 3)
            XCTAssertTrue(body?.json.contains("Carol") ?? false)
        }
    }
}
