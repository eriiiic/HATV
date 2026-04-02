import Foundation

extension Error {
    func userFacingMessage(context: String? = nil) -> String {
        let prefix = context.map { "\($0): " } ?? ""

        if let decodingError = self as? DecodingError {
            return prefix + decodingError.userFacingMessage
        }

        if let localizedError = self as? LocalizedError,
           let description = localizedError.errorDescription,
           !description.isEmpty {
            return prefix + description
        }

        let fallback = localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        return prefix + (fallback.isEmpty ? "Something went wrong." : fallback)
    }
}

private extension DecodingError {
    var userFacingMessage: String {
        switch self {
        case .keyNotFound(let key, let context):
            return "Home Assistant response is missing `\(key.stringValue)`\(codingPathSuffix(from: context.codingPath))."
        case .valueNotFound(_, let context):
            return "Home Assistant response is missing a value\(codingPathSuffix(from: context.codingPath))."
        case .typeMismatch(_, let context):
            return "Home Assistant response has an unexpected format\(codingPathSuffix(from: context.codingPath))."
        case .dataCorrupted(let context):
            return "Home Assistant response contains invalid data\(codingPathSuffix(from: context.codingPath))."
        @unknown default:
            return "Home Assistant response could not be decoded."
        }
    }

    private func codingPathSuffix(from codingPath: [CodingKey]) -> String {
        guard !codingPath.isEmpty else {
            return "."
        }

        let path = codingPath.map { key in
            if let index = key.intValue {
                return "[\(index)]"
            }
            return key.stringValue
        }
        .joined(separator: ".")

        return " at `\(path)`."
    }
}
