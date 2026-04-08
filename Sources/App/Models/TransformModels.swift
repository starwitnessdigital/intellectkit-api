import Vapor

// MARK: - JSON to CSV

struct JsonToCsvRequest: Content {
    let json: String
    let delimiter: String?
}

struct JsonToCsvResponse: Content {
    let csv: String
    let rows: Int
    let columns: Int
    let headers: [String]
}

// MARK: - CSV to JSON

struct CsvToJsonRequest: Content {
    let csv: String
    let delimiter: String?
    let hasHeader: Bool?
}

struct CsvToJsonResponse: Content {
    let json: String
    let rows: Int
    let columns: Int
    let headers: [String]
}
