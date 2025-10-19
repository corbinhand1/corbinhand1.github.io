//
//  NetworkUtilities.swift
//  Cue to Cue
//
//  Created by Corbin Hand on 8/31/24.
//

import Foundation
import Network
import Darwin

class NetworkUtilities {
    
    // MARK: - IP Address Utilities
    
    static func getLocalIPAddress() -> String? {
        var address: String?
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        
        guard getifaddrs(&ifaddr) == 0 else {
            return nil
        }
        defer { freeifaddrs(ifaddr) }
        
        var ptr = ifaddr
        while ptr != nil {
            defer { ptr = ptr?.pointee.ifa_next }
            
            guard let interface = ptr?.pointee else { continue }
            let addrFamily = interface.ifa_addr.pointee.sa_family
            
            if addrFamily == UInt8(AF_INET) {
                let name = String(cString: interface.ifa_name)
                if name == "en0" { // Wi-Fi interface
                    var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    let saLen = interface.ifa_addr.pointee.sa_len
                    getnameinfo(interface.ifa_addr, socklen_t(saLen),
                                &hostname, socklen_t(hostname.count),
                                nil, socklen_t(0), NI_NUMERICHOST)
                    address = String(cString: hostname)
                    break
                }
            }
        }
        return address
    }
    
    static func getDeviceName() -> String {
        return Host.current().localizedName ?? "Unknown Device"
    }
    
    // MARK: - Endpoint Parsing
    
    static func extractIPAddress(from endpoint: String) -> String {
        // Extract IP address from endpoint string like "192.168.1.100:12345"
        if let colonRange = endpoint.range(of: ":"),
           let ipAddress = endpoint[..<colonRange.lowerBound].components(separatedBy: " ").last {
            return String(ipAddress)
        }
        return "Unknown"
    }
    
    static func getNetworkInterface(for connection: NWConnection) -> String {
        // Try to determine network interface type from the connection
        let endpoint = String(describing: connection.endpoint)
        
        // This is a simplified approach - in a real implementation you'd use NWPathMonitor
        // For now, we'll return a placeholder that could be enhanced later
        if endpoint.contains("192.168") || endpoint.contains("10.") || endpoint.contains("172.") {
            return "Local Network"
        } else {
            return "External Network"
        }
    }
    
    // MARK: - User Agent Parsing
    
    static func extractBrowserType(from userAgent: String) -> String {
        let ua = userAgent.lowercased()
        
        // Check for Chrome (including Chromium-based browsers)
        if ua.contains("chrome") && !ua.contains("edg") {
            if ua.contains("chromium") {
                return "Chromium"
            } else if ua.contains("brave") {
                return "Brave"
            } else {
                return "Chrome"
            }
        }
        // Check for Edge (must come before Chrome check)
        else if ua.contains("edg") {
            return "Edge"
        }
        // Check for Firefox
        else if ua.contains("firefox") {
            return "Firefox"
        }
        // Check for Safari (must be after Chrome check)
        else if ua.contains("safari") && !ua.contains("chrome") {
            return "Safari"
        }
        // Check for Opera
        else if ua.contains("opera") || ua.contains("opr") {
            return "Opera"
        }
        // Check for Internet Explorer
        else if ua.contains("msie") || ua.contains("trident") {
            return "Internet Explorer"
        }
        // Check for other browsers
        else if ua.contains("vivaldi") {
            return "Vivaldi"
        } else if ua.contains("ucbrowser") {
            return "UC Browser"
        } else if ua.contains("samsungbrowser") {
            return "Samsung Browser"
        } else {
            return "Unknown Browser"
        }
    }
    
    static func extractDeviceType(from userAgent: String) -> String {
        let ua = userAgent.lowercased()
        
        // Check for mobile devices first
        if ua.contains("mobile") || ua.contains("android") || ua.contains("iphone") {
            if ua.contains("ipad") {
                return "iPad"
            } else if ua.contains("android") {
                return "Android Mobile"
            } else if ua.contains("iphone") {
                return "iPhone"
            } else {
                return "Mobile Device"
            }
        }
        // Check for tablets
        else if ua.contains("tablet") || ua.contains("ipad") {
            return "Tablet"
        }
        // Check for desktop operating systems
        else if ua.contains("windows") {
            return "Windows Desktop"
        } else if ua.contains("macintosh") || ua.contains("mac os") {
            return "macOS Desktop"
        } else if ua.contains("linux") {
            return "Linux Desktop"
        } else if ua.contains("x11") {
            return "Unix Desktop"
        }
        // Check for other devices
        else if ua.contains("smart tv") || ua.contains("tv") {
            return "Smart TV"
        } else if ua.contains("game console") || ua.contains("playstation") || ua.contains("xbox") {
            return "Game Console"
        } else {
            return "Unknown Device"
        }
    }
    
    static func extractDeviceName(from userAgent: String) -> String {
        // Try to extract a meaningful device name from User-Agent
        let ua = userAgent
        
        // For iOS devices, try to get a more descriptive name
        if ua.contains("iPhone") {
            return "iPhone"
        } else if ua.contains("iPad") {
            return "iPad"
        } else if ua.contains("iPod") {
            return "iPod"
        }
        // For Android devices
        else if ua.contains("Android") {
            // Try to extract device model if available
            if let range = ua.range(of: "Build/") {
                let beforeBuild = String(ua[..<range.lowerBound])
                if let lastSpace = beforeBuild.lastIndex(of: " ") {
                    let devicePart = String(beforeBuild[lastSpace...]).trimmingCharacters(in: .whitespaces)
                    if !devicePart.isEmpty && devicePart != "Mobile" && devicePart != "Tablet" {
                        return devicePart
                    }
                }
            }
            return "Android Device"
        }
        // For macOS connections, use the actual host device name
        else if ua.contains("Macintosh") || ua.contains("Mac OS") {
            return getDeviceName()
        } else if ua.contains("Windows") {
            return "Windows PC"
        } else if ua.contains("Linux") {
            return "Linux PC"
        }
        
        return "Unknown Device"
    }
    
    // MARK: - Connection Type Detection
    
    static func determineConnectionType(endpoint: String, state: String) -> String {
        // Determine if this is a main connection or resource connection
        if state.contains("ready") {
            return "Active"
        } else if state.contains("waiting") {
            return "Establishing"
        } else if state.contains("failed") || state.contains("cancelled") {
            return "Dead"
        } else {
            return "Unknown"
        }
    }
}
