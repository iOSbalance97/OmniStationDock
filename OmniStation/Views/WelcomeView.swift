import SwiftUI

struct WelcomeView: View {
    @State private var isVisible = false
    @State private var showHome = false

    var body: some View {
        ZStack {
            if showHome {
                HomeView()
                    .transition(.opacity)
            } else {
                welcomeScreen
                    .transition(.opacity)
            }
        }
        .preferredColorScheme(.dark)
        .task {
            guard !showHome else { return }

            withAnimation(.easeOut(duration: 0.8)) {
                isVisible = true
            }

            try? await Task.sleep(nanoseconds: 2_500_000_000)

            guard !Task.isCancelled else { return }

            withAnimation(.easeInOut(duration: 0.45)) {
                showHome = true
            }
        }
    }

    private var welcomeScreen: some View {
        GeometryReader { geometry in
            ZStack {
                Image("SpaceBackground")
                    .resizable()
                    .scaledToFill()
                    .frame(
                        width: geometry.size.width,
                        height: geometry.size.height
                    )
                    .clipped()
                    .ignoresSafeArea()

                LinearGradient(
                    colors: [
                        .black.opacity(0.22),
                        Color(red: 0.01, green: 0.025, blue: 0.08)
                            .opacity(0.35),
                        .black.opacity(0.55)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()

                VStack(spacing: 22) {
                    Spacer()

                    Image("OmniLogo")
                        .resizable()
                        .scaledToFit()
                        .frame(
                            width: min(geometry.size.width * 0.48, 220),
                            height: min(geometry.size.width * 0.48, 220)
                        )
                        .clipShape(
                            RoundedRectangle(
                                cornerRadius: 42,
                                style: .continuous
                            )
                        )
                        .overlay {
                            RoundedRectangle(
                                cornerRadius: 42,
                                style: .continuous
                            )
                            .stroke(.white.opacity(0.18), lineWidth: 1)
                        }
                        .shadow(color: .blue.opacity(0.4), radius: 28)

                    HStack(spacing: 0) {
                        Text("OmniStation").foregroundStyle(.white)
                        Text(" Dock")
                            .foregroundStyle(
                                Color(red: 0.25, green: 0.59, blue: 1)
                            )
                    }
                    .font(.system(size: 31, weight: .semibold))
                    .minimumScaleFactor(0.75)
                    .lineLimit(1)

                    Text("TU UNIVERSO DE JUEGOS\nEN UN SOLO LUGAR")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .tracking(2.2)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.white.opacity(0.72))

                    Spacer()

                    Capsule()
                        .fill(.white.opacity(0.15))
                        .frame(width: 110, height: 3)
                        .overlay(alignment: .leading) {
                            Capsule()
                                .fill(Color.blue)
                                .frame(width: isVisible ? 110 : 8, height: 3)
                                .shadow(color: .blue, radius: 8)
                        }

                    Spacer().frame(height: 26)
                }
                .padding(.horizontal, 28)
                .opacity(isVisible ? 1 : 0)
                .scaleEffect(isVisible ? 1 : 0.96)
            }
            .background(Color.black)
        }
        .ignoresSafeArea()
    }
}

#Preview {
    WelcomeView()
}
