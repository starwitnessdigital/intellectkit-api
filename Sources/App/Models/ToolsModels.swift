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

// MARK: - IP Info

struct IPInfoResponse: Content {
    let ip: String
    let country: String?
    let countryCode: String?
    let region: String?
    let regionName: String?
    let city: String?
    let isp: String?
    let org: String?
    let asNumber: String?
    let timezone: String?
    let lat: Double?
    let lon: Double?
    let checkedAt: String
}

// MARK: - SSL Info

struct SSLInfoResponse: Content {
    let domain: String
    let issuer: String?
    let subject: String?
    let validFrom: String?
    let validTo: String?
    let daysUntilExpiry: Int?
    let serialNumber: String?
    let signatureAlgorithm: String?
    let checkedAt: String
}

// MARK: - URL Info

struct RedirectHop: Content {
    let url: String
    let statusCode: Int
}

struct URLInfoResponse: Content {
    let url: String
    let scheme: String?
    let domain: String?
    let subdomain: String?
    let path: String?
    let queryParams: [String: String]
    let fragment: String?
    let isHttps: Bool
    let redirectChain: [RedirectHop]
    let checkedAt: String
}

// MARK: - Hash

struct HashResponse: Content {
    let text: String
    let algorithm: String
    let hash: String
}

// MARK: - Encode / Decode

struct EncodeDecodeResponse: Content {
    let input: String
    let output: String
    let format: String
    let operation: String
}

// MARK: - JSON Validate

struct JSONStructureSummary: Content {
    let type: String
    let keyCount: Int?
    let keys: [String]?
    let arrayLength: Int?
    let depth: Int
}

struct JSONValidateResponse: Content {
    let valid: Bool
    let error: String?
    let structure: JSONStructureSummary?
}
