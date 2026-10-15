import SwiftUI

struct WelcomeView: View {
    @State private var isVisible = false
    @State private var showHome = false

    var body: some View {
        ZStack {
            if showHome {
                HomeView().transition(.opacity)
            } else {
                welcomeScreen.transition(.opacity)
            }
        }
        .preferredColorScheme(.dark)
        .task {
            guard !showHome else { return }
            withAnimation(.easeOut(duration: 0.9)) { isVisible = true }
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.45)) { showHome = true }
        }
    }

    private var welcomeScreen: some View {
        GeometryReader { geometry in
            ZStack {
                Image("SpaceBackground")
                    .resizable()
                    .scaledToFill()
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .clipped()
                    .ignoresSafeArea()

                LinearGradient(
                    colors: [
                        Color(red: 0.005, green: 0.018, blue: 0.055).opacity(0.2),
                        Color(red: 0.005, green: 0.025, blue: 0.08).opacity(0.45),
                        .black.opacity(0.72)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()

                VStack(spacing: 0) {
                    Spacer(minLength: 24)

                    Image("OmniLogo")
                        .resizable()
                        .scaledToFit()
                        .frame(
                            width: min(min(geometry.size.width * 0.52, geometry.size.height * 0.29), 245),
                            height: min(min(geometry.size.width * 0.52, geometry.size.height * 0.29), 245)
                        )
                        .shadow(color: .blue.opacity(0.42), radius: 28)
                        .accessibilityLabel("Planeta de OmniStation Dock")

                    VStack(spacing: 3) {
                        Text("OMNISTATION")
                            .font(.system(size: min(geometry.size.width * 0.075, 31), weight: .medium, design: .rounded))
                            .tracking(geometry.size.width < 400 ? 3.5 : 5.5)
                            .foregroundStyle(.white)
                            .minimumScaleFactor(0.65)
                            .lineLimit(1)

                        Text("DOCK")
                            .font(.system(size: min(geometry.size.width * 0.09, 38), weight: .bold, design: .rounded))
                            .tracking(geometry.size.width < 400 ? 7 : 10)
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [Color(red: 0.2, green: 0.55, blue: 1), .cyan],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                    }
                    .padding(.top, 22)

                    Spacer()

                    Text("TU UNIVERSO DE JUEGOS,\nEN UN SOLO LUGAR.")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .tracking(2.5)
                        .multilineTextAlignment(.center)
                        .lineSpacing(7)
                        .foregroundStyle(.white.opacity(0.78))

                    Capsule()
                        .fill(.white.opacity(0.15))
                        .frame(width: min(geometry.size.width * 0.52, 210), height: 3)
                        .overlay(alignment: .leading) {
                            Capsule()
                                .fill(LinearGradient(colors: [.blue, .cyan], startPoint: .leading, endPoint: .trailing))
                                .frame(width: isVisible ? min(geometry.size.width * 0.52, 210) : 8, height: 3)
                                .shadow(color: .cyan, radius: 8)
                        }
                        .padding(.top, 28)

                    Spacer(minLength: 44)
                }
                .padding(.horizontal, 28)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .opacity(isVisible ? 1 : 0)
                .scaleEffect(isVisible ? 1 : 0.97)
            }
            .background(Color.black)
        }
        .ignoresSafeArea()
    }
}

#Preview {
    WelcomeView()
}
