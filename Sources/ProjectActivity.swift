import Foundation

/// Daily completion counts only. Prompts, terminal output and token usage are never stored.
struct ProjectActivity {
    private(set) var counts: [String: [String: Int]] = [:]
    private(set) var imported: [String: [String: ImportedDay]] = [:]
    static let daysShown = 84
    static let retentionDays = 366

    struct ImportedDay: Codable {
        let baseline: Int
        let liveAtImport: Int
    }

    init(data: Data? = nil, importedData: Data? = nil, now: Date = Date(), calendar: Calendar = .current) {
        if let data, let saved = try? JSONDecoder().decode([String: [String: Int]].self, from: data) {
            counts = saved
        }
        if let importedData, let saved = try? JSONDecoder().decode([String: [String: ImportedDay]].self, from: importedData) {
            imported = saved
        }
        prune(now: now, calendar: calendar)
    }

    mutating func record(in path: String, at date: Date, calendar: Calendar = .current) {
        let key = Self.dayKey(date, calendar: calendar)
        counts[path, default: [:]][key, default: 0] += 1
        prune(now: date, calendar: calendar)
    }

    func count(in path: String, on date: Date, calendar: Calendar = .current) -> Int {
        let key = Self.dayKey(date, calendar: calendar)
        let live = counts[path]?[key] ?? 0
        guard let snapshot = imported[path]?[key] else { return live }
        return max(live, snapshot.baseline + max(0, live - snapshot.liveAtImport))
    }

    func data() -> Data? { try? JSONEncoder().encode(counts) }
    func importedData() -> Data? { try? JSONEncoder().encode(imported) }

    /// Re-scanning replaces the historical baseline instead of adding it again.
    mutating func mergeHistoricalCounts(_ dailyCounts: [String: Int], in path: String, now: Date = Date(), calendar: Calendar = .current) {
        for (day, historicalCount) in dailyCounts where historicalCount > 0 {
            let live = counts[path]?[day] ?? 0
            let existing = imported[path]?[day].map { max(live, $0.baseline + max(0, live - $0.liveAtImport)) } ?? live
            imported[path, default: [:]][day] = ImportedDay(baseline: max(existing, historicalCount), liveAtImport: live)
        }
        prune(now: now, calendar: calendar)
    }

    private mutating func prune(now: Date, calendar: Calendar) {
        guard let oldest = calendar.date(byAdding: .day, value: -(Self.retentionDays - 1), to: calendar.startOfDay(for: now)) else { return }
        let minimum = Self.dayKey(oldest, calendar: calendar)
        counts = counts.compactMapValues { days in
            let retained = days.filter { $0.key >= minimum && $0.value > 0 }
            return retained.isEmpty ? nil : retained
        }
        imported = imported.compactMapValues { days in
            let retained = days.filter { $0.key >= minimum && $0.value.baseline > 0 }
            return retained.isEmpty ? nil : retained
        }
    }

    static func dayKey(_ date: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }
}
