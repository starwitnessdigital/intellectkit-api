import Vapor

// MARK: - Hash

struct HashRequest: Content {
    let text: String
    let algorithm: String      // "md5", "sha1", "sha256", "sha512"
}

struct HashResponse: Content {
    let hash: String
    let algorithm: String
    let inputLength: Int
}

// MARK: - Password Strength

struct PasswordStrengthRequest: Content {
    let password: String
}

struct PasswordStrengthResponse: Content {
    let score: Int             // 0–4
    let strength: String       // "very weak" … "very strong"
    let entropy: Double        // estimated bits of entropy
    let feedback: [String]
    let hasLowercase: Bool
    let hasUppercase: Bool
    let hasDigits: Bool
    let hasSymbols: Bool
    let isLongEnough: Bool     // >= 12 chars
    let noCommonPatterns: Bool
}
