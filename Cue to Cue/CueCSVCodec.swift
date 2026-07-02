//
//  CueCSVCodec.swift
//  Cue to Cue
//
//  RFC 4180 CSV encode/decode for cue stack portability (Excel, Numbers, etc.).
//

import Foundation

// MARK: - Format

enum CueCSVFormatVersion: Int, Sendable {
    case v1 = 1
}

struct CueCSVExportOptions: Sendable {
    var includeVersionComment: Bool = true
    var includeUTF8BOM: Bool = false
}

struct CueCSVImportResult: Sendable {
    var stacks: [CueStack]
    var warnings: [String]
}

enum CueCSVError: LocalizedError, Equatable {
    case emptyFile
    case missingHeader
    case missingCueStackColumn
    case rowFieldCountMismatch(line: Int, expected: Int, found: Int)
    case invalidEncoding

    var errorDescription: String? {
        switch self {
        case .emptyFile:
            return "The CSV file is empty."
        case .missingHeader:
            return "The CSV file does not contain a valid header row."
        case .missingCueStackColumn:
            return "The header row must include a \"Cue Stack\" column (Cue to Cue export format)."
        case .rowFieldCountMismatch(let line, let expected, let found):
            return "Row \(line): expected \(expected) columns, found \(found)."
        case .invalidEncoding:
            return "The file could not be read as UTF-8 text."
        }
    }
}

// MARK: - Codec

enum CueCSVCodec {

    static let versionCommentPrefix = "# Cue to Cue CSV v"
    static let cueStackColumnName = "Cue Stack"
    static let timerColumnName = "Timer"
    static let strikethroughColumnName = "Strikethrough"

    // MARK: Encode

    static func encode(stacks: [CueStack], options: CueCSVExportOptions = CueCSVExportOptions()) -> Data {
        var lines: [String] = []

        if options.includeVersionComment {
            lines.append("\(versionCommentPrefix)\(CueCSVFormatVersion.v1.rawValue)")
        }

        var allColumnNames: [String] = []
        for stack in stacks {
            for col in stack.columns where !allColumnNames.contains(col.name) {
                allColumnNames.append(col.name)
            }
        }

        let header: [String] = [cueStackColumnName] + allColumnNames + [timerColumnName, strikethroughColumnName]
        lines.append(header.map(csvEscape).joined(separator: ","))

        for stack in stacks {
            for cue in stack.cues {
                var row: [String] = [stack.name]
                for unionColName in allColumnNames {
                    if let stackIdx = stack.columns.firstIndex(where: { $0.name == unionColName }),
                       stackIdx < cue.values.count {
                        row.append(cue.values[stackIdx])
                    } else {
                        row.append("")
                    }
                }
                row.append(cue.timerValue)
                row.append(cue.isStruckThrough ? "TRUE" : "FALSE")
                lines.append(row.map(csvEscape).joined(separator: ","))
            }
        }

        let body = lines.joined(separator: "\r\n") + "\r\n"
        var data = body.data(using: .utf8) ?? Data()
        if options.includeUTF8BOM {
            data = Data([0xEF, 0xBB, 0xBF]) + data
        }
        return data
    }

    // MARK: Decode

    static func decode(data: Data) throws -> CueCSVImportResult {
        var raw = data
        if raw.starts(with: [0xEF, 0xBB, 0xBF]) {
            raw = Data(raw.dropFirst(3))
        }

        guard let content = String(data: raw, encoding: .utf8) else {
            throw CueCSVError.invalidEncoding
        }

        let records = parseRecords(from: content)
        guard !records.isEmpty else {
            throw CueCSVError.emptyFile
        }

        var warnings: [String] = []
        var recordIndex = 0

        // Skip version comment lines
        while recordIndex < records.count,
              let first = records[recordIndex].first,
              first.hasPrefix(versionCommentPrefix) || first.hasPrefix("#") {
            recordIndex += 1
        }

        guard recordIndex < records.count else {
            throw CueCSVError.missingHeader
        }

        let header = records[recordIndex].map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        recordIndex += 1

        guard let cueStackIndex = header.firstIndex(where: { $0.caseInsensitiveCompare(cueStackColumnName) == .orderedSame }) else {
            throw CueCSVError.missingCueStackColumn
        }

        let timerIndex = header.firstIndex(where: { $0.caseInsensitiveCompare(timerColumnName) == .orderedSame })
        let strikeIndex = header.firstIndex(where: { $0.caseInsensitiveCompare(strikethroughColumnName) == .orderedSame })

        let reserved = Set([cueStackIndex, timerIndex, strikeIndex].compactMap { $0 })
        let dataColumnIndices: [(name: String, index: Int)] = header.enumerated().compactMap { idx, name in
            guard !reserved.contains(idx) else { return nil }
            return (name, idx)
        }

        if timerIndex == nil {
            warnings.append("No \"Timer\" column in header; imported cues will have empty timers.")
        }
        if strikeIndex == nil {
            warnings.append("No \"Strikethrough\" column in header; imported cues will not be struck through.")
        }

        let expectedFieldCount = header.count
        var stackOrder: [String] = []
        var importedRowsByStack: [String: [(values: [String], timer: String, struck: Bool)]] = [:]

        for (offset, row) in records.dropFirst(recordIndex).enumerated() {
            let lineNumber = recordIndex + offset + 1
            if row.allSatisfy({ $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
                continue
            }

            if row.count != expectedFieldCount {
                throw CueCSVError.rowFieldCountMismatch(
                    line: lineNumber,
                    expected: expectedFieldCount,
                    found: row.count
                )
            }

            let stackName = row[cueStackIndex].trimmingCharacters(in: .whitespacesAndNewlines)
            let effectiveStackName = stackName.isEmpty ? "Imported" : stackName

            if importedRowsByStack[effectiveStackName] == nil {
                importedRowsByStack[effectiveStackName] = []
                stackOrder.append(effectiveStackName)
            }

            let values = dataColumnIndices.map { row[$0.index] }
            let timer = timerIndex.map { row[$0] } ?? ""
            let struck = strikeIndex.map { parseBool(row[$0]) } ?? false
            importedRowsByStack[effectiveStackName]?.append((values: values, timer: timer, struck: struck))
        }

        let stacks = stackOrder.compactMap { name -> CueStack? in
            guard let rows = importedRowsByStack[name] else { return nil }
            return buildStack(name: name, rows: rows, dataColumnIndices: dataColumnIndices)
        }

        if stacks.isEmpty {
            warnings.append("No cue rows were found in the file.")
        }

        return CueCSVImportResult(stacks: stacks, warnings: warnings)
    }

    // MARK: RFC 4180 helpers

    static func csvEscape(_ value: String) -> String {
        if value.contains(",") || value.contains("\"") || value.contains("\n") || value.contains("\r") {
            let escaped = value.replacingOccurrences(of: "\"", with: "\"\"")
            return "\"\(escaped)\""
        }
        return value
    }

    /// Parse CSV content into records (rows), respecting quoted fields and embedded newlines.
    /// Uses Unicode scalars so CRLF sequences are not treated as a single grapheme cluster.
    static func parseRecords(from content: String) -> [[String]] {
        var records: [[String]] = []
        var currentRecord: [String] = []
        var currentField = ""
        var inQuotes = false
        let scalars = content.unicodeScalars
        var index = scalars.startIndex

        func finishField() {
            currentRecord.append(currentField)
            currentField = ""
        }

        func finishRecord() {
            finishField()
            if !currentRecord.allSatisfy({ $0.isEmpty }) {
                records.append(currentRecord)
            }
            currentRecord = []
        }

        func appendScalar(_ scalar: UnicodeScalar) {
            currentField.unicodeScalars.append(scalar)
        }

        while index < scalars.endIndex {
            let scalar = scalars[index]

            if inQuotes {
                if scalar == "\"" {
                    let next = scalars.index(after: index)
                    if next < scalars.endIndex, scalars[next] == "\"" {
                        appendScalar("\"")
                        index = scalars.index(after: next)
                        continue
                    }
                    inQuotes = false
                } else {
                    appendScalar(scalar)
                }
            } else {
                switch scalar.value {
                case 0x22: // "
                    inQuotes = true
                case 0x2C: // ,
                    finishField()
                case 0x0D: // \r
                    let next = scalars.index(after: index)
                    if next < scalars.endIndex, scalars[next].value == 0x0A {
                        index = next
                    }
                    finishRecord()
                case 0x0A: // \n
                    finishRecord()
                default:
                    appendScalar(scalar)
                }
            }

            index = scalars.index(after: index)
        }

        if inQuotes {
            finishRecord()
        } else if !currentField.isEmpty || !currentRecord.isEmpty {
            finishRecord()
        }

        return records
    }

    private static func parseBool(_ value: String) -> Bool {
        switch value.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() {
        case "TRUE", "YES", "1":
            return true
        default:
            return false
        }
    }

    /// Reconstructs one stack using only data columns that have at least one
    /// non-empty cell in that stack. Export uses a union header across stacks,
    /// so empty placeholder cells must not become columns on import.
    private static func buildStack(
        name: String,
        rows: [(values: [String], timer: String, struck: Bool)],
        dataColumnIndices: [(name: String, index: Int)]
    ) -> CueStack {
        let usedOffsets = dataColumnIndices.indices.filter { offset in
            rows.contains { row in
                !row.values[offset].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
        }

        let columns = usedOffsets.map { Column(name: dataColumnIndices[$0].name, width: 100) }
        let cues = rows.map { row in
            let values = usedOffsets.map { row.values[$0] }
            return Cue(values: values, timerValue: row.timer, isStruckThrough: row.struck)
        }
        return CueStack(name: name, cues: cues, columns: columns)
    }
}

// MARK: - Import application

extension CueCSVCodec {
    /// Returns imported stacks with names disambiguated against existing stack names.
    static func stacksForAdd(imported: [CueStack], existingNames: [String]) -> [CueStack] {
        var used = Set(existingNames)
        return imported.map { stack in
            var name = stack.name
            if used.contains(name) {
                name = disambiguatedName(base: name, used: used)
            }
            used.insert(name)
            return CueStack(name: name, cues: stack.cues, columns: stack.columns)
        }
    }

    /// Merges cues from an imported stack into an existing stack, unioning columns by name.
    static func mergedStack(existing: CueStack, imported: CueStack) -> CueStack {
        var unionNames = existing.columns.map(\.name)
        for column in imported.columns where !unionNames.contains(column.name) {
            unionNames.append(column.name)
        }

        let existingColumnNames = existing.columns.map(\.name)
        let importedColumnNames = imported.columns.map(\.name)
        let unionColumns = unionNames.map { name -> Column in
            if let column = existing.columns.first(where: { $0.name == name }) {
                return column
            }
            if let column = imported.columns.first(where: { $0.name == name }) {
                return column
            }
            return Column(name: name, width: 100)
        }

        let cues = existing.cues.map {
            remappedCue($0, columnNames: existingColumnNames, unionNames: unionNames)
        } + imported.cues.map {
            remappedCue($0, columnNames: importedColumnNames, unionNames: unionNames)
        }

        return CueStack(name: existing.name, cues: cues, columns: unionColumns)
    }

    private static func disambiguatedName(base: String, used: Set<String>) -> String {
        var suffix = 2
        var candidate = "\(base) (\(suffix))"
        while used.contains(candidate) {
            suffix += 1
            candidate = "\(base) (\(suffix))"
        }
        return candidate
    }

    private static func remappedCue(_ cue: Cue, columnNames: [String], unionNames: [String]) -> Cue {
        let values = unionNames.map { name in
            if let index = columnNames.firstIndex(of: name), index < cue.values.count {
                return cue.values[index]
            }
            return ""
        }
        return Cue(values: values, timerValue: cue.timerValue, isStruckThrough: cue.isStruckThrough)
    }
}

// MARK: - Round-trip comparison (tests & validation)

extension CueCSVCodec {
    /// Expands stacks to the union-column shape produced by export (for round-trip tests).
    static func normalizedStacksForExport(_ stacks: [CueStack]) -> [CueStack] {
        var allColumnNames: [String] = []
        for stack in stacks {
            for col in stack.columns where !allColumnNames.contains(col.name) {
                allColumnNames.append(col.name)
            }
        }

        return stacks.map { stack in
            let columns = allColumnNames.map { Column(name: $0, width: 100) }
            let cues = stack.cues.map { cue -> Cue in
                let values = allColumnNames.map { name -> String in
                    if let idx = stack.columns.firstIndex(where: { $0.name == name }),
                       idx < cue.values.count {
                        return cue.values[idx]
                    }
                    return ""
                }
                return Cue(values: values, timerValue: cue.timerValue, isStruckThrough: cue.isStruckThrough)
            }
            return CueStack(name: stack.name, cues: cues, columns: columns)
        }
    }

    /// Compares cue data ignoring UUIDs and column widths.
    static func cueDataMatches(_ lhs: [CueStack], _ rhs: [CueStack]) -> Bool {
        guard lhs.count == rhs.count else { return false }
        for (a, b) in zip(lhs, rhs) {
            guard a.name == b.name else { return false }
            guard a.columns.map(\.name) == b.columns.map(\.name) else { return false }
            guard a.cues.count == b.cues.count else { return false }
            for (ca, cb) in zip(a.cues, b.cues) {
                guard ca.values == cb.values,
                      ca.timerValue == cb.timerValue,
                      ca.isStruckThrough == cb.isStruckThrough else {
                    return false
                }
            }
        }
        return true
    }
}
