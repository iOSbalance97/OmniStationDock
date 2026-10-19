//
//  JoystickDPadPoint.swift
//  Melo-Controller
//
//  Created by Stossy11 on 26/1/2026.
//

import SwiftUI
import Foundation

class JoystickDPadPoint: ObservableObject {
    static var shared = JoystickDPadPoint()
    var controller: (any Controller)? = nil
    @Published var joystickDpadPoint: (x: Double, y: Double) = (0, 0)
    @Published var currentlyPressed: Set<VirtualControllerButton> = []
    @Published var isJoystickActive: Bool = false
    
    
    func pressed(_ button: VirtualControllerButton) {
        guard button.isDPad else { return }
        currentlyPressed.insert(button)
        print(button)
        print(currentlyPressed)
        recomputeDPad()
    }

    func released(_ button: VirtualControllerButton) {
        guard button.isDPad else { return }
        currentlyPressed.remove(button)
        print(button)
        print(currentlyPressed)
        recomputeDPad()
    }

    private func recomputeDPad() {
        // Y axis
        if currentlyPressed.contains(.dPadUp) {
            joystickDpadPoint.y = -1
        } else if currentlyPressed.contains(.dPadDown) {
            joystickDpadPoint.y = 1
        } else {
            joystickDpadPoint.y = 0
        }

        // X axis
        if currentlyPressed.contains(.dPadLeft) {
            joystickDpadPoint.x = -1
        } else if currentlyPressed.contains(.dPadRight) {
            joystickDpadPoint.x = 1
        } else {
            joystickDpadPoint.x = 0
        }
        
        print(joystickDpadPoint)
        
        controller?.joystickMoved(position: CGPoint(x: joystickDpadPoint.x, y: joystickDpadPoint.y), right: false)
    }
}
