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
    @State private var isManagingVideoCameras = false
    @State private var isShowingHiddenVideoCameras = false

    private let dashboardColumns = [
        GridItem(.adaptive(minimum: 420, maximum: 520), spacing: 20, alignment: .top)
    ]
    private let videoColumns = [
        GridItem(.adaptive(minimum: 280, maximum: 340), spacing: 16, alignment: .top)
    ]

    var body: some View {
        ZStack(alignment: .top) {
            dashboardContent
                .padding(.top, isChromeVisible ? 124 : 10)

            if isChromeVisible {
                header
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .padding(.horizontal, 36)
        .padding(.vertical, 24)
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
            if !viewModel.isShowingVideoHub {
                isManagingVideoCameras = false
                isShowingHiddenVideoCameras = false
            }
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
            VStack(alignment: .leading, spacing: 18) {
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
                        if currentView.cards.contains(where: viewModel.shouldDisplayCard) {
                            cardGrid(for: currentView.cards)
                        } else {
                            emptyDashboardState
                        }
                    } else {
                        ForEach(currentView.sections.filter { $0.cards.contains(where: viewModel.shouldDisplayCard) }) { section in
                            VStack(alignment: .leading, spacing: 14) {
                                if let title = section.title, !title.isEmpty {
                                    Text(title)
                                        .font(.system(size: 22, weight: .bold, design: .rounded))
                                        .foregroundStyle(.white)
                                        .padding(.leading, 2)
                                }

                                cardGrid(for: section.cards)
                            }
                        }
                    }
                } else {
                    emptyDashboardState
                }
            }
            .padding(.bottom, 32)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(viewModel.selectedDashboard?.title ?? "Dashboard")
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)

                    if let instanceInfo = viewModel.instanceInfo {
                        Text("\(instanceInfo.locationName) • \(instanceInfo.timeZone)")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.60))
                    }
                }

                Spacer()

                HStack(spacing: 10) {
                    flatHeaderButton(title: "Dashboards", action: showDashboards)

                    flatHeaderButton(title: "Connection", action: changeConnection)
                }
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    Button {
                        Task { await viewModel.showVideoHub() }
                        revealChrome()
                    } label: {
                        flatTopTab(
                            title: "Video",
                            systemImage: "video.fill",
                            isSelected: viewModel.isShowingVideoHub
                        )
                    }
                    .buttonStyle(.plain)

                    ForEach(viewModel.dashboardConfig?.views ?? []) { view in
                        Button {
                            viewModel.selectView(view)
                            revealChrome()
                        } label: {
                            flatTopTab(
                                title: view.displayTitle,
                                isSelected: !viewModel.isShowingVideoHub && view.id == viewModel.currentView?.id
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(red: 0.05, green: 0.10, blue: 0.15), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(.white.opacity(0.08))
        )
        .background(alignment: .top) {
            LinearGradient(
                colors: [.black.opacity(0.30), .clear],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 150)
            .ignoresSafeArea(edges: .top)
        }
    }

    @ViewBuilder
    private func cardGrid(for cards: [HAAnyConfig]) -> some View {
        LazyVGrid(columns: dashboardColumns, alignment: .leading, spacing: 18) {
            ForEach(cards.filter(viewModel.shouldDisplayCard)) { card in
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
        let visibleCameras = viewModel.visibleCameraStates
        let hiddenCameras = viewModel.hiddenCameraStates
        let displayedCameras = isShowingHiddenVideoCameras ? hiddenCameras : visibleCameras

        if viewModel.allCameraStates.isEmpty {
            VStack(spacing: 12) {
                Text("No cameras are available")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)

                Text("Add camera entities in Home Assistant to populate the video wall.")
                    .font(.headline.weight(.medium))
                    .foregroundStyle(.white.opacity(0.68))
            }
            .frame(maxWidth: .infinity, minHeight: 320)
        } else {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .center, spacing: 14) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(isShowingHiddenVideoCameras ? "Hidden cameras" : "Video wall")
                            .font(.system(size: 20, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)

                        Text(isManagingVideoCameras
                             ? (isShowingHiddenVideoCameras
                                ? "Select a camera to restore it to the dashboard and video wall."
                                : "Select a camera to hide it from the dashboard and video wall.")
                             : "Jump into any live feed and keep the wall clean.")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.64))
                    }

                    Spacer()

                    HStack(spacing: 10) {
                        if !hiddenCameras.isEmpty {
                            Button(isShowingHiddenVideoCameras ? "Visible" : "Hidden \(hiddenCameras.count)") {
                                isShowingHiddenVideoCameras.toggle()
                                isManagingVideoCameras = false
                            }
                            .buttonStyle(.plain)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 9)
                            .background(Color.white.opacity(isShowingHiddenVideoCameras ? 0.14 : 0.06), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }

                        Button(isManagingVideoCameras ? "Done" : "Manage") {
                            isManagingVideoCameras.toggle()
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)
                        .background(Color.white.opacity(isManagingVideoCameras ? 0.14 : 0.06), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    .foregroundStyle(.white)
                    .font(.subheadline.weight(.bold))
                }

                if displayedCameras.isEmpty {
                    VStack(spacing: 12) {
                        Text(isShowingHiddenVideoCameras ? "No hidden cameras" : "All cameras are hidden")
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)

                        Text(isShowingHiddenVideoCameras
                             ? "Hidden cameras will appear here so you can restore them."
                             : "Open Hidden to bring a camera back.")
                            .font(.headline.weight(.medium))
                            .foregroundStyle(.white.opacity(0.68))
                    }
                    .frame(maxWidth: .infinity, minHeight: 240)
                    .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                } else {
                    LazyVGrid(columns: videoColumns, alignment: .leading, spacing: 18) {
                        ForEach(displayedCameras) { camera in
                            DashboardCameraTile(
                                title: camera.friendlyName,
                                subtitle: isManagingVideoCameras
                                    ? (isShowingHiddenVideoCameras ? "Hidden" : "Visible")
                                    : camera.displayState,
                                detail: isManagingVideoCameras
                                    ? (isShowingHiddenVideoCameras ? "Restore camera" : "Hide camera")
                                    : (camera.subtitle ?? "Open full screen"),
                                previewURL: viewModel.cameraPreviewURL(for: camera.entityID),
                                badgeText: isManagingVideoCameras
                                    ? (isShowingHiddenVideoCameras ? "RESTORE" : "HIDE")
                                    : "LIVE",
                                tint: isManagingVideoCameras
                                    ? (isShowingHiddenVideoCameras ? .green : .orange)
                                    : .cyan,
                                isDimmed: isShowingHiddenVideoCameras
                            ) {
                                if isManagingVideoCameras {
                                    if isShowingHiddenVideoCameras {
                                        viewModel.unhideCamera(camera.entityID)
                                    } else {
                                        viewModel.hideCamera(camera.entityID)
                                    }
                                } else {
                                    presentCamera(entityID: camera.entityID, title: camera.friendlyName)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private var emptyDashboardState: some View {
        VStack(spacing: 12) {
            Text("This dashboard is empty")
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundStyle(.white)

            Text("Pick another dashboard or add cards in Home Assistant.")
                .font(.headline.weight(.medium))
                .foregroundStyle(.white.opacity(0.68))
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
        HStack(alignment: .top, spacing: 20) {
            VStack(alignment: .leading, spacing: 10) {
                Text(title)
                    .font(.system(size: 38, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)

                Text(subtitle)
                    .font(.headline.weight(.medium))
                    .foregroundStyle(.white.opacity(0.70))

                HStack(spacing: 10) {
                    KioskInfoPill(title: "Cameras", value: "\(cameraCount)", tint: .cyan)
                    KioskInfoPill(title: "Lights On", value: "\(lightsOnCount)", tint: .yellow)
                    KioskInfoPill(title: "Climate", value: "\(activeClimateCount)", tint: .orange)
                    KioskInfoPill(title: "Media", value: "\(activeMediaCount)", tint: .pink)
                }
            }

            Spacer()

            TimelineView(.periodic(from: .now, by: 60)) { context in
                VStack(alignment: .trailing, spacing: 6) {
                    Text(context.date, format: .dateTime.hour().minute())
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)

                    Text(context.date, format: .dateTime.weekday(.wide).month(.wide).day())
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.white.opacity(0.64))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .background(accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(.white.opacity(0.08))
                )
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(red: 0.06, green: 0.11, blue: 0.16))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(accent.opacity(0.18))
        )
    }
}

private struct KioskInfoPill: View {
    let title: String
    let value: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.64))

            Text(value)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

@ViewBuilder
private func flatHeaderButton(title: String, action: @escaping () -> Void) -> some View {
    Button(title, action: action)
        .buttonStyle(.plain)
        .font(.subheadline.weight(.bold))
        .foregroundStyle(.white)
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(.white.opacity(0.08))
        )
}

@ViewBuilder
private func flatTopTab(title: String, systemImage: String? = nil, isSelected: Bool) -> some View {
    Group {
        if let systemImage {
            Label(title, systemImage: systemImage)
        } else {
            Text(title)
        }
    }
    .font(.subheadline.weight(.bold))
    .foregroundStyle(.white)
    .padding(.horizontal, 14)
    .padding(.vertical, 9)
    .background(
        isSelected ? Color.white.opacity(0.14) : Color.white.opacity(0.05),
        in: RoundedRectangle(cornerRadius: 10, style: .continuous)
    )
    .overlay(
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .strokeBorder(.white.opacity(isSelected ? 0.16 : 0.07))
    )
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
                    .font(.system(size: 32, weight: .bold, design: .rounded))
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
        .padding(.bottom, 16)
        .background(Color.black.opacity(0.24))
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
        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
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
        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(.white.opacity(0.10))
        )
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
