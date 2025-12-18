//
//  FileHelper.swift
//  Cue to Cue
//
//  Created by Corbin Hand on 5/29/24.
//

import Foundation
import UniformTypeIdentifiers
import AppKit

class FileHelper {
    static func saveFile(data: Data, allowedContentTypes: [UTType], defaultFilename: String, completion: @escaping (Result<URL, Error>) -> Void) {
        DispatchQueue.main.async {
            let panel = NSSavePanel()
            panel.allowedContentTypes = allowedContentTypes
            panel.nameFieldStringValue = defaultFilename
            panel.canCreateDirectories = true
            panel.isExtensionHidden = false
            panel.allowsOtherFileTypes = false

            panel.begin { response in
                if response == .OK, let url = panel.url {
                    do {
                        try data.write(to: url)
                        completion(.success(url))
                    } catch {
                        completion(.failure(error))
                    }
                } else {
                    completion(.failure(NSError(domain: "SaveCancelled", code: -1, userInfo: nil)))
                }
            }
        }
    }

    static func openFile(allowedContentTypes: [UTType], completion: @escaping (Result<URL, Error>) -> Void) {
        DispatchQueue.main.async {
            let panel = NSOpenPanel()
            panel.allowedContentTypes = allowedContentTypes
            panel.allowsMultipleSelection = false
            panel.canChooseDirectories = false
            panel.canCreateDirectories = false
            panel.canChooseFiles = true

            panel.begin { response in
                if response == .OK, let url = panel.url {
                    completion(.success(url))
                } else {
                    completion(.failure(NSError(domain: "OpenCancelled", code: -1, userInfo: nil)))
                }
            }
        }
    }
}
