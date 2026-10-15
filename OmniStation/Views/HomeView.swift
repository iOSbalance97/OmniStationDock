import SwiftUI

private enum DockTab: String, CaseIterable {
    case inicio = "Inicio", biblioteca = "Biblioteca", emuladores = "Emuladores", ajustes = "Ajustes"
    var symbol: String {
        switch self { case .inicio: return "house.fill"; case .biblioteca: return "square.grid.2x2.fill"; case .emuladores: return "gamecontroller.fill"; case .ajustes: return "gearshape.fill" }
    }
}

struct HomeView: View {
    @State private var searchText = ""
    @State private var selectedPlatform = "Todos"
    @State private var selectedTab: DockTab = .inicio
    private let platforms = ["Todos", "PS2", "PSP", "GameCube", "Wii", "Switch", "3DS", "NDS", "GBA"]
    private let games: [(name: String, platform: String, symbol: String, tint: Color)] = [
        ("God of War", "PS2", "flame.fill", Color(red: 0.64, green: 0.22, blue: 0.17)),
        ("Silent Hill 2", "PS2", "moon.fill", Color(red: 0.35, green: 0.43, blue: 0.52)),
        ("Resident Evil 4", "GameCube", "eye.fill", Color(red: 0.42, green: 0.31, blue: 0.22)),
        ("Pokémon Esmeralda", "GBA", "leaf.fill", Color(red: 0.15, green: 0.48, blue: 0.35)),
        ("Mario Kart DS", "NDS", "flag.checkered", Color(red: 0.72, green: 0.23, blue: 0.21)),
        ("Pokémon Rojo Fuego", "GBA", "bolt.fill", Color(red: 0.73, green: 0.29, blue: 0.19))
    ]
    private var filteredGames: [(name: String, platform: String, symbol: String, tint: Color)] {
        games.filter { (selectedPlatform == "Todos" || $0.platform == selectedPlatform) && (searchText.isEmpty || $0.name.localizedCaseInsensitiveContains(searchText)) }
    }

    var body: some View {
        ZStack {
            Color(red: 0.015, green: 0.025, blue: 0.055).ignoresSafeArea()
            VStack(spacing: 0) {
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 22) {
                        header
                        if selectedTab == .inicio || selectedTab == .biblioteca {
                            searchBar
                            platformFilters
                            HStack {
                                Text(selectedTab == .inicio ? "Tu biblioteca" : "Biblioteca")
                                    .font(.system(size: 23, weight: .bold))
                                Spacer()
                                Text("\(filteredGames.count) elementos").font(.caption).foregroundStyle(.white.opacity(0.48))
                            }
                            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 14) {
                                ForEach(filteredGames, id: \.name) { game in
                                    GameTile(game: game)
                                }
                            }
                            if filteredGames.isEmpty {
                                ContentUnavailableView("Sin resultados", systemImage: "magnifyingglass", description: Text("Prueba otro nombre o plataforma."))
                            }
                            glassNotice
                        } else if selectedTab == .emuladores {
                            sectionTitle("Emuladores", subtitle: "Tus plataformas en un solo lugar")
                            ForEach([("PlayStation 2", "PS2", "gamecontroller.fill"), ("Nintendo DS", "NDS", "rectangle.on.rectangle"), ("Game Boy Advance", "GBA", "gameboy.fill")], id: \.1) { item in
                                HStack(spacing: 14) {
                                    Image(systemName: item.2).font(.title2).foregroundStyle(.cyan).frame(width: 42, height: 42).background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 13))
                                    VStack(alignment: .leading, spacing: 3) { Text(item.0).fontWeight(.semibold); Text("Configuración pendiente").font(.caption).foregroundStyle(.white.opacity(0.48)) }
                                    Spacer(); Image(systemName: "chevron.right").foregroundStyle(.white.opacity(0.4))
                                }.padding(14).glassCard()
                            }
                        } else {
                            sectionTitle("Ajustes", subtitle: "Personaliza OmniStation Dock")
                            ForEach([("Apariencia", "Tema oscuro y acentos azules"), ("Biblioteca", "Carpetas y organización"), ("Acerca de", "OmniStation Dock · versión 0.0.2")], id: \.0) { item in
                                HStack { VStack(alignment: .leading, spacing: 4) { Text(item.0).fontWeight(.semibold); Text(item.1).font(.caption).foregroundStyle(.white.opacity(0.5)) }; Spacer(); Image(systemName: "chevron.right").foregroundStyle(.white.opacity(0.4)) }.padding(15).glassCard()
                            }
                        }
                    }
                    .padding(.horizontal, 18).padding(.top, 14).padding(.bottom, 24)
                }
                bottomBar
            }
        }
        .preferredColorScheme(.dark)
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image("OmniLogo").resizable().scaledToFill().frame(width: 48, height: 48).clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous)).overlay(RoundedRectangle(cornerRadius: 15).stroke(.white.opacity(0.18), lineWidth: 1)).shadow(color: .blue.opacity(0.22), radius: 10)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 0) { Text("OmniStation").foregroundStyle(.white); Text(" Dock").foregroundStyle(Color.cyan) }.font(.system(size: 20, weight: .bold))
                Text("TU UNIVERSO, A TU MANERA").font(.system(size: 8, weight: .medium)).tracking(1.5).foregroundStyle(.white.opacity(0.48))
            }
            Spacer()
            Button {} label: { Image(systemName: "slider.horizontal.3").font(.system(size: 17, weight: .semibold)).foregroundStyle(.white).frame(width: 42, height: 42).glassCard() }
        }
    }
    
    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.cyan)

            TextField("Buscar juegos y plataformas…", text: $searchText)
                .font(.subheadline)

            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.white.opacity(0.45))
                }
            }
        }
        .padding(13)
        .glassCard()
    }
    private var platformFilters: some View {
        ScrollView(.horizontal, showsIndicators: false) { HStack(spacing: 8) { ForEach(platforms, id: \.self) { platform in
            Button { withAnimation(.easeInOut(duration: 0.2)) { selectedPlatform = platform } } label: {
                Text(platform).font(.system(size: 12, weight: .semibold)).padding(.horizontal, 14).padding(.vertical, 9)
                    .foregroundStyle(selectedPlatform == platform ? .white : .white.opacity(0.68))
                    .background { Capsule().fill(selectedPlatform == platform ? LinearGradient(colors: [Color.blue, Color.cyan.opacity(0.75)], startPoint: .topLeading, endPoint: .bottomTrailing) : LinearGradient(colors: [.white.opacity(0.09), .white.opacity(0.035)], startPoint: .top, endPoint: .bottom)) }
                    .overlay(Capsule().stroke(.white.opacity(selectedPlatform == platform ? 0.25 : 0.08), lineWidth: 1))
            }
        } } }
    }
    private var glassNotice: some View {
        HStack(spacing: 12) { Image(systemName: "sparkles").foregroundStyle(.cyan).font(.title2); VStack(alignment: .leading, spacing: 3) { Text("Tu universo está tomando forma").font(.subheadline.weight(.semibold)); Text("Estos elementos son ejemplos visuales. La importación real llegará en una próxima fase.").font(.caption).foregroundStyle(.white.opacity(0.55)) } }.padding(14).glassCard()
    }
    private func sectionTitle(_ title: String, subtitle: String) -> some View { VStack(alignment: .leading, spacing: 5) { Text(title).font(.system(size: 25, weight: .bold)); Text(subtitle).font(.subheadline).foregroundStyle(.white.opacity(0.52)) }.padding(.vertical, 6) }
    private var bottomBar: some View {
        HStack(spacing: 0) { ForEach(DockTab.allCases, id: \.self) { tab in
            Button { withAnimation(.easeInOut(duration: 0.18)) { selectedTab = tab } } label: {
                VStack(spacing: 5) { Image(systemName: tab.symbol).font(.system(size: 18, weight: .semibold)); Text(tab.rawValue).font(.system(size: 9, weight: .medium)) }
                    .foregroundStyle(selectedTab == tab ? Color.cyan : .white.opacity(0.48)).frame(maxWidth: .infinity).padding(.top, 12).padding(.bottom, 8)
            }
        } }.padding(.horizontal, 8).background(.ultraThinMaterial).overlay(alignment: .top) { Rectangle().fill(.white.opacity(0.1)).frame(height: 0.5) }
    }
}

private struct GameTile: View {
    let game: (name: String, platform: String, symbol: String, tint: Color)
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack {
                LinearGradient(colors: [game.tint.opacity(0.95), Color(red: 0.025, green: 0.05, blue: 0.11)], startPoint: .topLeading, endPoint: .bottomTrailing)
                Circle().fill(.white.opacity(0.07)).frame(width: 90, height: 90).blur(radius: 1).offset(x: 28, y: -28)
                Image(systemName: game.symbol).font(.system(size: 34, weight: .medium)).foregroundStyle(.white.opacity(0.92)).shadow(color: .black.opacity(0.25), radius: 8)
                VStack { HStack { Text(game.platform).font(.system(size: 9, weight: .bold)).padding(.horizontal, 7).padding(.vertical, 4).background(.black.opacity(0.35), in: Capsule()); Spacer() }; Spacer() }.padding(8)
            }.frame(height: 118).clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            Text(game.name).font(.system(size: 12, weight: .semibold)).lineLimit(2).foregroundStyle(.white.opacity(0.94)).frame(height: 30, alignment: .topLeading)
        }.padding(7).frame(maxWidth: .infinity, alignment: .leading).glassCard()
    }
}

private extension View {
    func glassCard() -> some View {
        self.background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(LinearGradient(colors: [.white.opacity(0.17), .white.opacity(0.035)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1))
    }
}

#Preview { HomeView() }
