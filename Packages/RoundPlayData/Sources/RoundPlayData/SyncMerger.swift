import Foundation
import SwiftData
import RoundPlayEngine

/// Union-merge of sync snapshots into the local SwiftData store.
public enum SyncMerger {
    public static func mergeRoster(_ payload: RosterPayload, into context: ModelContext) throws {
        for snapshot in payload.players {
            if let existing = try fetchPlayer(id: snapshot.id, in: context) {
                snapshot.apply(to: existing)
            } else {
                let record = PlayerRecord(id: snapshot.id, name: snapshot.name, handicapIndex: snapshot.handicapIndex)
                snapshot.apply(to: record)
                context.insert(record)
            }
        }
        try context.save()
    }

    public static func mergeCourses(_ payload: CoursesPayload, into context: ModelContext) throws {
        for snapshot in payload.courses {
            if let existing = try fetchCourse(id: snapshot.id, in: context) {
                snapshot.apply(to: existing)
            } else {
                let record = CourseRecord(
                    id: snapshot.id,
                    name: snapshot.name,
                    pars: snapshot.pars,
                    strokeIndexes: snapshot.strokeIndexes,
                    openGolfID: snapshot.openGolfID
                )
                snapshot.apply(to: record)
                context.insert(record)
            }
        }
        for snapshot in payload.favorites {
            if let existing = try fetchFavorite(openGolfID: snapshot.openGolfID, in: context) {
                existing.name = snapshot.name
                existing.city = snapshot.city
                existing.state = snapshot.state
                existing.favoritedAt = snapshot.favoritedAt
            } else {
                let record = FavoriteCourseRecord(
                    openGolfID: snapshot.openGolfID,
                    name: snapshot.name,
                    city: snapshot.city,
                    state: snapshot.state
                )
                record.favoritedAt = snapshot.favoritedAt
                context.insert(record)
            }
        }
        try context.save()
    }

    public static func mergeRounds(_ payload: RoundsPayload, into context: ModelContext) throws {
        for snapshot in payload.rounds {
            try mergeRound(snapshot, into: context)
        }
        try context.save()
    }

    private static func mergeRound(_ snapshot: RoundSnapshot, into context: ModelContext) throws {
        let round: RoundRecord
        if let existing = try fetchRound(id: snapshot.id, in: context) {
            round = existing
            round.courseID = snapshot.courseID
            round.courseName = snapshot.courseName
            round.startedAt = snapshot.startedAt
            round.completedAt = snapshot.completedAt
            round.deletedAt = snapshot.deletedAt
            round.nextSequence = max(round.nextSequence, snapshot.nextSequence)
            round.holesPlayedRaw = snapshot.holesPlayedRaw
            round.strokeModeRaw = snapshot.strokeModeRaw
            round.handicapAllowancePercent = snapshot.handicapAllowancePercent
            round.maxHandicapStrokes = snapshot.maxHandicapStrokes
        } else {
            round = RoundRecord(id: snapshot.id, courseID: snapshot.courseID, courseName: snapshot.courseName)
            round.startedAt = snapshot.startedAt
            round.completedAt = snapshot.completedAt
            round.deletedAt = snapshot.deletedAt
            round.nextSequence = snapshot.nextSequence
            round.holesPlayedRaw = snapshot.holesPlayedRaw
            round.strokeModeRaw = snapshot.strokeModeRaw
            round.handicapAllowancePercent = snapshot.handicapAllowancePercent
            round.maxHandicapStrokes = snapshot.maxHandicapStrokes
            context.insert(round)
        }

        let knownSeatIDs = Set((round.seats ?? []).map(\.id))
        for seat in snapshot.seats where !knownSeatIDs.contains(seat.id) {
            let record = SeatRecord(
                id: seat.id,
                playerID: seat.playerID,
                name: seat.name,
                courseHandicap: seat.courseHandicap,
                position: seat.position
            )
            record.strokeOverride = seat.strokeOverride
            round.seats = (round.seats ?? []) + [record]
            context.insert(record)
        }

        let knownGameIDs = Set((round.games ?? []).map(\.id))
        for game in snapshot.games where !knownGameIDs.contains(game.id) {
            let record = GameInstanceRecord(
                id: game.id,
                gameTypeRaw: game.gameTypeRaw,
                configurationData: game.configurationData
            )
            round.games = (round.games ?? []) + [record]
            context.insert(record)
        }

        let knownEventIDs = Set((round.events ?? []).map(\.id))
        for event in snapshot.events where !knownEventIDs.contains(event.id) {
            let record = try ScoreEventRecord(
                id: event.id,
                hole: event.hole,
                playerID: event.playerID,
                payload: try JSONDecoder().decode(ScoreEventPayload.self, from: event.payloadData),
                enteredBy: event.enteredBy,
                enteredByName: event.enteredByName,
                sequence: event.sequence,
                recordedAt: event.recordedAt,
                deviceID: event.deviceID
            )
            record.payloadData = event.payloadData
            round.events = (round.events ?? []) + [record]
            context.insert(record)
        }
    }

    private static func fetchPlayer(id: UUID, in context: ModelContext) throws -> PlayerRecord? {
        let descriptor = FetchDescriptor<PlayerRecord>(predicate: #Predicate { $0.id == id })
        return try context.fetch(descriptor).first
    }

    private static func fetchCourse(id: UUID, in context: ModelContext) throws -> CourseRecord? {
        let descriptor = FetchDescriptor<CourseRecord>(predicate: #Predicate { $0.id == id })
        return try context.fetch(descriptor).first
    }

    private static func fetchFavorite(openGolfID: String, in context: ModelContext) throws -> FavoriteCourseRecord? {
        let descriptor = FetchDescriptor<FavoriteCourseRecord>(predicate: #Predicate { $0.openGolfID == openGolfID })
        return try context.fetch(descriptor).first
    }

    private static func fetchRound(id: UUID, in context: ModelContext) throws -> RoundRecord? {
        let descriptor = FetchDescriptor<RoundRecord>(predicate: #Predicate { $0.id == id })
        return try context.fetch(descriptor).first
    }
}
