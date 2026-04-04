import Observation
import SwiftUI

struct ConnectionSetupView: View {
    @Bindable var viewModel: RootViewModel
    let connect: () -> Void

    var body: some View {
        HStack(spacing: 44) {
            VStack(alignment: .leading, spacing: 22) {
                Text("HATV")
                    .font(.system(size: 72, weight: .black, design: .rounded))
                    .foregroundStyle(.white)

                Text("A clean Home Assistant dashboard for Apple TV.")
                    .font(.system(size: 26, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.80))
                    .frame(maxWidth: 560, alignment: .leading)

                VStack(alignment: .leading, spacing: 14) {
                    HighlightRow(symbol: "square.grid.2x2.fill", text: "Pick an existing Lovelace dashboard")
                    HighlightRow(symbol: "video.fill", text: "Open camera feeds full screen")
                    HighlightRow(symbol: "switch.2", text: "Control devices without editing anything")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .leading, spacing: 20) {
                Text("Connect to Home Assistant")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)

                VStack(alignment: .leading, spacing: 12) {
                    Text("Name")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.62))
                    TextField("Home Assistant", text: $viewModel.connectionName)
                        .hatvInputStyle()

                    Text("Server URL")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.62))
                    TextField("https://ha.example.com", text: $viewModel.serverURLString)
                        .textInputAutocapitalization(.never)
                        .hatvInputStyle()

                    Text("Long-lived access token")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.62))
                    SecureField("Paste your Home Assistant token", text: $viewModel.accessToken)
                        .textInputAutocapitalization(.never)
                        .hatvInputStyle()
                }

                if let instanceInfo = viewModel.instanceInfo {
                    Label("\(instanceInfo.locationName) • Home Assistant \(instanceInfo.version)", systemImage: "checkmark.seal.fill")
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.green)
                }

                Button(action: connect) {
                    HStack(spacing: 12) {
                        if viewModel.isBusy {
                            ProgressView()
                                .tint(.black)
                        }
                        Text(viewModel.isBusy ? "Connecting…" : "Connect")
                            .font(.headline.weight(.bold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color.white, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .foregroundStyle(.black)
                }
                .buttonStyle(.plain)
                .disabled(viewModel.isBusy)
            }
            .padding(28)
            .frame(width: 620)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .strokeBorder(.white.opacity(0.10))
            )
        }
        .padding(.horizontal, 72)
        .padding(.vertical, 40)
    }
}

private extension View {
    func hatvInputStyle() -> some View {
        self
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.06))
            )
            .foregroundStyle(.white)
    }
}

private struct HighlightRow: View {
    let symbol: String
    let text: String

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.headline.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 34, height: 34)
                .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

            Text(text)
                .font(.title3.weight(.semibold))
                .foregroundStyle(.white.opacity(0.82))
        }
    }
}
