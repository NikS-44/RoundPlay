import Foundation

/// Random nicknames for guests added without a real name.
///
/// Picking rather than requiring a name keeps the "add someone right now, on the first tee"
/// path fast — the nickname is just a starting value in the same name field, so renaming it
/// later needs no separate affordance.
enum GuestNickname {
    /// Skips any name already used elsewhere in the roster so two guests never collide.
    static func random(avoiding usedNames: Set<String>) -> String {
        let available = pool.filter { !usedNames.contains($0) }
        return (available.isEmpty ? pool : available).randomElement()!
    }

    private static let pool: [String] = [
        "Birdie Malone", "Bogey Sanchez", "Eagle Prescott", "Ace McCoy", "Duffer Grant",
        "Mulligan Cruz", "Shank Rivera", "Hook Delgado", "Slice Nguyen", "Fairway Doyle",
        "Rough Higgins", "Bunker Marsh", "Chip Osei", "Putt Nakamura", "Par Kowalski",
        "Wedge Larsen", "Divot Ramos", "Caddie Boone", "Green Alonzo", "Fore Winslow",
        "Gimme Ferro", "Scramble Wu", "Draw Solano", "Fade Duffy", "Yips Cassidy",
        "Flag Bianchi", "Tee Novak", "Pin Reyes", "Chunk Abara", "Topspin Chu",
        "Skull Vasquez", "Whiff Prentiss", "Snowman Ellis", "Grip Hargrove", "Stance Okafor",
        "Backswing Fry", "Chunky Sutter", "Flub Ainsley", "Sandy Beaumont", "Birdie Castillo",
        "Bogey Whitfield", "Eagle Fitzgerald", "Ace Blackwood", "Duffer Calloway", "Mulligan Reyes",
        "Shank Merriman", "Hook Sorrento", "Slice Redmond", "Fairway Novak", "Rough Delacroix",
        "Bunker Fitch", "Chip Rowley", "Putt Sinclair", "Par Bellamy", "Wedge Donahue",
        "Divot Sterling", "Caddie Marsh", "Green Doyle", "Fore Alvarez", "Gimme Osei",
        "Scramble Everhart", "Draw Higgins", "Fade Kowalski", "Yips Nakamura", "Flag Delgado",
        "Tee Rivera", "Pin Sanchez", "Chunk Boone", "Topspin Grant", "Skull Winslow",
        "Whiff Larsen", "Snowman Cruz", "Grip McCoy", "Stance Malone", "Backswing Osei",
        "Chunky Ashworth", "Flub Nguyen", "Sandy Ramos", "Birdie Solano", "Bogey Ferro",
        "Eagle Duffy", "Ace Cassidy", "Duffer Bianchi", "Mulligan Novak", "Shank Reyes",
        "Hook Abara", "Slice Chu", "Fairway Wu", "Rough Ainsley", "Bunker Hargrove",
        "Chip Okafor", "Putt Beaumont", "Par Castillo", "Wedge Whitfield", "Divot Blackwood",
        "Caddie Calloway", "Green Sorrento", "Fore Whitmore", "Gimme Delacroix", "Scramble Fitch",
        "Birdie Halloran", "Bogey Trentino", "Eagle Marchetti", "Ace Donovan", "Duffer Whitaker",
        "Mulligan Beckham", "Shank Fontaine", "Hook Larimore", "Slice Radley", "Fairway Sinclaire"
    ]
}
