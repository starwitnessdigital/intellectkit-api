import Vapor
import Foundation
import Crypto

/// Developer utility tool endpoints.
///
/// GET /v1/tools/validate-email?email=user@example.com
/// GET /v1/tools/dns?domain=example.com
struct ToolsController {

    // MARK: - Email Validation

    func validateEmail(req: Request) async throws -> EmailValidationResponse {
        guard let email = req.query[String.self, at: "email"], !email.isEmpty else {
            throw Abort(.badRequest, reason: "Missing required query parameter: email")
        }

        let parts = email.split(separator: "@", maxSplits: 1)
        guard parts.count == 2 else {
            return EmailValidationResponse(
                email: email,
                isValid: false,
                reason: "Missing @ symbol",
                domain: nil,
                local: nil
            )
        }

        let local = String(parts[0])
        let domain = String(parts[1])

        if local.isEmpty {
            return EmailValidationResponse(email: email, isValid: false, reason: "Empty local part", domain: domain, local: local)
        }
        if domain.isEmpty || !domain.contains(".") {
            return EmailValidationResponse(email: email, isValid: false, reason: "Invalid domain", domain: domain, local: local)
        }
        if domain.hasPrefix(".") || domain.hasSuffix(".") {
            return EmailValidationResponse(email: email, isValid: false, reason: "Domain cannot start or end with a dot", domain: domain, local: local)
        }

        // RFC 5321 local part length
        if local.count > 64 {
            return EmailValidationResponse(email: email, isValid: false, reason: "Local part exceeds 64 characters", domain: domain, local: local)
        }
        if email.count > 254 {
            return EmailValidationResponse(email: email, isValid: false, reason: "Email exceeds 254 characters", domain: domain, local: local)
        }

        // Basic regex pattern check
        let pattern = #"^[a-zA-Z0-9.!#$%&'*+/=?^_`{|}~-]+@[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(?:\.[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)*$"#
        let isValid = email.range(of: pattern, options: .regularExpression) != nil

        return EmailValidationResponse(
            email: email,
            isValid: isValid,
            reason: isValid ? nil : "Failed format validation",
            domain: domain,
            local: local
        )
    }

    // MARK: - DNS Lookup

    func dns(req: Request) async throws -> DNSLookupResponse {
        guard let domain = req.query[String.self, at: "domain"], !domain.isEmpty else {
            throw Abort(.badRequest, reason: "Missing required query parameter: domain")
        }

        // Validate domain is reasonable before shelling out
        let cleaned = domain.trimmingCharacters(in: .whitespaces)
            .lowercased()
            .trimmingCharacters(in: CharacterSet(charactersIn: "."))

        guard !cleaned.isEmpty,
              cleaned.count <= 253,
              cleaned.range(of: #"^[a-z0-9][a-z0-9.\-]*[a-z0-9]$"#, options: .regularExpression) != nil else {
            throw Abort(.badRequest, reason: "Invalid domain name: \(domain)")
        }

        // Use the system `dig` command (available on Linux and macOS)
        // We query A, MX, TXT, and NS records
        var records: [DNSRecord] = []

        let recordTypes = ["A", "MX", "TXT", "NS", "CNAME"]
        for rtype in recordTypes {
            let result = try await runDig(domain: cleaned, type: rtype, req: req)
            records.append(contentsOf: result)
        }

        return DNSLookupResponse(
            domain: cleaned,
            records: records,
            checkedAt: ISO8601DateFormatter().string(from: Date())
        )
    }

    // MARK: - IP Info

    func ipInfo(req: Request) async throws -> IPInfoResponse {
        guard let ip = req.query[String.self, at: "ip"], !ip.isEmpty else {
            throw Abort(.badRequest, reason: "Missing required query parameter: ip")
        }

        let trimmed = ip.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, trimmed.count <= 45 else {
            throw Abort(.badRequest, reason: "Invalid IP address")
        }

        // ip-api.com free tier (HTTP only, 45 req/min, no key required)
        let fields = "status,message,country,countryCode,region,regionName,city,lat,lon,timezone,isp,org,as,query"
        let apiURL = "http://ip-api.com/json/\(trimmed)?fields=\(fields)"

        let clientResponse = try await req.client.get(URI(string: apiURL))

        guard clientResponse.status == .ok else {
            throw Abort(.badGateway, reason: "IP geolocation service unavailable")
        }

        let apiData = try clientResponse.content.decode(IPAPIResponse.self)

        if apiData.status != "success" {
            throw Abort(.badRequest, reason: apiData.message ?? "Invalid or private IP address")
        }

        return IPInfoResponse(
            ip: apiData.query ?? trimmed,
            country: apiData.country,
            countryCode: apiData.countryCode,
            region: apiData.region,
            regionName: apiData.regionName,
            city: apiData.city,
            isp: apiData.isp,
            org: apiData.org,
            asNumber: apiData.asNumber,
            timezone: apiData.timezone,
            lat: apiData.lat,
            lon: apiData.lon,
            checkedAt: ISO8601DateFormatter().string(from: Date())
        )
    }

    // MARK: - SSL Certificate Info

    func ssl(req: Request) async throws -> SSLInfoResponse {
        guard let domain = req.query[String.self, at: "domain"], !domain.isEmpty else {
            throw Abort(.badRequest, reason: "Missing required query parameter: domain")
        }

        let cleaned = domain.trimmingCharacters(in: .whitespaces)
            .lowercased()
            .trimmingCharacters(in: CharacterSet(charactersIn: "."))

        guard !cleaned.isEmpty,
              cleaned.count <= 253,
              cleaned.range(of: #"^[a-z0-9][a-z0-9.\-]*[a-z0-9]$"#, options: .regularExpression) != nil else {
            throw Abort(.badRequest, reason: "Invalid domain name: \(domain)")
        }

        let output = await runShellScript("""
            CERT=$(echo | openssl s_client -connect \(cleaned):443 -servername \(cleaned) 2>/dev/null)
            echo "$CERT" | openssl x509 -noout -issuer -subject -dates -serial 2>/dev/null
            echo "sigalg=$(echo "$CERT" | openssl x509 -noout -text 2>/dev/null | grep 'Signature Algorithm' | head -1 | sed 's/.*Signature Algorithm: //' | tr -d ' ')"
            """)

        func field(_ prefix: String) -> String? {
            let line = output.components(separatedBy: "\n")
                .first { $0.hasPrefix(prefix) }
            return line.map { String($0.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces) }
                .flatMap { $0.isEmpty ? nil : $0 }
        }

        let notAfterStr = field("notAfter=")

        var daysUntilExpiry: Int? = nil
        if let dateStr = notAfterStr {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "MMM d HH:mm:ss yyyy zzz"
            if let expiry = formatter.date(from: dateStr) {
                daysUntilExpiry = Calendar.current.dateComponents([.day], from: Date(), to: expiry).day
            }
        }

        return SSLInfoResponse(
            domain: cleaned,
            issuer: field("issuer="),
            subject: field("subject="),
            validFrom: field("notBefore="),
            validTo: notAfterStr,
            daysUntilExpiry: daysUntilExpiry,
            serialNumber: field("serial="),
            signatureAlgorithm: field("sigalg="),
            checkedAt: ISO8601DateFormatter().string(from: Date())
        )
    }

    // MARK: - URL Info

    func urlInfo(req: Request) async throws -> URLInfoResponse {
        guard let urlStr = req.query[String.self, at: "url"], !urlStr.isEmpty else {
            throw Abort(.badRequest, reason: "Missing required query parameter: url")
        }

        guard let components = URLComponents(string: urlStr),
              let scheme = components.scheme,
              scheme == "http" || scheme == "https" else {
            throw Abort(.badRequest, reason: "url must start with http:// or https://")
        }

        let host = components.host ?? ""
        let parts = host.split(separator: ".").map(String.init)
        let subdomain: String? = parts.count > 2 ? parts.dropLast(2).joined(separator: ".") : nil

        let queryParams = components.queryItems?.reduce(into: [String: String]()) { dict, item in
            dict[item.name] = item.value ?? ""
        } ?? [:]

        let redirectChain = await followRedirects(from: urlStr)

        return URLInfoResponse(
            url: urlStr,
            scheme: scheme,
            domain: host.isEmpty ? nil : host,
            subdomain: subdomain,
            path: components.path.isEmpty ? nil : components.path,
            queryParams: queryParams,
            fragment: components.fragment,
            isHttps: scheme == "https",
            redirectChain: redirectChain,
            checkedAt: ISO8601DateFormatter().string(from: Date())
        )
    }

    // MARK: - Hash

    func hash(req: Request) async throws -> HashResponse {
        guard let text = req.query[String.self, at: "text"] else {
            throw Abort(.badRequest, reason: "Missing required query parameter: text")
        }
        let algorithm = (req.query[String.self, at: "algorithm"] ?? "sha256").lowercased()
        let data = Data(text.utf8)

        let hashHex: String
        switch algorithm {
        case "md5":
            hashHex = Insecure.MD5.hash(data: data).hexString
        case "sha1":
            hashHex = Insecure.SHA1.hash(data: data).hexString
        case "sha256":
            hashHex = SHA256.hash(data: data).hexString
        case "sha512":
            hashHex = SHA512.hash(data: data).hexString
        default:
            throw Abort(.badRequest, reason: "Unsupported algorithm '\(algorithm)'. Valid options: md5, sha1, sha256, sha512")
        }

        return HashResponse(text: text, algorithm: algorithm, hash: hashHex)
    }

    // MARK: - Encode

    func encode(req: Request) async throws -> EncodeDecodeResponse {
        guard let text = req.query[String.self, at: "text"] else {
            throw Abort(.badRequest, reason: "Missing required query parameter: text")
        }
        let format = (req.query[String.self, at: "format"] ?? "base64").lowercased()

        let output: String
        switch format {
        case "base64":
            output = Data(text.utf8).base64EncodedString()
        case "url":
            output = text.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? text
        case "html":
            output = text
                .replacingOccurrences(of: "&", with: "&amp;")
                .replacingOccurrences(of: "<", with: "&lt;")
                .replacingOccurrences(of: ">", with: "&gt;")
                .replacingOccurrences(of: "\"", with: "&quot;")
                .replacingOccurrences(of: "'", with: "&#39;")
        default:
            throw Abort(.badRequest, reason: "Unsupported format '\(format)'. Valid options: base64, url, html")
        }

        return EncodeDecodeResponse(input: text, output: output, format: format, operation: "encode")
    }

    // MARK: - Decode

    func decode(req: Request) async throws -> EncodeDecodeResponse {
        guard let text = req.query[String.self, at: "text"] else {
            throw Abort(.badRequest, reason: "Missing required query parameter: text")
        }
        let format = (req.query[String.self, at: "format"] ?? "base64").lowercased()

        let output: String
        switch format {
        case "base64":
            guard let data = Data(base64Encoded: text, options: .ignoreUnknownCharacters),
                  let decoded = String(data: data, encoding: .utf8) else {
                throw Abort(.badRequest, reason: "Invalid base64 input")
            }
            output = decoded
        case "url":
            output = text.removingPercentEncoding ?? text
        case "html":
            var result = text
            let entities: [(String, String)] = [
                ("&amp;", "&"), ("&lt;", "<"), ("&gt;", ">"),
                ("&quot;", "\""), ("&#39;", "'"), ("&apos;", "'"),
                ("&nbsp;", " "), ("&copy;", "©"), ("&reg;", "®"),
            ]
            for (entity, char) in entities {
                result = result.replacingOccurrences(of: entity, with: char)
            }
            output = result
        default:
            throw Abort(.badRequest, reason: "Unsupported format '\(format)'. Valid options: base64, url, html")
        }

        return EncodeDecodeResponse(input: text, output: output, format: format, operation: "decode")
    }

    // MARK: - JSON Validate

    func jsonValidate(req: Request) async throws -> JSONValidateResponse {
        guard let buffer = req.body.data, buffer.readableBytes > 0 else {
            throw Abort(.badRequest, reason: "Request body is required — send the JSON to validate as the raw body")
        }

        let bodyString = String(buffer: buffer)
        guard let bodyData = bodyString.data(using: .utf8) else {
            return JSONValidateResponse(valid: false, error: "Body is not valid UTF-8", structure: nil)
        }

        do {
            let parsed = try JSONSerialization.jsonObject(with: bodyData, options: [])
            let summary = buildJSONSummary(parsed)
            return JSONValidateResponse(valid: true, error: nil, structure: summary)
        } catch {
            return JSONValidateResponse(valid: false, error: error.localizedDescription, structure: nil)
        }
    }

    // MARK: - Private Helpers

    private func runShellScript(_ script: String) async -> String {
        return await withCheckedContinuation { continuation in
            DispatchQueue.global().async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/bin/sh")
                process.arguments = ["-c", script]
                let pipe = Pipe()
                process.standardOutput = pipe
                process.standardError = Pipe()
                do {
                    try process.run()
                    process.waitUntilExit()
                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    continuation.resume(returning: String(data: data, encoding: .utf8) ?? "")
                } catch {
                    continuation.resume(returning: "")
                }
            }
        }
    }

    private func followRedirects(from urlString: String) async -> [RedirectHop] {
        return await withCheckedContinuation { continuation in
            DispatchQueue.global().async {
                var hops: [RedirectHop] = []
                var current = urlString
                let maxHops = 10
                let delegate = RedirectBlockingDelegate()

                for _ in 0..<maxHops {
                    guard let url = URL(string: current) else { break }

                    var request = URLRequest(url: url, timeoutInterval: 8)
                    request.httpMethod = "GET"

                    let config = URLSessionConfiguration.default
                    config.timeoutIntervalForRequest = 8
                    let session = URLSession(configuration: config, delegate: delegate, delegateQueue: nil)

                    let sema = DispatchSemaphore(value: 0)
                    var statusCode = 0
                    var nextURL: String? = nil

                    session.dataTask(with: request) { _, response, _ in
                        if let http = response as? HTTPURLResponse {
                            statusCode = http.statusCode
                            if (300...308).contains(statusCode),
                               let location = http.value(forHTTPHeaderField: "Location") {
                                // Resolve relative redirects
                                if location.hasPrefix("http://") || location.hasPrefix("https://") {
                                    nextURL = location
                                } else if location.hasPrefix("/"), let base = URL(string: current) {
                                    nextURL = "\(base.scheme ?? "https")://\(base.host ?? "")\(location)"
                                } else {
                                    nextURL = location
                                }
                            }
                        }
                        sema.signal()
                    }.resume()

                    sema.wait()
                    session.invalidateAndCancel()

                    if statusCode > 0 {
                        hops.append(RedirectHop(url: current, statusCode: statusCode))
                    }

                    guard let next = nextURL else { break }
                    current = next
                }

                continuation.resume(returning: hops)
            }
        }
    }

    private func buildJSONSummary(_ value: Any) -> JSONStructureSummary {
        let depth = jsonDepth(value)
        if let dict = value as? [String: Any] {
            return JSONStructureSummary(
                type: "object",
                keyCount: dict.count,
                keys: Array(dict.keys.sorted().prefix(30)),
                arrayLength: nil,
                depth: depth
            )
        } else if let array = value as? [Any] {
            return JSONStructureSummary(
                type: "array",
                keyCount: nil,
                keys: nil,
                arrayLength: array.count,
                depth: depth
            )
        } else {
            return JSONStructureSummary(type: "scalar", keyCount: nil, keys: nil, arrayLength: nil, depth: 0)
        }
    }

    private func jsonDepth(_ value: Any) -> Int {
        if let dict = value as? [String: Any] {
            let max = dict.values.map { jsonDepth($0) }.max() ?? 0
            return 1 + max
        } else if let array = value as? [Any] {
            let max = array.map { jsonDepth($0) }.max() ?? 0
            return 1 + max
        }
        return 0
    }

    private func runDig(domain: String, type: String, req: Request) async throws -> [DNSRecord] {
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global().async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/dig")
                // +short gives just the answer values, +time=3 limits wait
                process.arguments = ["+short", "+time=3", "+tries=1", type, domain]

                let pipe = Pipe()
                process.standardOutput = pipe
                process.standardError = Pipe()

                do {
                    try process.run()
                    process.waitUntilExit()
                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    let output = String(data: data, encoding: .utf8) ?? ""
                    let lines = output.components(separatedBy: "\n")
                        .map { $0.trimmingCharacters(in: .whitespaces) }
                        .filter { !$0.isEmpty }
                    let dnsRecords = lines.map { DNSRecord(type: type, value: $0) }
                    continuation.resume(returning: dnsRecords)
                } catch {
                    // dig not available — return empty
                    continuation.resume(returning: [])
                }
            }
        }
    }
}

// MARK: - Private file-scope helpers

private struct IPAPIResponse: Decodable {
    let status: String
    let message: String?
    let country: String?
    let countryCode: String?
    let region: String?
    let regionName: String?
    let city: String?
    let lat: Double?
    let lon: Double?
    let timezone: String?
    let isp: String?
    let org: String?
    let asNumber: String?
    let query: String?

    enum CodingKeys: String, CodingKey {
        case status, message, country, countryCode, region, regionName
        case city, lat, lon, timezone, isp, org, query
        case asNumber = "as"
    }
}

/// URLSession delegate that prevents automatic redirect following so we can
/// capture each hop in the redirect chain manually.
private final class RedirectBlockingDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping @Sendable (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }
}

// MARK: - Digest hex helpers

private extension Digest {
    var hexString: String {
        self.map { String(format: "%02hhx", $0) }.joined()
    }
}
