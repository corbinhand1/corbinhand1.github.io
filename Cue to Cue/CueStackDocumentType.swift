//
//  CueStackDocumentType.swift
//  Cue to Cue
//

import Foundation
import UniformTypeIdentifiers

extension UTType {
    /// Primary on-disk format for cue stack documents. Double-clicking a
    /// `.cuestack` file opens Cue to Cue (see Info.plist exported UTI).
    static let cueStackDocument = UTType(exportedAs: "com.nebula-creative.cue-to-cue.cuestack", conformingTo: .data)

    /// Types accepted by Open / Save panels and drag-and-drop.
    static let cueStackReadableTypes: [UTType] = [.cueStackDocument, .json]
}

enum CueStackDocumentType {
    static let contentTypeIdentifier = UTType.cueStackDocument.identifier
    private static let contentTypeRepairVersion = 2
    private static let contentTypeRepairVersionKey = "CueStackContentTypeRepairVersion"

    /// Returns true when Spotlight/Launch Services already treat the file as
    /// our exported `.cuestack` document type.
    static func hasRegisteredContentType(at url: URL) -> Bool {
        guard url.pathExtension.lowercased() == "cuestack" else { return true }
        guard let identifier = try? url.resourceValues(forKeys: [.contentTypeKey]).contentType?.identifier else {
            return false
        }
        return identifier == contentTypeIdentifier
    }

    /// Files renamed to `.cuestack` before the app registered its exported
    /// type can keep a dynamic UTI forever. Quick Look only invokes our
    /// preview extension for the exact exported identifier, so repair the
    /// on-disk type metadata when we detect that mismatch.
    static func repairContentTypeIfNeeded(at url: URL) {
        guard url.pathExtension.lowercased() == "cuestack" else { return }

        let repairedVersion = UserDefaults.standard.integer(forKey: contentTypeRepairVersionKey)
        let needsRepair = !hasRegisteredContentType(at: url) || repairedVersion < contentTypeRepairVersion
        guard needsRepair else {
            reimportMetadata(for: url)
            return
        }

        guard let data = try? Data(contentsOf: url) else { return }
        do {
            try data.write(to: url, options: [.atomic])
            reimportMetadata(for: url)
            UserDefaults.standard.set(contentTypeRepairVersion, forKey: contentTypeRepairVersionKey)
        } catch {
            NSLog("CueStackDocumentType: failed to repair content type for \(url.path): \(error.localizedDescription)")
        }
    }

    private static func reimportMetadata(for url: URL) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/mdimport")
        process.arguments = [url.path]
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            NSLog("CueStackDocumentType: mdimport failed for \(url.path): \(error.localizedDescription)")
        }
    }

    /// Returns true for user cue-stack files we should open from Finder.
    static func shouldOpen(at url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        guard ext == "cuestack" || ext == "json" else { return false }

        let name = url.lastPathComponent.lowercased()
        if name.hasSuffix(".backup.json") || name.hasSuffix(".backup.cuestack") { return false }
        if name == "manifest.json" { return false }
        if url.pathComponents.contains(where: { $0.hasSuffix(".backups") }) { return false }

        return true
    }

    static func defaultSaveFilename(stem: String) -> String {
        let trimmed = stem.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed == "Untitled" {
            return "Untitled.cuestack"
        }
        if trimmed.lowercased().hasSuffix(".cuestack") || trimmed.lowercased().hasSuffix(".json") {
            return trimmed
        }
        return "\(trimmed).cuestack"
    }
}
