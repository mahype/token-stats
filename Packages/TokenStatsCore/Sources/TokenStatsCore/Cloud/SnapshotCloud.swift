import CloudKit
import Foundation

/// Datenweg Mac → iPhone (Issue #11): ein Datensatz je Mac in der privaten CloudKit-Datenbank,
/// Inhalt ist dieselbe `WidgetSnapshot`-JSON wie für die Widgets – keine Zugangsdaten, keine
/// Logs, keine Rohdaten, einige Kilobyte. Eigene Zone statt Abfrage: `recordZoneChanges`
/// braucht keinen Index im CloudKit-Dashboard, und eine Zonen-Subscription liefert den
/// stillen Push, mit dem iPhone-App und Widgets nachladen, ohne zu pollen.
public enum SnapshotCloud {
    public static let containerIdentifier = "iCloud.de.mahype.TokenStats"
    public static let zoneID = CKRecordZone.ID(zoneName: "Snapshots", ownerName: CKCurrentUserDefaultName)
    public static let recordType = "Snapshot"
    public static let subscriptionID = "snapshots-changed"

    /// Ob dieser Build die iCloud-Berechtigung trägt. Ohne sie bricht `CKContainer` beim ersten
    /// Zugriff ab, darum wird vorher geprüft. Auf dem Mac kommt sie nur mit `make build ICLOUD=1`
    /// bzw. einem Developer-ID-Profil ins Bundle; iOS-Builds tragen sie immer.
    public static var isEntitled: Bool {
        #if os(macOS)
        guard let task = SecTaskCreateFromSelf(nil),
              let value = SecTaskCopyValueForEntitlement(task, "com.apple.developer.icloud-container-identifiers" as CFString, nil)
        else { return false }
        return (value as? [String])?.contains(containerIdentifier) ?? false
        #else
        return true
        #endif
    }

    private static var database: CKDatabase {
        CKContainer(identifier: containerIdentifier).privateCloudDatabase
    }

    // MARK: Umwandlung – ohne Netz, testbar

    public static func record(from snapshot: WidgetSnapshot, machineID: String) throws -> CKRecord {
        let record = CKRecord(recordType: recordType, recordID: CKRecord.ID(recordName: machineID, zoneID: zoneID))
        record["machine"] = snapshot.machine ?? ""
        record["writtenAt"] = snapshot.writtenAt
        record["version"] = snapshot.version
        record["payload"] = try snapshot.jsonData()
        return record
    }

    public static func snapshot(from record: CKRecord) -> WidgetSnapshot? {
        guard let data = record["payload"] as? Data else { return nil }
        return WidgetSnapshot.decode(data)
    }

    // MARK: Mac: schreiben

    public static func accountStatus() async throws -> CKAccountStatus {
        try await CKContainer(identifier: containerIdentifier).accountStatus()
    }

    /// Legt die Zone an (idempotent) und ersetzt den Datensatz dieses Macs.
    public static func publish(_ snapshot: WidgetSnapshot, machineID: String) async throws {
        let database = database
        _ = try await database.modifyRecordZones(saving: [CKRecordZone(zoneID: zoneID)], deleting: [])
        let record = try record(from: snapshot, machineID: machineID)
        let result = try await database.modifyRecords(saving: [record], deleting: [], savePolicy: .allKeys)
        for (_, outcome) in result.saveResults { _ = try outcome.get() }
    }

    // MARK: iPhone: lesen

    /// Alle Macs, neuester Stand zuerst. Solange kein Mac übertragen hat, gibt es die Zone
    /// noch nicht – das ist kein Fehler, sondern „noch kein Stand“.
    public static func fetchAll() async throws -> [WidgetSnapshot] {
        do {
            let changes = try await database.recordZoneChanges(inZoneWith: zoneID, since: nil)
            return changes.modificationResultsByID.values
                .compactMap { try? $0.get().record }
                .compactMap(snapshot(from:))
                .sorted { $0.writtenAt > $1.writtenAt }
        } catch let error as CKError where error.code == .zoneNotFound || error.code == .userDeletedZone {
            return []
        }
    }

    /// Stiller Push bei jeder Änderung in der Zone; mehrfaches Anlegen ist unschädlich.
    public static func subscribe() async throws {
        let subscription = CKRecordZoneSubscription(zoneID: zoneID, subscriptionID: subscriptionID)
        let info = CKSubscription.NotificationInfo()
        info.shouldSendContentAvailable = true
        subscription.notificationInfo = info
        _ = try await database.modifySubscriptions(saving: [subscription], deleting: [])
    }
}
