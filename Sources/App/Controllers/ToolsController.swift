import Vapor
import Foundation

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

    // MARK: - Private Helpers

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
