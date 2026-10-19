//
//  Joystick.swift
//  Melo-Controller
//
//  Created by Stossy11 on 21/03/2025.
//


import UIKit
import SwiftUI

// i am never doing uikit again
final class JoystickView: UIView {
    var right: Bool = true
    var background: Bool = false
    var sensitivity: CGFloat = 1.2
        
    var deadZone: CGFloat = 0.08
    
    private var dragDiameter: CGFloat {
        let base: CGFloat = 160
        if UIDevice.current.systemName.contains("iPadOS") {
            return base * 1.2
        }
        return base
    }
    
    private var joystickSize: CGFloat { dragDiameter * 0.2 }
    private var boundarySize: CGFloat { dragDiameter }
    
    var onPositionChanged: ((CGPoint) -> Void)?
    var onActiveChanged: ((Bool) -> Void)?
    
    private let boundaryView          = UIView()
    private let backgroundView        = UIView()
    private let joystickView          = UIView()
    private let joystickBackgroundView = UIView()
    
    private var offset: CGPoint = .zero
    
    private let edgeImpact   = UIImpactFeedbackGenerator(style: .light)
    private var didHitEdge   = false
    
    private var springAnimator: UIViewPropertyAnimator?
    
    private var extendedRadius: CGFloat {
        let maxRadius = (boundarySize - joystickSize) / 2
        return maxRadius + (joystickSize / 2)
    }
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }
    
    private func setup() {
        clipsToBounds = false
        
        addSubview(boundaryView)
        addSubview(backgroundView)
        addSubview(joystickBackgroundView)
        addSubview(joystickView)
        
        backgroundView.backgroundColor = UIColor.gray.withAlphaComponent(0.4)
        backgroundView.alpha = background ? 1 : 0
        
        joystickBackgroundView.backgroundColor = UIColor.gray.withAlphaComponent(0.3)
        joystickView.backgroundColor = UIColor.white.withAlphaComponent(0.5)
        
        joystickView.layer.shadowColor = UIColor.black.cgColor
        joystickView.layer.shadowOpacity = 0.18
        joystickView.layer.shadowOffset  = CGSize(width: 0, height: 2)
        joystickView.layer.shadowRadius  = 4

        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan))
        addGestureRecognizer(pan)

        edgeImpact.prepare()
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        
        let size = bounds.width
        boundaryView.frame              = CGRect(origin: .zero, size: frame.size)
        boundaryView.layer.cornerRadius = size / 2
        
        backgroundView.frame              = boundaryView.frame
        backgroundView.layer.cornerRadius = size / 2
        
        joystickBackgroundView.bounds = CGRect(
            x: 0, y: 0,
            width: joystickSize * 1.25,
            height: joystickSize * 1.25
        )
        joystickBackgroundView.layer.cornerRadius = joystickBackgroundView.bounds.width / 2
        
        joystickView.bounds = CGRect(
            x: 0, y: 0,
            width: joystickSize,
            height: joystickSize
        )
        joystickView.layer.cornerRadius = joystickSize / 2
        
        placeAtCenter()
    }
    
    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        let location = gesture.location(in: self)
        
        let rawOffset = CGPoint(
            x: location.x - bounds.midX,
            y: location.y - bounds.midY
        )
        
        switch gesture.state {
        case .began:
            springAnimator?.stopAnimation(true)
            springAnimator = nil
            
            didHitEdge = false
            edgeImpact.prepare()
            animateBackground(show: true)
            
            processOffset(rawOffset)
            updateJoystickPosition()
            onPositionChanged?(normalizedPosition())
            
            UIView.animate(withDuration: 0.12, delay: 0,
                           usingSpringWithDamping: 0.6, initialSpringVelocity: 1) {
                self.joystickView.transform = CGAffineTransform(scaleX: 1.12, y: 1.12)
                self.joystickBackgroundView.transform = CGAffineTransform(scaleX: 1.08, y: 1.08)
            }
            onActiveChanged?(true)
            
        case .changed:
            processOffset(rawOffset)
            updateJoystickPosition()
            onPositionChanged?(normalizedPosition())
            
        case .ended, .cancelled:
            UIView.animate(withDuration: 0.15) {
                self.joystickView.transform          = .identity
                self.joystickBackgroundView.transform = .identity
            }
            
            animateBackground(show: false)
            onPositionChanged?(.zero)
            springReturnToCenter()
            onActiveChanged?(false)
            
        default:
            break
        }
    }
    
    private func normalizedPosition() -> CGPoint {
        let rx = offset.x / extendedRadius
        let ry = offset.y / extendedRadius
        let magnitude = hypot(rx, ry)
        
        guard magnitude > deadZone else { return .zero }
        
        let scale = (magnitude - deadZone) / (1 - deadZone) / magnitude

        return CGPoint(
            x: max(-1, min(1, rx * scale * sensitivity)),
            y: max(-1, min(1, ry * scale * sensitivity))
        )
    }
    
    private func processOffset(_ rawOffset: CGPoint) {
        let distance = hypot(rawOffset.x, rawOffset.y)
        let atEdge   = distance >= extendedRadius
        
        if atEdge {
            let angle = atan2(rawOffset.y, rawOffset.x)
            offset = CGPoint(
                x: cos(angle) * extendedRadius,
                y: sin(angle) * extendedRadius
            )
            
            if !didHitEdge {
                edgeImpact.impactOccurred(intensity: 0.55)
                didHitEdge = true
            }
        } else {
            offset     = rawOffset
            didHitEdge = false
        }
    }
    
    private func updateJoystickPosition() {
        let center = CGPoint(
            x: bounds.midX + offset.x,
            y: bounds.midY + offset.y
        )
        joystickView.center          = center
        joystickBackgroundView.center = center
    }
    
    private func placeAtCenter() {
        offset = .zero
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        joystickView.center          = center
        joystickBackgroundView.center = center
    }
    
    private func springReturnToCenter() {
        let center = CGPoint(x: bounds.midX, y: bounds.midY)

        let params = UISpringTimingParameters(
            mass: 0.6,
            stiffness: 280,
            damping: 18,
            initialVelocity: .zero
        )

        let animator = UIViewPropertyAnimator(duration: 0, timingParameters: params)
        animator.addAnimations {
            self.joystickView.center          = center
            self.joystickBackgroundView.center = center
        }
        animator.addCompletion { _ in
            self.offset        = .zero
            self.springAnimator = nil
        }
        animator.startAnimation()
        springAnimator = animator
    }
    
    private func animateBackground(show: Bool) {
        if !background {
            UIView.animate(withDuration: 0.15) {
                self.backgroundView.alpha = show ? 1 : 0
            }
        }
    }
}
