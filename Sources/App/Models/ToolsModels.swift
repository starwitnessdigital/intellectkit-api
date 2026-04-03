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

// MARK: - WHOIS Lookup

struct WhoisResponse: Content {
    let domain: String
    let registrar: String?
    let creationDate: String?
    let expiryDate: String?
    let updatedDate: String?
    let nameServers: [String]
    let status: [String]
    let registrantName: String?
    let registrantOrg: String?
    let registrantCountry: String?
    let rawOutput: String
    let checkedAt: String
}

// MARK: - HTTP Headers Inspection

struct SecurityHeaders: Content {
    let contentSecurityPolicy: String?
    let strictTransportSecurity: String?
    let xFrameOptions: String?
    let xContentTypeOptions: String?
    let referrerPolicy: String?
    let permissionsPolicy: String?
}

struct CacheHeaders: Content {
    let cacheControl: String?
    let etag: String?
    let lastModified: String?
    let expires: String?
}

struct HeadersResponse: Content {
    let url: String
    let statusCode: Int
    let statusReason: String
    let server: String?
    let contentType: String?
    let allHeaders: [String: String]
    let securityHeaders: SecurityHeaders
    let cacheHeaders: CacheHeaders
    let cookies: [String]
    let checkedAt: String
}

// MARK: - Robots.txt

struct RobotsUserAgentRule: Content {
    let userAgent: String
    let allow: [String]
    let disallow: [String]
    let crawlDelay: Double?
}

struct RobotsResponse: Content {
    let url: String
    let robotsTxtUrl: String
    let found: Bool
    let rules: [RobotsUserAgentRule]
    let sitemaps: [String]
    let checkedAt: String
}

// MARK: - Sitemap

struct SitemapEntry: Content {
    let url: String
    let lastmod: String?
    let changefreq: String?
    let priority: Double?
}

struct SitemapResponse: Content {
    let url: String
    let sitemapUrl: String
    let found: Bool
    let urlCount: Int
    let urls: [SitemapEntry]
    let checkedAt: String
}

// MARK: - Social Links

struct SocialLinksResponse: Content {
    let url: String
    let twitter: String?
    let instagram: String?
    let linkedin: String?
    let facebook: String?
    let youtube: String?
    let tiktok: String?
    let github: String?
    let checkedAt: String
}

// MARK: - Tech Stack Detection

struct TechStackResponse: Content {
    let url: String
    let framework: String?
    let cms: String?
    let analytics: [String]
    let hosting: String?
    let server: String?
    let cdn: String?
    let detected: [String]
    let checkedAt: String
}
