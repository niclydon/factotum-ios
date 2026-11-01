import Foundation

/// Shared tokenization for the photo text index
/// (DESIGN-PHOTO-TEXT-INDEX.md). The prototype's v1 rules —
/// case-fold, split on non-alphanumerics, min length 2, dedupe per
/// asset, cap 200, NO stemming (fidelity for sign and proper-noun
/// text) — plus the full build's stopword filter, added on the
/// prototype's evidence: the index's most frequent terms were
/// stopwords (the, to, in, for, and), pure bulk in a search index.
/// The cap counts EXPORTED terms (after filtering).
enum PhotoTermTokenizer {
    static let maxTermsPerAsset = 200

    static func terms(from text: String) -> [String] {
        var seen = Set<String>()
        var terms: [String] = []
        for raw in text.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted) {
            let term = raw.trimmingCharacters(in: .whitespaces)
            guard term.count >= 2, !stopwords.contains(term), !seen.contains(term) else { continue }
            seen.insert(term)
            terms.append(term)
            if terms.count >= maxTermsPerAsset { break }
        }
        return terms
    }

    /// Compact English function-word set. Content words that merely
    /// look function-y in some contexts (will, can, may) stay out:
    /// in photo text they are as often names and signage as grammar.
    static let stopwords: Set<String> = [
        "the", "be", "to", "of", "and", "in", "that", "it", "was", "for",
        "on", "are", "as", "with", "his", "they", "at", "one", "have",
        "this", "from", "or", "had", "by", "word", "but", "not", "what",
        "all", "were", "we", "when", "your", "there", "use", "an", "each",
        "which", "she", "do", "how", "their", "will", "up", "other",
        "about", "out", "many", "then", "them", "these", "so", "some",
        "her", "would", "make", "like", "him", "into", "time", "has",
        "look", "two", "more", "go", "no", "way", "could", "my", "than",
        "first", "been", "call", "who", "its", "now", "did", "get",
        "come", "made", "over", "also", "after", "back", "only", "just",
        "where", "very", "through", "much", "before", "too", "any",
        "same", "am", "is", "are", "was", "were", "been", "being",
        "have", "has", "had", "having", "does", "did", "doing", "would",
        "shall", "should", "can", "could", "may", "might", "must",
        "i", "you", "he", "she", "it", "we", "they", "them", "his",
        "her", "hers", "its", "our", "ours", "their", "theirs", "this",
        "that", "these", "those", "am", "an", "the", "and", "but",
        "if", "or", "because", "as", "until", "while", "of", "at",
        "by", "for", "with", "about", "into", "through", "after",
        "over", "between", "out", "against", "during", "without",
        "before", "under", "around", "among", "isn", "aren", "wasn",
        "weren", "hasn", "haven", "hadn", "doesn", "didn", "won",
        "wouldn", "shan", "shouldn", "can", "cannot", "couldn",
        "mustn", "let", "ll", "re", "ve", "d", "s", "t", "m",
    ]
}
