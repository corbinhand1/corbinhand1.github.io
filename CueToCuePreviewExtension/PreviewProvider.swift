//
//  PreviewProvider.swift
//  CueToCuePreviewExtension
//
//  Created by Corbin Hand on 8/31/24.
//

import Cocoa
import Quartz

class PreviewProvider: QLPreviewProvider {
    
    func providePreview(for request: QLFilePreviewRequest) async throws -> QLPreviewReply {
        let contentType = UTType.json
        
        let reply = QLPreviewReply(dataOfContentType: contentType, contentSize: CGSize(width: 600, height: 400)) { replyToUpdate in
            guard let data = try? Data(contentsOf: request.fileURL) else {
                return Data("Unable to load JSON data".utf8)
            }
            
            return data
        }
        
        return reply
    }
}
