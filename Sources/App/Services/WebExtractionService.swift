import Vapor
import SwiftSoup
import Foundation

// MARK: - Web Extraction Service
//
// Fetches a remote URL and parses the HTML with SwiftSoup to return
// typed structured data. All parsing is best-effort — fields that
// can't be found are nil rather than errors.

struct WebExtractionService {
    let html: String
    let baseURL: String

    // MARK: - Factory

    /// Fetches `url` and returns a service ready to parse its HTML.
    static func fetch(url: String, client: Client) async throws -> WebExtractionService {
        let uri = URI(string: url)
        let response = try await client.get(uri) { req in
            req.headers.replaceOrAdd(name: .userAgent, value: "IntellectKitBot/1.0 (AI Agent Web Extractor; https://intellectkit.dev)")
            req.headers.replaceOrAdd(name: .accept, value: "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8")
        }
        guard let body = response.body,
              let html = body.getString(at: body.readerIndex, length: body.readableBytes) else {
            throw Abort(.badGateway, reason: "Could not read response body from \(url). HTTP \(response.status.code).")
        }
        return WebExtractionService(html: html, baseURL: url)
    }

    // MARK: - Article

    func extractArticle() throws -> ArticleExtractionResponse {
        let doc = try SwiftSoup.parse(html)

        // Title: prefer OG, fall back to <title>
        let title = nonEmpty(try? doc.select("meta[property=og:title]").first()?.attr("content"))
            ?? nonEmpty(try? doc.title())

        // Author
        let author = nonEmpty(try? doc.select("meta[name=author]").first()?.attr("content"))
            ?? nonEmpty(try? doc.select("[rel=author]").first()?.text())
            ?? nonEmpty(try? doc.select("[itemprop=author]").first()?.text())
            ?? nonEmpty(try? doc.select(".author").first()?.text())
            ?? nonEmpty(try? doc.select(".byline").first()?.text())

        // Published date
        let publishedDate = nonEmpty(try? doc.select("meta[property=article:published_time]").first()?.attr("content"))
            ?? nonEmpty(try? doc.select("[itemprop=datePublished]").first()?.attr("datetime"))
            ?? nonEmpty(try? doc.select("[itemprop=datePublished]").first()?.attr("content"))
            ?? nonEmpty(try? doc.select("time[datetime]").first()?.attr("datetime"))

        // Article body: prefer <article>, then <main>, fall back to <body>
        let articleEl: Element? = (try? doc.select("article").first())
            ?? (try? doc.select("[role=main]").first())
            ?? (try? doc.select("main").first())
            ?? doc.body()

        // Strip noise from the selected element
        for selector in ["nav", "header", "footer", "aside", "script", "style", "noscript",
                         ".related", ".comments", ".social-share", ".sidebar",
                         "[class*=advertisement]", "[class*=cookie]", "[class*=popup]"] {
            if let els = try? articleEl?.select(selector) {
                for el in els { try? el.remove() }
            }
        }

        let bodyText = (try? articleEl?.text()) ?? ""

        // Images within the article
        var images: [String] = []
        if let imgEls = try? articleEl?.select("img[src]") {
            for el in imgEls {
                if let src = try? el.attr("src"), let resolved = resolveURL(src) {
                    images.append(resolved)
                }
            }
        }

        let words = bodyText.split(whereSeparator: \.isWhitespace).count
        let readingTime = max(1, words / 200)
        let summary: String = {
            let trimmed = bodyText.trimmingCharacters(in: .whitespaces)
            guard trimmed.count > 300 else { return trimmed }
            let idx = trimmed.index(trimmed.startIndex, offsetBy: 300)
            return String(trimmed[..<idx]) + "…"
        }()

        return ArticleExtractionResponse(
            url: baseURL,
            title: title,
            author: author,
            publishedDate: publishedDate,
            bodyText: bodyText,
            images: images,
            wordCount: words,
            readingTimeMinutes: readingTime,
            summary: summary,
            extractedAt: nowISO8601()
        )
    }

    // MARK: - Product

    func extractProduct() throws -> ProductExtractionResponse {
        let doc = try SwiftSoup.parse(html)

        let name = nonEmpty(try? doc.select("[itemprop=name]").first()?.text())
            ?? nonEmpty(try? doc.select("meta[property=og:title]").first()?.attr("content"))
            ?? nonEmpty(try? doc.select("h1").first()?.text())

        let price = nonEmpty(try? doc.select("[itemprop=price]").first()?.attr("content"))
            ?? nonEmpty(try? doc.select("[itemprop=price]").first()?.text())
            ?? nonEmpty(try? doc.select("meta[property=product:price:amount]").first()?.attr("content"))

        let currency = nonEmpty(try? doc.select("[itemprop=priceCurrency]").first()?.attr("content"))
            ?? nonEmpty(try? doc.select("meta[property=product:price:currency]").first()?.attr("content"))

        let description = nonEmpty(try? doc.select("[itemprop=description]").first()?.text())
            ?? nonEmpty(try? doc.select("meta[property=og:description]").first()?.attr("content"))
            ?? nonEmpty(try? doc.select("meta[name=description]").first()?.attr("content"))

        let brand = nonEmpty(try? doc.select("[itemprop=brand] [itemprop=name]").first()?.text())
            ?? nonEmpty(try? doc.select("[itemprop=brand]").first()?.text())

        let availability = nonEmpty(try? doc.select("[itemprop=availability]").first()?.attr("content"))
            ?? nonEmpty(try? doc.select("[itemprop=availability]").first()?.text())

        let ratingValue = nonEmpty(try? doc.select("[itemprop=ratingValue]").first()?.attr("content"))
            ?? nonEmpty(try? doc.select("[itemprop=ratingValue]").first()?.text())

        let reviewCount = nonEmpty(try? doc.select("[itemprop=reviewCount]").first()?.attr("content"))
            ?? nonEmpty(try? doc.select("[itemprop=reviewCount]").first()?.text())

        // Images: OG image first, then itemprop=image
        var images: [String] = []
        if let ogImg = nonEmpty(try? doc.select("meta[property=og:image]").first()?.attr("content")) {
            images.append(ogImg)
        }
        if let imgEls = try? doc.select("[itemprop=image]") {
            for el in imgEls {
                let src = nonEmpty(try? el.attr("src")) ?? nonEmpty(try? el.attr("content"))
                if let s = src, !images.contains(s) {
                    images.append(resolveURL(s) ?? s)
                }
            }
        }

        return ProductExtractionResponse(
            url: baseURL,
            name: name,
            price: price,
            currency: currency,
            description: description,
            images: images,
            brand: brand,
            availability: availability,
            ratingValue: ratingValue,
            reviewCount: reviewCount,
            extractedAt: nowISO8601()
        )
    }

    // MARK: - Metadata

    func extractMetadata() throws -> MetadataExtractionResponse {
        let doc = try SwiftSoup.parse(html)

        let title = nonEmpty(try? doc.title())
        let description = nonEmpty(try? doc.select("meta[name=description]").first()?.attr("content"))

        var ogTags: [String: String] = [:]
        if let els = try? doc.select("meta[property^=og:]") {
            for el in els {
                if let prop = nonEmpty(try? el.attr("property")),
                   let content = try? el.attr("content") {
                    let key = prop.replacingOccurrences(of: "og:", with: "")
                    ogTags[key] = content
                }
            }
        }

        var twitterTags: [String: String] = [:]
        if let els = try? doc.select("meta[name^=twitter:]") {
            for el in els {
                if let name = nonEmpty(try? el.attr("name")),
                   let content = try? el.attr("content") {
                    let key = name.replacingOccurrences(of: "twitter:", with: "")
                    twitterTags[key] = content
                }
            }
        }

        let canonicalURL = nonEmpty(try? doc.select("link[rel=canonical]").first()?.attr("href"))
        let language = nonEmpty(try? doc.select("html").first()?.attr("lang"))

        let favicon: String? = {
            let selectors = ["link[rel='shortcut icon']", "link[rel=icon]", "link[rel='apple-touch-icon']"]
            for sel in selectors {
                if let href = nonEmpty(try? doc.select(sel).first()?.attr("href")) {
                    return resolveURL(href) ?? href
                }
            }
            return nil
        }()

        var jsonLD: [String] = []
        if let els = try? doc.select("script[type=application/ld+json]") {
            for el in els {
                if let data = nonEmpty(try? el.data()) {
                    jsonLD.append(data)
                }
            }
        }

        return MetadataExtractionResponse(
            url: baseURL,
            title: title,
            description: description,
            ogTags: ogTags,
            twitterTags: twitterTags,
            canonicalURL: canonicalURL,
            language: language,
            favicon: favicon,
            jsonLD: jsonLD,
            extractedAt: nowISO8601()
        )
    }

    // MARK: - Links

    func extractLinks() throws -> LinksExtractionResponse {
        let doc = try SwiftSoup.parse(html)
        let baseHost = URL(string: baseURL)?.host ?? ""

        var links: [ExtractedLink] = []
        let anchors = (try? doc.select("a[href]")) ?? Elements()

        for anchor in anchors {
            guard let rawHref = try? anchor.attr("href"),
                  !rawHref.isEmpty,
                  !rawHref.hasPrefix("#"),
                  !rawHref.hasPrefix("javascript:"),
                  !rawHref.hasPrefix("mailto:"),
                  !rawHref.hasPrefix("tel:") else { continue }

            let href = resolveURL(rawHref) ?? rawHref
            let text = (try? anchor.text())?.trimmingCharacters(in: .whitespaces) ?? ""
            let rel = nonEmpty(try? anchor.attr("rel"))

            let isExternal: Bool = {
                guard let linkHost = URL(string: href)?.host else { return false }
                return linkHost != baseHost
            }()

            links.append(ExtractedLink(href: href, text: text, rel: rel, isExternal: isExternal))
        }

        let internalCount = links.filter { !$0.isExternal }.count
        let externalCount = links.filter { $0.isExternal }.count

        return LinksExtractionResponse(
            url: baseURL,
            totalLinks: links.count,
            internalLinks: internalCount,
            externalLinks: externalCount,
            links: links,
            extractedAt: nowISO8601()
        )
    }

    // MARK: - Clean Text

    func extractText() throws -> TextExtractionResponse {
        let doc = try SwiftSoup.parse(html)

        let noiseSelectors = [
            "nav", "header", "footer", "aside", "script", "style", "noscript",
            "[class*=nav]", "[class*=menu]", "[class*=sidebar]",
            "[class*=cookie]", "[class*=banner]", "[class*=advertisement]",
            "[class*=popup]", "[class*=modal]",
            "[id*=nav]", "[id*=menu]", "[id*=sidebar]", "[id*=cookie]",
        ]
        for selector in noiseSelectors {
            if let els = try? doc.select(selector) {
                for el in els { try? el.remove() }
            }
        }

        let text = ((try? doc.body()?.text()) ?? "").trimmingCharacters(in: .whitespaces)
        let words = text.split(whereSeparator: \.isWhitespace).count

        return TextExtractionResponse(
            url: baseURL,
            text: text,
            wordCount: words,
            characterCount: text.count,
            extractedAt: nowISO8601()
        )
    }

    // MARK: - Helpers

    /// Resolves relative URLs against the base URL.
    private func resolveURL(_ path: String?) -> String? {
        guard let path = path, !path.isEmpty else { return nil }
        if path.hasPrefix("http://") || path.hasPrefix("https://") { return path }
        guard let base = URL(string: baseURL) else { return path }
        if path.hasPrefix("//") {
            return "\(base.scheme ?? "https"):\(path)"
        }
        if path.hasPrefix("/") {
            let port = base.port.map { ":\($0)" } ?? ""
            return "\(base.scheme ?? "https")://\(base.host ?? "")\(port)\(path)"
        }
        return URL(string: path, relativeTo: base)?.absoluteString ?? path
    }

    /// Returns nil if the string is nil or empty/whitespace-only.
    private func nonEmpty(_ value: String?) -> String? {
        guard let v = value, !v.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        return v
    }

    private func nowISO8601() -> String {
        ISO8601DateFormatter().string(from: Date())
    }
}
