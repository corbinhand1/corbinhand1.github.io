//
//  OfflineFileServer.swift
//  Cue to Cue
//
//  Created by Corbin Hand on 8/31/24.
//

import Foundation

class OfflineFileServer {
    
    // MARK: - Offline File Serving
    
    func serveOfflineHTML() -> HTTPResponse {
        let offlineHTMLPath = Bundle.main.path(forResource: "offline", ofType: "html")
        if let path = offlineHTMLPath, let data = try? Data(contentsOf: URL(fileURLWithPath: path)) {
            return HTTPResponse(
                status: .ok,
                headers: ["Content-Type": "text/html; charset=utf-8"],
                body: data
            )
        }
        
        // Enhanced fallback offline page with better functionality
        let fallbackHTML = """
        <!DOCTYPE html>
        <html lang="en">
        <head>
            <meta charset="UTF-8">
            <meta name="viewport" content="width=device-width, initial-scale=1.0">
            <title>Cue to Cue - Offline</title>
            <style>
                body { font-family: -apple-system, sans-serif; text-align: center; padding: 50px; background: #f5f5f5; }
                .container { max-width: 500px; margin: 0 auto; background: white; padding: 40px; border-radius: 10px; box-shadow: 0 2px 10px rgba(0,0,0,0.1); }
                h1 { color: #333; margin-bottom: 20px; }
                p { color: #666; line-height: 1.6; margin-bottom: 20px; }
                .button { background: #007AFF; color: white; border: none; padding: 12px 24px; border-radius: 6px; cursor: pointer; font-size: 16px; }
                .button:hover { background: #0056CC; }
            </style>
        </head>
        <body>
            <div class="container">
                <h1>📱 You're Offline</h1>
                <p>Don't worry! You can still view your cue sheets and settings that were previously loaded.</p>
                <p>Some features may be limited while offline.</p>
                <button class="button" onclick="checkConnectionAndReconnect()">🔄 Try to Reconnect</button>
                <script>
                    function checkConnectionAndReconnect() {
                        const button = event.target;
                        const originalText = button.textContent;
                        
                        button.textContent = '🔄 Checking...';
                        button.disabled = true;
                        
                        // Check if we're online first
                        if (!navigator.onLine) {
                            button.textContent = '❌ No Internet';
                            setTimeout(() => {
                                button.textContent = originalText;
                                button.disabled = false;
                            }, 2000);
                            return;
                        }
                        
                        // Test connection
                        fetch('/health', { method: 'HEAD' })
                            .then(() => {
                                button.textContent = '✅ Connected!';
                                setTimeout(() => {
                                    window.location.reload();
                                }, 1000);
                            })
                            .catch(() => {
                                button.textContent = '❌ Failed';
                                setTimeout(() => {
                                    button.textContent = originalText;
                                    button.disabled = false;
                                }, 2000);
                            });
                    }
                </script>
            </div>
        </body>
        </html>
        """
        
        return HTTPResponse(
            status: .ok,
            headers: ["Content-Type": "text/html; charset=utf-8"],
            body: fallbackHTML.data(using: .utf8) ?? Data()
        )
    }
    
    func serveOfflineServiceWorker() -> HTTPResponse {
        let serviceWorkerPath = Bundle.main.path(forResource: "offline-service-worker", ofType: "js")
        if let path = serviceWorkerPath, let data = try? Data(contentsOf: URL(fileURLWithPath: path)) {
            return HTTPResponse(
                status: .ok,
                headers: ["Content-Type": "application/javascript; charset=utf-8"],
                body: data
            )
        }
        return HTTPResponse(
            status: .notFound,
            headers: ["Content-Type": "text/plain"],
            body: "Service worker not found".data(using: .utf8) ?? Data()
        )
    }
    
    func serveOfflineDataManager() -> HTTPResponse {
        let dataManagerPath = Bundle.main.path(forResource: "offline-data-manager", ofType: "js")
        if let path = dataManagerPath, let data = try? Data(contentsOf: URL(fileURLWithPath: path)) {
            return HTTPResponse(
                status: .ok,
                headers: ["Content-Type": "application/javascript; charset=utf-8"],
                body: data
            )
        }
        return HTTPResponse(
            status: .notFound,
            headers: ["Content-Type": "text/plain"],
            body: "Data manager not found".data(using: .utf8) ?? Data()
        )
    }
    
    func serveOfflineStateManager() -> HTTPResponse {
        let stateManagerPath = Bundle.main.path(forResource: "offline-state-manager", ofType: "js")
        if let path = stateManagerPath, let data = try? Data(contentsOf: URL(fileURLWithPath: path)) {
            return HTTPResponse(
                status: .ok,
                headers: ["Content-Type": "application/javascript; charset=utf-8"],
                body: data
            )
        }
        return HTTPResponse(
            status: .notFound,
            headers: ["Content-Type": "text/plain"],
            body: "State manager not found".data(using: .utf8) ?? Data()
        )
    }
    
    func serveOfflineStyles() -> HTTPResponse {
        let stylesPath = Bundle.main.path(forResource: "offline-styles", ofType: "css")
        if let path = stylesPath, let data = try? Data(contentsOf: URL(fileURLWithPath: path)) {
            return HTTPResponse(
                status: .ok,
                headers: ["Content-Type": "text/css; charset=utf-8"],
                body: data
            )
        }
        return HTTPResponse(
            status: .notFound,
            headers: ["Content-Type": "text/plain"],
            body: "Styles not found".data(using: .utf8) ?? Data()
        )
    }
    
    func serveOfflineIntegration() -> HTTPResponse {
        let integrationPath = Bundle.main.path(forResource: "offline-integration", ofType: "js")
        if let path = integrationPath, let data = try? Data(contentsOf: URL(fileURLWithPath: path)) {
            return HTTPResponse(
                status: .ok,
                headers: ["Content-Type": "application/javascript; charset=utf-8"],
                body: data
            )
        }
        return HTTPResponse(
            status: .notFound,
            headers: ["Content-Type": "text/plain"],
            body: "Integration script not found".data(using: .utf8) ?? Data()
        )
    }
    
    func serveManifest() -> HTTPResponse {
        let manifestPath = Bundle.main.path(forResource: "manifest", ofType: "json")
        if let path = manifestPath, let data = try? Data(contentsOf: URL(fileURLWithPath: path)) {
            return HTTPResponse(
                status: .ok,
                headers: ["Content-Type": "application/json; charset=utf-8"],
                body: data
            )
        }
        return HTTPResponse(
            status: .notFound,
            headers: ["Content-Type": "text/plain"],
            body: "Manifest not found".data(using: .utf8) ?? Data()
        )
    }
    
    func serveTestOfflineHTML() -> HTTPResponse {
        let testOfflinePath = Bundle.main.path(forResource: "test-offline", ofType: "html")
        if let path = testOfflinePath, let data = try? Data(contentsOf: URL(fileURLWithPath: path)) {
            return HTTPResponse(
                status: .ok,
                headers: ["Content-Type": "text/html; charset=utf-8"],
                body: data
            )
        }
        return HTTPResponse(
            status: .notFound,
            headers: ["Content-Type": "text/plain"],
            body: "Test offline page not found".data(using: .utf8) ?? Data()
        )
    }
    
    func serveDigital7MonoFont() -> HTTPResponse {
        // Try multiple ways to find the font file in the bundle
        var fontData: Data?
        
        // Try the exact resource name first
        if let fontPath = Bundle.main.path(forResource: "digital-7 (mono)", ofType: "ttf") {
            fontData = try? Data(contentsOf: URL(fileURLWithPath: fontPath))
        }
        
        // If not found, try without spaces
        if fontData == nil, let fontPath = Bundle.main.path(forResource: "digital-7-mono", ofType: "ttf") {
            fontData = try? Data(contentsOf: URL(fileURLWithPath: fontPath))
        }
        
        // If still not found, try the dataset path
        if fontData == nil {
            let datasetPath = Bundle.main.path(forResource: "digital-7 (mono)", ofType: "ttf", inDirectory: "Assets.xcassets/digital-7 (mono).dataset")
            if let path = datasetPath {
                fontData = try? Data(contentsOf: URL(fileURLWithPath: path))
            }
        }
        
        if let data = fontData {
            return HTTPResponse(
                status: .ok,
                headers: [
                    "Content-Type": "font/ttf",
                    "Cache-Control": "public, max-age=31536000", // Cache for 1 year
                    "Access-Control-Allow-Origin": "*"
                ],
                body: data
            )
        }
        
        return HTTPResponse(
            status: .notFound,
            headers: ["Content-Type": "text/plain"],
            body: "Font not found".data(using: .utf8) ?? Data()
        )
    }
    
    func serveOfflineStatus(cueStacksCount: Int, activeConnections: Int, maxConnections: Int) -> HTTPResponse {
        let status = [
            "timestamp": Date().timeIntervalSince1970,
            "server": "running",
            "offline_support": "enabled",
            "cached_data": cueStacksCount > 0,
            "cue_stacks_count": cueStacksCount,
            "active_connections": activeConnections,
            "max_connections": maxConnections
        ] as [String: Any]
        
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: status, options: [])
            return HTTPResponse(
                status: .ok,
                headers: ["Content-Type": "application/json; charset=utf-8"],
                body: jsonData
            )
        } catch {
            return HTTPResponse(
                status: .internalServerError,
                headers: ["Content-Type": "text/plain"],
                body: "Failed to generate status".data(using: .utf8) ?? Data()
            )
        }
    }
    
    func serveHealthCheck() -> HTTPResponse {
        return HTTPResponse(
            status: .ok,
            headers: ["Content-Type": "text/plain"],
            body: "OK".data(using: .utf8) ?? Data()
        )
    }
}
