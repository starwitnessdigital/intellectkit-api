import Vapor
import SwiftSoup
import Foundation

/// Developer utility tool endpoints.
///
/// GET /v1/tools/validate-email?email=user@example.com
/// GET /v1/tools/dns?domain=example.com
/// GET /v1/tools/whois?domain=example.com
/// GET /v1/tools/headers?url=https://example.com
/// GET /v1/tools/robots?url=https://example.com
/// GET /v1/tools/sitemap?url=https://example.com
/// GET /v1/tools/social?url=https://example.com
/// GET /v1/tools/tech-stack?url=https://example.com
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

    // MARK: - WHOIS Lookup

    func whois(req: Request) async throws -> WhoisResponse {
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

        let raw = try await runWhois(domain: cleaned)
        let parsed = parseWhoisOutput(raw)

        return WhoisResponse(
            domain: cleaned,
            registrar: parsed.registrar,
            creationDate: parsed.creationDate,
            expiryDate: parsed.expiryDate,
            updatedDate: parsed.updatedDate,
            nameServers: parsed.nameServers,
            status: parsed.status,
            registrantName: parsed.registrantName,
            registrantOrg: parsed.registrantOrg,
            registrantCountry: parsed.registrantCountry,
            rawOutput: raw,
            checkedAt: ISO8601DateFormatter().string(from: Date())
        )
    }

    // MARK: - HTTP Headers Inspection

    func httpHeaders(req: Request) async throws -> HeadersResponse {
        let url = try validatedURL(req)

        let uri = URI(string: url)
        let response = try await req.client.get(uri) { outReq in
            outReq.headers.replaceOrAdd(name: .userAgent, value: "IntellectKitBot/1.0 (AI Agent Web Extractor; https://intellectkit.dev)")
        }

        // Collect all headers into a flat dict (last value wins for duplicates except Set-Cookie)
        var allHeaders: [String: String] = [:]
        var cookies: [String] = []
        for (name, value) in response.headers {
            let lower = name.lowercased()
            if lower == "set-cookie" {
                cookies.append(value)
            } else {
                // Join multiple values with ", "
                if let existing = allHeaders[lower] {
                    allHeaders[lower] = "\(existing), \(value)"
                } else {
                    allHeaders[lower] = value
                }
            }
        }

        let security = SecurityHeaders(
            contentSecurityPolicy: allHeaders["content-security-policy"],
            strictTransportSecurity: allHeaders["strict-transport-security"],
            xFrameOptions: allHeaders["x-frame-options"],
            xContentTypeOptions: allHeaders["x-content-type-options"],
            referrerPolicy: allHeaders["referrer-policy"],
            permissionsPolicy: allHeaders["permissions-policy"]
        )

        let cache = CacheHeaders(
            cacheControl: allHeaders["cache-control"],
            etag: allHeaders["etag"],
            lastModified: allHeaders["last-modified"],
            expires: allHeaders["expires"]
        )

        return HeadersResponse(
            url: url,
            statusCode: Int(response.status.code),
            statusReason: response.status.reasonPhrase,
            server: allHeaders["server"],
            contentType: allHeaders["content-type"],
            allHeaders: allHeaders,
            securityHeaders: security,
            cacheHeaders: cache,
            cookies: cookies,
            checkedAt: ISO8601DateFormatter().string(from: Date())
        )
    }

    // MARK: - Robots.txt

    func robots(req: Request) async throws -> RobotsResponse {
        let url = try validatedURL(req)
        let robotsURL = try baseURL(from: url) + "/robots.txt"

        let uri = URI(string: robotsURL)
        let response = try await req.client.get(uri) { outReq in
            outReq.headers.replaceOrAdd(name: .userAgent, value: "IntellectKitBot/1.0 (AI Agent Web Extractor; https://intellectkit.dev)")
        }

        guard response.status.code < 400,
              let body = response.body,
              let text = body.getString(at: body.readerIndex, length: body.readableBytes) else {
            return RobotsResponse(
                url: url,
                robotsTxtUrl: robotsURL,
                found: false,
                rules: [],
                sitemaps: [],
                checkedAt: ISO8601DateFormatter().string(from: Date())
            )
        }

        let (rules, sitemaps) = parseRobotsTxt(text)

        return RobotsResponse(
            url: url,
            robotsTxtUrl: robotsURL,
            found: true,
            rules: rules,
            sitemaps: sitemaps,
            checkedAt: ISO8601DateFormatter().string(from: Date())
        )
    }

    // MARK: - Sitemap

    func sitemap(req: Request) async throws -> SitemapResponse {
        let url = try validatedURL(req)
        let sitemapURL = try baseURL(from: url) + "/sitemap.xml"

        let uri = URI(string: sitemapURL)
        let response = try await req.client.get(uri) { outReq in
            outReq.headers.replaceOrAdd(name: .userAgent, value: "IntellectKitBot/1.0 (AI Agent Web Extractor; https://intellectkit.dev)")
        }

        guard response.status.code < 400,
              let body = response.body,
              let xmlText = body.getString(at: body.readerIndex, length: body.readableBytes) else {
            return SitemapResponse(
                url: url,
                sitemapUrl: sitemapURL,
                found: false,
                urlCount: 0,
                urls: [],
                checkedAt: ISO8601DateFormatter().string(from: Date())
            )
        }

        let entries = parseSitemap(xmlText)
        // Cap at 500 to keep response sizes sane
        let limited = Array(entries.prefix(500))

        return SitemapResponse(
            url: url,
            sitemapUrl: sitemapURL,
            found: true,
            urlCount: entries.count,
            urls: limited,
            checkedAt: ISO8601DateFormatter().string(from: Date())
        )
    }

    // MARK: - Social Links

    func social(req: Request) async throws -> SocialLinksResponse {
        let url = try validatedURL(req)

        let uri = URI(string: url)
        let response = try await req.client.get(uri) { outReq in
            outReq.headers.replaceOrAdd(name: .userAgent, value: "IntellectKitBot/1.0 (AI Agent Web Extractor; https://intellectkit.dev)")
            outReq.headers.replaceOrAdd(name: .accept, value: "text/html,application/xhtml+xml,*/*;q=0.8")
        }
        guard let body = response.body,
              let html = body.getString(at: body.readerIndex, length: body.readableBytes) else {
            throw Abort(.badGateway, reason: "Could not read response from \(url)")
        }

        let doc = try SwiftSoup.parse(html)
        let linkEls = (try? doc.select("a[href]")) ?? Elements()
        var hrefs: [String] = []
        for el in linkEls {
            if let href = try? el.attr("href"), !href.isEmpty {
                hrefs.append(href)
            }
        }

        return SocialLinksResponse(
            url: url,
            twitter: findSocial(hrefs, patterns: ["twitter.com/", "x.com/"], exclusions: ["twitter.com/share", "twitter.com/intent", "x.com/intent"]),
            instagram: findSocial(hrefs, patterns: ["instagram.com/"], exclusions: ["instagram.com/p/"]),
            linkedin: findSocial(hrefs, patterns: ["linkedin.com/in/", "linkedin.com/company/", "linkedin.com/school/"]),
            facebook: findSocial(hrefs, patterns: ["facebook.com/"], exclusions: ["facebook.com/sharer", "facebook.com/dialog"]),
            youtube: findSocial(hrefs, patterns: ["youtube.com/channel/", "youtube.com/c/", "youtube.com/@", "youtube.com/user/"]),
            tiktok: findSocial(hrefs, patterns: ["tiktok.com/@"]),
            github: findSocial(hrefs, patterns: ["github.com/"], exclusions: ["github.com/features", "github.com/pricing", "github.com/login", "github.com/signup", "github.com/about"]),
            checkedAt: ISO8601DateFormatter().string(from: Date())
        )
    }

    // MARK: - Tech Stack Detection

    func techStack(req: Request) async throws -> TechStackResponse {
        let url = try validatedURL(req)

        let uri = URI(string: url)
        let response = try await req.client.get(uri) { outReq in
            outReq.headers.replaceOrAdd(name: .userAgent, value: "IntellectKitBot/1.0 (AI Agent Web Extractor; https://intellectkit.dev)")
            outReq.headers.replaceOrAdd(name: .accept, value: "text/html,application/xhtml+xml,*/*;q=0.8")
        }

        var allHeaders: [String: String] = [:]
        for (name, value) in response.headers {
            let lower = name.lowercased()
            if allHeaders[lower] == nil { allHeaders[lower] = value }
        }

        let html: String
        if let body = response.body,
           let str = body.getString(at: body.readerIndex, length: body.readableBytes) {
            html = str
        } else {
            html = ""
        }

        let doc = try? SwiftSoup.parse(html)
        let scriptSrcs = (try? doc?.select("script[src]"))?.compactMap { try? $0.attr("src") } ?? []
        let linkHrefs = (try? doc?.select("link[href]"))?.compactMap { try? $0.attr("href") } ?? []
        let metaGenerator = (try? doc?.select("meta[name=generator]").first()?.attr("content")) ?? ""
        let bodyHTML = html.lowercased()

        var detected: [String] = []

        // --- Server ---
        let server = allHeaders["server"]
        if let s = server, !s.isEmpty { detected.append("Server: \(s)") }

        // --- CDN / Hosting detection from headers ---
        var cdn: String? = nil
        var hosting: String? = nil

        if allHeaders["cf-ray"] != nil || allHeaders["cf-cache-status"] != nil {
            cdn = "Cloudflare"
            detected.append("CDN: Cloudflare")
        } else if allHeaders["x-vercel-id"] != nil {
            hosting = "Vercel"
            detected.append("Hosting: Vercel")
        } else if allHeaders["x-nf-request-id"] != nil || allHeaders["x-netlify"] != nil {
            hosting = "Netlify"
            detected.append("Hosting: Netlify")
        } else if allHeaders["x-amz-cf-id"] != nil || allHeaders["x-amz-request-id"] != nil {
            hosting = "AWS"
            detected.append("Hosting: AWS")
        } else if allHeaders["x-fly-request-id"] != nil {
            hosting = "Fly.io"
            detected.append("Hosting: Fly.io")
        } else if let via = allHeaders["via"], via.contains("varnish") {
            cdn = "Varnish"
            detected.append("CDN: Varnish")
        }

        if let xPowered = allHeaders["x-powered-by"] {
            detected.append("X-Powered-By: \(xPowered)")
        }

        // --- CMS Detection ---
        var cms: String? = nil
        let metaGen = metaGenerator.lowercased()

        if metaGen.contains("wordpress") || scriptSrcs.contains(where: { $0.contains("wp-content") || $0.contains("wp-includes") }) || linkHrefs.contains(where: { $0.contains("wp-content") }) {
            cms = "WordPress"
            detected.append("CMS: WordPress")
        } else if scriptSrcs.contains(where: { $0.contains("cdn.shopify.com") }) || bodyHTML.contains("shopify.com/s/files") {
            cms = "Shopify"
            detected.append("CMS: Shopify")
        } else if metaGen.contains("squarespace") || bodyHTML.contains("squarespace.com") {
            cms = "Squarespace"
            detected.append("CMS: Squarespace")
        } else if metaGen.contains("wix") || bodyHTML.contains("wix.com") || bodyHTML.contains("parastorage.com") {
            cms = "Wix"
            detected.append("CMS: Wix")
        } else if metaGen.contains("ghost") || bodyHTML.contains("ghost.io") {
            cms = "Ghost"
            detected.append("CMS: Ghost")
        } else if metaGen.contains("drupal") || bodyHTML.contains("drupal.js") {
            cms = "Drupal"
            detected.append("CMS: Drupal")
        } else if metaGen.contains("joomla") {
            cms = "Joomla"
            detected.append("CMS: Joomla")
        } else if metaGen.contains("webflow") || bodyHTML.contains("webflow.com") {
            cms = "Webflow"
            detected.append("CMS: Webflow")
        }

        // --- Framework Detection ---
        var framework: String? = nil

        if bodyHTML.contains("__next_data__") || scriptSrcs.contains(where: { $0.contains("/_next/") }) {
            framework = "Next.js"
            detected.append("Framework: Next.js")
        } else if bodyHTML.contains("__nuxt") || scriptSrcs.contains(where: { $0.contains("/_nuxt/") }) {
            framework = "Nuxt.js"
            detected.append("Framework: Nuxt.js")
        } else if scriptSrcs.contains(where: { $0.lowercased().contains("react") }) || bodyHTML.contains("data-reactroot") || bodyHTML.contains("data-reactid") {
            framework = "React"
            detected.append("Framework: React")
        } else if scriptSrcs.contains(where: { $0.lowercased().contains("vue") }) || bodyHTML.contains("data-v-") {
            framework = "Vue.js"
            detected.append("Framework: Vue.js")
        } else if bodyHTML.contains("ng-version") || scriptSrcs.contains(where: { $0.lowercased().contains("angular") }) {
            framework = "Angular"
            detected.append("Framework: Angular")
        } else if scriptSrcs.contains(where: { $0.lowercased().contains("svelte") }) || bodyHTML.contains("svelte") {
            framework = "Svelte"
            detected.append("Framework: Svelte")
        } else if scriptSrcs.contains(where: { $0.lowercased().contains("gatsby") }) || bodyHTML.contains("___gatsby") {
            framework = "Gatsby"
            detected.append("Framework: Gatsby")
        } else if bodyHTML.contains("django") && (allHeaders["x-frame-options"] != nil) {
            framework = "Django"
            detected.append("Framework: Django")
        } else if let powered = allHeaders["x-powered-by"] {
            let p = powered.lowercased()
            if p.contains("express") { framework = "Express.js"; detected.append("Framework: Express.js") }
            else if p.contains("rails") { framework = "Ruby on Rails"; detected.append("Framework: Ruby on Rails") }
            else if p.contains("laravel") { framework = "Laravel"; detected.append("Framework: Laravel") }
            else if p.contains("asp.net") { framework = "ASP.NET"; detected.append("Framework: ASP.NET") }
        }

        // --- Analytics Detection ---
        var analytics: [String] = []

        if scriptSrcs.contains(where: { $0.contains("google-analytics.com") || $0.contains("googletagmanager.com") }) || bodyHTML.contains("gtag(") || bodyHTML.contains("ga(") {
            analytics.append("Google Analytics")
            detected.append("Analytics: Google Analytics")
        }
        if scriptSrcs.contains(where: { $0.contains("plausible.io") }) || bodyHTML.contains("plausible.io") {
            analytics.append("Plausible")
            detected.append("Analytics: Plausible")
        }
        if scriptSrcs.contains(where: { $0.contains("hotjar.com") }) || bodyHTML.contains("hotjar") {
            analytics.append("Hotjar")
            detected.append("Analytics: Hotjar")
        }
        if scriptSrcs.contains(where: { $0.contains("mixpanel.com") }) || bodyHTML.contains("mixpanel") {
            analytics.append("Mixpanel")
            detected.append("Analytics: Mixpanel")
        }
        if scriptSrcs.contains(where: { $0.contains("segment.com") || $0.contains("segment.io") }) {
            analytics.append("Segment")
            detected.append("Analytics: Segment")
        }
        if scriptSrcs.contains(where: { $0.contains("posthog.com") }) || bodyHTML.contains("posthog") {
            analytics.append("PostHog")
            detected.append("Analytics: PostHog")
        }
        if scriptSrcs.contains(where: { $0.contains("fathom") }) {
            analytics.append("Fathom")
            detected.append("Analytics: Fathom")
        }

        return TechStackResponse(
            url: url,
            framework: framework,
            cms: cms,
            analytics: analytics,
            hosting: hosting,
            server: server,
            cdn: cdn,
            detected: detected,
            checkedAt: ISO8601DateFormatter().string(from: Date())
        )
    }

    // MARK: - Private Helpers

    private func validatedURL(_ req: Request) throws -> String {
        guard let url = req.query[String.self, at: "url"], !url.isEmpty else {
            throw Abort(.badRequest, reason: "Missing required query parameter: url")
        }
        let lower = url.lowercased()
        guard lower.hasPrefix("http://") || lower.hasPrefix("https://") else {
            throw Abort(.badRequest, reason: "URL must start with http:// or https://")
        }
        return url
    }

    private func baseURL(from url: String) throws -> String {
        guard let components = URLComponents(string: url),
              let scheme = components.scheme,
              let host = components.host else {
            throw Abort(.badRequest, reason: "Could not parse URL: \(url)")
        }
        let port = components.port.map { ":\($0)" } ?? ""
        return "\(scheme)://\(host)\(port)"
    }

    private func findSocial(_ hrefs: [String], patterns: [String], exclusions: [String] = []) -> String? {
        for href in hrefs {
            let lower = href.lowercased()
            let matches = patterns.contains { lower.contains($0) }
            let excluded = exclusions.contains { lower.contains($0) }
            if matches && !excluded {
                return href
            }
        }
        return nil
    }

    private func parseRobotsTxt(_ text: String) -> ([RobotsUserAgentRule], [String]) {
        var rules: [RobotsUserAgentRule] = []
        var sitemaps: [String] = []

        var currentUserAgents: [String] = []
        var currentAllow: [String] = []
        var currentDisallow: [String] = []
        var currentCrawlDelay: Double? = nil
        var inDirectiveBlock = false

        func flushBlock() {
            guard !currentUserAgents.isEmpty else { return }
            for agent in currentUserAgents {
                rules.append(RobotsUserAgentRule(
                    userAgent: agent,
                    allow: currentAllow,
                    disallow: currentDisallow,
                    crawlDelay: currentCrawlDelay
                ))
            }
            currentUserAgents = []
            currentAllow = []
            currentDisallow = []
            currentCrawlDelay = nil
            inDirectiveBlock = false
        }

        for line in text.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)

            // Blank line or comment ends the current block
            if trimmed.isEmpty || trimmed.hasPrefix("#") {
                if inDirectiveBlock { flushBlock() }
                continue
            }

            guard let colonIdx = trimmed.firstIndex(of: ":") else { continue }
            let key = String(trimmed[trimmed.startIndex..<colonIdx])
                .trimmingCharacters(in: .whitespaces)
                .lowercased()
            let value = String(trimmed[trimmed.index(after: colonIdx)...])
                .trimmingCharacters(in: .whitespaces)

            switch key {
            case "user-agent":
                if inDirectiveBlock { flushBlock() }
                currentUserAgents.append(value)
            case "allow":
                inDirectiveBlock = true
                if !value.isEmpty { currentAllow.append(value) }
            case "disallow":
                inDirectiveBlock = true
                if !value.isEmpty { currentDisallow.append(value) }
            case "crawl-delay":
                inDirectiveBlock = true
                currentCrawlDelay = Double(value)
            case "sitemap":
                if !value.isEmpty { sitemaps.append(value) }
            default:
                break
            }
        }
        flushBlock()

        return (rules, sitemaps)
    }

    private func parseSitemap(_ xml: String) -> [SitemapEntry] {
        let parser = SitemapXMLParser()
        if let data = xml.data(using: .utf8) {
            let xmlParser = XMLParser(data: data)
            xmlParser.delegate = parser
            xmlParser.parse()
        }
        return parser.entries
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

    private func runWhois(domain: String) async throws -> String {
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global().async {
                // Try both /usr/bin/whois and /usr/local/bin/whois
                let whoisPaths = ["/usr/bin/whois", "/usr/local/bin/whois"]
                let executableURL = whoisPaths.compactMap { path -> URL? in
                    let url = URL(fileURLWithPath: path)
                    return FileManager.default.fileExists(atPath: path) ? url : nil
                }.first

                guard let execURL = executableURL else {
                    continuation.resume(returning: "whois command not available")
                    return
                }

                let process = Process()
                process.executableURL = execURL
                process.arguments = [domain]

                let pipe = Pipe()
                process.standardOutput = pipe
                process.standardError = Pipe()

                do {
                    try process.run()
                    // Whois can be slow; give it 10 seconds
                    let deadline = DispatchTime.now() + .seconds(10)
                    if process.isRunning {
                        DispatchQueue.global().asyncAfter(deadline: deadline) {
                            if process.isRunning { process.terminate() }
                        }
                    }
                    process.waitUntilExit()
                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    let output = String(data: data, encoding: .utf8) ?? ""
                    continuation.resume(returning: output)
                } catch {
                    continuation.resume(returning: "")
                }
            }
        }
    }

    private func parseWhoisOutput(_ raw: String) -> (
        registrar: String?,
        creationDate: String?,
        expiryDate: String?,
        updatedDate: String?,
        nameServers: [String],
        status: [String],
        registrantName: String?,
        registrantOrg: String?,
        registrantCountry: String?
    ) {
        var registrar: String? = nil
        var creationDate: String? = nil
        var expiryDate: String? = nil
        var updatedDate: String? = nil
        var nameServers: [String] = []
        var status: [String] = []
        var registrantName: String? = nil
        var registrantOrg: String? = nil
        var registrantCountry: String? = nil

        for line in raw.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("%"), !trimmed.hasPrefix("#") else { continue }

            guard let colonIdx = trimmed.firstIndex(of: ":") else { continue }
            let key = String(trimmed[trimmed.startIndex..<colonIdx])
                .trimmingCharacters(in: .whitespaces)
                .lowercased()
            let value = String(trimmed[trimmed.index(after: colonIdx)...])
                .trimmingCharacters(in: .whitespaces)

            guard !value.isEmpty else { continue }

            switch key {
            case "registrar":
                if registrar == nil { registrar = value }
            case "creation date", "created", "domain registration date", "registered on":
                if creationDate == nil { creationDate = value }
            case "registry expiry date", "registrar registration expiration date", "expiry date", "expires on", "expiration date":
                if expiryDate == nil { expiryDate = value }
            case "updated date", "last updated", "last modified":
                if updatedDate == nil { updatedDate = value }
            case "name server":
                let ns = value.lowercased()
                if !nameServers.contains(ns) { nameServers.append(ns) }
            case "domain status":
                // Status lines often have a URL appended, take just the first word
                let statusValue = value.components(separatedBy: " ").first ?? value
                if !status.contains(statusValue) { status.append(statusValue) }
            case "registrant name":
                if registrantName == nil { registrantName = value }
            case "registrant organization", "registrant org":
                if registrantOrg == nil { registrantOrg = value }
            case "registrant country":
                if registrantCountry == nil { registrantCountry = value }
            default:
                break
            }
        }

        return (registrar, creationDate, expiryDate, updatedDate, nameServers, status, registrantName, registrantOrg, registrantCountry)
    }
}

// MARK: - Sitemap XML Parser

private class SitemapXMLParser: NSObject, XMLParserDelegate {
    var entries: [SitemapEntry] = []

    private var currentLoc: String? = nil
    private var currentLastmod: String? = nil
    private var currentChangefreq: String? = nil
    private var currentPriority: Double? = nil
    private var currentElement: String = ""
    private var currentText: String = ""
    private var inURL = false

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        currentElement = elementName.lowercased()
        currentText = ""
        if currentElement == "url" {
            inURL = true
            currentLoc = nil
            currentLastmod = nil
            currentChangefreq = nil
            currentPriority = nil
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        currentText += string
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        let el = elementName.lowercased()
        let text = currentText.trimmingCharacters(in: .whitespacesAndNewlines)

        if inURL {
            switch el {
            case "loc": currentLoc = text
            case "lastmod": currentLastmod = text.isEmpty ? nil : text
            case "changefreq": currentChangefreq = text.isEmpty ? nil : text
            case "priority": currentPriority = Double(text)
            case "url":
                if let loc = currentLoc, !loc.isEmpty {
                    entries.append(SitemapEntry(
                        url: loc,
                        lastmod: currentLastmod,
                        changefreq: currentChangefreq,
                        priority: currentPriority
                    ))
                }
                inURL = false
            default: break
            }
        }
        currentText = ""
    }
}
