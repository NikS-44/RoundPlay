import Foundation
import SwiftData
import RoundPlayData

/// The person whose phone this is.
///
/// Onboarding asks for a name and a handicap once and stores the resulting `PlayerRecord`'s id.
/// Every round after that defaults them into a seat rather than asking again — which is the whole
/// reason onboarding asks at all.
enum MyPlayer {
    static let defaultsKey = "myPlayerID"

    /// The stored player, or `nil` if none was ever stored or the record has since been deleted
    /// from the roster. Used where a missing "me" should simply mean "don't prefill anything".
    ///
    /// `defaults` defaults to `.standard` for every real call site. Tests must pass a private,
    /// disposable suite instead — `RoundPlayTests` is an app-hosted target, so `.standard` inside
    /// a test *is* this simulator's real UserDefaults. A test that clears `defaultsKey` on
    /// `.standard` for isolation wipes the pointer to whoever is actually onboarded on that
    /// device, and the next real solo round self-heals by minting a second "Me" behind it.
    static func existing(in context: ModelContext, defaults: UserDefaults = .standard) -> PlayerRecord? {
        guard let idString = defaults.string(forKey: defaultsKey),
              let id = UUID(uuidString: idString)
        else { return nil }
        let descriptor = FetchDescriptor<PlayerRecord>(predicate: #Predicate { $0.id == id })
        return try? context.fetch(descriptor).first ?? nil
    }

    /// The stored player, creating one if it has gone missing.
    ///
    /// A solo round is *entirely* this player, so unlike `existing` it cannot return nothing and
    /// leave the caller with an empty seat. An install predating onboarding, or a roster the user
    /// has since cleared out, self-heals into a plain "Me" with no handicap rather than dead-ending
    /// the only path to a solo round.
    static func resolve(in context: ModelContext, defaults: UserDefaults = .standard) -> PlayerRecord {
        if let existing = existing(in: context, defaults: defaults) { return existing }
        let created = PlayerRecord(name: "Me")
        context.insert(created)
        // Saved immediately, not left to whoever calls next. The defaults key is written here, so
        // if the insert were still pending when something else called `existing`, the key would
        // name a record the fetch couldn't find and a second "Me" would be created behind it.
        try? context.save()
        defaults.set(created.id.uuidString, forKey: defaultsKey)
        return created
    }
}
