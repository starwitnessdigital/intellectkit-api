import Vapor
import SwiftSoup
import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif

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

    // MARK: - Markdown to HTML

    func markdownToHtml(req: Request) async throws -> MarkdownToHtmlResponse {
        let body = try req.content.decode(MarkdownToHtmlRequest.self)
        guard !body.markdown.isEmpty else {
            throw Abort(.badRequest, reason: "markdown field is required and cannot be empty")
        }
        let html = convertMarkdown(body.markdown)
        return MarkdownToHtmlResponse(
            html: html,
            characterCount: html.count,
            convertedAt: ISO8601DateFormatter().string(from: Date())
        )
    }

    // MARK: - Color Info

    func colorInfo(req: Request) async throws -> ColorInfoResponse {
        guard let hex = req.query[String.self, at: "hex"], !hex.isEmpty else {
            throw Abort(.badRequest, reason: "Missing required query parameter: hex")
        }

        let cleanHex = hex.trimmingCharacters(in: .whitespaces)
            .uppercased()
            .replacingOccurrences(of: "#", with: "")

        let normalHex: String
        if cleanHex.count == 3 {
            let chars = Array(cleanHex)
            normalHex = "\(chars[0])\(chars[0])\(chars[1])\(chars[1])\(chars[2])\(chars[2])"
        } else if cleanHex.count == 6 {
            normalHex = cleanHex
        } else {
            throw Abort(.badRequest, reason: "Invalid hex color. Expected 3 or 6 hex digits (e.g., FF5733 or F53)")
        }

        guard normalHex.range(of: #"^[0-9A-F]{6}$"#, options: .regularExpression) != nil else {
            throw Abort(.badRequest, reason: "Invalid hex color. Only hex characters (0-9, A-F) are allowed")
        }

        let r = Int(normalHex.prefix(2), radix: 16)!
        let g = Int(normalHex.dropFirst(2).prefix(2), radix: 16)!
        let b = Int(normalHex.dropFirst(4).prefix(2), radix: 16)!

        let (h, s, l) = rgbToHSL(r: r, g: g, b: b)

        let rgb = RGBColor(r: r, g: g, b: b, css: "rgb(\(r), \(g), \(b))")
        let hsl = HSLColor(h: h, s: s, l: l, css: "hsl(\(Int(h)), \(Int(s))%, \(Int(l))%)")

        let name = closestColorName(r: r, g: g, b: b)

        let compHue = (h + 180).truncatingRemainder(dividingBy: 360)
        let compHex = hslToHex(h: compHue, s: s, l: l)

        let triadic1 = hslToHex(h: (h + 120).truncatingRemainder(dividingBy: 360), s: s, l: l)
        let triadic2 = hslToHex(h: (h + 240).truncatingRemainder(dividingBy: 360), s: s, l: l)

        return ColorInfoResponse(
            hex: "#\(normalHex)",
            rgb: rgb,
            hsl: hsl,
            name: name,
            complementary: "#\(compHex)",
            triadic: ["#\(triadic1)", "#\(triadic2)"]
        )
    }

    // MARK: - Timestamp

    func timestamp(req: Request) async throws -> TimestampResponse {
        let format = req.query[String.self, at: "format"] ?? "iso"
        let providedUnix = req.query[Int.self, at: "timestamp"]

        let date = providedUnix.map { Date(timeIntervalSince1970: TimeInterval($0)) } ?? Date()
        let unixTime = Int(date.timeIntervalSince1970)

        let iso = ISO8601DateFormatter().string(from: date)

        let rfc2822Formatter = DateFormatter()
        rfc2822Formatter.locale = Locale(identifier: "en_US_POSIX")
        rfc2822Formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss Z"
        rfc2822Formatter.timeZone = TimeZone(abbreviation: "UTC")
        let rfc2822 = rfc2822Formatter.string(from: date)

        let humanFormatter = DateFormatter()
        humanFormatter.locale = Locale(identifier: "en_US")
        humanFormatter.dateStyle = .long
        humanFormatter.timeStyle = .long
        humanFormatter.timeZone = TimeZone(abbreviation: "UTC")
        let human = humanFormatter.string(from: date)

        let formatted: String
        switch format.lowercased() {
        case "unix":    formatted = "\(unixTime)"
        case "rfc2822": formatted = rfc2822
        case "human":   formatted = human
        default:        formatted = iso
        }

        return TimestampResponse(unix: unixTime, iso: iso, rfc2822: rfc2822, human: human, formatted: formatted)
    }

    // MARK: - Random

    func random(req: Request) async throws -> RandomResponse {
        let type = (req.query[String.self, at: "type"] ?? "uuid").lowercased()

        switch type {
        case "uuid":
            return RandomResponse(type: "uuid", value: UUID().uuidString)

        case "password":
            let length = min(max(req.query[Int.self, at: "length"] ?? 16, 8), 128)
            let charset = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789!@#$%^&*()-_=+[]{}|;:,.<>?"
            let value = String((0..<length).map { _ in charset.randomElement()! })
            return RandomResponse(type: "password", value: value)

        case "hex":
            let length = min(max(req.query[Int.self, at: "length"] ?? 32, 1), 256)
            let charset = "0123456789abcdef"
            let value = String((0..<length).map { _ in charset.randomElement()! })
            return RandomResponse(type: "hex", value: value)

        case "number":
            let minVal = req.query[Int.self, at: "min"] ?? 0
            let maxVal = req.query[Int.self, at: "max"] ?? 1_000_000
            guard minVal <= maxVal else {
                throw Abort(.badRequest, reason: "min must be less than or equal to max")
            }
            return RandomResponse(type: "number", value: "\(Int.random(in: minVal...maxVal))")

        case "string":
            let length = min(max(req.query[Int.self, at: "length"] ?? 16, 1), 256)
            let charset = req.query[String.self, at: "charset"] ?? "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ"
            guard !charset.isEmpty else {
                throw Abort(.badRequest, reason: "charset cannot be empty")
            }
            let value = String((0..<length).map { _ in charset.randomElement()! })
            return RandomResponse(type: "string", value: value)

        default:
            throw Abort(.badRequest, reason: "Unknown type: \(type). Valid types: uuid, password, hex, number, string")
        }
    }

    // MARK: - Diff

    func diff(req: Request) async throws -> DiffResponse {
        let body = try req.content.decode(DiffRequest.self)

        let lines1 = Array(body.text1.components(separatedBy: "\n").prefix(500))
        let lines2 = Array(body.text2.components(separatedBy: "\n").prefix(500))

        let diffLines = computeLCSDiff(lines1, lines2)

        let additions = diffLines.filter { $0.type == "addition" }.count
        let deletions = diffLines.filter { $0.type == "deletion" }.count
        let unchanged = diffLines.filter { $0.type == "unchanged" }.count
        let total = max(lines1.count + lines2.count, 1)
        let similarity = (Double(unchanged * 2) / Double(total) * 1000.0).rounded() / 10.0

        return DiffResponse(
            additions: additions,
            deletions: deletions,
            unchanged: unchanged,
            similarity: similarity,
            diff: diffLines
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

    // MARK: - Markdown Conversion

    private func convertMarkdown(_ markdown: String) -> String {
        let lines = markdown.components(separatedBy: "\n")
        var html = ""
        var inCodeBlock = false
        var codeBlockContent = ""
        var inUnorderedList = false
        var inOrderedList = false

        func closeLists() {
            if inUnorderedList { html += "</ul>\n"; inUnorderedList = false }
            if inOrderedList { html += "</ol>\n"; inOrderedList = false }
        }

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.hasPrefix("```") {
                if inCodeBlock {
                    html += escapeHTML(codeBlockContent) + "</code></pre>\n"
                    codeBlockContent = ""
                    inCodeBlock = false
                } else {
                    closeLists()
                    let lang = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                    let langAttr = lang.isEmpty ? "" : " class=\"language-\(lang)\""
                    html += "<pre><code\(langAttr)>"
                    inCodeBlock = true
                }
                continue
            }

            if inCodeBlock {
                if !codeBlockContent.isEmpty { codeBlockContent += "\n" }
                codeBlockContent += line
                continue
            }

            if trimmed.isEmpty {
                closeLists()
                continue
            }

            if trimmed.count >= 3 && trimmed.allSatisfy({ $0 == "-" || $0 == "*" || $0 == "_" }) && Set(trimmed).count == 1 {
                closeLists(); html += "<hr>\n"; continue
            }

            if trimmed.hasPrefix("###### ") {
                closeLists(); html += "<h6>\(inlineMD(String(trimmed.dropFirst(7))))</h6>\n"
            } else if trimmed.hasPrefix("##### ") {
                closeLists(); html += "<h5>\(inlineMD(String(trimmed.dropFirst(6))))</h5>\n"
            } else if trimmed.hasPrefix("#### ") {
                closeLists(); html += "<h4>\(inlineMD(String(trimmed.dropFirst(5))))</h4>\n"
            } else if trimmed.hasPrefix("### ") {
                closeLists(); html += "<h3>\(inlineMD(String(trimmed.dropFirst(4))))</h3>\n"
            } else if trimmed.hasPrefix("## ") {
                closeLists(); html += "<h2>\(inlineMD(String(trimmed.dropFirst(3))))</h2>\n"
            } else if trimmed.hasPrefix("# ") {
                closeLists(); html += "<h1>\(inlineMD(String(trimmed.dropFirst(2))))</h1>\n"
            } else if trimmed.hasPrefix("> ") {
                closeLists(); html += "<blockquote><p>\(inlineMD(String(trimmed.dropFirst(2))))</p></blockquote>\n"
            } else if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") || trimmed.hasPrefix("+ ") {
                if inOrderedList { html += "</ol>\n"; inOrderedList = false }
                if !inUnorderedList { html += "<ul>\n"; inUnorderedList = true }
                html += "<li>\(inlineMD(String(trimmed.dropFirst(2))))</li>\n"
            } else if trimmed.range(of: #"^\d+\. "#, options: .regularExpression) != nil {
                if inUnorderedList { html += "</ul>\n"; inUnorderedList = false }
                if !inOrderedList { html += "<ol>\n"; inOrderedList = true }
                let content = trimmed.replacingOccurrences(of: #"^\d+\. "#, with: "", options: .regularExpression)
                html += "<li>\(inlineMD(content))</li>\n"
            } else {
                closeLists(); html += "<p>\(inlineMD(trimmed))</p>\n"
            }
        }

        closeLists()
        if inCodeBlock { html += escapeHTML(codeBlockContent) + "</code></pre>\n" }
        return html.trimmingCharacters(in: .newlines)
    }

    private func inlineMD(_ text: String) -> String {
        var r = text
        // Images before links
        r = r.replacingOccurrences(of: #"!\[([^\]]*)\]\(([^)]+)\)"#, with: "<img src=\"$2\" alt=\"$1\">", options: .regularExpression)
        // Links
        r = r.replacingOccurrences(of: #"\[([^\]]+)\]\(([^)]+)\)"#, with: "<a href=\"$2\">$1</a>", options: .regularExpression)
        // Bold+italic
        r = r.replacingOccurrences(of: #"\*\*\*([^*]+)\*\*\*"#, with: "<strong><em>$1</em></strong>", options: .regularExpression)
        // Bold
        r = r.replacingOccurrences(of: #"\*\*([^*]+)\*\*"#, with: "<strong>$1</strong>", options: .regularExpression)
        r = r.replacingOccurrences(of: #"__([^_]+)__"#, with: "<strong>$1</strong>", options: .regularExpression)
        // Italic
        r = r.replacingOccurrences(of: #"\*([^*\s][^*]*)\*"#, with: "<em>$1</em>", options: .regularExpression)
        r = r.replacingOccurrences(of: #"_([^_\s][^_]*)_"#, with: "<em>$1</em>", options: .regularExpression)
        // Strikethrough
        r = r.replacingOccurrences(of: #"~~([^~]+)~~"#, with: "<del>$1</del>", options: .regularExpression)
        // Inline code
        r = r.replacingOccurrences(of: #"`([^`]+)`"#, with: "<code>$1</code>", options: .regularExpression)
        return r
    }

    private func escapeHTML(_ text: String) -> String {
        return text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    // MARK: - Color Helpers

    private func rgbToHSL(r: Int, g: Int, b: Int) -> (Double, Double, Double) {
        let rf = Double(r) / 255.0, gf = Double(g) / 255.0, bf = Double(b) / 255.0
        let maxC = Swift.max(rf, gf, bf), minC = Swift.min(rf, gf, bf)
        let delta = maxC - minC
        let l = (maxC + minC) / 2.0
        var h: Double = 0, s: Double = 0
        if delta > 0 {
            s = delta / (1 - abs(2 * l - 1))
            if maxC == rf      { h = 60 * (((gf - bf) / delta).truncatingRemainder(dividingBy: 6)) }
            else if maxC == gf { h = 60 * ((bf - rf) / delta + 2) }
            else               { h = 60 * ((rf - gf) / delta + 4) }
            if h < 0 { h += 360 }
        }
        return (h.rounded(), (s * 100).rounded(), (l * 100).rounded())
    }

    private func hslToHex(h: Double, s: Double, l: Double) -> String {
        let sf = s / 100.0, lf = l / 100.0
        let c = (1 - abs(2 * lf - 1)) * sf
        let x = c * (1 - abs((h / 60).truncatingRemainder(dividingBy: 2) - 1))
        let m = lf - c / 2
        var rf: Double, gf: Double, bf: Double
        switch h {
        case 0..<60:   rf = c; gf = x; bf = 0
        case 60..<120: rf = x; gf = c; bf = 0
        case 120..<180: rf = 0; gf = c; bf = x
        case 180..<240: rf = 0; gf = x; bf = c
        case 240..<300: rf = x; gf = 0; bf = c
        default:       rf = c; gf = 0; bf = x
        }
        let ri = Int(((rf + m) * 255).rounded())
        let gi = Int(((gf + m) * 255).rounded())
        let bi = Int(((bf + m) * 255).rounded())
        return String(format: "%02X%02X%02X", ri, gi, bi)
    }

    private func closestColorName(r: Int, g: Int, b: Int) -> String {
        let colors: [(String, Int, Int, Int)] = [
            ("Red", 255, 0, 0), ("Green", 0, 128, 0), ("Blue", 0, 0, 255),
            ("White", 255, 255, 255), ("Black", 0, 0, 0), ("Yellow", 255, 255, 0),
            ("Cyan", 0, 255, 255), ("Magenta", 255, 0, 255), ("Orange", 255, 165, 0),
            ("Purple", 128, 0, 128), ("Pink", 255, 192, 203), ("Brown", 165, 42, 42),
            ("Gray", 128, 128, 128), ("Silver", 192, 192, 192), ("Gold", 255, 215, 0),
            ("Navy", 0, 0, 128), ("Teal", 0, 128, 128), ("Maroon", 128, 0, 0),
            ("Olive", 128, 128, 0), ("Lime", 0, 255, 0), ("Coral", 255, 127, 80),
            ("Salmon", 250, 128, 114), ("Indigo", 75, 0, 130), ("Violet", 238, 130, 238),
            ("Turquoise", 64, 224, 208), ("Crimson", 220, 20, 60), ("Khaki", 240, 230, 140),
            ("Lavender", 230, 230, 250), ("Beige", 245, 245, 220), ("Ivory", 255, 255, 240),
            ("Charcoal", 54, 69, 79), ("Tan", 210, 180, 140), ("Sky Blue", 135, 206, 235),
            ("Mint", 152, 255, 152), ("Peach", 255, 218, 185), ("Rose", 255, 0, 127),
            ("Burgundy", 128, 0, 32), ("Emerald", 0, 201, 87), ("Amber", 255, 191, 0),
            ("Slate", 112, 128, 144),
        ]
        var closest = colors[0].0
        var minDist = Int.max
        for (name, cr, cg, cb) in colors {
            let d = (r - cr) * (r - cr) + (g - cg) * (g - cg) + (b - cb) * (b - cb)
            if d < minDist { minDist = d; closest = name }
        }
        return closest
    }

    // MARK: - Diff Helper

    private func computeLCSDiff(_ a: [String], _ b: [String]) -> [DiffLine] {
        let m = a.count, n = b.count
        if m == 0 { return b.map { DiffLine(type: "addition", content: $0) } }
        if n == 0 { return a.map { DiffLine(type: "deletion", content: $0) } }

        var dp = Array(repeating: Array(repeating: 0, count: n + 1), count: m + 1)
        for i in 1...m {
            for j in 1...n {
                dp[i][j] = a[i-1] == b[j-1] ? dp[i-1][j-1] + 1 : Swift.max(dp[i-1][j], dp[i][j-1])
            }
        }

        var result: [DiffLine] = []
        var i = m, j = n
        while i > 0 || j > 0 {
            if i > 0 && j > 0 && a[i-1] == b[j-1] {
                result.append(DiffLine(type: "unchanged", content: a[i-1])); i -= 1; j -= 1
            } else if j > 0 && (i == 0 || dp[i][j-1] >= dp[i-1][j]) {
                result.append(DiffLine(type: "addition", content: b[j-1])); j -= 1
            } else {
                result.append(DiffLine(type: "deletion", content: a[i-1])); i -= 1
            }
        }
        return result.reversed()
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
