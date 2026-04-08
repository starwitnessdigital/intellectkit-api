import Vapor
import Crypto

/// Security utility endpoints.
///
/// POST /v1/security/hash               – generate MD5/SHA1/SHA256/SHA512 hash
/// POST /v1/security/password-strength  – score password strength with feedback
struct SecurityController {

    func hash(req: Request) async throws -> HashResponse {
        let body = try req.content.decode(HashRequest.self)
        guard !body.text.isEmpty else {
            throw Abort(.badRequest, reason: "text must not be empty")
        }
        let algo = body.algorithm.lowercased()
        guard ["md5", "sha1", "sha256", "sha512"].contains(algo) else {
            throw Abort(.badRequest, reason: "algorithm must be one of: md5, sha1, sha256, sha512")
        }
        return try computeHash(body.text, algorithm: algo)
    }

    func passwordStrength(req: Request) async throws -> PasswordStrengthResponse {
        let body = try req.content.decode(PasswordStrengthRequest.self)
        guard !body.password.isEmpty else {
            throw Abort(.badRequest, reason: "password must not be empty")
        }
        return analyzePassword(body.password)
    }
}

// MARK: - Hash

private extension SecurityController {

    func computeHash(_ text: String, algorithm: String) throws -> HashResponse {
        let data = Data(text.utf8)
        let hex: String
        switch algorithm {
        case "md5":    hex = Insecure.MD5.hash(data: data).hexString
        case "sha1":   hex = Insecure.SHA1.hash(data: data).hexString
        case "sha256": hex = SHA256.hash(data: data).hexString
        case "sha512": hex = SHA512.hash(data: data).hexString
        default: throw Abort(.badRequest, reason: "Unsupported algorithm: \(algorithm)")
        }
        return HashResponse(hash: hex, algorithm: algorithm, inputLength: text.utf8.count)
    }
}

// MARK: - Password Strength

private extension SecurityController {

    // Patterns that indicate weak passwords
    static let commonWords: Set<String> = [
        "password", "passw0rd", "password1", "password123", "p@ssword",
        "123456", "1234567", "12345678", "123456789", "1234567890",
        "qwerty", "qwerty123", "abc123", "letmein", "welcome",
        "admin", "login", "iloveyou", "sunshine", "monkey",
        "dragon", "master", "superman", "batman", "football",
        "baseball", "soccer", "hockey", "basketball", "michael",
        "shadow", "thomas", "jennifer", "jessica", "daniel"
    ]

    func analyzePassword(_ password: String) -> PasswordStrengthResponse {
        let lower = password.lowercased()
        let chars = Array(password)

        let hasLower  = chars.contains { $0.isLowercase }
        let hasUpper  = chars.contains { $0.isUppercase }
        let hasDigit  = chars.contains { $0.isNumber }
        let hasSymbol = chars.contains { "!@#$%^&*()_+-=[]{}|;':\",./<>?`~\\".contains($0) }
        let isLong    = chars.count >= 12

        let noCommon  = !Self.commonWords.contains(lower) &&
                        !Self.commonWords.contains(lower.filter { $0.isLetter || $0.isNumber })
        let noRepeat  = !hasLongRepeat(chars)
        let noSeq     = !hasKeyboardSequence(lower)
        let noCommonPatterns = noCommon && noRepeat && noSeq

        // Entropy estimate: pool size based on character classes used
        var pool = 0
        if hasLower  { pool += 26 }
        if hasUpper  { pool += 26 }
        if hasDigit  { pool += 10 }
        if hasSymbol { pool += 32 }
        if pool == 0 { pool = 1 }
        let entropy = Double(chars.count) * log2(Double(pool))

        // Score 0–4
        var score = 0
        let variety = [hasLower, hasUpper, hasDigit, hasSymbol].filter { $0 }.count
        if chars.count >= 8  { score += 1 }
        if chars.count >= 12 { score += 1 }
        if variety >= 3      { score += 1 }
        if noCommonPatterns  { score += 1 }
        if !noCommonPatterns { score = max(0, score - 1) }

        let strength: String
        switch score {
        case 0:    strength = "very weak"
        case 1:    strength = "weak"
        case 2:    strength = "fair"
        case 3:    strength = "strong"
        default:   strength = "very strong"
        }

        // Build actionable feedback
        var feedback: [String] = []
        if chars.count < 8  { feedback.append("Use at least 8 characters") }
        if chars.count < 12 { feedback.append("12+ characters is much stronger") }
        if !hasUpper        { feedback.append("Add uppercase letters") }
        if !hasLower        { feedback.append("Add lowercase letters") }
        if !hasDigit        { feedback.append("Add numbers") }
        if !hasSymbol       { feedback.append("Add symbols (e.g. !@#$)") }
        if !noCommon        { feedback.append("Avoid common passwords") }
        if !noRepeat        { feedback.append("Avoid repeated characters (e.g. aaaa)") }
        if !noSeq           { feedback.append("Avoid keyboard sequences (e.g. qwerty, 1234)") }

        return PasswordStrengthResponse(
            score: score,
            strength: strength,
            entropy: (entropy * 10).rounded() / 10,
            feedback: feedback,
            hasLowercase: hasLower,
            hasUppercase: hasUpper,
            hasDigits: hasDigit,
            hasSymbols: hasSymbol,
            isLongEnough: isLong,
            noCommonPatterns: noCommonPatterns
        )
    }

    func hasLongRepeat(_ chars: [Character]) -> Bool {
        var run = 1
        for i in 1..<chars.count {
            if chars[i] == chars[i - 1] { run += 1 } else { run = 1 }
            if run >= 4 { return true }
        }
        return false
    }

    func hasKeyboardSequence(_ text: String) -> Bool {
        let sequences = ["qwerty", "qwertz", "asdfgh", "zxcvbn",
                         "abcdef", "abcdefg", "123456", "234567",
                         "345678", "456789", "654321", "fedcba"]
        return sequences.contains { text.contains($0) }
    }
}

// MARK: - Digest hex helper

private extension Digest {
    var hexString: String {
        map { String(format: "%02x", $0) }.joined()
    }
}
