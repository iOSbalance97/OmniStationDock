import SwiftUI
import UIKit
import Melo_Controller

// MARK: - Mando táctil de MeloNX en el núcleo integrado
//
// Es el mismo mando en pantalla que usa la app MeloNX (paquete Melo-Controller, GPL-3.0,
// https://github.com/stossy11/Melo-Controller), con su distribución y su editor de posiciones.
// OSMeloNXEngine (Objective-C) lo crea por su nombre con OSNXTouchScreenFactory y le pasa dos
// bloques: uno para los botones y otro para los sticks. Todo va al jugador 1, el mismo que usa
// el mando físico, así que se puede pasar de uno a otro en mitad de la partida.

/// Recibe la pulsación de Melo-Controller y la reenvía al motor con la numeración de MeloNX.
final class OSNXTouchBridge: ObservableObject, Controller {
    /// Mismo orden que MeloNX 2.7 (VirtualControllerButton.rawValue) y que OSNXButton.
    private static let order: [String] = [
        VirtualControllerButton.A.id, VirtualControllerButton.B.id, VirtualControllerButton.X.id,
        VirtualControllerButton.Y.id, VirtualControllerButton.back.id, VirtualControllerButton.guide.id,
        VirtualControllerButton.start.id, VirtualControllerButton.leftStick.id,
        VirtualControllerButton.rightStick.id, VirtualControllerButton.leftShoulder.id,
        VirtualControllerButton.rightShoulder.id, VirtualControllerButton.dPadUp.id,
        VirtualControllerButton.dPadDown.id, VirtualControllerButton.dPadLeft.id,
        VirtualControllerButton.dPadRight.id, VirtualControllerButton.leftTrigger.id,
        VirtualControllerButton.rightTrigger.id
    ]

    private let button: (Int, Bool) -> Void
    private let stick: (Bool, Double, Double) -> Void

    init(button: @escaping (Int, Bool) -> Void, stick: @escaping (Bool, Double, Double) -> Void) {
        self.button = button
        self.stick = stick
    }

    private func send(_ pressedButton: VirtualControllerButton, pressed: Bool) {
        guard let index = Self.order.firstIndex(of: pressedButton.id) else { return }
        button(index, pressed)
    }

    func buttonPressed(_ button: VirtualControllerButton) {
        send(button, pressed: true)
    }

    func buttonReleased(_ button: VirtualControllerButton) {
        send(button, pressed: false)
    }

    /// Melo-Controller da la Y hacia abajo; el motor la invierte (como hace MeloNX).
    func joystickMoved(position: CGPoint, right: Bool) {
        stick(right, Double(position.x), Double(position.y))
    }
}

/// Si se enseña el mando táctil (se oculta con mando físico, salvo que se pida siempre).
final class OSNXTouchState: ObservableObject {
    @Published var visible: Bool = true
}

/// La pantalla del juego (UIView de Objective-C) dentro de SwiftUI.
private struct OSNXGameViewRepresentable: UIViewRepresentable {
    let gameView: UIView

    func makeUIView(context: Context) -> UIView {
        gameView
    }

    func updateUIView(_ uiView: UIView, context: Context) {}
}

private struct OSNXTouchScreen: View {
    let gameView: UIView
    let bridge: OSNXTouchBridge
    @ObservedObject var state: OSNXTouchState
    @AppStorage("melonxCoreTouchOpacity") private var opacity: Double = 0.85

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            OSNXGameViewRepresentable(gameView: gameView)
                .ignoresSafeArea()
            if state.visible {
                ControllerView(controller: bridge, isEditing: false)
                    .opacity(min(max(opacity, 0.2), 1.0))
                    .ignoresSafeArea(.all, edges: .vertical)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .persistentSystemOverlays(.hidden)
        .statusBarHidden(true)
    }
}

/// Pantalla de juego con el mando táctil encima. Responde a setTouchVisible: desde Objective-C.
@MainActor
final class OSNXTouchHostingController: UIHostingController<AnyView> {
    let state: OSNXTouchState
    private let bridge: OSNXTouchBridge

    init(gameView: UIView, bridge: OSNXTouchBridge, state: OSNXTouchState) {
        self.state = state
        self.bridge = bridge
        super.init(rootView: AnyView(OSNXTouchScreen(gameView: gameView, bridge: bridge, state: state)))
        view.backgroundColor = .black
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) no se usa")
    }

    @objc(setTouchVisible:)
    func setTouchVisible(_ visible: Bool) {
        if state.visible != visible { state.visible = visible }
    }

    override var prefersStatusBarHidden: Bool { true }
    override var prefersHomeIndicatorAutoHidden: Bool { true }
}

/// Lo que llama OSMeloNXEngine con NSClassFromString(@"OSNXTouchScreenFactory").
@objc(OSNXTouchScreenFactory)
@MainActor
final class OSNXTouchScreenFactory: NSObject {
    @objc(makeWithGameView:button:stick:)
    static func make(gameView: UIView,
                     button: @escaping @convention(block) (Int, Bool) -> Void,
                     stick: @escaping @convention(block) (Bool, Double, Double) -> Void) -> UIViewController {
        let bridge = OSNXTouchBridge(button: { button($0, $1) }, stick: { stick($0, $1, $2) })
        return OSNXTouchHostingController(gameView: gameView, bridge: bridge, state: OSNXTouchState())
    }
}
