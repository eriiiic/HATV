import AVKit
import Observation
import SwiftUI

struct DashboardScreen: View {
    @Bindable var viewModel: RootViewModel
    let showDashboards: () -> Void
    let changeConnection: () -> Void

    @State private var presentedCamera: PresentedCamera?
    @State private var isChromeVisible = true
    @State private var chromeAutoHideTask: Task<Void, Never>?

    private let dashboardColumns = [
        GridItem(.adaptive(minimum: 430, maximum: 560), spacing: 28, alignment: .top)
    ]
    private let videoColumns = [
        GridItem(.adaptive(minimum: 360, maximum: 480), spacing: 24, alignment: .top)
    ]

    var body: some View {
        ZStack(alignment: .top) {
            dashboardContent
                .padding(.top, isChromeVisible ? 188 : 20)

            if isChromeVisible {
                header
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .padding(.horizontal, 64)
        .padding(.vertical, 40)
        .animation(.easeInOut(duration: 0.28), value: isChromeVisible)
        .onAppear {
            revealChrome()
        }
        .onDisappear {
            cancelChromeAutoHide()
        }
        .onChange(of: viewModel.selectedViewIndex) { _, _ in
            revealChrome()
        }
        .onChange(of: viewModel.isShowingVideoHub) { _, _ in
            revealChrome()
        }
        .onChange(of: presentedCamera) { _, camera in
            if camera == nil {
                revealChrome()
            } else {
                cancelChromeAutoHide()
            }
        }
        .onPlayPauseCommand {
            revealChrome()
        }
        .onExitCommand {
            if isChromeVisible {
                showDashboards()
            } else {
                revealChrome()
            }
        }
        .fullScreenCover(item: $presentedCamera) { camera in
            CameraFullScreenView(
                title: camera.title,
                entityID: camera.entityID,
                viewModel: viewModel
            )
        }
    }

    @ViewBuilder
    private var dashboardContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                KioskOverviewBanner(
                    title: heroTitle,
                    subtitle: heroSubtitle,
                    cameraCount: viewModel.allCameraStates.count,
                    lightsOnCount: viewModel.lightsOnCount,
                    activeClimateCount: viewModel.activeClimateCount,
                    activeMediaCount: viewModel.activeMediaCount,
                    accent: viewModel.isShowingVideoHub ? .cyan : .white
                )

                if viewModel.isShowingVideoHub {
                    videoHubContent
                } else if let currentView = viewModel.currentView {
                    if currentView.sections.isEmpty {
                        cardGrid(for: currentView.cards)
                    } else {
                        ForEach(currentView.sections) { section in
                            VStack(alignment: .leading, spacing: 18) {
                                if let title = section.title, !title.isEmpty {
                                    Text(title)
                                        .font(.system(size: 28, weight: .bold, design: .rounded))
                                        .foregroundStyle(.white)
                                }

                                cardGrid(for: section.cards)
                            }
                        }
                    }
                } else {
                    emptyDashboardState
                }
            }
            .padding(.bottom, 48)
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
                    Button {
                        Task { await viewModel.showVideoHub() }
                        revealChrome()
                    } label: {
                        Label("Video", systemImage: "video.fill")
                            .font(.headline.weight(.bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 12)
                            .background(
                                (viewModel.isShowingVideoHub ? Color.white.opacity(0.20) : Color.white.opacity(0.08)),
                                in: Capsule()
                            )
                    }
                    .buttonStyle(.plain)

                    ForEach(viewModel.dashboardConfig?.views ?? []) { view in
                        Button {
                            viewModel.selectView(view)
                            revealChrome()
                        } label: {
                            Text(view.displayTitle)
                                .font(.headline.weight(.bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 20)
                                .padding(.vertical, 12)
                                .background(
                                    ((!viewModel.isShowingVideoHub && view.id == viewModel.currentView?.id) ? Color.white.opacity(0.20) : Color.white.opacity(0.08)),
                                    in: Capsule()
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(.bottom, 20)
        .background(alignment: .top) {
            LinearGradient(
                colors: [.black.opacity(0.42), .clear],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 220)
            .ignoresSafeArea(edges: .top)
        }
    }

    @ViewBuilder
    private func cardGrid(for cards: [HAAnyConfig]) -> some View {
        LazyVGrid(columns: dashboardColumns, alignment: .leading, spacing: 28) {
            ForEach(cards) { card in
                DashboardCardView(
                    card: card,
                    viewModel: viewModel,
                    openCamera: { entityID, title in
                        presentCamera(entityID: entityID, title: title)
                    }
                )
            }
        }
    }

    @ViewBuilder
    private var videoHubContent: some View {
        if viewModel.allCameraStates.isEmpty {
            VStack(spacing: 14) {
                Text("No cameras are available")
                    .font(.title.bold())
                    .foregroundStyle(.white)

                Text("Add camera entities in Home Assistant to populate the video wall.")
                    .foregroundStyle(.white.opacity(0.72))
            }
            .frame(maxWidth: .infinity, minHeight: 320)
        } else {
            VStack(alignment: .leading, spacing: 20) {
                Text("All video streams")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)

                Text("Jump into any live feed and stay in fullscreen until you need the controls.")
                    .font(.headline.weight(.medium))
                    .foregroundStyle(.white.opacity(0.72))

                LazyVGrid(columns: videoColumns, alignment: .leading, spacing: 24) {
                    ForEach(viewModel.allCameraStates) { camera in
                        DashboardCameraTile(
                            title: camera.friendlyName,
                            subtitle: camera.displayState,
                            detail: camera.subtitle ?? "Open full screen",
                            previewURL: viewModel.cameraPreviewURL(for: camera.entityID)
                        ) {
                            presentCamera(entityID: camera.entityID, title: camera.friendlyName)
                        }
                    }
                }
            }
        }
    }

    private var emptyDashboardState: some View {
        VStack(spacing: 14) {
            Text("This dashboard is empty")
                .font(.title.bold())
                .foregroundStyle(.white)

            Text("Pick another dashboard or add cards in Home Assistant.")
                .foregroundStyle(.white.opacity(0.72))
        }
        .frame(maxWidth: .infinity, minHeight: 320)
    }

    private var heroTitle: String {
        if viewModel.isShowingVideoHub {
            return "Video Wall"
        }

        return viewModel.currentView?.displayTitle
            ?? viewModel.selectedDashboard?.title
            ?? "Dashboard"
    }

    private var heroSubtitle: String {
        if viewModel.isShowingVideoHub {
            return "Every Home Assistant camera in one native fullscreen hub."
        }

        if let dashboardTitle = viewModel.selectedDashboard?.title {
            return "Kiosk view for \(dashboardTitle)."
        }

        return "Home Assistant companion for Apple TV."
    }

    private func presentCamera(entityID: String, title: String) {
        revealChrome()
        presentedCamera = PresentedCamera(entityID: entityID, title: title)
    }

    private func revealChrome() {
        withAnimation(.easeOut(duration: 0.24)) {
            isChromeVisible = true
        }
        scheduleChromeAutoHide()
    }

    private func scheduleChromeAutoHide() {
        cancelChromeAutoHide()
        chromeAutoHideTask = Task {
            try? await Task.sleep(for: .seconds(7))
            guard !Task.isCancelled else { return }

            await MainActor.run {
                withAnimation(.easeInOut(duration: 0.3)) {
                    isChromeVisible = false
                }
            }
        }
    }

    private func cancelChromeAutoHide() {
        chromeAutoHideTask?.cancel()
        chromeAutoHideTask = nil
    }
}

private struct KioskOverviewBanner: View {
    let title: String
    let subtitle: String
    let cameraCount: Int
    let lightsOnCount: Int
    let activeClimateCount: Int
    let activeMediaCount: Int
    let accent: Color

    var body: some View {
        HStack(alignment: .top, spacing: 28) {
            VStack(alignment: .leading, spacing: 14) {
                Text(title)
                    .font(.system(size: 56, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)

                Text(subtitle)
                    .font(.title3.weight(.medium))
                    .foregroundStyle(.white.opacity(0.76))

                HStack(spacing: 12) {
                    KioskInfoPill(title: "Cameras", value: "\(cameraCount)", tint: .cyan)
                    KioskInfoPill(title: "Lights On", value: "\(lightsOnCount)", tint: .yellow)
                    KioskInfoPill(title: "Climate", value: "\(activeClimateCount)", tint: .orange)
                    KioskInfoPill(title: "Media", value: "\(activeMediaCount)", tint: .pink)
                }
            }

            Spacer()

            TimelineView(.periodic(from: .now, by: 60)) { context in
                VStack(alignment: .trailing, spacing: 8) {
                    Text(context.date, format: .dateTime.hour().minute())
                        .font(.system(size: 54, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)

                    Text(context.date, format: .dateTime.weekday(.wide).month(.wide).day())
                        .font(.headline.weight(.medium))
                        .foregroundStyle(.white.opacity(0.74))
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 22)
                .background(accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 28, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .strokeBorder(.white.opacity(0.10))
                )
            }
        }
        .padding(32)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 34, style: .continuous)
                    .fill(.ultraThinMaterial)

                LinearGradient(
                    colors: [accent.opacity(0.16), .clear, .black.opacity(0.08)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .clipShape(RoundedRectangle(cornerRadius: 34, style: .continuous))
            }
        )
        .overlay(
            RoundedRectangle(cornerRadius: 34, style: .continuous)
                .strokeBorder(.white.opacity(0.12))
        )
    }
}

private struct KioskInfoPill: View {
    let title: String
    let value: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.64))

            Text(value)
                .font(.headline.weight(.bold))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(tint.opacity(0.22), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
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

private struct PresentedCamera: Identifiable, Equatable {
    let entityID: String
    let title: String

    var id: String { entityID }
}

private struct CameraFullScreenView: View {
    let title: String
    let entityID: String
    @Bindable var viewModel: RootViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var streamURL: URL?
    @State private var playbackState: CameraPlaybackState = .loading
    @State private var errorMessage: String?
    @State private var reloadToken = UUID()
    @State private var isChromeVisible = true
    @State private var chromeAutoHideTask: Task<Void, Never>?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let streamURL {
                CameraPlayerView(url: streamURL) { state in
                    playbackState = state
                    if case .failed(let message) = state {
                        errorMessage = message
                    } else {
                        errorMessage = nil
                    }
                }
                    .ignoresSafeArea()
            }

            if streamURL == nil || errorMessage != nil {
                unavailableStateView
            }

            if playbackState == .loading {
                loadingOverlay
            }

            if shouldShowChrome {
                VStack(spacing: 0) {
                    LinearGradient(
                        colors: [.black.opacity(0.72), .clear],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 180)
                    .overlay(alignment: .top) {
                        header
                    }

                    Spacer()
                }
                .ignoresSafeArea()
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.28), value: shouldShowChrome)
        .task(id: reloadToken) {
            await loadStream(refresh: streamURL != nil)
        }
        .onAppear {
            revealChrome()
        }
        .onDisappear {
            cancelChromeAutoHide()
        }
        .onChange(of: playbackState) { _, newValue in
            updateChromeVisibility(for: newValue)
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 10) {
                Text(title)
                    .font(.largeTitle.bold())
                    .foregroundStyle(.white)

                HStack(spacing: 12) {
                    Label(statusText, systemImage: playbackState == .playing ? "dot.radiowaves.left.and.right" : "clock")
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.86))

                    Text("Press Menu to return")
                        .font(.headline.weight(.medium))
                        .foregroundStyle(.white.opacity(0.66))
                }
            }

            Spacer()

            HStack(spacing: 12) {
                Button("Refresh") {
                    reloadToken = UUID()
                }
                .buttonStyle(.borderedProminent)
                .tint(.white.opacity(0.18))

                Button("Close") {
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .tint(.white.opacity(0.28))
            }
        }
        .padding(.horizontal, 40)
        .padding(.top, 34)
    }

    private var loadingOverlay: some View {
        VStack(spacing: 14) {
            ProgressView()
                .tint(.white)
                .scaleEffect(1.2)

            Text("Buffering live stream…")
                .font(.headline.weight(.semibold))
                .foregroundStyle(.white.opacity(0.88))
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 22)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private var unavailableStateView: some View {
        VStack(spacing: 18) {
            Image(systemName: "video.slash.fill")
                .font(.system(size: 60, weight: .bold))
                .foregroundStyle(.white.opacity(0.82))

            Text(errorMessage ?? "Live stream unavailable")
                .font(.title.bold())
                .foregroundStyle(.white)

            Text("The stream may need a fresh signed URL from Home Assistant.")
                .font(.headline.weight(.medium))
                .foregroundStyle(.white.opacity(0.72))
                .multilineTextAlignment(.center)

            Button("Retry stream") {
                reloadToken = UUID()
            }
            .buttonStyle(.borderedProminent)
            .tint(.white.opacity(0.22))
        }
        .padding(40)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
    }

    private var statusText: String {
        switch playbackState {
        case .idle:
            return "Preparing"
        case .loading:
            return "Buffering"
        case .playing:
            return "Live"
        case .failed:
            return "Needs refresh"
        }
    }

    private var shouldShowChrome: Bool {
        isChromeVisible || playbackState != .playing || errorMessage != nil || streamURL == nil
    }

    private func loadStream(refresh: Bool) async {
        let previousURL = streamURL
        playbackState = .loading
        errorMessage = nil

        do {
            streamURL = try await viewModel.loadCameraStreamURL(for: entityID, refresh: refresh)
        } catch {
            streamURL = previousURL
            playbackState = .failed(error.localizedDescription)
            errorMessage = error.localizedDescription
        }
    }

    private func updateChromeVisibility(for state: CameraPlaybackState) {
        switch state {
        case .playing:
            scheduleChromeAutoHide()
        case .idle, .loading, .failed:
            revealChrome()
        }
    }

    private func revealChrome() {
        withAnimation(.easeOut(duration: 0.24)) {
            isChromeVisible = true
        }

        if playbackState == .playing, errorMessage == nil, streamURL != nil {
            scheduleChromeAutoHide()
        } else {
            cancelChromeAutoHide()
        }
    }

    private func scheduleChromeAutoHide() {
        cancelChromeAutoHide()
        chromeAutoHideTask = Task {
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }

            await MainActor.run {
                guard playbackState == .playing, errorMessage == nil, streamURL != nil else {
                    return
                }

                withAnimation(.easeInOut(duration: 0.3)) {
                    isChromeVisible = false
                }
            }
        }
    }

    private func cancelChromeAutoHide() {
        chromeAutoHideTask?.cancel()
        chromeAutoHideTask = nil
    }
}

private enum CameraPlaybackState: Equatable {
    case idle
    case loading
    case playing
    case failed(String)
}

private struct CameraPlayerView: UIViewControllerRepresentable {
    let url: URL
    let playbackStateChanged: @MainActor (CameraPlaybackState) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(playbackStateChanged: playbackStateChanged)
    }

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.showsPlaybackControls = true
        controller.requiresLinearPlayback = false
        context.coordinator.attach(to: controller, url: url)
        return controller
    }

    func updateUIViewController(_ controller: AVPlayerViewController, context: Context) {
        context.coordinator.attach(to: controller, url: url)
    }

    static func dismantleUIViewController(_ controller: AVPlayerViewController, coordinator: Coordinator) {
        coordinator.invalidate()
        controller.player?.pause()
    }

    final class Coordinator: NSObject {
        private let playbackStateChanged: @MainActor (CameraPlaybackState) -> Void
        private var currentURL: URL?
        private var itemStatusObservation: NSKeyValueObservation?
        private var playerStatusObservation: NSKeyValueObservation?

        init(playbackStateChanged: @escaping @MainActor (CameraPlaybackState) -> Void) {
            self.playbackStateChanged = playbackStateChanged
        }

        func attach(to controller: AVPlayerViewController, url: URL) {
            guard currentURL != url || controller.player == nil else {
                return
            }

            currentURL = url
            invalidate()

            let player = controller.player ?? AVPlayer()
            player.automaticallyWaitsToMinimizeStalling = true

            let item = AVPlayerItem(url: url)
            observe(item: item, player: player)

            player.replaceCurrentItem(with: item)
            controller.player = player

            Task { @MainActor in
                playbackStateChanged(.loading)
            }

            player.play()
        }

        func invalidate() {
            itemStatusObservation?.invalidate()
            itemStatusObservation = nil
            playerStatusObservation?.invalidate()
            playerStatusObservation = nil
        }

        private func observe(item: AVPlayerItem, player: AVPlayer) {
            itemStatusObservation = item.observe(\.status, options: [.initial, .new]) { [weak self] observedItem, _ in
                guard let self else { return }

                Task { @MainActor in
                    switch observedItem.status {
                    case .readyToPlay:
                        self.playbackStateChanged(.loading)
                    case .failed:
                        self.playbackStateChanged(.failed(observedItem.error?.localizedDescription ?? "Unable to start the live stream."))
                    case .unknown:
                        self.playbackStateChanged(.loading)
                    @unknown default:
                        self.playbackStateChanged(.loading)
                    }
                }
            }

            playerStatusObservation = player.observe(\.timeControlStatus, options: [.initial, .new]) { [weak self] observedPlayer, _ in
                guard let self else { return }

                Task { @MainActor in
                    switch observedPlayer.timeControlStatus {
                    case .playing:
                        self.playbackStateChanged(.playing)
                    case .waitingToPlayAtSpecifiedRate:
                        self.playbackStateChanged(.loading)
                    case .paused:
                        break
                    @unknown default:
                        self.playbackStateChanged(.loading)
                    }
                }
            }
        }
    }
}
