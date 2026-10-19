//
//  JoystickViewRepresentable.swift
//  Melo-Controller
//
//  Created by Stossy11 on 28/2/2026.
//


import SwiftUI

struct JoystickViewRepresentable: UIViewRepresentable {
    var right: Bool
    @Binding var showBackground: Bool
    var controller: any Controller
    
    init(controller: any Controller, right: Bool, showBackground: Binding<Bool>) {
        self.right = right
        self._showBackground = showBackground
        self.controller = controller
    }
    
    func makeUIView(context: Context) -> JoystickView {
        let view = JoystickView()
        view.right = right
        view.background = showBackground
        
        view.onPositionChanged = { newPosition in
            DispatchQueue.main.async {
                controller.joystickMoved(position: newPosition, right: right)
            }
        }
        
        view.onActiveChanged = { active in
               DispatchQueue.main.async {
                   showBackground = active
               }
           }
        
        return view
    }
    
    func updateUIView(_ uiView: JoystickView, context: Context) {}
}
