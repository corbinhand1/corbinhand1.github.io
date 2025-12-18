//
//  TextFieldWithFocus.swift
//  Cue to Cue
//
//  Created by Corbin Hand on 8/5/24.
//

import Foundation
import SwiftUI

struct TextFieldWithFocus: UIViewRepresentable {
    class Coordinator: NSObject, UITextFieldDelegate {
        var parent: TextFieldWithFocus

        init(parent: TextFieldWithFocus) {
            self.parent = parent
        }

        func textFieldDidBeginEditing(_ textField: UITextField) {
            DispatchQueue.main.async {
                textField.selectAll(nil)
            }
        }
    }

    @Binding var text: String
    var isFirstResponder: Bool

    func makeUIView(context: Context) -> UITextField {
        let textField = UITextField()
        textField.delegate = context.coordinator
        textField.text = text
        return textField
    }

    func updateUIView(_ uiView: UITextField, context: Context) {
        uiView.text = text
        if isFirstResponder {
            DispatchQueue.main.async {
                uiView.becomeFirstResponder()
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }
}
