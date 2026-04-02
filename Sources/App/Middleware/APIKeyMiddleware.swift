import Vapor

// MARK: - API Tier

enum APITier: String {
    case free       = "free"
    case starter    = "starter"
    case pro        = "pro"
    case enterprise = "enterprise"

    var dailyLimit: Int? {
        switch self {
        case .free:       return 100
        case .starter:    return 1_000
        case .pro:        return 10_000
        case .enterprise: return nil   // unlimited
        }
    }

    var monthlyPriceUSD: Int {
        switch self {
        case .free:       return 0
        case .starter:    return 9
        case .pro:        return 29
        case .enterprise: return 99
        }
    }
}

// MARK: - API Key Middleware
//
// Checks the X-API-Key header and enforces per-tier rate limits.
//
// TODO: Production implementation:
//   1. Store API keys + tiers in a database (Fluent + PostgreSQL)
//   2. Use Redis for rate limit counters (vapor/redis package):
//      let count = try await req.redis.increment("ratelimit:\(apiKey):\(today)")
//      try await req.redis.expire("ratelimit:\(apiKey):\(today)", after: .hours(24))
//   3. Replace the hardcoded demo keys below with real key lookup
//
// For now: demo keys are hardcoded so you can test immediately with `swift run`.
// Set IK_DEMO_MODE=1 env var to bypass auth entirely for local dev.

struct APIKeyMiddleware: AsyncMiddleware {

    // Demo keys for local testing — replace with real DB lookup in production
    private static let demoKeys: [String: APITier] = [
        "ik_free_demo_key_123":       .free,
        "ik_starter_demo_key_456":    .starter,
        "ik_pro_demo_key_789":        .pro,
        "ik_enterprise_demo_key_000": .enterprise,
    ]

    // In-memory rate limiter — NOT suitable for multi-process production deployments.
    // Replace with Redis as noted above.
    private static let rateLimiter = InMemoryRateLimiter()

    func respond(to request: Request, chainingTo next: AsyncResponder) async throws -> Response {
        // Allow bypassing auth in demo/local mode
        if Environment.get("IK_DEMO_MODE") == "1" {
            return try await next.respond(to: request)
        }

        guard let apiKey = request.headers.first(name: "X-API-Key"),
              !apiKey.isEmpty else {
            throw Abort(.unauthorized, reason: "Missing X-API-Key header. Get your key at intellectkit.dev/keys")
        }

        guard let tier = Self.demoKeys[apiKey] else {
            throw Abort(.unauthorized, reason: "Invalid API key. Get your key at intellectkit.dev/keys")
        }

        // Rate limit check
        if let limit = tier.dailyLimit {
            let today = Self.todayString()
            let count = await Self.rateLimiter.increment(key: "\(apiKey):\(today)")
            if count > limit {
                throw Abort(.tooManyRequests,
                            reason: "Rate limit exceeded: \(count)/\(limit) requests today for \(tier.rawValue) tier. " +
                                    "Upgrade at intellectkit.dev/pricing")
            }
        }

        // Attach tier info to request storage for downstream use
        request.storage.set(APITierKey.self, to: tier)

        return try await next.respond(to: request)
    }

    private static func todayString() -> String {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        let c = cal.dateComponents([.year, .month, .day], from: Date())
        return "\(c.year!)-\(c.month!)-\(c.day!)"
    }
}

// MARK: - Storage Key

struct APITierKey: StorageKey {
    typealias Value = APITier
}

// MARK: - In-Memory Rate Limiter
//
// Simple actor-based counter. Fine for single-instance deployments.
// For multi-instance: replace with Redis INCR + EXPIRE.

actor InMemoryRateLimiter {
    private var counts: [String: (count: Int, day: String)] = [:]

    func increment(key: String) -> Int {
        let today = todayString()
        if let existing = counts[key], existing.day == today {
            let newCount = existing.count + 1
            counts[key] = (newCount, today)
            return newCount
        } else {
            counts[key] = (1, today)
            return 1
        }
    }

    private func todayString() -> String {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        let c = cal.dateComponents([.year, .month, .day], from: Date())
        return "\(c.year!)-\(c.month!)-\(c.day!)"
    }
}
