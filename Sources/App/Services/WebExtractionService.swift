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

    // MARK: - Structured Extraction

    func extractStructured(schema: String) throws -> StructuredExtractionResponse {
        let doc = try SwiftSoup.parse(html)
        var fields: [String: String] = [:]
        var arrays: [String: [String]] = [:]

        let jsonLDBlocks = extractJSONLDBlocks(doc)

        switch schema.lowercased() {
        case "product":
            if let block = jsonLDBlock(from: jsonLDBlocks, types: ["Product"]) {
                setLD(&fields, "name", ldString(block, "name"))
                setLD(&fields, "description", ldString(block, "description"))
                setLD(&fields, "price", ldNestedString(block, "offers", "price"))
                setLD(&fields, "currency", ldNestedString(block, "offers", "priceCurrency"))
                setLD(&fields, "brand", ldString(block, "brand") ?? ldNestedString(block, "brand", "name"))
                setLD(&fields, "availability", ldNestedString(block, "offers", "availability"))
                setLD(&fields, "sku", ldString(block, "sku"))
                setLD(&fields, "ratingValue", ldNestedString(block, "aggregateRating", "ratingValue"))
                setLD(&fields, "reviewCount", ldNestedString(block, "aggregateRating", "reviewCount"))
                if let img = ldImageURL(block) { arrays["images"] = [img] }
            }
            if fields["name"] == nil { fields["name"] = nonEmpty(try? doc.select("[itemprop=name]").first()?.text()) ?? nonEmpty(try? doc.select("h1").first()?.text()) }
            if fields["price"] == nil { fields["price"] = nonEmpty(try? doc.select("[itemprop=price]").first()?.attr("content")) ?? nonEmpty(try? doc.select("[itemprop=price]").first()?.text()) }
            if fields["description"] == nil { fields["description"] = nonEmpty(try? doc.select("[itemprop=description]").first()?.text()) ?? nonEmpty(try? doc.select("meta[property=og:description]").first()?.attr("content")) }
            if arrays["images"] == nil { arrays["images"] = [nonEmpty(try? doc.select("meta[property=og:image]").first()?.attr("content"))].compactMap { $0 } }

        case "article":
            if let block = jsonLDBlock(from: jsonLDBlocks, types: ["Article", "NewsArticle", "BlogPosting"]) {
                setLD(&fields, "title", ldString(block, "headline") ?? ldString(block, "name"))
                setLD(&fields, "description", ldString(block, "description"))
                setLD(&fields, "author", ldString(block, "author") ?? ldNestedString(block, "author", "name"))
                setLD(&fields, "publishedDate", ldString(block, "datePublished"))
                setLD(&fields, "modifiedDate", ldString(block, "dateModified"))
                if let img = ldImageURL(block) { arrays["images"] = [img] }
            }
            if fields["title"] == nil { fields["title"] = nonEmpty(try? doc.select("meta[property=og:title]").first()?.attr("content")) ?? nonEmpty(try? doc.title()) }
            if fields["author"] == nil { fields["author"] = nonEmpty(try? doc.select("meta[name=author]").first()?.attr("content")) ?? nonEmpty(try? doc.select("[rel=author]").first()?.text()) }
            if fields["publishedDate"] == nil { fields["publishedDate"] = nonEmpty(try? doc.select("meta[property=article:published_time]").first()?.attr("content")) ?? nonEmpty(try? doc.select("[itemprop=datePublished]").first()?.attr("datetime")) }
            if fields["description"] == nil { fields["description"] = nonEmpty(try? doc.select("meta[name=description]").first()?.attr("content")) }

        case "recipe":
            if let block = jsonLDBlock(from: jsonLDBlocks, types: ["Recipe"]) {
                setLD(&fields, "name", ldString(block, "name"))
                setLD(&fields, "description", ldString(block, "description"))
                setLD(&fields, "author", ldString(block, "author") ?? ldNestedString(block, "author", "name"))
                setLD(&fields, "prepTime", ldString(block, "prepTime"))
                setLD(&fields, "cookTime", ldString(block, "cookTime"))
                setLD(&fields, "totalTime", ldString(block, "totalTime"))
                setLD(&fields, "servings", ldString(block, "recipeYield"))
                setLD(&fields, "calories", ldNestedString(block, "nutrition", "calories"))
                setLD(&fields, "cuisine", ldString(block, "recipeCuisine"))
                setLD(&fields, "category", ldString(block, "recipeCategory"))
                if let img = ldImageURL(block) { arrays["images"] = [img] }
                let ingredients = ldArray(block, "recipeIngredient")
                if !ingredients.isEmpty { arrays["ingredients"] = ingredients }
                let instructions = ldInstructions(block)
                if !instructions.isEmpty { arrays["instructions"] = instructions }
            }
            if fields["name"] == nil { fields["name"] = nonEmpty(try? doc.select("[itemprop=name]").first()?.text()) ?? nonEmpty(try? doc.select("h1").first()?.text()) }
            if arrays["ingredients"] == nil {
                let els = (try? doc.select("[itemprop=recipeIngredient]")) ?? Elements()
                let items = els.compactMap { try? $0.text() }.filter { !$0.isEmpty }
                if !items.isEmpty { arrays["ingredients"] = items }
            }

        case "event":
            if let block = jsonLDBlock(from: jsonLDBlocks, types: ["Event"]) {
                setLD(&fields, "name", ldString(block, "name"))
                setLD(&fields, "description", ldString(block, "description"))
                setLD(&fields, "startDate", ldString(block, "startDate"))
                setLD(&fields, "endDate", ldString(block, "endDate"))
                setLD(&fields, "url", ldString(block, "url"))
                setLD(&fields, "location", ldString(block, "location") ?? ldNestedString(block, "location", "name"))
                setLD(&fields, "organizer", ldString(block, "organizer") ?? ldNestedString(block, "organizer", "name"))
                if let img = ldImageURL(block) { arrays["images"] = [img] }
            }
            if fields["name"] == nil { fields["name"] = nonEmpty(try? doc.select("[itemprop=name]").first()?.text()) ?? nonEmpty(try? doc.select("h1").first()?.text()) }
            if fields["startDate"] == nil { fields["startDate"] = nonEmpty(try? doc.select("[itemprop=startDate]").first()?.attr("content")) ?? nonEmpty(try? doc.select("[itemprop=startDate]").first()?.attr("datetime")) }
            if fields["location"] == nil { fields["location"] = nonEmpty(try? doc.select("[itemprop=location] [itemprop=name]").first()?.text()) ?? nonEmpty(try? doc.select("[itemprop=location]").first()?.text()) }

        case "person":
            if let block = jsonLDBlock(from: jsonLDBlocks, types: ["Person"]) {
                setLD(&fields, "name", ldString(block, "name"))
                setLD(&fields, "jobTitle", ldString(block, "jobTitle"))
                setLD(&fields, "description", ldString(block, "description"))
                setLD(&fields, "email", ldString(block, "email"))
                setLD(&fields, "telephone", ldString(block, "telephone"))
                setLD(&fields, "url", ldString(block, "url"))
                setLD(&fields, "organization", ldString(block, "worksFor") ?? ldNestedString(block, "worksFor", "name"))
                if let img = ldImageURL(block) { fields["image"] = img }
                let sameAs = ldArray(block, "sameAs")
                if !sameAs.isEmpty { arrays["sameAs"] = sameAs }
            }
            if fields["name"] == nil { fields["name"] = nonEmpty(try? doc.select("[itemprop=name]").first()?.text()) ?? nonEmpty(try? doc.select("h1").first()?.text()) }
            if fields["jobTitle"] == nil { fields["jobTitle"] = nonEmpty(try? doc.select("[itemprop=jobTitle]").first()?.text()) }
            if fields["description"] == nil { fields["description"] = nonEmpty(try? doc.select("meta[name=description]").first()?.attr("content")) }

        case "organization":
            if let block = jsonLDBlock(from: jsonLDBlocks, types: ["Organization", "LocalBusiness", "Corporation"]) {
                setLD(&fields, "name", ldString(block, "name"))
                setLD(&fields, "description", ldString(block, "description"))
                setLD(&fields, "url", ldString(block, "url"))
                setLD(&fields, "email", ldString(block, "email"))
                setLD(&fields, "telephone", ldString(block, "telephone"))
                setLD(&fields, "address", ldFormattedAddress(block["address"] as? [String: Any]))
                if let logo = ldImageURL(block, key: "logo") { fields["logo"] = logo }
                if let img = ldImageURL(block) { fields["image"] = img }
                let sameAs = ldArray(block, "sameAs")
                if !sameAs.isEmpty { arrays["sameAs"] = sameAs }
            }
            if fields["name"] == nil { fields["name"] = nonEmpty(try? doc.select("[itemprop=name]").first()?.text()) ?? nonEmpty(try? doc.select("meta[property=og:site_name]").first()?.attr("content")) }
            if fields["description"] == nil { fields["description"] = nonEmpty(try? doc.select("meta[name=description]").first()?.attr("content")) }
            if fields["url"] == nil { fields["url"] = nonEmpty(try? doc.select("link[rel=canonical]").first()?.attr("href")) }

        default:
            throw Abort(.badRequest, reason: "Unknown schema: \(schema). Valid schemas: product, article, recipe, event, person, organization")
        }

        return StructuredExtractionResponse(
            url: baseURL,
            schema: schema,
            fields: fields.filter { !$0.value.isEmpty },
            arrays: arrays.filter { !$0.value.isEmpty },
            extractedAt: nowISO8601()
        )
    }

    // MARK: - JSON-LD Helpers

    private func extractJSONLDBlocks(_ doc: Document) -> [[String: Any]] {
        var blocks: [[String: Any]] = []
        guard let scripts = try? doc.select("script[type=application/ld+json]") else { return blocks }
        for script in scripts {
            guard let content = try? script.data(),
                  let data = content.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) else { continue }
            if let dict = json as? [String: Any] {
                if let graph = dict["@graph"] as? [[String: Any]] {
                    blocks.append(contentsOf: graph)
                } else {
                    blocks.append(dict)
                }
            } else if let arr = json as? [[String: Any]] {
                blocks.append(contentsOf: arr)
            }
        }
        return blocks
    }

    private func jsonLDBlock(from blocks: [[String: Any]], types: [String]) -> [String: Any]? {
        let lower = types.map { $0.lowercased() }
        return blocks.first { block in
            if let t = block["@type"] as? String { return lower.contains(t.lowercased()) }
            if let ts = block["@type"] as? [String] { return ts.contains { lower.contains($0.lowercased()) } }
            return false
        }
    }

    private func ldString(_ block: [String: Any], _ key: String) -> String? {
        if let v = block[key] as? String, !v.isEmpty { return v }
        if let v = block[key] as? [String: Any] { return v["name"] as? String ?? v["@id"] as? String }
        return nil
    }

    private func ldNestedString(_ block: [String: Any], _ key: String, _ nested: String) -> String? {
        if let obj = block[key] as? [String: Any] { return obj[nested] as? String }
        if let arr = block[key] as? [[String: Any]], let first = arr.first { return first[nested] as? String }
        return nil
    }

    private func ldArray(_ block: [String: Any], _ key: String) -> [String] {
        if let arr = block[key] as? [String] { return arr }
        if let str = block[key] as? String { return [str] }
        if let arr = block[key] as? [[String: Any]] { return arr.compactMap { $0["text"] as? String ?? $0["name"] as? String } }
        return []
    }

    private func ldImageURL(_ block: [String: Any], key: String = "image") -> String? {
        if let v = block[key] as? String, !v.isEmpty { return v }
        if let v = block[key] as? [String: Any] { return v["url"] as? String ?? v["@id"] as? String }
        if let arr = block[key] as? [String], let first = arr.first { return first }
        if let arr = block[key] as? [[String: Any]], let first = arr.first { return first["url"] as? String }
        return nil
    }

    private func ldInstructions(_ block: [String: Any]) -> [String] {
        let raw: Any? = block["recipeInstructions"]
        if let arr = raw as? [String] { return arr }
        if let arr = raw as? [[String: Any]] { return arr.compactMap { $0["text"] as? String } }
        if let str = raw as? String { return [str] }
        return []
    }

    private func ldFormattedAddress(_ addr: [String: Any]?) -> String? {
        guard let addr = addr else { return nil }
        let parts = [addr["streetAddress"], addr["addressLocality"], addr["addressRegion"],
                     addr["postalCode"], addr["addressCountry"]].compactMap { $0 as? String }
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }

    private func setLD(_ dict: inout [String: String], _ key: String, _ value: String?) {
        if let v = value, !v.isEmpty { dict[key] = v }
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
