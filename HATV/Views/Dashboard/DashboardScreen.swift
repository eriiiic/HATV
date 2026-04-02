import AVKit
import Observation
import SwiftUI

struct DashboardScreen: View {
    @Bindable var viewModel: RootViewModel
    let showDashboards: () -> Void
    let changeConnection: () -> Void

    @State private var presentedCamera: PresentedCamera?

    private let columns = [
        GridItem(.flexible(), spacing: 28),
        GridItem(.flexible(), spacing: 28)
    ]

    var body: some View {
        VStack(spacing: 24) {
            header

            if let currentView = viewModel.currentView {
                ScrollView {
                    VStack(alignment: .leading, spacing: 32) {
                        if currentView.sections.isEmpty {
                            cardGrid(for: currentView.cards)
                        } else {
                            ForEach(currentView.sections) { section in
                                VStack(alignment: .leading, spacing: 18) {
                                    if let title = section.title, !title.isEmpty {
                                        Text(title)
                                            .font(.title.bold())
                                            .foregroundStyle(.white)
                                    }

                                    cardGrid(for: section.cards)
                                }
                            }
                        }
                    }
                    .padding(.bottom, 48)
                }
            } else {
                VStack(spacing: 14) {
                    Text("This dashboard is empty")
                        .font(.title.bold())
                        .foregroundStyle(.white)

                    Text("Pick another dashboard or add cards in Home Assistant.")
                        .foregroundStyle(.white.opacity(0.72))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding(.horizontal, 64)
        .padding(.vertical, 40)
        .fullScreenCover(item: $presentedCamera) { camera in
            CameraFullScreenView(
                title: camera.title,
                url: viewModel.cameraStreamURL(for: camera.entityID)
            )
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .top, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(viewModel.selectedDashboard?.title ?? "Dashboard")
                        .font(.system(size: 44, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)

                    if let instanceInfo = viewModel.instanceInfo {
                        Text("\(instanceInfo.locationName) • \(instanceInfo.timeZone)")
                            .font(.headline.weight(.medium))
                            .foregroundStyle(.white.opacity(0.72))
                    }
                }

                Spacer()

                HStack(spacing: 14) {
                    Button("Dashboards", action: showDashboards)
                        .buttonStyle(.borderedProminent)
                        .tint(.white.opacity(0.16))

                    Button("Connection", action: changeConnection)
                        .buttonStyle(.borderedProminent)
                        .tint(.white.opacity(0.16))
                }
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    ForEach(viewModel.dashboardConfig?.views ?? []) { view in
                        Button {
                            viewModel.selectView(view)
                        } label: {
                            Text(view.displayTitle)
                                .font(.headline.weight(.bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 20)
                                .padding(.vertical, 12)
                                .background(
                                    (view.id == viewModel.currentView?.id ? Color.white.opacity(0.20) : Color.white.opacity(0.08)),
                                    in: Capsule()
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func cardGrid(for cards: [HAAnyConfig]) -> some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 28) {
            ForEach(cards) { card in
                DashboardCardView(
                    card: card,
                    viewModel: viewModel,
                    openCamera: { entityID, title in
                        presentedCamera = PresentedCamera(entityID: entityID, title: title)
                    }
                )
            }
        }
    }
}

private struct DashboardCardView: View {
    let card: HAAnyConfig
    @Bindable var viewModel: RootViewModel
    let openCamera: (String, String) -> Void

    var body: some View {
        DashboardCardContent(card: card, viewModel: viewModel, openCamera: openCamera)
    }
}

private struct PresentedCamera: Identifiable {
    let entityID: String
    let title: String

    var id: String { entityID }
}

private struct CameraFullScreenView: View {
    let title: String
    let url: URL?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()

            if let url {
                CameraPlayerView(url: url)
                    .ignoresSafeArea()
            } else {
                VStack(spacing: 16) {
                    Image(systemName: "video.slash.fill")
                        .font(.system(size: 60, weight: .bold))
                        .foregroundStyle(.white.opacity(0.8))
                    Text("Live stream unavailable")
                        .font(.title.bold())
                        .foregroundStyle(.white)
                }
            }

            HStack {
                VStack(alignment: .leading, spacing: 8) {
                    Text(title)
                        .font(.largeTitle.bold())
                        .foregroundStyle(.white)
                    Text("Press Menu to return")
                        .foregroundStyle(.white.opacity(0.72))
                }
                Spacer()
                Button("Close") {
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(40)
        }
    }
}

private struct CameraPlayerView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.showsPlaybackControls = true
        controller.player = AVPlayer(url: url)
        controller.player?.play()
        return controller
    }

    func updateUIViewController(_ controller: AVPlayerViewController, context: Context) {
        if (controller.player?.currentItem?.asset as? AVURLAsset)?.url != url {
            controller.player = AVPlayer(url: url)
            controller.player?.play()
        }
    }

    static func dismantleUIViewController(_ controller: AVPlayerViewController, coordinator: ()) {
        controller.player?.pause()
    }
}
