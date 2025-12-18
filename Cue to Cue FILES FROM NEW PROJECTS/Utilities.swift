//
//  Utilities.swift
//  Cue to Cue
//
//  Created by Corbin Hand on 8/11/24.
//

import Foundation

func parseCSV(data: Data) -> [Cue] {
    let content = String(data: data, encoding: .utf8) ?? ""
    
    // Use NSString's line separation to handle different line break styles
    let lines = (content as NSString).components(separatedBy: .newlines)
    
    // Filter out empty lines and parse each non-empty line
    return lines.filter { !$0.isEmpty }.map { line -> Cue in
        // Use comma as separator, but handle cases where commas might be within quoted fields
        var values: [String] = []
        var currentValue = ""
        var insideQuotes = false
        
        for character in line {
            switch character {
            case "\"":
                insideQuotes.toggle()
            case ",":
                if insideQuotes {
                    currentValue.append(character)
                } else {
                    values.append(currentValue.trimmingCharacters(in: .whitespaces))
                    currentValue = ""
                }
            default:
                currentValue.append(character)
            }
        }
        
        // Add the last value
        values.append(currentValue.trimmingCharacters(in: .whitespaces))
        
        return Cue(values: values)
    }
}
