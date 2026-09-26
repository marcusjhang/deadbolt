import Foundation

/// An injectable clock. The current time can be overridden with the
/// `DEADBOLT_NOW` environment variable (RFC3339) so timed-lock expiration is
/// deterministic in tests and e2e. When unset, the real wall clock is used.
public enum Clock {
    public static func now(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> Date {
        if let raw = environment["DEADBOLT_NOW"], !raw.isEmpty, let date = parseRFC3339(raw) {
            return date
        }
        return Date()
    }

    /// Parses an RFC3339 timestamp with optional fractional seconds.
    public static func parseRFC3339(_ string: String) -> Date? {
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = withFraction.date(from: string) { return date }

        let withoutFraction = ISO8601DateFormatter()
        withoutFraction.formatOptions = [.withInternetDateTime]
        return withoutFraction.date(from: string)
    }

    /// Formats a date as RFC3339 (with fractional seconds) for human output.
    public static func formatRFC3339(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }
}
