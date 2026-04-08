import Vapor

/// Data transformation endpoints.
///
/// POST /v1/transform/json-to-csv  – convert a JSON array of objects to CSV
/// POST /v1/transform/csv-to-json  – convert CSV to a JSON array of objects
struct TransformController {

    func jsonToCsv(req: Request) async throws -> JsonToCsvResponse {
        let body = try req.content.decode(JsonToCsvRequest.self)
        guard !body.json.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw Abort(.badRequest, reason: "json must not be empty")
        }
        let delim = validatedDelimiter(body.delimiter)
        return try convertJsonToCsv(body.json, delimiter: delim)
    }

    func csvToJson(req: Request) async throws -> CsvToJsonResponse {
        let body = try req.content.decode(CsvToJsonRequest.self)
        guard !body.csv.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw Abort(.badRequest, reason: "csv must not be empty")
        }
        let delim = validatedDelimiter(body.delimiter)
        let hasHeader = body.hasHeader ?? true
        return try convertCsvToJson(body.csv, delimiter: delim, hasHeader: hasHeader)
    }
}

// MARK: - JSON → CSV

private extension TransformController {

    func convertJsonToCsv(_ jsonString: String, delimiter: Character) throws -> JsonToCsvResponse {
        guard let data = jsonString.data(using: .utf8),
              let raw = try? JSONSerialization.jsonObject(with: data) else {
            throw Abort(.badRequest, reason: "Invalid JSON: could not parse input")
        }

        guard let array = raw as? [[String: Any]] else {
            throw Abort(.badRequest, reason: "JSON must be an array of objects (e.g. [{\"key\": \"value\"}])")
        }

        guard !array.isEmpty else {
            return JsonToCsvResponse(csv: "", rows: 0, columns: 0, headers: [])
        }

        // Collect all unique keys, preserving order of first object
        var seen = Set<String>()
        var headers: [String] = []
        for row in array {
            for key in row.keys where seen.insert(key).inserted {
                headers.append(key)
            }
        }
        headers.sort()

        var lines: [String] = []
        lines.append(headers.map { csvEscape($0, delimiter: delimiter) }.joined(separator: String(delimiter)))

        for row in array {
            let values = headers.map { key -> String in
                guard let val = row[key] else { return "" }
                return csvEscape(jsonValueToString(val), delimiter: delimiter)
            }
            lines.append(values.joined(separator: String(delimiter)))
        }

        let csv = lines.joined(separator: "\n")
        return JsonToCsvResponse(
            csv: csv,
            rows: array.count,
            columns: headers.count,
            headers: headers
        )
    }

    func jsonValueToString(_ value: Any) -> String {
        switch value {
        case let s as String:  return s
        case let n as NSNumber: return n.stringValue
        case let b as Bool:    return b ? "true" : "false"
        case is NSNull:        return ""
        default:
            if let data = try? JSONSerialization.data(withJSONObject: value),
               let s = String(data: data, encoding: .utf8) { return s }
            return "\(value)"
        }
    }
}

// MARK: - CSV → JSON

private extension TransformController {

    func convertCsvToJson(_ csv: String, delimiter: Character, hasHeader: Bool) throws -> CsvToJsonResponse {
        let lines = csv.components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .init(charactersIn: "\r")) }
            .filter { !$0.isEmpty }

        guard !lines.isEmpty else {
            return CsvToJsonResponse(json: "[]", rows: 0, columns: 0, headers: [])
        }

        let firstRow = parseCsvRow(lines[0], delimiter: delimiter)
        let headers: [String]
        let dataLines: [String]

        if hasHeader {
            headers = firstRow
            dataLines = Array(lines.dropFirst())
        } else {
            headers = firstRow.indices.map { "column\($0 + 1)" }
            dataLines = lines
        }

        var objects: [[String: String]] = []
        for line in dataLines {
            let values = parseCsvRow(line, delimiter: delimiter)
            var obj: [String: String] = [:]
            for (i, header) in headers.enumerated() {
                obj[header] = i < values.count ? values[i] : ""
            }
            objects.append(obj)
        }

        guard let jsonData = try? JSONSerialization.data(
            withJSONObject: objects,
            options: [.prettyPrinted, .sortedKeys]
        ),
        let jsonString = String(data: jsonData, encoding: .utf8) else {
            throw Abort(.internalServerError, reason: "Failed to serialize output JSON")
        }

        return CsvToJsonResponse(
            json: jsonString,
            rows: objects.count,
            columns: headers.count,
            headers: headers
        )
    }

    func parseCsvRow(_ row: String, delimiter: Character) -> [String] {
        var fields: [String] = []
        var current = ""
        var inQuotes = false
        var i = row.startIndex

        while i < row.endIndex {
            let ch = row[i]
            if ch == "\"" {
                let next = row.index(after: i)
                if inQuotes && next < row.endIndex && row[next] == "\"" {
                    current.append("\"")
                    i = row.index(after: next)
                    continue
                }
                inQuotes.toggle()
            } else if ch == delimiter && !inQuotes {
                fields.append(current)
                current = ""
            } else {
                current.append(ch)
            }
            i = row.index(after: i)
        }
        fields.append(current)
        return fields
    }

    func csvEscape(_ value: String, delimiter: Character) -> String {
        let needsQuoting = value.contains(delimiter) || value.contains("\"") || value.contains("\n")
        if needsQuoting {
            return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return value
    }

    func validatedDelimiter(_ raw: String?) -> Character {
        guard let s = raw, !s.isEmpty else { return "," }
        let allowed: Set<Character> = [",", ";", "\t", "|"]
        return allowed.contains(s.first!) ? s.first! : ","
    }
}
