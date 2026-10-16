import SwiftUI

// MARK: - Mandos

struct ControllersSheet: View {
    let lang: String
    @ObservedObject var monitor: ControllerMonitor
    @Binding var navigationEnabled: Bool
    @Environment(\.dismiss) private var dismiss

    private func tr(_ key: String, _ args: CVarArg...) -> String {
        let base = L10n.tr(key, lang)
        return args.isEmpty ? base : String(format: base, arguments: args)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    if monitor.controllers.isEmpty {
                        emptyState
                    } else {
                        ForEach(monitor.controllers) { controller in
                            row(controller)
                        }
                    }
                    navigationToggle
                }
                .padding(16)
            }
            .navigationTitle(tr("Mandos"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(tr("Listo")) { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationBackground(.ultraThinMaterial)
        .preferredColorScheme(.dark)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "gamecontroller")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(Color.cyan)
            Text(tr("Ningún mando conectado"))
                .font(.system(size: 15, weight: .semibold, design: .rounded))
            Text(tr("Conecta un mando por Bluetooth (DualSense, Xbox…) y aparecerá aquí."))
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.55))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(22)
        .glassCard()
    }

    private func row(_ controller: ControllerMonitor.Info) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "gamecontroller.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Color.cyan)
                .frame(width: 40, height: 40)
                .background(Color.cyan.opacity(0.14), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(controller.name)
                    .font(.system(size: 14, weight: .semibold))
                Text(controller.category)
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.5))
            }
            Spacer(minLength: 6)
            if let battery = controller.battery {
                Label(controller.charging ? tr("Cargando") + " \(battery)%" : "\(battery)%", systemImage: controller.charging ? "battery.100.bolt" : "battery.75")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.7))
            }
        }
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }

    private var navigationToggle: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(tr("Navegar con el mando"))
                    .font(.system(size: 14, weight: .semibold))
                Text(tr("L1 y R1 cambian de pestaña"))
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.5))
            }
            Spacer(minLength: 6)
            Toggle(tr("Navegar con el mando"), isOn: $navigationEnabled)
                .labelsHidden()
                .tint(Color.cyan)
        }
        .padding(13)
        .glassCard()
    }
}

// MARK: - Reorganizar plataformas

struct PlatformOrderSheet: View {
    let lang: String
    @Binding var orderRaw: String
    @Environment(\.dismiss) private var dismiss
    @State private var items: [String] = []

    private func tr(_ key: String) -> String { L10n.tr(key, lang) }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(items, id: \.self) { name in
                        Label(name, systemImage: Platforms.symbol(for: name))
                            .font(.system(size: 15, weight: .semibold))
                            .listRowBackground(Color.white.opacity(0.07))
                    }
                    .onMove { source, destination in
                        items.move(fromOffsets: source, toOffset: destination)
                        orderRaw = items.joined(separator: "|")
                    }
                } footer: {
                    Text(tr("Arrastra para cambiar el orden de los filtros."))
                }
            }
            .environment(\.editMode, .constant(.active))
            .scrollContentBackground(.hidden)
            .navigationTitle(tr("Reorganizar plataformas"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(tr("Restablecer")) {
                        orderRaw = ""
                        items = Platforms.ordered("")
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(tr("Listo")) { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationBackground(.ultraThinMaterial)
        .preferredColorScheme(.dark)
        .onAppear { items = Platforms.ordered(orderRaw) }
    }
}

// MARK: - Añadir acceso directo (URL)

struct AddShortcutSheet: View {
    let lang: String
    var onSave: (LibraryGame) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var platform = "PS2"
    @State private var name = ""
    @State private var urlText = ""

    private func tr(_ key: String) -> String { L10n.tr(key, lang) }

    private var cleanName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var cleanURL: String { urlText.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var urlIsValid: Bool {
        guard let url = URL(string: cleanURL), let scheme = url.scheme else { return false }
        return !scheme.isEmpty && cleanURL.contains("://")
    }

    private var canSave: Bool { !cleanName.isEmpty && urlIsValid }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    caption(tr("Plataforma"))
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 92), spacing: 8)], spacing: 8) {
                        ForEach(Platforms.movableNames, id: \.self) { item in
                            platformChip(item)
                        }
                    }

                    caption(tr("Nombre"))
                    TextField(tr("Nombre del juego"), text: $name)
                        .textInputAutocapitalization(.words)
                        .padding(14)
                        .glassCard(cornerRadius: 14)

                    caption(tr("URL de acceso directo"))
                    TextField("app://juego", text: $urlText)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .padding(14)
                        .glassCard(cornerRadius: 14)

                    Text(tr("Debe incluir el esquema de la app, por ejemplo app://…"))
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.5))
                }
                .padding(16)
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(tr("Añadir acceso directo"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(tr("Cancelar")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(tr("Añadir")) { save() }
                        .disabled(!canSave)
                }
            }
        }
        .presentationDetents([.large])
        .presentationBackground(.ultraThinMaterial)
        .preferredColorScheme(.dark)
    }

    private func caption(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 11, weight: .heavy, design: .rounded))
            .tracking(1.4)
            .foregroundStyle(Color.cyan.opacity(0.85))
    }

    private func platformChip(_ item: String) -> some View {
        let selected = platform == item
        return Button {
            platform = item
        } label: {
            HStack(spacing: 6) {
                Image(systemName: Platforms.symbol(for: item))
                    .font(.system(size: 12, weight: .semibold))
                Text(item)
                    .font(.system(size: 13, weight: .semibold))
            }
            .foregroundStyle(selected ? Color.white : Color.white.opacity(0.78))
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)
            .liquidGlass(in: Capsule(), tint: selected ? Color(red: 0.05, green: 0.45, blue: 1.0) : nil, interactive: true)
            .overlay {
                if selected {
                    Capsule().strokeBorder(Color.cyan.opacity(0.7), lineWidth: 1)
                }
            }
        }
        .buttonStyle(ControllerFocusableButtonStyle())
        .focusable()
    }

    private func save() {
        guard canSave else { return }
        let item = LibraryGame(
            id: "\(platform)/\(cleanName)",
            name: cleanName,
            platform: platform,
            launchURL: cleanURL,
            source: "url"
        )
        onSave(item)
        dismiss()
    }
}
