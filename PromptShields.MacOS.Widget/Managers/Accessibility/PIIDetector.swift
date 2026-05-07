import Foundation

// PIIDetector — fast, local, pre-LLM heuristic scanner. When this returns
// `.containsPII`, the UI surfaces the Redaction suggestion at the top of
// the list so the user can sanitise before sending.
//
// Design intent:
// - Runs on every keystroke (well within the AXObserver debounce budget).
// - Never sends anything over the network.
// - High-recall, medium-precision. False positives are acceptable (the
//   user can still pick a different suggestion); false negatives defeat
//   the whole pitch.
// - Category names align with what the redaction prompt template asks
//   the LLM to replace ([NAME], [EMAIL], [ACCOUNT_ID], etc) so downstream
//   analytics can correlate.

enum PIICategory: String, Sendable, CaseIterable {
    case email
    case phone
    case creditCard
    case ssn                  // US SSN, reused for generic 3-2-4 national IDs
    case ipAddress
    case apiKey
    case jwt
    case iban
    case bitcoinAddress
    case currency             // €2.4M, $45,000, NOK 12M — often confidential
    case personName           // First + Last, capitalised — soft signal
}

struct PIIMatch: Equatable, Sendable {
    let category: PIICategory
    /// Range in the scanned string.
    let range: Range<String.Index>
}

enum PIIDetector {
    /// Cheap pre-screen: does the text have anything that *might* be PII?
    /// Use when you just need a yes/no answer (e.g. reorder the suggestion
    /// list). For showing per-match highlights, call `findMatches`.
    static func containsPII(_ text: String) -> Bool {
        !findMatches(in: text, firstOnly: true).isEmpty
    }

    /// Returns every detected PII span. Safe to call on large prompts —
    /// short-circuits via compiled regexes.
    static func findMatches(in text: String, firstOnly: Bool = false) -> [PIIMatch] {
        guard !text.isEmpty, text.count <= maxScanLength else { return [] }

        var hits: [PIIMatch] = []

        for rule in rules {
            for match in rule.regex.matches(in: text, options: [], range: NSRange(text.startIndex..., in: text)) {
                guard let range = Range(match.range, in: text) else { continue }

                // Category-specific validators — cheap sanity checks to cull
                // common false positives (e.g. the number 1234567890 is not
                // a credit card).
                if let validator = rule.validator, !validator(String(text[range])) {
                    continue
                }

                hits.append(PIIMatch(category: rule.category, range: range))
                if firstOnly { return hits }
            }
        }
        return hits
    }

    // MARK: - Rules

    /// 50kB of scanned text is plenty for a prompt; beyond that we bail to
    /// avoid regex catastrophe on a pasted dump.
    private static let maxScanLength = 50_000

    private struct Rule: @unchecked Sendable {
        let category: PIICategory
        let regex: NSRegularExpression
        /// Optional second-pass validator (e.g. Luhn check for cards).
        /// `@Sendable` because the rules table is global and accessed
        /// from any actor; closures here are pure (Luhn / phone digit
        /// checks) so the unchecked Sendable conformance is safe.
        let validator: (@Sendable (String) -> Bool)?
    }

    // swiftlint:disable:next force_try
    nonisolated(unsafe) private static let rules: [Rule] = {
        func compile(_ pattern: String, options: NSRegularExpression.Options = []) -> NSRegularExpression {
            // swiftlint:disable:next force_try
            try! NSRegularExpression(pattern: pattern, options: options)
        }

        return [
            Rule(category: .email,
                 regex: compile(#"[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}"#, options: .caseInsensitive),
                 validator: nil),

            // Bitcoin (P2PKH/P2SH + bech32). Do this before generic digits.
            Rule(category: .bitcoinAddress,
                 regex: compile(#"\b(?:[13][a-km-zA-HJ-NP-Z1-9]{25,34}|bc1[a-zA-HJ-NP-Z0-9]{25,62})\b"#),
                 validator: nil),

            // JWT tokens — three base64 groups.
            Rule(category: .jwt,
                 regex: compile(#"\beyJ[A-Za-z0-9_-]{5,}\.[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{5,}\b"#),
                 validator: nil),

            // API-key-ish prefixes (OpenAI, Anthropic, Stripe, AWS, generic).
            Rule(category: .apiKey,
                 regex: compile(#"\b(?:sk-[a-zA-Z0-9_-]{20,}|sk_live_[a-zA-Z0-9]{20,}|pk_live_[a-zA-Z0-9]{20,}|AIza[0-9A-Za-z_-]{20,}|AKIA[0-9A-Z]{16}|ghp_[A-Za-z0-9]{20,}|xoxb-[0-9]+-[0-9]+-[A-Za-z0-9]+)\b"#),
                 validator: nil),

            // IBAN
            Rule(category: .iban,
                 regex: compile(#"\b[A-Z]{2}[0-9]{2}[A-Z0-9]{10,30}\b"#),
                 validator: nil),

            // IPv4
            Rule(category: .ipAddress,
                 regex: compile(#"\b(?:25[0-5]|2[0-4][0-9]|[01]?[0-9]{1,2})(?:\.(?:25[0-5]|2[0-4][0-9]|[01]?[0-9]{1,2})){3}\b"#),
                 validator: nil),

            // Credit card (Visa/MC/Amex-ish). Luhn-validated.
            Rule(category: .creditCard,
                 regex: compile(#"\b(?:\d[ -]?){13,19}\b"#),
                 validator: { luhnValid(stripSeparators($0)) }),

            // US SSN style: 3-2-4. Overlaps with some national IDs.
            Rule(category: .ssn,
                 regex: compile(#"\b\d{3}-\d{2}-\d{4}\b"#),
                 validator: nil),

            // Phone numbers — E.164-ish + common spaced formats.
            Rule(category: .phone,
                 regex: compile(#"(?:\+?\d{1,3}[-.\s]?)?\(?\d{2,4}\)?[-.\s]?\d{3,4}[-.\s]?\d{3,5}"#),
                 validator: { phoneValid($0) }),

            // Currency with explicit symbol/code — catches "€2.4M", "$45K", "NOK 12M".
            Rule(category: .currency,
                 regex: compile(#"(?:[€£¥$]\s?\d[\d,.]*\s?(?:[KMBkmb]|thousand|million|billion)?|\b(?:USD|EUR|GBP|NOK|SEK|DKK|CHF|JPY|CNY|INR)\s?\d[\d,.]*\s?(?:[KMBkmb]|thousand|million|billion)?)\b"#),
                 validator: nil),

            // Person-name soft signal: two capitalised words, not at start of
            // sentence. Last to run; intentionally broad so we *nudge* toward
            // redaction without forcing it.
            Rule(category: .personName,
                 regex: compile(#"(?<![.!?]\s|^)\b[A-Z][a-z]{1,20}\s+[A-Z][a-z]{1,20}\b"#),
                 validator: { !commonBigrams.contains($0.lowercased()) })
        ]
    }()

    // MARK: - Validators

    private static func stripSeparators(_ s: String) -> String {
        s.filter { $0.isNumber }
    }

    private static func luhnValid(_ digits: String) -> Bool {
        guard (13...19).contains(digits.count) else { return false }
        var sum = 0
        for (i, ch) in digits.reversed().enumerated() {
            guard let d = ch.wholeNumberValue else { return false }
            if i % 2 == 1 {
                let doubled = d * 2
                sum += doubled > 9 ? doubled - 9 : doubled
            } else {
                sum += d
            }
        }
        return sum % 10 == 0
    }

    private static func phoneValid(_ s: String) -> Bool {
        let digits = s.filter { $0.isNumber }
        // Reject 4-digit years, small order totals, etc.
        return (7...15).contains(digits.count)
    }

    /// Common non-PII bigrams that the personName regex would otherwise
    /// flag. Keep short and pragmatic — exhaustive dictionaries belong in
    /// a server-side redaction model, not a client heuristic.
    private static let commonBigrams: Set<String> = [
        "united states", "new york", "san francisco", "north america",
        "south america", "hong kong", "white house", "wall street",
        "silicon valley", "machine learning", "artificial intelligence",
        "data science", "customer service", "product manager", "project manager",
        "chief executive", "best regards", "kind regards", "thank you",
        "lorem ipsum"
    ]
}
