import SwiftUI

struct WelcomeView: View {
    @State private var isVisible = false

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Image("SpaceBackground")
                    .resizable()
                    .scaledToFill()
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .clipped()
                    .ignoresSafeArea()

                // Slight darkening keeps the logo and title readable on every device.
                LinearGradient(
                    colors: [
                        Color.black.opacity(0.18),
                        Color(red: 0.01, green: 0.025, blue: 0.07).opacity(0.24),
                        Color.black.opacity(0.40)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()

                VStack(spacing: 18) {
                    Spacer(minLength: 24)

                    Image("OmniLogo")
                        .resizable()
                        .scaledToFit()
                        .frame(
                            width: min(geometry.size.width * 0.60, 270),
                            height: min(geometry.size.width * 0.60, 270)
                        )
                        .shadow(color: Color.cyan.opacity(0.22), radius: 24, y: 0)
                        .accessibilityLabel("Icono de OmniStation Dock")

                    HStack(spacing: 0) {
                        Text("OmniStation")
                            .foregroundStyle(Color.white)
                        Text(" Dock")
                            .foregroundStyle(Color(red: 0.22, green: 0.57, blue: 1.0))
                    }
                    .font(.system(size: 32, weight: .semibold, design: .default))
                    .minimumScaleFactor(0.72)
                    .lineLimit(1)
                    .shadow(color: .black.opacity(0.45), radius: 10, y: 2)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("OmniStation Dock")

                    Spacer(minLength: 32)
                }
                .padding(.horizontal, 24)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .opacity(isVisible ? 1 : 0)
                .scaleEffect(isVisible ? 1 : 0.965)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .background(Color.black)
            .onAppear {
                withAnimation(.easeOut(duration: 1.0)) {
                    isVisible = true
                }
            }
        }
        .ignoresSafeArea()
    }
}

#Preview {
    WelcomeView()
}
