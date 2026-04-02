import Vapor

// MARK: - Email Validation

struct EmailValidationResponse: Content {
    let email: String
    let isValid: Bool
    let reason: String?
    let domain: String?
    let local: String?
}

// MARK: - DNS Lookup

struct DNSRecord: Content {
    let type: String
    let value: String
}

struct DNSLookupResponse: Content {
    let domain: String
    let records: [DNSRecord]
    let checkedAt: String
}
