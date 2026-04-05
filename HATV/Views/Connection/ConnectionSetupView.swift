import CoreImage
import CoreImage.CIFilterBuiltins
import Observation
import SwiftUI

struct ConnectionSetupView: View {
    @Bindable var viewModel: RootViewModel
    let testConnection: () -> Void
    let connect: () -> Void

    var body: some View {
        HStack(spacing: 36) {
            VStack(alignment: .leading, spacing: 24) {
                Text("HATV")
                    .font(.system(size: 72, weight: .black, design: .rounded))
                    .foregroundStyle(.white)

                VStack(alignment: .leading, spacing: 10) {
                    Text("Home Assistant, simplified for Apple TV.")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)

                    Text("Pick one existing dashboard, open it fullscreen, and keep the interface calm enough to live on a television.")
                        .font(.system(size: 22, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.74))
                        .frame(maxWidth: 620, alignment: .leading)
                }

                VStack(alignment: .leading, spacing: 12) {
                    ConnectionStep(
                        number: "1",
                        title: "Enter your Home Assistant address",
                        detail: "HATV connects directly to your server and keeps the setup local."
                    )
                    ConnectionStep(
                        number: "2",
                        title: "Use your phone to open the profile page",
                        detail: "Create a long-lived token once, then paste it here."
                    )
                    ConnectionStep(
                        number: "3",
                        title: "Choose a dashboard and go fullscreen",
                        detail: "HATV remembers your last dashboard and view for kiosk-style relaunches."
                    )
                }

                if let tokenHelpURL {
                    QRCodePanel(
                        title: "Token Help",
                        caption: "Open the Home Assistant profile page on your phone to create a long-lived token.",
                        url: tokenHelpURL
                    )
                    .frame(width: 340)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top, spacing: 16) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Connect")
                            .font(.system(size: 30, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)

                        Text("Manual token setup is the most reliable tvOS flow today.")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.62))
                    }

                    Spacer()

                    if let tokenHelpURL {
                        Text(tokenHelpURL.absoluteString.replacingOccurrences(of: "https://", with: ""))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.46))
                            .lineLimit(1)
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("Name")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white.opacity(0.62))
                    TextField("Home Assistant", text: $viewModel.connectionName)
                        .hatvInputStyle()

                    Text("Server URL")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white.opacity(0.62))
                    TextField("https://ha.example.com", text: $viewModel.serverURLString)
                        .textInputAutocapitalization(.never)
                        .hatvInputStyle()

                    Text("Long-lived access token")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white.opacity(0.62))
                    SecureField("Paste your Home Assistant token", text: $viewModel.accessToken)
                        .textInputAutocapitalization(.never)
                        .hatvInputStyle()
                }

                if let instanceInfo = viewModel.instanceInfo {
                    HStack(spacing: 10) {
                        Image(systemName: "checkmark.seal.fill")
                            .foregroundStyle(.green)

                        Text("\(instanceInfo.locationName) • Home Assistant \(instanceInfo.version)")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(.white)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(Color.green.opacity(0.14), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }

                if let connectionProbeMessage = viewModel.connectionProbeMessage {
                    HStack(spacing: 10) {
                        Image(systemName: "network")
                            .foregroundStyle(.cyan)

                        Text(connectionProbeMessage)
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(.white)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(Color.cyan.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }

                HStack(spacing: 12) {
                    Button(action: testConnection) {
                        HStack(spacing: 10) {
                            Image(systemName: "network")
                            Text("Test Server")
                                .font(.headline.weight(.bold))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .foregroundStyle(.white)
                    }
                    .buttonStyle(.plain)
                    .disabled(viewModel.isBusy)

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
                        .background(Color.white, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .foregroundStyle(.black)
                    }
                    .buttonStyle(.plain)
                    .disabled(viewModel.isBusy)
                }

                Text("Tip: once connected, HATV stores the token securely and relaunches directly into your selected dashboard.")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.white.opacity(0.54))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(24)
            .frame(width: 640)
            .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(.white.opacity(0.08))
            )
        }
        .padding(.horizontal, 72)
        .padding(.vertical, 40)
    }

    private var tokenHelpURL: URL? {
        var value = viewModel.serverURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }

        if !value.contains("://") {
            value = "https://\(value)"
        }

        guard let baseURL = URL(string: value) else {
            return nil
        }

        return URL(string: "profile", relativeTo: baseURL)?.absoluteURL
    }
}

private extension View {
    func hatvInputStyle() -> some View {
        self
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.06))
            )
            .foregroundStyle(.white)
    }
}

private struct ConnectionStep: View {
    let number: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Text(number)
                .font(.headline.weight(.black))
                .foregroundStyle(.white)
                .frame(width: 34, height: 34)
                .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.white)

                Text(detail)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white.opacity(0.64))
            }
        }
    }
}

private struct QRCodePanel: View {
    let title: String
    let caption: String
    let url: URL

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title)
                .font(.headline.weight(.bold))
                .foregroundStyle(.white)

            QRCodeView(url: url)
                .frame(width: 156, height: 156)
                .padding(12)
                .background(Color.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))

            Text(caption)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.66))
                .fixedSize(horizontal: false, vertical: true)

            Text(url.absoluteString)
                .font(.caption2.weight(.medium))
                .foregroundStyle(.white.opacity(0.44))
                .lineLimit(3)
        }
        .padding(18)
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(.white.opacity(0.08))
        )
    }
}

private struct QRCodeView: View {
    private static let context = CIContext()

    let url: URL

    var body: some View {
        if let image = makeImage() {
            Image(decorative: image, scale: 1, orientation: .up)
                .interpolation(.none)
                .resizable()
                .scaledToFit()
        } else {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.black.opacity(0.08))
        }
    }

    private func makeImage() -> CGImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.setValue(Data(url.absoluteString.utf8), forKey: "inputMessage")
        filter.correctionLevel = "M"

        guard let outputImage = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: 12, y: 12)) else {
            return nil
        }

        return Self.context.createCGImage(outputImage, from: outputImage.extent)
    }
}
