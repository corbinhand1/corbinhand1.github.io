//
//  AICueStackGenerator.swift
//  Cue to Cue
//
//  File ▸ New Cue Stack from Documents…: reads a run of show and a client
//  document (Google Sheets exported as CSV/TSV, a shared Sheets link, or
//  pasted text), shows Claude a few of the user's own cue stacks as style
//  examples, and gets back a new cue stack in the same columns and voice.
//
//  Talks to the Anthropic Messages API over plain HTTPS (there is no
//  official Swift SDK). The API key lives in the Keychain.
//

import Foundation
import Security

// MARK: - API key storage

protocol AnthropicKeyStore: AnyObject {
    func readKey() -> String?
    func writeKey(_ key: String?) throws
}

final class KeychainAnthropicKeyStore: AnthropicKeyStore {
    private let service = "Cue to Cue AI"
    private let account = "anthropic-api-key"

    func readKey() -> String? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              let key = String(data: data, encoding: .utf8),
              !key.isEmpty else { return nil }
        return key
    }

    func writeKey(_ key: String?) throws {
        SecItemDelete(baseQuery as CFDictionary)
        guard let key, !key.isEmpty else { return }
        var item = baseQuery
        item[kSecValueData as String] = Data(key.utf8)
        item[kSecAttrLabel as String] = "Cue to Cue AI cue stacks (Anthropic API key)"
        let status = SecItemAdd(item as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status),
                          userInfo: [NSLocalizedDescriptionKey: "Couldn't save the key to the Keychain (error \(status))."])
        }
    }

    private var baseQuery: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }
}

final class InMemoryAnthropicKeyStore: AnthropicKeyStore {
    private var key: String?
    init(key: String? = nil) { self.key = key }
    func readKey() -> String? { key }
    func writeKey(_ key: String?) throws { self.key = key }
}

// MARK: - Source documents

/// One document the user gave us, already turned into plain text.
struct SourceDocument: Equatable {
    var name: String
    var text: String

    var isEmpty: Bool { text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
}

enum SourceDocumentReader {
    enum ReadError: LocalizedError, Equatable {
        case unsupportedFile(String)
        case unreadable(String)
        case privateSheet
        case notASheetsLink

        var errorDescription: String? {
            switch self {
            case .unsupportedFile(let ext):
                return "Cue to Cue can't read .\(ext) files. Use an Excel (.xlsx) or CSV file: in Google Sheets choose File ▸ Download ▸ Microsoft Excel."
            case .unreadable(let name):
                return "Couldn't read \u{201C}\(name)\u{201D} as text."
            case .privateSheet:
                return "That Google Sheet isn't shared publicly, so Cue to Cue can't open it. Set sharing to \u{201C}Anyone with the link\u{201D}, or download it as CSV and choose the file."
            case .notASheetsLink:
                return "That doesn't look like a Google Sheets link."
            }
        }
    }

    static let readableExtensions = ["xlsx", "csv", "tsv", "txt", "md", "text"]

    /// Reads a CSV/TSV/text file and turns it into a compact table.
    static func read(fileURL: URL) throws -> SourceDocument {
        let ext = fileURL.pathExtension.lowercased()
        guard readableExtensions.contains(ext) else { throw ReadError.unsupportedFile(ext) }
        if ext == "xlsx" {
            let sheets = try XLSXReader.read(fileURL: fileURL)
            // One sheet reads as a plain table; several get a heading each.
            let text = sheets.count == 1
                ? table(from: sheets[0].rows)
                : sheets.map { "## Sheet: \($0.name)\n" + table(from: $0.rows) }.joined(separator: "\n\n")
            return SourceDocument(name: fileURL.lastPathComponent, text: text)
        }
        let data = try Data(contentsOf: fileURL)
        guard let raw = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else {
            throw ReadError.unreadable(fileURL.lastPathComponent)
        }
        return SourceDocument(name: fileURL.lastPathComponent, text: normalize(raw, fileExtension: ext))
    }

    /// A workbook's visible tabs, so the user can choose which to send.
    static func sheets(fileURL: URL) throws -> [XLSXReader.Sheet] {
        try XLSXReader.read(fileURL: fileURL)
    }

    /// Picks the tabs that look like the show flow ("Main Keynote",
    /// "Run of Show", "Show Flow") and not templates or examples.
    static func likelyShowSheets(_ sheets: [XLSXReader.Sheet]) -> Set<String> {
        let wanted = ["keynote", "run of show", "show flow", "ros", "rundown", "agenda"]
        let unwanted = ["example", "template", "spec", "deadline", "tracker"]
        let matches = sheets.map(\.name).filter { name in
            let lower = name.lowercased()
            return wanted.contains { lower.contains($0) } && !unwanted.contains { lower.contains($0) }
        }
        return Set(matches.isEmpty ? sheets.prefix(1).map(\.name) : matches)
    }

    static func document(fileName: String, sheet: XLSXReader.Sheet) -> SourceDocument {
        SourceDocument(name: "\(fileName) \u{25B8} \(sheet.name)", text: table(from: sheet.rows))
    }

    /// Spreadsheet text (CSV or TSV) becomes one line per row with cells
    /// joined by " | ". Empty rows and trailing empty cells are dropped so
    /// the model reads less padding. Other text passes through unchanged.
    static func normalize(_ raw: String, fileExtension ext: String) -> String {
        let records: [[String]]
        switch ext {
        case "csv":
            records = CueCSVCodec.parseRecords(from: raw)
        case "tsv":
            records = raw.components(separatedBy: .newlines).map { $0.components(separatedBy: "\t") }
        default:
            return raw
        }
        return table(from: records)
    }

    static func table(from records: [[String]]) -> String {
        var lines: [String] = []
        for record in records {
            var cells = record.map { $0.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespaces) }
            while let last = cells.last, last.isEmpty { cells.removeLast() }
            guard !cells.isEmpty else { continue }
            lines.append(cells.joined(separator: " | "))
        }
        return lines.joined(separator: "\n")
    }

    /// The CSV export address for a Google Sheets link, keeping the tab
    /// (gid) the user was looking at.
    static func csvExportURL(forSheetsLink link: String) -> URL? {
        guard let url = URL(string: link.trimmingCharacters(in: .whitespacesAndNewlines)),
              let host = url.host, host.hasSuffix("docs.google.com") else { return nil }
        let parts = url.pathComponents
        guard let dIndex = parts.firstIndex(of: "d"), parts.indices.contains(dIndex + 1),
              parts.contains("spreadsheets") else { return nil }
        let id = parts[dIndex + 1]
        var gid: String?
        for source in [url.fragment, url.query] {
            guard let source else { continue }
            for pair in source.split(separator: "&") where pair.hasPrefix("gid=") {
                gid = String(pair.dropFirst(4))
            }
        }
        var components = URLComponents(string: "https://docs.google.com/spreadsheets/d/\(id)/export")!
        components.queryItems = [URLQueryItem(name: "format", value: "csv")]
        if let gid { components.queryItems?.append(URLQueryItem(name: "gid", value: gid)) }
        return components.url
    }

    /// Downloads a Google Sheet shared as "Anyone with the link".
    static func read(sheetsLink: String, session: URLSession = .shared) async throws -> SourceDocument {
        guard let exportURL = csvExportURL(forSheetsLink: sheetsLink) else { throw ReadError.notASheetsLink }
        let (data, response) = try await session.data(from: exportURL)
        let http = response as? HTTPURLResponse
        let contentType = http?.value(forHTTPHeaderField: "Content-Type")?.lowercased() ?? ""
        // A private sheet answers with a sign-in page (HTML), not CSV.
        guard http?.statusCode == 200, !contentType.contains("text/html"),
              let raw = String(data: data, encoding: .utf8) else {
            throw ReadError.privateSheet
        }
        return SourceDocument(name: "Google Sheet", text: normalize(raw, fileExtension: "csv"))
    }
}

// MARK: - Style examples

enum CueStyleExamples {
    /// Upper bounds that keep the request a sensible size.
    static let maxStacks = 6
    static let maxCuesPerStack = 150

    /// Renders the user's own stacks as compact tables: the model copies
    /// their columns, numbering, wording and timer habits from these.
    static func render(_ stacks: [CueStack]) -> String {
        stacks.prefix(maxStacks).map(render).joined(separator: "\n\n")
    }

    static func render(_ stack: CueStack) -> String {
        let columns = stack.columns.map(\.name)
        var lines = ["<example_stack name=\"\(escapeAttribute(stack.name))\">",
                     "Columns: " + (columns + ["Timer"]).joined(separator: " | ")]
        var count = 0
        for cue in stack.cues where !cue.isStruckThrough {
            var cells = (0..<columns.count).map { index in
                index < cue.values.count ? clean(cue.values[index]) : ""
            }
            cells.append(clean(cue.timerValue))
            guard cells.contains(where: { !$0.isEmpty }) else { continue }
            lines.append(cells.joined(separator: " | "))
            count += 1
            if count >= maxCuesPerStack { break }
        }
        lines.append("</example_stack>")
        return lines.joined(separator: "\n")
    }

    private static func clean(_ value: String) -> String {
        value.replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "|", with: "/")
            .trimmingCharacters(in: .whitespaces)
    }

    private static func escapeAttribute(_ value: String) -> String {
        value.replacingOccurrences(of: "\"", with: "'").replacingOccurrences(of: "\n", with: " ")
    }
}

// MARK: - Request

struct CueStackGenerationRequest {
    var runOfShow: [SourceDocument]
    var clientDocuments: [SourceDocument]
    var examples: [CueStack]
    /// Columns the new stack must use, in order. Empty lets Claude follow the examples.
    var columns: [String]
    var stackName: String
    var notes: String

    static let model = "claude-opus-5-5"
    static let maxTokens = 32000

    static let instructions = """
    You build cue stacks for Cue to Cue, a Mac app a live-event show caller \
    uses to call corporate keynotes and conferences. A cue stack is a table: \
    one row per cue, in show order, plus a countdown timer value per row.

    You are given one or more run-of-show documents (the producer's schedule of segments, \
    speakers, walk-ups, videos and transitions), sometimes client documents \
    (scripts, speaker names, graphics, walk-in and walk-out music, video \
    names), and example stacks this show caller built for earlier shows.

    Write the new stack the way this show caller writes theirs. Match the \
    examples closely: column use, cue numbering pattern, how descriptions are \
    phrased and abbreviated, which department columns get filled and with \
    what kind of words, where standby lines and clock times go, and how timer \
    values are written (for example "30:00", "2:45", or "8" for a short \
    count-in). Leave a cell empty where the examples would leave it empty. \
    Keep the show caller's habits even when they are informal.

    Every row of the run of show that needs a call should become one or more \
    cues; skip rows that are only logistics with nothing to call. Do not \
    invent speakers, video titles or times that are not in the documents. \
    When the documents leave something the show caller must confirm, write \
    the cue anyway and list the open question in notes.

    Each cue's cells array must have exactly one string per column, in \
    column order. The timer goes only in the timer field, never in a cell. \
    notes is a short plain-text list (one item per line, starting with "- ") \
    of assumptions and questions for the show caller; empty if none.
    """

    /// JSON schema the response must follow (structured outputs).
    static let responseSchema: [String: Any] = [
        "type": "object",
        "additionalProperties": false,
        "required": ["stackName", "columns", "cues", "notes"],
        "properties": [
            "stackName": ["type": "string"],
            "columns": ["type": "array", "items": ["type": "string"]],
            "cues": [
                "type": "array",
                "items": [
                    "type": "object",
                    "additionalProperties": false,
                    "required": ["cells", "timer"],
                    "properties": [
                        "cells": ["type": "array", "items": ["type": "string"]],
                        "timer": ["type": "string"],
                    ],
                ],
            ],
            "notes": ["type": "string"],
        ],
    ]

    func userMessage() -> String {
        var parts: [String] = []
        for document in runOfShow where !document.isEmpty {
            parts.append("<run_of_show name=\"\(document.name)\">\n\(document.text)\n</run_of_show>")
        }
        for document in clientDocuments where !document.isEmpty {
            parts.append("<client_document name=\"\(document.name)\">\n\(document.text)\n</client_document>")
        }
        if columns.isEmpty {
            parts.append("Use the columns the examples use most (without the Timer column, which is the timer field).")
        } else {
            parts.append("Use exactly these columns, in this order: " + columns.joined(separator: " | "))
        }
        let name = stackName.trimmingCharacters(in: .whitespacesAndNewlines)
        parts.append(name.isEmpty ? "Name the stack after the show or session in the run of show." : "Name the stack \"\(name)\".")
        let extra = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        if !extra.isEmpty {
            parts.append("Notes from the show caller for this show:\n\(extra)")
        }
        return parts.joined(separator: "\n\n")
    }

    /// Body for POST /v1/messages. Streaming, high effort, JSON output, and
    /// the instructions plus examples cached so re-running a show is cheaper.
    func body() -> [String: Any] {
        var system: [[String: Any]] = [["type": "text", "text": Self.instructions]]
        let renderedExamples = CueStyleExamples.render(examples)
        if !renderedExamples.isEmpty {
            system.append(["type": "text",
                           "text": "Example stacks by this show caller:\n\n" + renderedExamples])
        }
        system[system.count - 1]["cache_control"] = ["type": "ephemeral"]
        return [
            "model": Self.model,
            "max_tokens": Self.maxTokens,
            "stream": true,
            "fallbacks": "default",
            "output_config": [
                "effort": "high",
                "format": ["type": "json_schema", "schema": Self.responseSchema],
            ],
            "system": system,
            "messages": [["role": "user", "content": userMessage()]],
        ]
    }
}

// MARK: - Result

struct GeneratedCueStack: Equatable {
    var stack: CueStack
    var notes: [String]
    /// Model that wrote the answer (differs from the requested one after a fallback).
    var model: String
}

struct GeneratedPayload: Decodable {
    struct Row: Decodable {
        var cells: [String]
        var timer: String
    }
    var stackName: String
    var columns: [String]
    var cues: [Row]
    var notes: String
}

enum CueStackGenerationError: LocalizedError, Equatable {
    case missingKey
    case invalidKey
    case rateLimited
    case overloaded
    case requestTooLarge
    case refused
    case truncated
    case badResponse(String)
    case server(Int, String)

    var errorDescription: String? {
        switch self {
        case .missingKey: return "Add your Anthropic API key first."
        case .invalidKey: return "Anthropic didn't accept the API key. Check it at console.anthropic.com and paste it again."
        case .rateLimited: return "Too many requests on this API key right now. Wait a minute and try again."
        case .overloaded: return "Claude is busy right now. Try again in a minute."
        case .requestTooLarge: return "The documents are too long to send in one go. Remove a style example or trim the documents."
        case .refused: return "Claude declined to build this stack. Try removing anything unusual from the documents."
        case .truncated: return "The stack was too long to finish in one answer. Split the run of show into parts and build each one."
        case .badResponse(let detail): return "Claude's answer couldn't be read (\(detail)). Try again."
        case .server(let code, let message): return "The request failed (\(code)): \(message)"
        }
    }
}

// MARK: - Client

final class CueStackGenerator {
    static let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!

    private let keyStore: AnthropicKeyStore
    private let session: URLSession

    init(keyStore: AnthropicKeyStore = KeychainAnthropicKeyStore(), session: URLSession? = nil) {
        self.keyStore = keyStore
        if let session {
            self.session = session
        } else {
            let config = URLSessionConfiguration.default
            // Thinking at high effort can pause the stream for a while.
            config.timeoutIntervalForRequest = 300
            config.timeoutIntervalForResource = 900
            self.session = URLSession(configuration: config)
        }
    }

    func urlRequest(for request: CueStackGenerationRequest, apiKey: String) throws -> URLRequest {
        try urlRequest(body: request.body(), apiKey: apiKey)
    }

    func urlRequest(body: [String: Any], apiKey: String) throws -> URLRequest {
        var urlRequest = URLRequest(url: Self.endpoint)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        urlRequest.setValue("2026-10-21", forHTTPHeaderField: "anthropic-version")
        urlRequest.setValue("server-side-fallback-2026-07-01", forHTTPHeaderField: "anthropic-beta")
        urlRequest.setValue("application/json", forHTTPHeaderField: "content-type")
        urlRequest.httpBody = try JSONSerialization.data(withJSONObject: body)
        return urlRequest
    }

    /// Runs the request. `progress` gets the number of cues written so far.
    func generate(_ request: CueStackGenerationRequest,
                  progress: @escaping @Sendable (Int) -> Void = { _ in }) async throws -> GeneratedCueStack {
        let stream = try await send(body: request.body(), progress: progress)
        return try Self.result(from: stream, request: request)
    }

    /// Sends a streaming Messages request and collects the answer.
    func send(body: [String: Any],
              progress: @escaping @Sendable (Int) -> Void = { _ in }) async throws -> MessageStreamAccumulator {
        guard let apiKey = keyStore.readKey() else { throw CueStackGenerationError.missingKey }
        let urlRequest = try urlRequest(body: body, apiKey: apiKey)

        let (bytes, response) = try await session.bytes(for: urlRequest)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else {
            var body = Data()
            for try await byte in bytes { body.append(byte) }
            throw Self.error(forStatus: status, body: body)
        }

        var stream = MessageStreamAccumulator()
        for try await line in bytes.lines {
            try stream.consume(line: line)
            progress(stream.cuesSoFar)
        }
        return stream
    }

    static func error(forStatus status: Int, body: Data) -> CueStackGenerationError {
        let message = (try? JSONSerialization.jsonObject(with: body) as? [String: Any])
            .flatMap { $0["error"] as? [String: Any] }
            .flatMap { $0["message"] as? String } ?? HTTPURLResponse.localizedString(forStatusCode: status)
        switch status {
        case 401, 403: return .invalidKey
        case 413: return .requestTooLarge
        case 429: return .rateLimited
        case 529, 503: return .overloaded
        default: return .server(status, message)
        }
    }

    static func result(from stream: MessageStreamAccumulator, request: CueStackGenerationRequest) throws -> GeneratedCueStack {
        if let error = stream.error { throw error }
        switch stream.stopReason {
        case "refusal": throw CueStackGenerationError.refused
        case "max_tokens": throw CueStackGenerationError.truncated
        case nil: throw CueStackGenerationError.badResponse("the answer ended early")
        default: break
        }
        guard let data = stream.text.data(using: .utf8),
              let payload = try? JSONDecoder().decode(GeneratedPayload.self, from: data) else {
            throw CueStackGenerationError.badResponse("not valid JSON")
        }
        return GeneratedCueStack(stack: makeStack(from: payload, request: request),
                                 notes: payload.notes.components(separatedBy: .newlines)
                                    .map { $0.trimmingCharacters(in: .whitespaces) }
                                    .map { $0.hasPrefix("- ") ? String($0.dropFirst(2)) : $0 }
                                    .filter { !$0.isEmpty },
                                 model: stream.model ?? CueStackGenerationRequest.model)
    }

    /// Builds the CueStack, padding or trimming rows to the column count and
    /// borrowing column widths from the examples so it looks like the others.
    static func makeStack(from payload: GeneratedPayload, request: CueStackGenerationRequest) -> CueStack {
        var names = request.columns.isEmpty ? payload.columns : request.columns
        names = names.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        if names.isEmpty { names = ["#", "Description"] }

        var widths: [String: CGFloat] = [:]
        for stack in request.examples {
            for column in stack.columns where widths[column.name.lowercased()] == nil {
                widths[column.name.lowercased()] = column.width
            }
        }
        let columns = names.map { name -> Column in
            let fallback: CGFloat = name.lowercased().contains("desc") ? 420 : (name.count <= 2 ? 60 : 120)
            return Column(name: name, width: widths[name.lowercased()] ?? fallback)
        }

        let cues = payload.cues.map { row -> Cue in
            var values = Array(row.cells.prefix(names.count))
            values += Array(repeating: "", count: names.count - values.count)
            return Cue(values: values, timerValue: row.timer.trimmingCharacters(in: .whitespaces))
        }

        let requested = request.stackName.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = requested.isEmpty ? payload.stackName.trimmingCharacters(in: .whitespacesAndNewlines) : requested
        return CueStack(name: name.isEmpty ? "New Cue Stack" : name, cues: cues, columns: columns)
    }
}

// MARK: - Streaming

/// Collects a Messages API server-sent event stream: the JSON text (all text
/// blocks in order, which stays correct across a mid-stream fallback), the
/// stop reason and the model that answered.
struct MessageStreamAccumulator {
    private(set) var text = ""
    private(set) var stopReason: String?
    private(set) var model: String?
    private(set) var error: CueStackGenerationError?
    private(set) var cuesSoFar = 0

    mutating func consume(line: String) throws {
        guard line.hasPrefix("data:") else { return }
        let json = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
        guard let data = json.data(using: .utf8),
              let event = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = event["type"] as? String else { return }

        switch type {
        case "message_start":
            if let message = event["message"] as? [String: Any] {
                model = message["model"] as? String
            }
        case "content_block_delta":
            if let delta = event["delta"] as? [String: Any],
               delta["type"] as? String == "text_delta",
               let piece = delta["text"] as? String {
                text += piece
                cuesSoFar += piece.components(separatedBy: "\"cells\"").count - 1
            }
        case "message_delta":
            if let delta = event["delta"] as? [String: Any], let reason = delta["stop_reason"] as? String {
                stopReason = reason
            }
        case "error":
            let detail = event["error"] as? [String: Any]
            let errorType = detail?["type"] as? String ?? ""
            let message = detail?["message"] as? String ?? "Unknown error"
            switch errorType {
            case "overloaded_error": error = .overloaded
            case "rate_limit_error": error = .rateLimited
            default: error = .server(0, message)
            }
        default:
            break
        }
    }
}

// MARK: - Excel (.xlsx)

/// Reads every visible sheet of an .xlsx workbook (what Google Sheets
/// gives you with File ▸ Download ▸ Microsoft Excel). An .xlsx is a zip of
/// XML files; the system `unzip` extracts the parts we need.
enum XLSXReader {
    struct Sheet: Equatable {
        var name: String
        var rows: [[String]]
    }

    enum ReadError: LocalizedError {
        case notAWorkbook(String)
        var errorDescription: String? {
            switch self {
            case .notAWorkbook(let name): return "\u{201C}\(name)\u{201D} isn't a readable Excel workbook."
            }
        }
    }

    static func read(fileURL: URL) throws -> [Sheet] {
        try read(entry: { try unzipEntry($0, from: fileURL) }, fileName: fileURL.lastPathComponent)
    }

    /// `entry` returns a part of the workbook by its path inside the zip.
    static func read(entry: (String) throws -> Data?, fileName: String) throws -> [Sheet] {
        guard let workbook = try entry("xl/workbook.xml") else { throw ReadError.notAWorkbook(fileName) }
        let shared = try entry("xl/sharedStrings.xml").map(SharedStringsParser.parse) ?? []
        let dateStyles = try entry("xl/styles.xml").map(StylesParser.dateStyleIndexes) ?? []
        let targets = try entry("xl/_rels/workbook.xml.rels").map(RelationshipsParser.parse) ?? [:]

        var sheets: [Sheet] = []
        for (index, sheet) in WorkbookParser.parse(workbook).enumerated() where !sheet.hidden {
            var path = targets[sheet.relationshipID] ?? "worksheets/sheet\(index + 1).xml"
            path = path.hasPrefix("/") ? String(path.dropFirst()) : "xl/" + path
            guard let data = try entry(path) else { continue }
            let rows = WorksheetParser.parse(data, sharedStrings: shared, dateStyles: dateStyles)
            if rows.contains(where: { $0.contains { !$0.isEmpty } }) {
                sheets.append(Sheet(name: sheet.name, rows: rows))
            }
        }
        return sheets
    }

    private static func unzipEntry(_ path: String, from url: URL) throws -> Data? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-p", url.path, path]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = Pipe()
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return process.terminationStatus == 0 && !data.isEmpty ? data : nil
    }

    // MARK: Cell values

    /// Excel stores dates and times as days since 1899-12-30; shows them the way a person would type them.
    static func formatDate(serial: Double, formatCode: String) -> String {
        let twelveHour = formatCode.uppercased().contains("AM/PM") || formatCode.isEmpty
        let days = serial.rounded(.down)
        let seconds = Int(((serial - days) * 86400).rounded())
        var parts: [String] = []
        if days > 0 {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(identifier: "UTC")!
            let base = calendar.date(from: DateComponents(year: 1899, month: 12, day: 30))!
            let date = calendar.date(byAdding: .day, value: Int(days), to: base)!
            let c = calendar.dateComponents([.year, .month, .day], from: date)
            parts.append("\(c.month!)/\(c.day!)/\(c.year!)")
        }
        if seconds > 0 || days == 0 {
            let h = (seconds / 3600) % 24, m = (seconds / 60) % 60, s = seconds % 60
            let secondsPart = s > 0 ? String(format: ":%02d", s) : ""
            if twelveHour {
                let hour12 = h % 12 == 0 ? 12 : h % 12
                parts.append(String(format: "%d:%02d", hour12, m) + secondsPart + (h < 12 ? " AM" : " PM"))
            } else {
                parts.append(String(format: "%d:%02d", h, m) + secondsPart)
            }
        }
        return parts.joined(separator: " ")
    }

    static func formatNumber(_ raw: String) -> String {
        guard let value = Double(raw) else { return raw }
        if value == value.rounded(), abs(value) < 1e15 { return String(Int64(value)) }
        return String(format: "%.10g", value)
    }

    /// "B12" → 1
    static func columnIndex(_ reference: String) -> Int? {
        var index = 0
        var sawLetter = false
        for scalar in reference.unicodeScalars {
            guard scalar.value >= 65, scalar.value <= 90 else { break }
            index = index * 26 + Int(scalar.value - 64)
            sawLetter = true
        }
        return sawLetter ? index - 1 : nil
    }
}

private final class SharedStringsParser: NSObject, XMLParserDelegate {
    private var strings: [String] = []
    private var current = ""
    private var inText = false
    private var inPhonetic = false

    static func parse(_ data: Data) -> [String] {
        let delegate = SharedStringsParser()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.parse()
        return delegate.strings
    }

    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String] = [:]) {
        switch name {
        case "si": current = ""
        case "rPh": inPhonetic = true
        case "t": inText = !inPhonetic
        default: break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if inText { current += string }
    }

    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
        switch name {
        case "t": inText = false
        case "rPh": inPhonetic = false
        case "si": strings.append(current)
        default: break
        }
    }
}

/// Which cell styles (indexes into cellXfs) show a date or time, and their format codes.
private final class StylesParser: NSObject, XMLParserDelegate {
    private var customFormats: [Int: String] = [:]
    private var inCellXfs = false
    private var styles: [String] = []   // format code per style ("" when not a date)

    static func dateStyleIndexes(_ data: Data) -> [String] {
        let delegate = StylesParser()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.parse()
        return delegate.styles
    }

    private static let builtInDateFormats: [Int: String] = [
        14: "m/d/yyyy", 15: "d-mmm-yy", 16: "d-mmm", 17: "mmm-yy", 18: "h:mm AM/PM", 19: "h:mm:ss AM/PM",
        20: "h:mm", 21: "h:mm:ss", 22: "m/d/yyyy h:mm", 45: "mm:ss", 46: "[h]:mm:ss", 47: "mm:ss.0",
    ]

    private static func isDateFormat(_ code: String) -> Bool {
        // Drop quoted text and [colors]; any of d, m, y, h, s left means a date/time.
        var cleaned = code.replacingOccurrences(of: "\"[^\"]*\"", with: "", options: .regularExpression)
        cleaned = cleaned.replacingOccurrences(of: "\\[(?![hms]+\\])[^\\]]*\\]", with: "", options: .regularExpression)
        return cleaned.lowercased().rangeOfCharacter(from: CharacterSet(charactersIn: "dmyhs")) != nil
    }

    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String] = [:]) {
        switch name {
        case "numFmt":
            if let id = attributes["numFmtId"].flatMap(Int.init), let code = attributes["formatCode"] {
                customFormats[id] = code
            }
        case "cellXfs": inCellXfs = true
        case "xf" where inCellXfs:
            let id = attributes["numFmtId"].flatMap(Int.init) ?? 0
            if let code = customFormats[id] {
                styles.append(Self.isDateFormat(code) ? code : "")
            } else {
                styles.append(Self.builtInDateFormats[id] ?? "")
            }
        default: break
        }
    }

    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
        if name == "cellXfs" { inCellXfs = false }
    }
}

private final class RelationshipsParser: NSObject, XMLParserDelegate {
    private var targets: [String: String] = [:]

    static func parse(_ data: Data) -> [String: String] {
        let delegate = RelationshipsParser()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.parse()
        return delegate.targets
    }

    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String] = [:]) {
        if name == "Relationship", let id = attributes["Id"], let target = attributes["Target"] {
            targets[id] = target
        }
    }
}

private final class WorkbookParser: NSObject, XMLParserDelegate {
    struct Entry { var name: String; var relationshipID: String; var hidden: Bool }
    private var entries: [Entry] = []

    static func parse(_ data: Data) -> [Entry] {
        let delegate = WorkbookParser()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.parse()
        return delegate.entries
    }

    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String] = [:]) {
        guard name == "sheet" else { return }
        let id = attributes.first { $0.key.hasSuffix(":id") || $0.key == "id" }?.value ?? ""
        entries.append(Entry(name: attributes["name"] ?? "Sheet", relationshipID: id,
                             hidden: (attributes["state"] ?? "visible") != "visible"))
    }
}

private final class WorksheetParser: NSObject, XMLParserDelegate {
    private let sharedStrings: [String]
    private let dateStyles: [String]
    private var rows: [Int: [Int: String]] = [:]
    private var rowIndex = -1
    private var nextColumn = 0
    private var cellColumn = 0
    private var cellType = ""
    private var cellStyle = 0
    private var value = ""
    private var capturing = false

    init(sharedStrings: [String], dateStyles: [String]) {
        self.sharedStrings = sharedStrings
        self.dateStyles = dateStyles
    }

    static func parse(_ data: Data, sharedStrings: [String], dateStyles: [String]) -> [[String]] {
        let delegate = WorksheetParser(sharedStrings: sharedStrings, dateStyles: dateStyles)
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.parse()
        guard let lastRow = delegate.rows.keys.max() else { return [] }
        return (0...lastRow).map { index in
            guard let cells = delegate.rows[index], let lastColumn = cells.keys.max() else { return [] }
            return (0...lastColumn).map { cells[$0] ?? "" }
        }
    }

    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String] = [:]) {
        switch name {
        case "row":
            rowIndex = attributes["r"].flatMap(Int.init).map { $0 - 1 } ?? rowIndex + 1
            nextColumn = 0
        case "c":
            cellColumn = attributes["r"].flatMap(XLSXReader.columnIndex) ?? nextColumn
            nextColumn = cellColumn + 1
            cellType = attributes["t"] ?? "n"
            cellStyle = attributes["s"].flatMap(Int.init) ?? 0
            value = ""
        case "v", "t":
            capturing = true
        default: break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if capturing { value += string }
    }

    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
        switch name {
        case "v", "t":
            capturing = false
        case "c":
            let text: String
            switch cellType {
            case "s": text = Int(value).flatMap { sharedStrings.indices.contains($0) ? sharedStrings[$0] : nil } ?? ""
            case "b": text = value == "1" ? "TRUE" : "FALSE"
            case "str", "inlineStr", "e": text = value
            default:
                let format = dateStyles.indices.contains(cellStyle) ? dateStyles[cellStyle] : ""
                if !format.isEmpty, let serial = Double(value) {
                    text = XLSXReader.formatDate(serial: serial, formatCode: format)
                } else {
                    text = XLSXReader.formatNumber(value)
                }
            }
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty, rowIndex >= 0 {
                rows[rowIndex, default: [:]][cellColumn] = trimmed
            }
        default: break
        }
    }
}
