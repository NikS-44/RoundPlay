import Foundation
import Observation
import SwiftData
#if canImport(WatchConnectivity)
import WatchConnectivity
#endif

public enum SyncConnectionState: String, Sendable {
    case live
    case syncing
    case offline
}

#if canImport(WatchConnectivity)
@Observable
public final class RoundSyncSession: NSObject, WCSessionDelegate, @unchecked Sendable {
    public static let shared = RoundSyncSession()

    public private(set) var connectionState: SyncConnectionState = .offline

    private var context: ModelContext?
    private var isWatchSide: Bool {
        #if os(watchOS)
        true
        #else
        false
        #endif
    }

    public func activate(context: ModelContext) {
        self.context = context
        EngineBridge.onLocalChange = { [weak self] in
            self?.pushAll()
        }
        guard WCSession.isSupported() else {
            connectionState = .offline
            return
        }
        let session = WCSession.default
        session.delegate = self
        session.activate()
    }

    public func pushAll() {
        // Building the snapshots reads `context`, and `ModelContext` is not thread-safe. Every
        // delegate callback below already hops to main before touching it, but this one is reached
        // a different way: `EngineBridge.onLocalChange` fires it synchronously on whatever thread
        // recorded the score. In the app that is always the main actor, so it never bit a user —
        // but it corrupted the heap the moment anything recorded scores off-main, which is exactly
        // what the parallel test suite does.
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in self?.pushAll() }
            return
        }
        guard let context else { return }
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.activationState == .activated else { return }

        do {
            if !isWatchSide {
                try transfer(.roster, payload: SyncCodec.encoder.encode(SyncSnapshotBuilder.roster(from: context)))
                try transfer(.courses, payload: SyncCodec.encoder.encode(SyncSnapshotBuilder.courses(from: context)))
            }
            try transfer(.rounds, payload: SyncCodec.encoder.encode(SyncSnapshotBuilder.rounds(from: context)))
            refreshConnectionState()
        } catch {
            connectionState = .offline
        }
    }

    private func transfer(_ channel: SyncChannel, payload: Data) {
        WCSession.default.transferUserInfo([
            "channel": channel.rawValue,
            "payload": payload
        ])
    }

    private func refreshConnectionState() {
        guard WCSession.isSupported() else {
            connectionState = .offline
            return
        }
        let session = WCSession.default
        #if os(iOS)
        let counterpartReachable = session.isReachable && session.isPaired && session.isWatchAppInstalled
        #else
        let counterpartReachable = session.isReachable
        #endif
        if session.activationState != .activated || !counterpartReachable {
            connectionState = session.outstandingUserInfoTransfers.isEmpty ? .offline : .syncing
        } else if !session.outstandingUserInfoTransfers.isEmpty {
            connectionState = .syncing
        } else {
            connectionState = .live
        }
    }

    public func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        DispatchQueue.main.async {
            self.refreshConnectionState()
            if activationState == .activated {
                self.pushAll()
            }
        }
    }

    public func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        guard let raw = userInfo["channel"] as? String,
              let channel = SyncChannel(rawValue: raw),
              let data = userInfo["payload"] as? Data,
              let context else { return }
        DispatchQueue.main.async {
            do {
                switch channel {
                case .roster:
                    try SyncMerger.mergeRoster(try SyncCodec.decoder.decode(RosterPayload.self, from: data), into: context)
                case .courses:
                    try SyncMerger.mergeCourses(try SyncCodec.decoder.decode(CoursesPayload.self, from: data), into: context)
                case .rounds:
                    try SyncMerger.mergeRounds(try SyncCodec.decoder.decode(RoundsPayload.self, from: data), into: context)
                }
                self.refreshConnectionState()
            } catch {
                self.connectionState = .offline
            }
        }
    }

    #if os(iOS)
    public func sessionDidBecomeInactive(_ session: WCSession) {
        DispatchQueue.main.async { self.connectionState = .offline }
    }

    public func sessionDidDeactivate(_ session: WCSession) {
        WCSession.default.activate()
    }

    public func sessionWatchStateDidChange(_ session: WCSession) {
        DispatchQueue.main.async { self.refreshConnectionState() }
    }
    #endif

    public func sessionReachabilityDidChange(_ session: WCSession) {
        DispatchQueue.main.async { self.refreshConnectionState() }
    }

    public func session(
        _ session: WCSession,
        didFinish userInfoTransfer: WCSessionUserInfoTransfer,
        error: Error?
    ) {
        DispatchQueue.main.async { self.refreshConnectionState() }
    }
}
#else
@Observable
public final class RoundSyncSession: @unchecked Sendable {
    public static let shared = RoundSyncSession()
    public private(set) var connectionState: SyncConnectionState = .offline
    public func activate(context: ModelContext) {}
    public func pushAll() {}
}
#endif
