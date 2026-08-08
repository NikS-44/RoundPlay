import Foundation

/// Marker for the engine module's rule-set version.
///
/// Bump this whenever a scoring rule changes in a way that would alter the money a past
/// round settled to. The web port (Phase 4) checks this against its own constant so the two
/// implementations cannot silently drift apart.
public enum RoundPlayEngineVersion {
    public static let current = "0.1.0"
}
