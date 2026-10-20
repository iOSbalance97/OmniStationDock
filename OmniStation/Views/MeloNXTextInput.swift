import SwiftUI
import UIKit
import GameController

// MARK: - Teclado de los juegos de Switch (applet de teclado de MeloNX) con el mando
//
// Cuando un juego pide un texto (por ejemplo el nombre en Pokémon), el núcleo llama a
// «show_text_input» y se queda esperando la respuesta. OSMeloNXEngine (Objective-C):
// • sin mando, enseña la alerta con el teclado de iOS;
// • con mando, crea este teclado por su nombre (OSNXTextInputFactory) para escribir con él.
// Mando: cruceta/stick mueven, ✕ pulsa la tecla, □ borra, L1 mayúsculas, ○ cancela y START acepta.

@MainActor
final class OSNXTextInputModel: ObservableObject {
    let title: String
    let message: String
    let placeholder: String
    let english: Bool
    @Published var text: String = ""
    @Published var shift: Bool = true
    /// 0..<teclas: una tecla; luego «Cancelar» y «Aceptar».
    @Published var selected: Int = 0
    @Published var gamepad: Bool = false
    var onFinish: ((String?) -> Void)?

    let keys: [String] = PadKeys.text
    var cancelIndex: Int { keys.count }
    var okIndex: Int { keys.count + 1 }

    init(title: String, message: String, placeholder: String, english: Bool) {
        self.title = title
        self.message = message
        self.placeholder = placeholder
        self.english = english
    }

    func t(_ spanish: String, _ englishText: String) -> String {
        english ? englishText : spanish
    }

    func press(_ index: Int) {
        if index == cancelIndex {
            onFinish?(nil)
            return
        }
        if index == okIndex {
            onFinish?(text)
            return
        }
        guard keys.indices.contains(index) else { return }
        selected = index
        PadKeys.apply(keys[index], to: &text, shift: &shift, autoCapitalize: true)
    }

    func deleteLetter() {
        if !text.isEmpty { text.removeLast() }
        shift = text.isEmpty || text.hasSuffix(" ")
    }

    func move(_ direction: String) {
        let columns: Int = PadKeys.columns
        let lastKey: Int = keys.count - 1
        switch direction {
        case "up":
            if selected >= keys.count {
                selected = selected == cancelIndex ? lastKey - columns + 1 : lastKey
            } else if selected >= columns {
                selected -= columns
            }
        case "down":
            if selected >= keys.count { return }
            if selected + columns <= lastKey {
                selected += columns
            } else {
                selected = (selected % columns) < columns / 2 ? cancelIndex : okIndex
            }
        case "left":
            if selected == okIndex {
                selected = cancelIndex
            } else if selected < keys.count, selected % columns > 0 {
                selected -= 1
            }
        case "right":
            if selected == cancelIndex {
                selected = okIndex
            } else if selected < keys.count, selected % columns < columns - 1, selected < lastKey {
                selected += 1
            }
        default:
            break
        }
    }
}

struct OSNXTextInputView: View {
    @ObservedObject var model: OSNXTextInputModel

    var body: some View {
        ZStack {
            Color.black.opacity(0.62).ignoresSafeArea()
            VStack(spacing: 10) {
                if !model.title.isEmpty {
                    Text(model.title)
                        .font(AppFont.text(16, .bold))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                }
                if !model.message.isEmpty {
                    Text(model.message)
                        .font(AppFont.text(12))
                        .foregroundStyle(.white.opacity(0.7))
                        .multilineTextAlignment(.center)
                }
                HStack(spacing: 0) {
                    Text(model.text.isEmpty ? model.placeholder : model.text)
                        .font(AppFont.text(17, .semibold))
                        .foregroundStyle(model.text.isEmpty ? Color.white.opacity(0.4) : Color.white)
                        .lineLimit(1)
                    Rectangle()
                        .fill(Color.cyan)
                        .frame(width: 2, height: 20)
                        .padding(.leading, 2)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                PadKeyboardView(
                    keys: model.keys,
                    selectedIndex: model.gamepad && model.selected < model.keys.count ? model.selected : nil,
                    lowercase: !model.shift,
                    onKey: { index in model.press(index) }
                )
                HStack(spacing: 10) {
                    actionButton(model.t("Cancelar", "Cancel"), index: model.cancelIndex, tint: Color.white.opacity(0.85))
                    actionButton(model.t("Aceptar", "OK"), index: model.okIndex, tint: Color.cyan)
                }
                if model.gamepad {
                    Text(model.t("✕ tecla · □ borrar · L1 mayúsculas · ○ cancelar · START aceptar",
                                 "✕ key · □ delete · L1 shift · ○ cancel · START OK"))
                        .font(AppFont.text(10, .semibold))
                        .foregroundStyle(.white.opacity(0.5))
                }
            }
            .padding(16)
            .frame(maxWidth: 560)
            .background(Color(white: 0.09).opacity(0.96), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(Color.white.opacity(0.12), lineWidth: 1))
            .padding(.horizontal, 20)
        }
        .preferredColorScheme(.dark)
    }

    private func actionButton(_ title: String, index: Int, tint: Color) -> some View {
        let selected: Bool = model.gamepad && model.selected == index
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        return Button {
            model.press(index)
        } label: {
            Text(title)
                .font(AppFont.text(14, .semibold))
                .foregroundStyle(selected ? Color.black : tint)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(selected ? Color.cyan : Color.white.opacity(0.08), in: shape)
                .contentShape(shape)
        }
        .buttonStyle(.plain)
    }
}

/// Teclado presentado encima de la partida. Lee el mando por su cuenta (en la partida la
/// navegación de OmniStation está apagada) y repite las direcciones al dejarlas pulsadas.
final class OSNXTextInputController: UIHostingController<OSNXTextInputView> {
    private let model: OSNXTextInputModel
    private var completion: ((String?) -> Void)?
    private var link: CADisplayLink?
    private var previous: Set<String> = []
    private var held: String?
    private var repeatAt: CFTimeInterval = 0

    init(model: OSNXTextInputModel, completion: @escaping (String?) -> Void) {
        self.model = model
        self.completion = completion
        super.init(rootView: OSNXTextInputView(model: model))
        modalPresentationStyle = .overFullScreen
        modalTransitionStyle = .crossDissolve
        view.backgroundColor = .clear
        model.onFinish = { [weak self] result in
            self?.finish(result)
        }
    }

    @MainActor required dynamic init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) no se usa")
    }

    override var prefersStatusBarHidden: Bool { true }
    override var prefersHomeIndicatorAutoHidden: Bool { true }
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask { .landscape }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard link == nil else { return }
        let displayLink = CADisplayLink(target: self, selector: #selector(poll(_:)))
        displayLink.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 60, preferred: 60)
        displayLink.add(to: .main, forMode: .common)
        link = displayLink
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        link?.invalidate()
        link = nil
    }

    private func finish(_ result: String?) {
        guard let completion else { return }
        self.completion = nil
        link?.invalidate()
        link = nil
        dismiss(animated: true) {
            completion(result)
        }
    }

    @objc private func poll(_ displayLink: CADisplayLink) {
        guard let pad = (GCController.current ?? GCController.controllers().first)?.extendedGamepad else {
            if model.gamepad { model.gamepad = false }
            previous = []
            held = nil
            return
        }
        if !model.gamepad { model.gamepad = true }
        var pressed: Set<String> = []
        let x: Float = abs(pad.dpad.xAxis.value) > 0.5 ? pad.dpad.xAxis.value : pad.leftThumbstick.xAxis.value
        let y: Float = abs(pad.dpad.yAxis.value) > 0.5 ? pad.dpad.yAxis.value : pad.leftThumbstick.yAxis.value
        if y > 0.5 { pressed.insert("up") }
        if y < -0.5 { pressed.insert("down") }
        if x < -0.5 { pressed.insert("left") }
        if x > 0.5 { pressed.insert("right") }
        if pad.buttonA.isPressed { pressed.insert("a") }
        if pad.buttonB.isPressed { pressed.insert("b") }
        if pad.buttonX.isPressed { pressed.insert("x") }
        if pad.leftShoulder.isPressed { pressed.insert("l1") }
        if pad.buttonMenu.isPressed { pressed.insert("start") }
        let now: CFTimeInterval = displayLink.timestamp
        let directions: Set<String> = ["up", "down", "left", "right"]
        for key in pressed.subtracting(previous) {
            handle(key)
            if directions.contains(key) {
                held = key
                repeatAt = now + 0.4
            }
        }
        if let current = held {
            if pressed.contains(current) {
                if now >= repeatAt {
                    handle(current)
                    repeatAt = now + 0.09
                }
            } else {
                held = nil
            }
        }
        previous = pressed
    }

    private func handle(_ key: String) {
        switch key {
        case "up", "down", "left", "right":
            model.move(key)
        case "a":
            model.press(model.selected)
        case "b":
            model.press(model.cancelIndex)
        case "x":
            model.deleteLetter()
        case "l1":
            model.shift.toggle()
        case "start":
            model.press(model.okIndex)
        default:
            break
        }
    }
}

/// Lo que llama OSMeloNXEngine con NSClassFromString(@"OSNXTextInputFactory").
@objc(OSNXTextInputFactory)
@MainActor
final class OSNXTextInputFactory: NSObject {
    @objc(makeWithTitle:message:placeholder:english:completion:)
    static func make(title: String, message: String, placeholder: String, english: Bool,
                     completion: @escaping @convention(block) (NSString?) -> Void) -> UIViewController {
        let model = OSNXTextInputModel(title: title, message: message, placeholder: placeholder, english: english)
        return OSNXTextInputController(model: model) { result in
            completion(result.map { $0 as NSString })
        }
    }
}
