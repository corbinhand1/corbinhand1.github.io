//
//  ConsoleLogger.swift
//  Cue to Cue
//
//  Global logging functions that capture to debug window
//

import Foundation

// MARK: - Print Interceptor
// This captures print() statements by redirecting stdout/stderr

class PrintInterceptor {
    static let shared = PrintInterceptor()
    
    private var originalStdout: Int32 = -1
    private var originalStderr: Int32 = -1
    private var pipe: Pipe?
    private var stderrPipe: Pipe?
    private var isIntercepting = false
    
    func startIntercepting() {
        guard !isIntercepting else { return }
        isIntercepting = true
        
        // Save original file descriptors
        originalStdout = dup(STDOUT_FILENO)
        originalStderr = dup(STDERR_FILENO)
        
        // Create pipes
        pipe = Pipe()
        stderrPipe = Pipe()
        
        guard let pipe = pipe, let stderrPipe = stderrPipe else { return }
        
        // Redirect stdout
        dup2(pipe.fileHandleForWriting.fileDescriptor, STDOUT_FILENO)
        close(pipe.fileHandleForWriting.fileDescriptor)
        
        // Redirect stderr
        dup2(stderrPipe.fileHandleForWriting.fileDescriptor, STDERR_FILENO)
        close(stderrPipe.fileHandleForWriting.fileDescriptor)
        
        // Set up reading from pipes
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if !data.isEmpty {
                if let string = String(data: data, encoding: .utf8) {
                    // Write to original stdout for Xcode console
                    if let self = self, self.originalStdout >= 0 {
                        let originalHandle = FileHandle(fileDescriptor: self.originalStdout, closeOnDealloc: false)
                        originalHandle.write(data)
                    }
                    
                    // Also capture to LogManager
                    let lines = string.components(separatedBy: .newlines)
                    for line in lines {
                        let trimmed = line.trimmingCharacters(in: .whitespaces)
                        if !trimmed.isEmpty {
                            // Pre-filter spam before sending to LogManager
                            if shouldFilterSpam(trimmed) {
                                continue
                            }
                            
                            DispatchQueue.main.async {
                                let level: LogLevel = determineLogLevel(from: trimmed)
                                LogManager.shared.addLog(trimmed, level: level)
                            }
                        }
                    }
                }
            }
        }
        
        stderrPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if !data.isEmpty {
                if let string = String(data: data, encoding: .utf8) {
                    // Write to original stderr for Xcode console
                    if let self = self, self.originalStderr >= 0 {
                        let originalHandle = FileHandle(fileDescriptor: self.originalStderr, closeOnDealloc: false)
                        originalHandle.write(data)
                    }
                    
                    // Also capture to LogManager as error
                    let lines = string.components(separatedBy: .newlines)
                    for line in lines {
                        let trimmed = line.trimmingCharacters(in: .whitespaces)
                        if !trimmed.isEmpty {
                            // Pre-filter spam before sending to LogManager
                            if shouldFilterSpam(trimmed) {
                                continue
                            }
                            
                            DispatchQueue.main.async {
                                // Determine log level based on content
                                let level: LogLevel = determineLogLevel(from: trimmed)
                                LogManager.shared.addLog(trimmed, level: level)
                            }
                        }
                    }
                }
            }
        }
    }
    
    func stopIntercepting() {
        guard isIntercepting else { return }
        isIntercepting = false
        
        // Restore original file descriptors
        if originalStdout >= 0 {
            dup2(originalStdout, STDOUT_FILENO)
            close(originalStdout)
            originalStdout = -1
        }
        
        if originalStderr >= 0 {
            dup2(originalStderr, STDERR_FILENO)
            close(originalStderr)
            originalStderr = -1
        }
        
        pipe?.fileHandleForReading.readabilityHandler = nil
        stderrPipe?.fileHandleForReading.readabilityHandler = nil
        pipe = nil
        stderrPipe = nil
    }
}

// MARK: - Helper Functions

private func shouldFilterSpam(_ message: String) -> Bool {
    let lowercased = message.lowercased()
    
    // Only filter truly spammy system messages, not useful debug info
    // Let LogManager handle the filtering - this is just a pre-filter for obvious spam
    if lowercased.contains("malloc: nano zone") ||
       lowercased.contains("nw_path_evaluator") ||
       lowercased.contains("attributegraph: cycle") {
        return true
    }
    
    return false
}

private func determineLogLevel(from message: String) -> LogLevel {
    let lowercased = message.lowercased()
    
    // Errors
    if lowercased.contains("error") || lowercased.contains("failed") || 
       lowercased.contains("❌") || lowercased.contains("exception") {
        return .error
    }
    
    // Warnings
    if lowercased.contains("warning") || lowercased.contains("⚠️") ||
       lowercased.contains("deprecated") {
        return .warning
    }
    
    // Debug messages (emoji indicators)
    if lowercased.contains("🔍") || lowercased.contains("🔄") ||
       lowercased.contains("📡") || lowercased.contains("📋") ||
       lowercased.contains("🌐") || lowercased.contains("🕐") {
        // Only show important debug messages, filter verbose ones
        if lowercased.contains("🔄 countdown reset") {
            // Filter out frequent countdown resets unless significant
            return .debug
        }
        return .debug
    }
    
    // Success/Info messages
    if lowercased.contains("✅") || lowercased.contains("🚀") ||
       lowercased.contains("📊") || lowercased.contains("🎯") {
        return .info
    }
    
    // Default to info
    return .info
}

// MARK: - Global Logging Functions

// Global logging functions that automatically capture to LogManager
func debugLog(_ message: String, level: LogLevel = .info) {
    // Print to console (for Xcode)
    print(message)
    
    // Also capture to LogManager for debug window
    LogManager.shared.addLog(message, level: level)
}

// Convenience functions
func logInfo(_ message: String) {
    debugLog(message, level: .info)
}

func logWarning(_ message: String) {
    debugLog(message, level: .warning)
}

func logError(_ message: String) {
    debugLog(message, level: .error)
}

func logDebug(_ message: String) {
    debugLog(message, level: .debug)
}

