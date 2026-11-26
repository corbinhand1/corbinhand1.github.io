//
//  AICueStackGeneratorTests.swift
//  Cue to CueTests
//
//  New Cue Stack from Documents: document reading, the request we send to
//  Claude, and turning the streamed answer into a CueStack. Network calls go
//  to a fake Anthropic API (URLProtocol); nothing leaves the machine.
//

import XCTest
@testable import Cue_to_Cue

final class FakeAnthropic: URLProtocol {
    static var status = 200
    static var body = ""
    static var lastRequest: URLRequest?
    static var lastBody: [String: Any]?

    static func session() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [FakeAnthropic.self]
        return URLSession(configuration: config)
    }

    override class func canInit(with request: URLRequest) -> Bool { request.url?.host == "api.anthropic.com" }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        Self.lastRequest = request
        if let stream = request.httpBodyStream {
            stream.open()
            var data = Data()
            var buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let read = stream.read(&buffer, maxLength: buffer.count)
                if read <= 0 { break }
                data.append(buffer, count: read)
            }
            stream.close()
            Self.lastBody = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        } else if let data = request.httpBody {
            Self.lastBody = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: Self.status, httpVersion: "HTTP/1.1",
                                       headerFields: ["Content-Type": "text/event-stream"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(Self.body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
}

final class AICueStackGeneratorTests: XCTestCase {

    private let example = CueStack(
        name: "Sales Keynote",
        cues: [
            Cue(values: ["201", "Doors, Walk in Music", "Rock"], timerValue: ""),
            Cue(values: ["202", "Preset 32 + FLS", ""], timerValue: "50:00"),
            Cue(values: ["", "Cut cue", ""], timerValue: "", isStruckThrough: true),
        ],
        columns: [Column(name: "#", width: 55), Column(name: "Description", width: 476), Column(name: "Audio", width: 90)]
    )

    private func request(columns: [String] = []) -> CueStackGenerationRequest {
        CueStackGenerationRequest(runOfShow: [SourceDocument(name: "ros.xlsx", text: "9:00 | Doors"),
                                              SourceDocument(name: "day2.csv", text: "10:00 | Doors")],
                                  clientDocuments: [SourceDocument(name: "client.csv", text: "Walk in: Rock")],
                                  examples: [example], columns: columns, stackName: "", notes: "Start at 300")
    }

    /// SSE stream whose text deltas split the JSON at awkward places.
    private func stream(json: String, stopReason: String = "end_turn", model: String = "claude-opus-5-5") -> String {
        var lines = ["event: message_start",
                     "data: {\"type\":\"message_start\",\"message\":{\"model\":\"\(model)\"}}", ""]
        var rest = Substring(json)
        while !rest.isEmpty {
            let piece = String(rest.prefix(17))
            rest = rest.dropFirst(17)
            let encoded = String(data: try! JSONSerialization.data(withJSONObject: ["type": "text_delta", "text": piece]), encoding: .utf8)!
            lines += ["event: content_block_delta",
                      "data: {\"type\":\"content_block_delta\",\"index\":0,\"delta\":\(encoded)}", ""]
        }
        lines += ["event: message_delta",
                  "data: {\"type\":\"message_delta\",\"delta\":{\"stop_reason\":\"\(stopReason)\"}}", "",
                  "event: message_stop", "data: {\"type\":\"message_stop\"}", ""]
        return lines.joined(separator: "\n")
    }

    private let answer = """
    {"stackName":"Service Keynote","columns":["#","Description","Audio"],"cues":[\
    {"cells":["301","Doors, Walk in Music","Rock"],"timer":""},\
    {"cells":["302","Preset 32 + FLS"],"timer":"30:00"},\
    {"cells":["303","VO","APM","extra"],"timer":" "}],\
    "notes":"- Confirm the walk-in song\\n- Who does the VO?"}
    """

    // MARK: Documents

    func testCSVBecomesCompactTable() {
        let csv = "Time,Segment,,\n,,,\n9:00,\"Doors, walk in\",,\n9:58,Roll records,Audio,\n"
        XCTAssertEqual(SourceDocumentReader.normalize(csv, fileExtension: "csv"),
                       "Time | Segment\n9:00 | Doors, walk in\n9:58 | Roll records | Audio")
    }

    func testTSVPastedFromSheets() {
        XCTAssertEqual(SourceDocumentReader.normalize("A\tB\t\n\t\t\nC\t\tD", fileExtension: "tsv"), "A | B\nC |  | D")
    }

    func testGoogleSheetsLinkKeepsTab() {
        let url = SourceDocumentReader.csvExportURL(forSheetsLink: "https://docs.google.com/spreadsheets/d/AbC123_x/edit#gid=456")
        XCTAssertEqual(url?.absoluteString, "https://docs.google.com/spreadsheets/d/AbC123_x/export?format=csv&gid=456")
        XCTAssertNil(SourceDocumentReader.csvExportURL(forSheetsLink: "https://example.com/spreadsheets/d/x"))
        XCTAssertNil(SourceDocumentReader.csvExportURL(forSheetsLink: "just some pasted text"))
    }

    func testUnsupportedFileIsExplained() {
        XCTAssertThrowsError(try SourceDocumentReader.read(fileURL: URL(fileURLWithPath: "/tmp/show.numbers"))) { error in
            XCTAssertEqual(error as? SourceDocumentReader.ReadError, .unsupportedFile("numbers"))
        }
    }

    // MARK: Excel

    /// A two-sheet workbook (plus a hidden one) as Google Sheets exports it:
    /// shared strings, a time column, a date, numbers and a gap column.
    private let workbookParts: [String: String] = [
        "xl/workbook.xml": """
        <workbook xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheets>
        <sheet name="Run of Show" sheetId="1" r:id="rId1"/><sheet name="Hidden" sheetId="2" state="hidden" r:id="rId2"/>
        <sheet name="Day 2" sheetId="3" r:id="rId3"/></sheets></workbook>
        """,
        "xl/_rels/workbook.xml.rels": """
        <Relationships><Relationship Id="rId1" Target="worksheets/sheet1.xml"/>
        <Relationship Id="rId2" Target="worksheets/sheet2.xml"/><Relationship Id="rId3" Target="/xl/worksheets/sheet3.xml"/></Relationships>
        """,
        "xl/sharedStrings.xml": """
        <sst><si><t>Time</t></si><si><t>Segment</t></si><si><r><t>Doors &amp; </t></r><r><t>walk in</t></r></si><si><t>Keynote</t></si></sst>
        """,
        "xl/styles.xml": """
        <styleSheet><numFmts><numFmt numFmtId="164" formatCode="h:mm AM/PM"/><numFmt numFmtId="165" formatCode="0.0"/></numFmts>
        <cellXfs><xf numFmtId="0"/><xf numFmtId="164"/><xf numFmtId="14"/><xf numFmtId="165"/></cellXfs></styleSheet>
        """,
        "xl/worksheets/sheet1.xml": """
        <worksheet><sheetData>
        <row r="1"><c r="A1" t="s"><v>0</v></c><c r="B1" t="s"><v>1</v></c></row>
        <row r="3"><c r="A3" s="1"><v>0.375</v></c><c r="B3" t="s"><v>2</v></c><c r="D3"><v>201</v></c></row>
        <row r="4"><c r="A4" s="1"><v>0.4152777777777778</v></c><c r="B4" t="inlineStr"><is><t>Walk up</t></is></c><c r="C4" s="3"><v>202.1</v></c></row>
        </sheetData></worksheet>
        """,
        "xl/worksheets/sheet2.xml": "<worksheet><sheetData><row r=\"1\"><c r=\"A1\" t=\"str\"><v>secret</v></c></row></sheetData></worksheet>",
        "xl/worksheets/sheet3.xml": """
        <worksheet><sheetData><row r="1"><c r="A1" s="2"><v>46280</v></c><c r="B1" t="s"><v>3</v></c></row></sheetData></worksheet>
        """,
    ]

    func testExcelWorkbookReadsVisibleSheets() throws {
        let sheets = try XLSXReader.read(entry: { workbookParts[$0].map { Data($0.utf8) } }, fileName: "ros.xlsx")
        XCTAssertEqual(sheets.map(\.name), ["Run of Show", "Day 2"])
        XCTAssertEqual(sheets[0].rows, [
            ["Time", "Segment"],
            [],
            ["9:00 AM", "Doors & walk in", "", "201"],
            ["9:58 AM", "Walk up", "202.1"],
        ])
        XCTAssertEqual(sheets[1].rows, [["9/15/2026", "Keynote"]])
    }

    func testExcelTimesAndColumns() {
        XCTAssertEqual(XLSXReader.formatDate(serial: 0.75, formatCode: "h:mm"), "18:00")
        XCTAssertEqual(XLSXReader.formatDate(serial: 0.5003472222, formatCode: "h:mm:ss AM/PM"), "12:00:30 PM")
        XCTAssertEqual(XLSXReader.formatNumber("8"), "8")
        XCTAssertEqual(XLSXReader.columnIndex("AB12"), 27)
    }

    func testRealXLSXFileOnDisk() throws {
        // Zip the parts with the system zip so the unzip path is exercised too.
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("xlsx-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        for (path, xml) in workbookParts {
            let url = dir.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(xml.utf8).write(to: url)
        }
        let zip = Process()
        zip.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        zip.currentDirectoryURL = dir
        zip.arguments = ["-qr", "show.xlsx", "xl"]
        try zip.run()
        zip.waitUntilExit()
        let document = try SourceDocumentReader.read(fileURL: dir.appendingPathComponent("show.xlsx"))
        XCTAssertEqual(document.text, """
        ## Sheet: Run of Show
        Time | Segment
        9:00 AM | Doors & walk in |  | 201
        9:58 AM | Walk up | 202.1

        ## Sheet: Day 2
        9/15/2026 | Keynote
        """)
    }

    // MARK: Request

    func testStyleExamplesSkipCutCuesAndShowTimer() {
        let text = CueStyleExamples.render(example)
        XCTAssertTrue(text.contains("Columns: # | Description | Audio | Timer"))
        XCTAssertTrue(text.contains("202 | Preset 32 + FLS |  | 50:00"))
        XCTAssertFalse(text.contains("Cut cue"))
    }

    func testRequestBody() {
        let body = request(columns: ["#", "Description"]).body()
        XCTAssertEqual(body["model"] as? String, "claude-opus-5-5")
        XCTAssertEqual(body["stream"] as? Bool, true)
        XCTAssertEqual(body["fallbacks"] as? String, "default")
        XCTAssertNil(body["thinking"], "Opus 5.5 always thinks; budgets are rejected")
        let output = body["output_config"] as? [String: Any]
        XCTAssertEqual(output?["effort"] as? String, "high")
        XCTAssertEqual((output?["format"] as? [String: Any])?["type"] as? String, "json_schema")

        let system = body["system"] as? [[String: Any]]
        XCTAssertEqual(system?.count, 2)
        XCTAssertNil(system?.first?["cache_control"])
        XCTAssertNotNil(system?.last?["cache_control"], "examples are cached")
        XCTAssertTrue((system?.last?["text"] as? String)?.contains("Sales Keynote") == true)

        let message = ((body["messages"] as? [[String: Any]])?.first?["content"] as? String) ?? ""
        XCTAssertTrue(message.contains("<run_of_show name=\"ros.xlsx\">"))
        XCTAssertTrue(message.contains("<run_of_show name=\"day2.csv\">\n10:00 | Doors"))
        XCTAssertTrue(message.contains("<client_document name=\"client.csv\">"))
        XCTAssertTrue(message.contains("Use exactly these columns, in this order: # | Description"))
        XCTAssertTrue(message.contains("Start at 300"))
        XCTAssertTrue(JSONSerialization.isValidJSONObject(body))
    }

    // MARK: Answer

    func testStreamedAnswerBecomesStack() throws {
        var accumulator = MessageStreamAccumulator()
        for line in stream(json: answer, model: "claude-opus-4-8").components(separatedBy: "\n") {
            try accumulator.consume(line: line)
        }
        let result = try CueStackGenerator.result(from: accumulator, request: request())
        XCTAssertEqual(result.stack.name, "Service Keynote")
        XCTAssertEqual(result.stack.columns.map(\.name), ["#", "Description", "Audio"])
        XCTAssertEqual(result.stack.columns.map(\.width), [55, 476, 90], "widths come from the examples")
        XCTAssertEqual(result.stack.cues.map(\.values), [
            ["301", "Doors, Walk in Music", "Rock"],
            ["302", "Preset 32 + FLS", ""],
            ["303", "VO", "APM"],
        ])
        XCTAssertEqual(result.stack.cues.map(\.timerValue), ["", "30:00", ""])
        XCTAssertEqual(result.notes, ["Confirm the walk-in song", "Who does the VO?"])
        XCTAssertEqual(result.model, "claude-opus-4-8")
        XCTAssertEqual(accumulator.cuesSoFar, 3)
    }

    func testRequestedNameAndColumnsWin() throws {
        var accumulator = MessageStreamAccumulator()
        for line in stream(json: answer).components(separatedBy: "\n") { try accumulator.consume(line: line) }
        var req = request(columns: ["#", "Description"])
        req.stackName = "Tuesday 9a"
        let result = try CueStackGenerator.result(from: accumulator, request: req)
        XCTAssertEqual(result.stack.name, "Tuesday 9a")
        XCTAssertEqual(result.stack.cues[0].values, ["301", "Doors, Walk in Music"])
    }

    func testRefusalAndTruncation() throws {
        for (reason, expected) in [("refusal", CueStackGenerationError.refused), ("max_tokens", .truncated)] {
            var accumulator = MessageStreamAccumulator()
            for line in stream(json: "{\"stackName\":", stopReason: reason).components(separatedBy: "\n") {
                try accumulator.consume(line: line)
            }
            XCTAssertThrowsError(try CueStackGenerator.result(from: accumulator, request: request())) { error in
                XCTAssertEqual(error as? CueStackGenerationError, expected)
            }
        }
    }

    func testHTTPErrors() {
        XCTAssertEqual(CueStackGenerator.error(forStatus: 401, body: Data()), .invalidKey)
        XCTAssertEqual(CueStackGenerator.error(forStatus: 529, body: Data()), .overloaded)
        let body = Data(#"{"type":"error","error":{"type":"invalid_request_error","message":"bad thing"}}"#.utf8)
        XCTAssertEqual(CueStackGenerator.error(forStatus: 400, body: body), .server(400, "bad thing"))
    }

    // MARK: End to end against the fake API

    func testGenerateSendsHeadersAndParsesStream() async throws {
        FakeAnthropic.status = 200
        FakeAnthropic.body = stream(json: answer)
        let generator = CueStackGenerator(keyStore: InMemoryAnthropicKeyStore(key: "sk-ant-test"),
                                          session: FakeAnthropic.session())
        let result = try await generator.generate(request())
        XCTAssertEqual(result.stack.cues.count, 3)
        let sent = try XCTUnwrap(FakeAnthropic.lastRequest)
        XCTAssertEqual(sent.value(forHTTPHeaderField: "x-api-key"), "sk-ant-test")
        XCTAssertEqual(sent.value(forHTTPHeaderField: "anthropic-version"), "2026-10-21")
        XCTAssertEqual(sent.value(forHTTPHeaderField: "anthropic-beta"), "server-side-fallback-2026-07-01")
        XCTAssertEqual(FakeAnthropic.lastBody?["model"] as? String, "claude-opus-5-5")
    }

    func testGenerateWithoutKey() async {
        let generator = CueStackGenerator(keyStore: InMemoryAnthropicKeyStore(), session: FakeAnthropic.session())
        do {
            _ = try await generator.generate(request())
            XCTFail("expected missingKey")
        } catch {
            XCTAssertEqual(error as? CueStackGenerationError, .missingKey)
        }
    }

    func testGenerateMapsHTTPFailure() async {
        FakeAnthropic.status = 401
        FakeAnthropic.body = #"{"type":"error","error":{"type":"authentication_error","message":"invalid x-api-key"}}"#
        let generator = CueStackGenerator(keyStore: InMemoryAnthropicKeyStore(key: "bad"), session: FakeAnthropic.session())
        do {
            _ = try await generator.generate(request())
            XCTFail("expected invalidKey")
        } catch {
            XCTAssertEqual(error as? CueStackGenerationError, .invalidKey)
        }
    }
}

extension AICueStackGeneratorTests {
    func testLikelyShowTabs() {
        let names = ["Specs & Deadlines", "Asset Tracker", "Main Keynote", "Show Flow Example"]
        let sheets = names.map { XLSXReader.Sheet(name: $0, rows: [["x"]]) }
        XCTAssertEqual(SourceDocumentReader.likelyShowSheets(sheets), ["Main Keynote"])
        XCTAssertEqual(SourceDocumentReader.likelyShowSheets([XLSXReader.Sheet(name: "Sheet1", rows: [])]), ["Sheet1"])
    }
}
