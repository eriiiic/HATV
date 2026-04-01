import Observation
import SwiftUI

struct ConnectionSetupView: View {
    @Bindable var viewModel: RootViewModel
    let connect: () -> Void

    var body: some View {
        HStack(spacing: 56) {
            VStack(alignment: .leading, spacing: 28) {
                Text("HATV")
                    .font(.system(size: 92, weight: .black, design: .rounded))
                    .foregroundStyle(.white)

                Text("A polished, kiosk-style Home Assistant dashboard for Apple TV.")
                    .font(.system(size: 34, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.86))
                    .frame(maxWidth: 700, alignment: .leading)

                VStack(alignment: .leading, spacing: 18) {
                    HighlightRow(symbol: "square.grid.2x2.fill", text: "Pick an existing Lovelace dashboard")
                    HighlightRow(symbol: "video.fill", text: "Open camera feeds full screen")
                    HighlightRow(symbol: "switch.2", text: "Control devices without editing dashboard config")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .leading, spacing: 24) {
                Text("Connect to Home Assistant")
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)

                VStack(alignment: .leading, spacing: 16) {
                    Text("Name")
                        .foregroundStyle(.white.opacity(0.7))
                    TextField("Home Assistant", text: $viewModel.connectionName)
                        .hatvInputStyle()

                    Text("Server URL")
                        .foregroundStyle(.white.opacity(0.7))
                    TextField("https://ha.example.com", text: $viewModel.serverURLString)
                        .textInputAutocapitalization(.never)
                        .hatvInputStyle()

                    Text("Long-lived access token")
                        .foregroundStyle(.white.opacity(0.7))
                    SecureField("Paste your Home Assistant token", text: $viewModel.accessToken)
                        .textInputAutocapitalization(.never)
                        .hatvInputStyle()
                }

                if let instanceInfo = viewModel.instanceInfo {
                    Label("\(instanceInfo.locationName) • Home Assistant \(instanceInfo.version)", systemImage: "checkmark.seal.fill")
                        .foregroundStyle(.green)
                }

                Button(action: connect) {
                    HStack(spacing: 14) {
                        if viewModel.isBusy {
                            ProgressView()
                                .tint(.black)
                        }
                        Text(viewModel.isBusy ? "Connecting…" : "Connect")
                            .font(.headline.weight(.bold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)
                    .background(Color.white, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .foregroundStyle(.black)
                }
                .buttonStyle(.plain)
                .disabled(viewModel.isBusy)
            }
            .padding(36)
            .frame(width: 720)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 32, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 32, style: .continuous)
                    .strokeBorder(.white.opacity(0.16))
            )
        }
        .padding(.horizontal, 84)
    }
}

private extension View {
    func hatvInputStyle() -> some View {
        self
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
            .background(Color.white.opacity(0.10), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.08))
            )
            .foregroundStyle(.white)
    }
}

private struct HighlightRow: View {
    let symbol: String
    let text: String

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: symbol)
                .font(.title3.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .background(Color.white.opacity(0.10), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            Text(text)
                .font(.title3.weight(.semibold))
                .foregroundStyle(.white.opacity(0.88))
        }
    }
}
