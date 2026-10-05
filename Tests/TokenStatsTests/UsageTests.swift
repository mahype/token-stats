import Foundation
import Testing
@testable import TokenStats

// Zeilenformen wie in ~/.claude/projects und ~/.codex/sessions (Stand 09/2026).

@Suite struct ClaudeLogParserTests {
    static let line = #"{"type":"assistant","timestamp":"2026-09-27T20:17:08.072Z","requestId":"req_1","message":{"id":"msg_1","model":"claude-opus-5-5","content":[],"usage":{"input_tokens":2,"cache_creation_input_tokens":24297,"cache_read_input_tokens":24920,"output_tokens":110,"cache_creation":{"ephemeral_1h_input_tokens":24297,"ephemeral_5m_input_tokens":0}}}}"#

    @Test func parsesUsageWithCacheSplit() throws {
        let event = try #require(ClaudeLogParser.parse(Data(Self.line.utf8)))
        #expect(event.model == "claude-opus-5-5")
        #expect(event.dedupKey == "msg_1:req_1")
        #expect(event.counts == TokenCounts(input: 2, output: 110, cacheWrite5m: 0, cacheWrite1h: 24297, cacheRead: 24920))
    }

    @Test func olderLinesWithoutSplitCountAs5m() throws {
        let line = #"{"type":"assistant","timestamp":"2026-01-01T10:00:00Z","message":{"model":"claude-sonnet-4-5","usage":{"input_tokens":10,"output_tokens":5,"cache_creation_input_tokens":100}}}"#
        let event = try #require(ClaudeLogParser.parse(Data(line.utf8)))
        #expect(event.counts.cacheWrite5m == 100)
        #expect(event.dedupKey == nil)
    }

    @Test func ignoresOtherLines() {
        #expect(ClaudeLogParser.parse(Data(#"{"type":"user","message":{"content":"usage"}}"#.utf8)) == nil)
        let synthetic = Self.line.replacingOccurrences(of: "claude-opus-5-5", with: "<synthetic>")
        #expect(ClaudeLogParser.parse(Data(synthetic.utf8)) == nil)
    }
}

@Suite struct CodexLogParserTests {
    static func tokenCount(_ input: Int, cached: Int, output: Int, lastInput: Int = 0, lastCached: Int = 0, lastOutput: Int = 0) -> Data {
        Data(#"{"timestamp":"2026-09-27T11:12:06.319Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":\#(input),"cached_input_tokens":\#(cached),"output_tokens":\#(output)},"last_token_usage":{"input_tokens":\#(lastInput),"cached_input_tokens":\#(lastCached),"output_tokens":\#(lastOutput)}}}}"#.utf8)
    }

    @Test func countsDeltasOfCumulativeTotals() throws {
        var state = CodexLogParser.FileState()
        #expect(CodexLogParser.parse(Data(#"{"type":"turn_context","payload":{"model":"gpt-5.6-sol"}}"#.utf8), state: &state) == nil)
        #expect(state.model == "gpt-5.6-sol")

        let first = try #require(CodexLogParser.parse(Self.tokenCount(1000, cached: 800, output: 50), state: &state))
        #expect(first.counts == TokenCounts(input: 200, output: 50, cacheRead: 800))
        #expect(first.model == "gpt-5.6-sol")

        // Wiederholtes Ereignis mit gleichen Summen zählt nicht doppelt.
        #expect(CodexLogParser.parse(Self.tokenCount(1000, cached: 800, output: 50), state: &state) == nil)

        let second = try #require(CodexLogParser.parse(Self.tokenCount(1500, cached: 1200, output: 80), state: &state))
        #expect(second.counts == TokenCounts(input: 100, output: 30, cacheRead: 400))
    }

    @Test func resetFallsBackToLastTurn() throws {
        var state = CodexLogParser.FileState()
        _ = CodexLogParser.parse(Self.tokenCount(5000, cached: 4000, output: 100), state: &state)
        let event = try #require(CodexLogParser.parse(
            Self.tokenCount(300, cached: 200, output: 10, lastInput: 300, lastCached: 200, lastOutput: 10), state: &state))
        #expect(event.counts == TokenCounts(input: 100, output: 10, cacheRead: 200))
    }
}

@Suite struct PricingTests {
    static let table = PriceTable(asOf: nil, models: [
        "claude-opus-5-5": .init(input: 4e-6, output: 20e-6, cacheRead: 0.2e-6, cacheWrite5m: 5e-6, cacheWrite1h: 8e-6),
        "gpt-5.6": .init(input: 4e-6, output: 20e-6, cacheRead: 0.4e-6, cacheWrite5m: 5e-6, cacheWrite1h: 4e-6),
    ])

    @Test func valueUsesEveryTokenKind() throws {
        let counts = TokenCounts(input: 1_000_000, output: 1_000_000, cacheWrite5m: 1_000_000, cacheWrite1h: 1_000_000, cacheRead: 1_000_000)
        let value = try #require(Self.table.value(of: counts, model: "claude-opus-5-5"))
        #expect(abs(value - (4 + 20 + 5 + 8 + 0.2)) < 1e-9)
    }

    @Test func lookupFallbacks() {
        #expect(Self.table.price(for: "claude-opus-5-5-20260901") != nil, "Datums-Suffix")
        #expect(Self.table.price(for: "gpt-5.6-sol") != nil, "Präfix")
        #expect(Self.table.price(for: "unbekannt") == nil)
    }

    @Test func bundledTableHasCurrentModels() {
        let bundled = PriceTable.bundled
        #expect(bundled.asOf != nil)
        #expect(bundled.price(for: "claude-opus-5-5") != nil)
        #expect(bundled.price(for: "claude-fable-5-1") != nil)
        #expect(bundled.price(for: "gpt-6-sol") != nil)
        #expect(bundled.price(for: "gpt-6.1-sol") != nil)
    }

    @Test func displayNames() {
        #expect(ModelName.display("claude-opus-5-5") == "Opus 5.5")
        #expect(ModelName.display("claude-haiku-4-5-20251001") == "Haiku 4.5")
        #expect(ModelName.display("claude-fable-5") == "Fable 5")
        #expect(ModelName.display("gpt-5.6-sol") == "GPT-5.6 Sol")
    }

    @Test func tokenFormat() {
        #expect(Format.tokens(38_400_000) == "38,4 M")
        #expect(Format.tokens(812_345) == "812 k")
        #expect(Format.tokens(950) == "950")
    }
}

@Suite struct PeriodTests {
    var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
        return calendar
    }

    func date(_ y: Int, _ m: Int, _ d: Int) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d, hour: 12))!
    }

    @Test func billingMonthStartsAtLastStichtag() {
        let range = UsagePeriod.billing.range(now: date(2026, 9, 28), billingDay: 15, calendar: calendar)
        #expect(range.from == calendar.startOfDay(for: date(2026, 9, 15)))
        let before = UsagePeriod.billing.range(now: date(2026, 9, 10), billingDay: 15, calendar: calendar)
        #expect(before.from == calendar.startOfDay(for: date(2026, 8, 15)))
    }

    @Test func billingDayClampsToShortMonths() {
        let range = UsagePeriod.billing.range(now: date(2026, 3, 5), billingDay: 31, calendar: calendar)
        #expect(range.from == calendar.startOfDay(for: date(2026, 2, 28)))
    }

    @Test func summaryFillsEmptyDays() {
        let week = UsagePeriod.week.range(now: date(2026, 9, 28), billingDay: 1, calendar: calendar)
        let rows = [UsageLedger.Row(day: "2026-09-28", model: "claude-opus-5-5", counts: TokenCounts(input: 10, output: 5))]
        let summary = UsageSummary.build(rows: rows, from: week.from, through: week.through,
                                         prices: PricingTests.table, calendar: calendar)
        #expect(summary.days.count == 7)
        #expect(summary.days.last?.tokens == 15)
        #expect(summary.total.total == 15)
        #expect(summary.hasUnpriced == false)
    }
}
