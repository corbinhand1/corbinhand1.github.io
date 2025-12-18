//
//  KeynoteConverter.swift
//  Cue to Cue
//
//  Created by Corbin Hand on 9/1/24.
//

import Foundation
import AppKit

class KeynoteConverter {
    static func convertToPDF(keynoteURL: URL, completion: @escaping (Result<URL, Error>) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let destinationURL = keynoteURL.deletingPathExtension().appendingPathExtension("pdf")
            
            print("Attempting to convert Keynote file: \(keynoteURL.path)")
            print("Destination PDF file: \(destinationURL.path)")
            
            ensureKeynoteIsRunningAndOpenFile(keynoteURL) { success in
                if success {
                    print("Keynote is confirmed to be running and file is opened")
                    self.exportToPDF(destinationURL: destinationURL) { result in
                        DispatchQueue.main.async {
                            completion(result)
                        }
                    }
                } else {
                    print("Failed to ensure Keynote is running and file is opened")
                    DispatchQueue.main.async {
                        completion(.failure(NSError(domain: "KeynoteConverterError", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to ensure Keynote is running and file is opened"])))
                    }
                }
            }
        }
    }
    
    private static func ensureKeynoteIsRunningAndOpenFile(_ url: URL, retryCount: Int = 3, completion: @escaping (Bool) -> Void) {
        let script = """
        tell application "Keynote"
            set keynoteVersion to version
            try
                open POSIX file "\(url.path)"
                return true
            on error errMsg
                return {false, errMsg}
            end try
        end tell
        """
        
        executeAppleScript(script) { success, output, error in
            if success, let outputString = output {
                if outputString.lowercased().contains("true") {
                    print("Keynote file opened successfully")
                    completion(true)
                } else {
                    print("Failed to open Keynote file. Output: \(outputString)")
                    if retryCount > 0 {
                        print("Retrying... (\(retryCount) attempts left)")
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                            self.ensureKeynoteIsRunningAndOpenFile(url, retryCount: retryCount - 1, completion: completion)
                        }
                    } else {
                        completion(false)
                    }
                }
            } else {
                print("Error executing AppleScript: \(error ?? "Unknown error")")
                if retryCount > 0 {
                    print("Retrying... (\(retryCount) attempts left)")
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                        self.ensureKeynoteIsRunningAndOpenFile(url, retryCount: retryCount - 1, completion: completion)
                    }
                } else {
                    completion(false)
                }
            }
        }
    }
    
    private static func exportToPDF(destinationURL: URL, completion: @escaping (Result<URL, Error>) -> Void) {
        let script = """
        tell application "Keynote"
            tell front document
                export to POSIX file "\(destinationURL.path)" as PDF
            end tell
            close front document saving no
        end tell
        """
        
        executeAppleScript(script) { success, output, error in
            if success && FileManager.default.fileExists(atPath: destinationURL.path) {
                print("PDF created successfully at: \(destinationURL.path)")
                completion(.success(destinationURL))
            } else {
                print("Failed to create PDF. Error: \(error ?? "Unknown error")")
                completion(.failure(NSError(domain: "KeynoteConverterError", code: -3, userInfo: [NSLocalizedDescriptionKey: "Failed to create PDF: \(error ?? "Unknown error")"])))
            }
        }
    }
    
    private static func executeAppleScript(_ script: String, completion: @escaping (Bool, String?, String?) -> Void) {
        let task = Process()
        task.launchPath = "/usr/bin/osascript"
        task.arguments = ["-e", script]
        
        let outputPipe = Pipe()
        task.standardOutput = outputPipe
        let errorPipe = Pipe()
        task.standardError = errorPipe
        
        do {
            try task.run()
            task.waitUntilExit()
            
            let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: outputData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            let error = String(data: errorData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            
            print("AppleScript Output: \(output ?? "No output")")
            if let error = error, !error.isEmpty {
                print("AppleScript Error: \(error)")
                completion(false, output, error)
            } else {
                completion(true, output, nil)
            }
        } catch {
            print("Failed to execute AppleScript: \(error.localizedDescription)")
            completion(false, nil, error.localizedDescription)
        }
    }
}
