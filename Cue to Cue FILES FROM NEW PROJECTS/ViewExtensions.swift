//
//  ViewExtensions.swift
//  Cue to Cue
//
//  Created by Corbin Hand on 8/12/24.
//

import Foundation
import SwiftUI

extension View {
    @ViewBuilder func `if`<Content: View>(_ condition: Bool, transform: (Self) -> Content) -> some View {
        if condition {
            transform(self)
        } else {
            self
        }
    }
}
