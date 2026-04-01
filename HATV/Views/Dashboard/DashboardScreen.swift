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
        switch card.type {
        case "entities":
            entitiesCard
        case "glance":
            glanceCard
        case "grid":
            nestedGridCard
        case "horizontal-stack":
            stackCard(axis: .horizontal)
        case "vertical-stack":
            stackCard(axis: .vertical)
        case "picture-entity", "picture-glance":
            cameraCard
        default:
            if let entityID = card.cameraEntityID, viewModel.state(for: entityID)?.domain == "camera" {
                cameraCard
            } else {
                actionTileCard
            }
        }
    }

    private var actionTileCard: some View {
        let state = viewModel.state(for: card.entityID)

        return Button {
            Task { await viewModel.executePrimaryAction(for: card) }
        } label: {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Image(systemName: state?.iconName ?? "square.grid.2x2.fill")
                        .font(.title.bold())
                        .foregroundStyle(.white)
                    Spacer()
                    Text(state?.displayState ?? "Ready")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(state?.isActive == true ? .green : .white.opacity(0.8))
                }

                Text(card.heading ?? state?.friendlyName ?? "Action")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.leading)

                if let subtitle = state?.subtitle ?? card.secondaryText {
                    Text(subtitle)
                        .font(.headline.weight(.medium))
                        .foregroundStyle(.white.opacity(0.72))
                }
            }
            .frame(maxWidth: .infinity, minHeight: 220, alignment: .topLeading)
            .padding(28)
            .background(cardBackground)
        }
        .buttonStyle(.plain)
    }

    private var entitiesCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            if let title = card.heading {
                Text(title)
                    .font(.title2.bold())
                    .foregroundStyle(.white)
            }

            ForEach(card.entities, id: \.entityID) { item in
                Button {
                    Task { await viewModel.executePrimaryAction(for: item) }
                } label: {
                    HStack(spacing: 16) {
                        let state = viewModel.state(for: item.entityID)

                        Image(systemName: state?.iconName ?? "circle.fill")
                            .font(.title3.weight(.bold))
                            .foregroundStyle(.white)
                            .frame(width: 44, height: 44)
                            .background(Color.white.opacity(0.10), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.name ?? state?.friendlyName ?? item.entityID)
                                .font(.headline.weight(.bold))
                                .foregroundStyle(.white)
                            if let subtitle = state?.subtitle {
                                Text(subtitle)
                                    .foregroundStyle(.white.opacity(0.68))
                            }
                        }

                        Spacer()

                        Text(state?.displayState ?? "Unavailable")
                            .font(.headline.weight(.bold))
                            .foregroundStyle(state?.isActive == true ? .green : .white.opacity(0.78))
                    }
                    .padding(18)
                    .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(28)
        .background(cardBackground)
    }

    private var glanceCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            if let title = card.heading {
                Text(title)
                    .font(.title2.bold())
                    .foregroundStyle(.white)
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 16)], spacing: 16) {
                ForEach(card.entities, id: \.entityID) { item in
                    let state = viewModel.state(for: item.entityID)

                    Button {
                        Task { await viewModel.executePrimaryAction(for: item) }
                    } label: {
                        VStack(spacing: 10) {
                            Image(systemName: state?.iconName ?? "circle.fill")
                                .font(.title.bold())
                                .foregroundStyle(.white)

                            Text(item.name ?? state?.friendlyName ?? item.entityID)
                                .font(.headline.weight(.bold))
                                .foregroundStyle(.white)
                                .multilineTextAlignment(.center)

                            Text(state?.displayState ?? "Unknown")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(state?.isActive == true ? .green : .white.opacity(0.7))
                        }
                        .frame(maxWidth: .infinity, minHeight: 170)
                        .padding(16)
                        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(28)
        .background(cardBackground)
    }

    private var nestedGridCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            if let title = card.heading {
                Text(title)
                    .font(.title2.bold())
                    .foregroundStyle(.white)
            }

            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 18), count: max(card.columns, 1)),
                spacing: 18
            ) {
                ForEach(card.childCards) { child in
                    DashboardCardView(card: child, viewModel: viewModel, openCamera: openCamera)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(28)
        .background(cardBackground)
    }

    @ViewBuilder
    private func stackCard(axis: Axis) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            if let title = card.heading {
                Text(title)
                    .font(.title2.bold())
                    .foregroundStyle(.white)
            }

            if axis == .horizontal {
                HStack(alignment: .top, spacing: 18) {
                    ForEach(card.childCards) { child in
                        DashboardCardView(card: child, viewModel: viewModel, openCamera: openCamera)
                    }
                }
            } else {
                VStack(spacing: 18) {
                    ForEach(card.childCards) { child in
                        DashboardCardView(card: child, viewModel: viewModel, openCamera: openCamera)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(28)
        .background(cardBackground)
    }

    private var cameraCard: some View {
        let entityID = card.cameraEntityID ?? ""
        let state = viewModel.state(for: entityID)
        let previewURL = viewModel.cameraPreviewURL(for: entityID)

        return Button {
            openCamera(entityID, state?.friendlyName ?? card.heading ?? "Camera")
        } label: {
            ZStack(alignment: .bottomLeading) {
                if let previewURL {
                    AsyncImage(url: previewURL) { image in
                        image
                            .resizable()
                            .scaledToFill()
                    } placeholder: {
                        Rectangle()
                            .fill(Color.white.opacity(0.06))
                            .overlay(ProgressView().tint(.white))
                    }
                } else {
                    Rectangle()
                        .fill(Color.white.opacity(0.06))
                }

                LinearGradient(
                    colors: [.clear, .black.opacity(0.85)],
                    startPoint: .top,
                    endPoint: .bottom
                )

                VStack(alignment: .leading, spacing: 10) {
                    Text(state?.friendlyName ?? card.heading ?? "Camera")
                        .font(.title2.bold())
                        .foregroundStyle(.white)

                    Text(state?.displayState ?? "Live")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(.white.opacity(0.8))

                    Label("Open full screen", systemImage: "arrow.up.left.and.arrow.down.right")
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.88))
                }
                .padding(24)
            }
            .frame(maxWidth: .infinity, minHeight: 260)
            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .strokeBorder(.white.opacity(0.14))
            )
        }
        .buttonStyle(.plain)
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 28, style: .continuous)
            .fill(.ultraThinMaterial)
            .overlay(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .strokeBorder(.white.opacity(0.12))
            )
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
