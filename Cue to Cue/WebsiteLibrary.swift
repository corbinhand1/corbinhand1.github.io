//
//  WebsiteLibrary.swift
//  Cue to Cue
//
//  What gets published to the website, and the library of past show files.
//
//  Repository layout (all under cuetocue/):
//    cuetocue-data.json      the current show's cue stacks (what the viewer opens by default)
//    metadata.json           the current show's name and publish time
//    shows/index.json        the library: every published show, newest first
//    shows/<slug>.json       each show's cue stacks, same format as cuetocue-data.json
//

import Foundation
import Security

// MARK: - Library index

struct ShowLibraryEntry: Codable, Equatable, Identifiable {
    /// File-safe identifier, derived from the show file name. Never changes.
    var slug: String
    /// Name shown on the website. Starts as the file name; can be renamed.
    var name: String
    /// The show file this came from, e.g. "WT_LHR_26_Fall.cuestack".
    var filename: String
    /// ISO 8601 time of the last publish.
    var lastPublished: String
    var stackCount: Int
    var cueCount: Int

    var id: String { slug }

    var lastPublishedDate: Date? {
        ISO8601DateFormatter.withFractionalSeconds.date(from: lastPublished)
            ?? ISO8601DateFormatter().date(from: lastPublished)
    }
}

struct ShowLibraryIndex: Codable, Equatable {
    var version: Int = 1
    /// Slug of the show the viewer opens by default.
    var current: String?
    var updated: String = ""
    var shows: [ShowLibraryEntry] = []

    /// Add or update a show and make it current. Keeps a custom name.
    mutating func publish(_ entry: ShowLibraryEntry, at time: String) {
        var entry = entry
        if let index = shows.firstIndex(where: { $0.slug == entry.slug }) {
            entry.name = shows[index].name
            shows.remove(at: index)
        }
        shows.insert(entry, at: 0)
        current = entry.slug
        updated = time
    }

    mutating func remove(slug: String, at time: String) {
        shows.removeAll { $0.slug == slug }
        if current == slug { current = shows.first?.slug }
        updated = time
    }

    mutating func rename(slug: String, to name: String, at time: String) {
        guard let index = shows.firstIndex(where: { $0.slug == slug }) else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        shows[index].name = trimmed
        updated = time
    }

    func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(self)
    }

    static func decode(_ data: Data?) -> ShowLibraryIndex {
        guard let data, let index = try? JSONDecoder().decode(ShowLibraryIndex.self, from: data) else {
            return ShowLibraryIndex()
        }
        return index
    }
}

extension ISO8601DateFormatter {
    static let withFractionalSeconds: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
}

// MARK: - Payload

enum WebsitePayload {
    static let dataPath = "cuetocue/cuetocue-data.json"
    static let metadataPath = "cuetocue/metadata.json"
    static let libraryIndexPath = "cuetocue/shows/index.json"

    static func showPath(_ slug: String) -> String { "cuetocue/shows/\(slug).json" }

    /// "WT_LHR_26_Fall.cuestack" -> "wt-lhr-26-fall". Never empty.
    static func slug(forFilename filename: String) -> String {
        let stem = (filename as NSString).deletingPathExtension
        let lowered = stem.lowercased().folding(options: .diacriticInsensitive, locale: .current)
        var slug = ""
        var lastWasDash = false
        for scalar in lowered.unicodeScalars {
            if CharacterSet.alphanumerics.contains(scalar) && scalar.isASCII {
                slug.unicodeScalars.append(scalar)
                lastWasDash = false
            } else if !lastWasDash && !slug.isEmpty {
                slug.append("-")
                lastWasDash = true
            }
        }
        while slug.hasSuffix("-") { slug.removeLast() }
        return slug.isEmpty ? "untitled" : String(slug.prefix(80))
    }

    /// The viewer's data format (unchanged keys, minus the duplicate
    /// "allCues" copy that nothing read and that doubled the upload).
    static func cueData(cueStacks: [CueStack], selectedCueStackIndex: Int, highlightColors: [HighlightColorSetting]) -> [String: Any] {
        func columnsJSON(_ columns: [Column]) -> [[String: Any]] {
            columns.map { ["id": $0.id.uuidString, "name": $0.name, "width": $0.width] }
        }
        let stacks: [[String: Any]] = cueStacks.map { stack in
            let cues: [[String: Any]] = stack.cues.map { cue in
                var row: [String: Any] = [
                    "id": cue.id.uuidString,
                    "timerValue": cue.timerValue,
                    "isStruckThrough": cue.isStruckThrough,
                ]
                for (index, column) in stack.columns.enumerated() {
                    row[column.name] = index < cue.values.count ? cue.values[index] : ""
                }
                return row
            }
            return ["id": stack.id.uuidString, "name": stack.name, "columns": columnsJSON(stack.columns), "cues": cues]
        }
        let primary = cueStacks.indices.contains(selectedCueStackIndex) ? cueStacks[selectedCueStackIndex].columns : (cueStacks.first?.columns ?? [])
        return [
            "availableCueStacks": stacks,
            "columns": columnsJSON(primary),
            "highlightColors": highlightColors.map { ["keyword": $0.keyword, "color": $0.color.toHex()] },
            "selectedCueStackIndex": selectedCueStackIndex,
        ]
    }

    struct Bundle {
        let changes: [GitHubFileChange]
        let entry: ShowLibraryEntry
        let library: ShowLibraryIndex
    }

    /// Everything one publish writes: current data + metadata, this show's
    /// library copy, and the updated library index.
    static func bundle(cueStacks: [CueStack],
                       selectedCueStackIndex: Int,
                       highlightColors: [HighlightColorSetting],
                       filename: String,
                       existingLibrary: ShowLibraryIndex,
                       now: Date = Date()) throws -> Bundle {
        let time = ISO8601DateFormatter.withFractionalSeconds.string(from: now)
        let slug = slug(forFilename: filename)
        let data = try JSONSerialization.data(
            withJSONObject: cueData(cueStacks: cueStacks, selectedCueStackIndex: selectedCueStackIndex, highlightColors: highlightColors),
            options: [.sortedKeys])
        let metadata: [String: Any] = [
            "filename": filename,
            "lastUpdated": time,
            "selectedCueStackIndex": selectedCueStackIndex,
            "totalCueStacks": cueStacks.count,
            "syncTimestamp": now.timeIntervalSince1970,
            "showSlug": slug,
        ]
        let metadataData = try JSONSerialization.data(withJSONObject: metadata, options: [.prettyPrinted, .sortedKeys])

        let entry = ShowLibraryEntry(
            slug: slug,
            name: (filename as NSString).deletingPathExtension,
            filename: filename,
            lastPublished: time,
            stackCount: cueStacks.count,
            cueCount: cueStacks.reduce(0) { $0 + $1.cues.count })
        var library = existingLibrary
        library.publish(entry, at: time)

        return Bundle(
            changes: [
                .write(path: dataPath, data: data),
                .write(path: metadataPath, data: metadataData),
                .write(path: showPath(slug), data: data),
                .write(path: libraryIndexPath, data: try library.encoded()),
            ],
            entry: library.shows.first!,
            library: library)
    }
}

// MARK: - Token storage

protocol GitHubTokenStore: AnyObject {
    func readToken() -> String?
    func writeToken(_ token: String?) throws
}

/// Stores the GitHub token in the login Keychain (earlier builds kept it in
/// plain text in the app's preferences file).
final class KeychainGitHubTokenStore: GitHubTokenStore {
    private let service: String
    private let account = "github-token"

    init(service: String = "Nebula-Creative.Cue-to-Cue.website") {
        self.service = service
    }

    func readToken() -> String? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              let token = String(data: data, encoding: .utf8), !token.isEmpty else { return nil }
        return token
    }

    func writeToken(_ token: String?) throws {
        SecItemDelete(baseQuery as CFDictionary)
        guard let token, !token.isEmpty else { return }
        var item = baseQuery
        item[kSecValueData as String] = Data(token.utf8)
        item[kSecAttrLabel as String] = "Cue to Cue website publishing (GitHub)"
        let status = SecItemAdd(item as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status),
                          userInfo: [NSLocalizedDescriptionKey: "Couldn't save the token to the Keychain (error \(status))."])
        }
    }

    private var baseQuery: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }
}

final class InMemoryGitHubTokenStore: GitHubTokenStore {
    private var token: String?
    init(token: String? = nil) { self.token = token }
    func readToken() -> String? { token }
    func writeToken(_ token: String?) throws { self.token = token }
}
