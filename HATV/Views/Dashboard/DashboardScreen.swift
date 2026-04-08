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
    @State private var selectedVideoAreaName: String?
    @State private var isShowingFavoriteVideoCameras = false
    @State private var videoManageMode: VideoHubManageMode = .hide
    @State private var isShowingDiagnostics = false
    @State private var headerHeight: CGFloat = 0

    var body: some View {
        GeometryReader { proxy in
            let contentWidth = max(proxy.size.width - 64, 0)

            ZStack(alignment: .top) {
                dashboardContent(contentWidth: contentWidth)
                    .padding(.top, isChromeVisible ? headerHeight + 10 : 8)

                if isChromeVisible {
                    header(contentWidth: contentWidth)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
            .padding(.horizontal, 32)
            .padding(.vertical, 20)
        }
        .animation(.easeInOut(duration: 0.28), value: isChromeVisible)
        .onPreferenceChange(DashboardHeaderHeightPreferenceKey.self) { height in
            guard height > 0, abs(height - headerHeight) > 1 else { return }
            headerHeight = height
        }
        .onAppear {
            revealChrome()
            applyExternalCameraRequestIfNeeded()
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
                isShowingFavoriteVideoCameras = false
                selectedVideoAreaName = nil
            }
            revealChrome()
            applyExternalCameraRequestIfNeeded()
        }
        .onChange(of: viewModel.externalCameraPresentation) { _, _ in
            applyExternalCameraRequestIfNeeded()
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
                presentation: camera,
                viewModel: viewModel,
                advance: { nextIndex in
                    presentedCamera = camera.withCurrentIndex(nextIndex)
                },
                close: {
                    presentedCamera = nil
                }
            )
        }
        .sheet(isPresented: $isShowingDiagnostics) {
            DashboardDiagnosticsView(viewModel: viewModel)
        }
    }

    @ViewBuilder
    private func dashboardContent(contentWidth: CGFloat) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                KioskOverviewBanner(
                    title: heroTitle,
                    subtitle: heroSubtitle,
                    cameraCount: viewModel.allCameraStates.count,
                    lightsOnCount: viewModel.lightsOnCount,
                    activeClimateCount: viewModel.activeClimateCount,
                    activeMediaCount: viewModel.activeMediaCount,
                    accent: viewModel.isShowingVideoHub ? .cyan : .white
                )
                .frame(maxWidth: .infinity, alignment: .leading)

                if viewModel.isShowingVideoHub {
                    videoHubContent(contentWidth: contentWidth)
                } else if let currentView = viewModel.currentView {
                    if currentView.sections.isEmpty {
                        if currentView.cards.contains(where: viewModel.shouldDisplayCard) {
                            cardGrid(
                                for: currentView.cards,
                                contentWidth: contentWidth,
                                viewMaxColumns: currentView.maxColumns
                            )
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

                                cardGrid(
                                    for: section.cards,
                                    contentWidth: contentWidth,
                                    viewMaxColumns: currentView.maxColumns
                                )
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                } else {
                    emptyDashboardState
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func header(contentWidth: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(viewModel.selectedDashboard?.title ?? "Dashboard")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)

                    if let instanceInfo = viewModel.instanceInfo {
                        Text("\(instanceInfo.locationName) • \(instanceInfo.timeZone)")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.58))
                    }
                }

                Spacer()

                HStack(spacing: 8) {
                    DashboardHeaderActionButton(title: "Dashboards", action: showDashboards)
                    DashboardHeaderActionButton(title: "Diagnostics") {
                        isShowingDiagnostics = true
                    }

                    DashboardHeaderActionButton(title: "Connection", action: changeConnection)
                }
                .focusSection()
            }

            navigationRail(contentWidth: contentWidth)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color(red: 0.05, green: 0.10, blue: 0.15), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(.white.opacity(0.07))
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
        .background(DashboardHeaderHeightReader())
    }

    @ViewBuilder
    private func cardGrid(
        for cards: [HAAnyConfig],
        contentWidth: CGFloat,
        viewMaxColumns: Int?
    ) -> some View {
        let visibleCards = cards.filter(viewModel.shouldDisplayCard)
        let maxColumns = maxDashboardColumnCount(for: contentWidth, viewMaxColumns: viewMaxColumns)
        let rows = dashboardRows(for: visibleCards, maxColumns: maxColumns)

        LazyVStack(alignment: .leading, spacing: dashboardGridSpacing) {
            ForEach(rows) { row in
                HStack(alignment: .top, spacing: dashboardGridSpacing) {
                    ForEach(row.items) { item in
                        DashboardCardView(
                            card: item.card,
                            viewModel: viewModel,
                            openCamera: { entityID, title in
                                presentCamera(entityID: entityID, title: title)
                            }
                        )
                        .frame(
                            width: dashboardItemWidth(
                                for: item.span,
                                maxColumns: maxColumns,
                                contentWidth: contentWidth
                            ),
                            alignment: .topLeading
                        )
                    }
                }
                .focusSection()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .focusSection()
    }

    @ViewBuilder
    private func videoHubContent(contentWidth: CGFloat) -> some View {
        let visibleCameras = viewModel.visibleCameraStates
        let hiddenCameras = viewModel.hiddenCameraStates
        let baseCameras = isShowingHiddenVideoCameras ? hiddenCameras : visibleCameras
        let favoriteFilteredCameras = isShowingFavoriteVideoCameras
            ? baseCameras.filter { viewModel.isCameraFavorite($0.entityID) }
            : baseCameras
        let displayedCameras = selectedVideoAreaName.map { areaName in
            favoriteFilteredCameras.filter { viewModel.cameraAreaName(for: $0.entityID) == areaName }
        } ?? favoriteFilteredCameras
        let columnCount = videoColumnCount(for: displayedCameras.count, contentWidth: contentWidth)
        let videoSections = groupedVideoSections(from: displayedCameras)

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
                                : (videoManageMode == .favorite
                                    ? "Select a camera to add or remove it from favorites."
                                    : "Select a camera to hide it from the dashboard and video wall."))
                             : "Open any feed full screen, tour favorites, or filter by area.")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.64))
                    }

                    Spacer()

                    HStack(spacing: 10) {
                        if !displayedCameras.isEmpty, !isManagingVideoCameras {
                            Button {
                                startCameraTour(with: displayedCameras)
                            } label: {
                                DashboardUtilityButtonLabel(title: "Tour", isActive: false)
                            }
                            .buttonStyle(.plain)
                            .focusEffectDisabled()
                        }

                        if !hiddenCameras.isEmpty {
                            Button {
                                isShowingHiddenVideoCameras.toggle()
                                isManagingVideoCameras = false
                                if isShowingHiddenVideoCameras {
                                    isShowingFavoriteVideoCameras = false
                                    selectedVideoAreaName = nil
                                }
                            } label: {
                                DashboardUtilityButtonLabel(
                                    title: isShowingHiddenVideoCameras ? "Visible" : "Hidden \(hiddenCameras.count)",
                                    isActive: isShowingHiddenVideoCameras
                                )
                            }
                            .buttonStyle(.plain)
                            .focusEffectDisabled()
                        }

                        Button {
                            isManagingVideoCameras.toggle()
                        } label: {
                            DashboardUtilityButtonLabel(
                                title: isManagingVideoCameras ? "Done" : "Manage",
                                isActive: isManagingVideoCameras
                            )
                        }
                        .buttonStyle(.plain)
                        .focusEffectDisabled()
                    }
                    .focusSection()
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        Button {
                            isShowingFavoriteVideoCameras = false
                            selectedVideoAreaName = nil
                        } label: {
                            DashboardTopTab(
                                title: "All",
                                isSelected: !isShowingFavoriteVideoCameras && selectedVideoAreaName == nil
                            )
                        }
                        .buttonStyle(.plain)
                        .focusEffectDisabled()

                        if !viewModel.favoriteCameraStates.isEmpty {
                            Button {
                                isShowingFavoriteVideoCameras = true
                                selectedVideoAreaName = nil
                            } label: {
                                DashboardTopTab(
                                    title: "Favorites",
                                    systemImage: "star.fill",
                                    isSelected: isShowingFavoriteVideoCameras
                                )
                            }
                            .buttonStyle(.plain)
                            .focusEffectDisabled()
                        }

                        ForEach(viewModel.availableCameraAreas, id: \.self) { areaName in
                            Button {
                                isShowingFavoriteVideoCameras = false
                                selectedVideoAreaName = areaName
                            } label: {
                                DashboardTopTab(
                                    title: areaName,
                                    isSelected: selectedVideoAreaName == areaName
                                )
                            }
                            .buttonStyle(.plain)
                            .focusEffectDisabled()
                        }
                    }
                    .padding(6)
                    .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(.white.opacity(0.06))
                    )
                    .focusSection()
                }

                if isManagingVideoCameras && !isShowingHiddenVideoCameras {
                    HStack(spacing: 8) {
                        Button {
                            videoManageMode = .favorite
                        } label: {
                            DashboardTopTab(
                                title: "Favorite",
                                systemImage: "star.fill",
                                isSelected: videoManageMode == .favorite
                            )
                        }
                        .buttonStyle(.plain)
                        .focusEffectDisabled()

                        Button {
                            videoManageMode = .hide
                        } label: {
                            DashboardTopTab(
                                title: "Hide",
                                systemImage: "eye.slash.fill",
                                isSelected: videoManageMode == .hide
                            )
                        }
                        .buttonStyle(.plain)
                        .focusEffectDisabled()
                    }
                    .focusSection()
                }

                if displayedCameras.isEmpty {
                    VStack(spacing: 12) {
                        Text(isShowingHiddenVideoCameras ? "No hidden cameras" : "No cameras match this filter")
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)

                        Text(isShowingHiddenVideoCameras
                             ? "Hidden cameras will appear here so you can restore them."
                             : "Try another area, switch back to All, or open Hidden to restore a camera.")
                            .font(.headline.weight(.medium))
                            .foregroundStyle(.white.opacity(0.68))
                    }
                    .frame(maxWidth: .infinity, minHeight: 240)
                    .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                } else {
                    VStack(alignment: .leading, spacing: 18) {
                        ForEach(videoSections) { section in
                            VStack(alignment: .leading, spacing: 12) {
                                if let title = section.title {
                                    HStack(alignment: .center, spacing: 10) {
                                        Text(title)
                                            .font(.headline.weight(.bold))
                                            .foregroundStyle(.white)

                                        Text("\(section.cameras.count)")
                                            .font(.caption.weight(.bold))
                                            .foregroundStyle(.white.opacity(0.62))
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 4)
                                            .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                                    }
                                }

                                videoGrid(for: section.cameras, columnCount: columnCount, contentWidth: contentWidth)
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
        presentCamera(entityIDs: [entityID], startingAt: 0, autoAdvance: false)
    }

    private func presentCamera(entityIDs: [String], startingAt index: Int, autoAdvance: Bool) {
        let normalizedEntityIDs = entityIDs.filter { !$0.isEmpty }
        guard !normalizedEntityIDs.isEmpty else { return }

        revealChrome()
        presentedCamera = PresentedCamera(
            cameraEntityIDs: normalizedEntityIDs,
            currentIndex: min(max(index, 0), normalizedEntityIDs.count - 1),
            autoAdvance: autoAdvance
        )
    }

    private func applyExternalCameraRequestIfNeeded() {
        guard let request = viewModel.externalCameraPresentation else { return }

        presentCamera(
            entityIDs: request.entityIDs,
            startingAt: request.startingIndex,
            autoAdvance: request.autoAdvance
        )
        viewModel.externalCameraPresentation = nil
    }

    private func startCameraTour(with cameras: [HAEntityState]) {
        let entityIDs = cameras.map(\.entityID)
        presentCamera(entityIDs: entityIDs, startingAt: 0, autoAdvance: true)
    }

    private func performManageAction(for camera: HAEntityState) {
        if isShowingHiddenVideoCameras {
            viewModel.unhideCamera(camera.entityID)
            return
        }

        switch videoManageMode {
        case .hide:
            viewModel.hideCamera(camera.entityID)
        case .favorite:
            viewModel.toggleFavoriteCamera(camera.entityID)
        }
    }

    private func videoManageBadge(for camera: HAEntityState) -> String {
        if isShowingHiddenVideoCameras {
            return "RESTORE"
        }

        switch videoManageMode {
        case .hide:
            return "HIDE"
        case .favorite:
            return viewModel.isCameraFavorite(camera.entityID) ? "STARRED" : "FAVORITE"
        }
    }

    private func videoManageDetail(for camera: HAEntityState) -> String {
        if isShowingHiddenVideoCameras {
            return "Restore camera"
        }

        switch videoManageMode {
        case .hide:
            return "Hide camera"
        case .favorite:
            return viewModel.isCameraFavorite(camera.entityID) ? "Remove favorite" : "Add favorite"
        }
    }

    private func videoManageTint(for camera: HAEntityState) -> Color {
        if isShowingHiddenVideoCameras {
            return .green
        }

        switch videoManageMode {
        case .hide:
            return .orange
        case .favorite:
            return viewModel.isCameraFavorite(camera.entityID) ? .yellow : .mint
        }
    }

    private func navigationRail(contentWidth: CGFloat) -> some View {
        let items = dashboardNavigationItems
        let usesGrid = shouldUseNavigationGrid(for: items.count, contentWidth: contentWidth)

        return Group {
            if usesGrid {
                LazyVGrid(
                    columns: Array(
                        repeating: GridItem(.flexible(minimum: 0, maximum: .infinity), spacing: 8, alignment: .top),
                        count: dashboardTabColumnCount(for: items.count, contentWidth: contentWidth)
                    ),
                    alignment: .leading,
                    spacing: 8
                ) {
                    ForEach(items) { item in
                        Button(action: item.action) {
                            DashboardTopTab(
                                title: item.title,
                                systemImage: item.systemImage,
                                isSelected: item.isSelected,
                                fillsWidth: true
                            )
                        }
                        .buttonStyle(.plain)
                        .focusEffectDisabled()
                    }
                }
                .padding(6)
                .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(.white.opacity(0.06))
                )
                .focusSection()
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(items) { item in
                            Button(action: item.action) {
                                DashboardTopTab(
                                    title: item.title,
                                    systemImage: item.systemImage,
                                    isSelected: item.isSelected
                                )
                            }
                            .buttonStyle(.plain)
                            .focusEffectDisabled()
                        }
                    }
                    .padding(6)
                }
                .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(.white.opacity(0.06))
                )
                .focusSection()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var dashboardNavigationItems: [DashboardNavigationItem] {
        var items = [
            DashboardNavigationItem(
                id: "__video",
                title: "Video",
                systemImage: "video.fill",
                isSelected: viewModel.isShowingVideoHub,
                action: {
                    Task { await viewModel.showVideoHub() }
                    revealChrome()
                }
            )
        ]

        items.append(contentsOf: (viewModel.dashboardConfig?.views ?? []).map { view in
            DashboardNavigationItem(
                id: view.id,
                title: view.displayTitle,
                systemImage: nil,
                isSelected: !viewModel.isShowingVideoHub && view.id == viewModel.currentView?.id,
                action: {
                    viewModel.selectView(view)
                    revealChrome()
                }
            )
        })

        return items
    }

    private func shouldUseNavigationGrid(for itemCount: Int, contentWidth: CGFloat) -> Bool {
        itemCount > dashboardTabColumnCount(for: itemCount, contentWidth: contentWidth)
    }

    private func dashboardTabColumnCount(for itemCount: Int, contentWidth: CGFloat) -> Int {
        let preferredCount: Int
        switch contentWidth {
        case ..<900:
            preferredCount = 2
        case ..<1180:
            preferredCount = 3
        case ..<1540:
            preferredCount = 4
        default:
            preferredCount = 5
        }

        return max(1, min(preferredCount, max(itemCount, 1)))
    }

    private func groupedVideoSections(from cameras: [HAEntityState]) -> [VideoHubSection] {
        guard !cameras.isEmpty else { return [] }

        if isShowingHiddenVideoCameras || isShowingFavoriteVideoCameras || selectedVideoAreaName != nil {
            return [VideoHubSection(title: nil, cameras: cameras)]
        }

        var sections: [VideoHubSection] = []
        let favoriteIDs = Set(viewModel.favoriteCameraEntityIDs)
        let favorites = cameras.filter { favoriteIDs.contains($0.entityID) }
        if !favorites.isEmpty {
            sections.append(VideoHubSection(title: "Favorites", cameras: favorites))
        }

        let remaining = cameras.filter { !favoriteIDs.contains($0.entityID) }
        let groupedByArea = Dictionary(grouping: remaining) { camera in
            viewModel.cameraAreaName(for: camera.entityID) ?? "Other"
        }

        let sortedAreaNames = groupedByArea.keys.sorted { lhs, rhs in
            lhs.localizedCaseInsensitiveCompare(rhs) == .orderedAscending
        }

        for areaName in sortedAreaNames {
            guard let areaCameras = groupedByArea[areaName], !areaCameras.isEmpty else { continue }
            sections.append(VideoHubSection(title: areaName, cameras: areaCameras))
        }

        return sections.isEmpty ? [VideoHubSection(title: nil, cameras: cameras)] : sections
    }

    @ViewBuilder
    private func videoGrid(for cameras: [HAEntityState], columnCount: Int, contentWidth: CGFloat) -> some View {
        LazyVGrid(columns: videoColumns(for: columnCount), alignment: .leading, spacing: 18) {
            ForEach(cameras) { camera in
                DashboardCameraTile(
                    title: camera.friendlyName,
                    subtitle: isManagingVideoCameras
                        ? (isShowingHiddenVideoCameras ? "Hidden" : (viewModel.isCameraFavorite(camera.entityID) ? "Favorite" : "Visible"))
                        : camera.displayState,
                    detail: isManagingVideoCameras
                        ? videoManageDetail(for: camera)
                        : (camera.subtitle ?? "Open full screen"),
                    previewURL: viewModel.cameraPreviewURL(for: camera.entityID),
                    badgeText: isManagingVideoCameras
                        ? videoManageBadge(for: camera)
                        : "LIVE",
                    tint: isManagingVideoCameras
                        ? videoManageTint(for: camera)
                        : .cyan,
                    isDimmed: isShowingHiddenVideoCameras,
                    style: .videoWall,
                    height: videoTileHeight(for: columnCount, contentWidth: contentWidth)
                ) {
                    if isManagingVideoCameras {
                        performManageAction(for: camera)
                    } else {
                        presentCamera(entityIDs: [camera.entityID], startingAt: 0, autoAdvance: false)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .focusSection()
    }

    private func revealChrome() {
        withAnimation(.easeOut(duration: 0.24)) {
            isChromeVisible = true
        }
        scheduleChromeAutoHide()
    }

    private func scheduleChromeAutoHide() {
        cancelChromeAutoHide()
        guard viewModel.prefersMinimalChrome else { return }
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

    private func videoColumns(for columnCount: Int) -> [GridItem] {
        return Array(
            repeating: GridItem(.flexible(minimum: 0, maximum: .infinity), spacing: 18, alignment: .top),
            count: columnCount
        )
    }

    private func videoColumnCount(for itemCount: Int, contentWidth: CGFloat) -> Int {
        min(maxVideoColumnCount(for: contentWidth), max(itemCount, 1))
    }

    private func videoTileHeight(for columnCount: Int, contentWidth: CGFloat) -> CGFloat {
        guard columnCount > 0, contentWidth > 0 else {
            return 204
        }

        let totalSpacing = CGFloat(max(columnCount - 1, 0)) * 18
        let tileWidth = (contentWidth - totalSpacing) / CGFloat(columnCount)
        return max(188, floor(tileWidth * 0.58))
    }

    private func dashboardRows(for cards: [HAAnyConfig], maxColumns: Int) -> [DashboardCardRow] {
        guard !cards.isEmpty else { return [] }

        guard maxColumns > 1 else {
            return cards.map { card in
                DashboardCardRow(items: [DashboardCardRowItem(card: card, span: 1)])
            }
        }

        var rows: [DashboardCardRow] = []
        var currentItems: [DashboardCardRowItem] = []
        var usedColumns = 0

        for card in cards {
            let preferredSpan = preferredSpan(for: card, maxColumns: maxColumns)

            if usedColumns + preferredSpan > maxColumns, !currentItems.isEmpty {
                rows.append(normalizedRow(from: currentItems, usedColumns: usedColumns, maxColumns: maxColumns))
                currentItems = []
                usedColumns = 0
            }

            currentItems.append(DashboardCardRowItem(card: card, span: preferredSpan))
            usedColumns += preferredSpan

            if usedColumns == maxColumns {
                rows.append(DashboardCardRow(items: currentItems))
                currentItems = []
                usedColumns = 0
            }
        }

        if !currentItems.isEmpty {
            rows.append(normalizedRow(from: currentItems, usedColumns: usedColumns, maxColumns: maxColumns))
        }

        return rows
    }

    private func normalizedRow(
        from items: [DashboardCardRowItem],
        usedColumns: Int,
        maxColumns: Int
    ) -> DashboardCardRow {
        guard usedColumns < maxColumns, !items.isEmpty else {
            return DashboardCardRow(items: items)
        }

        var adjustedItems = items
        let remainingColumns = maxColumns - usedColumns

        if adjustedItems.count == 1, shouldPromoteToFullWidth(adjustedItems[0].card, maxColumns: maxColumns) {
            adjustedItems[0].span = maxColumns
        } else if adjustedItems.count == 2, shouldStretchTrailingItem(adjustedItems[1].card, maxColumns: maxColumns) {
            adjustedItems[1].span += remainingColumns
        }

        return DashboardCardRow(items: adjustedItems)
    }

    private func preferredSpan(for card: HAAnyConfig, maxColumns: Int) -> Int {
        guard maxColumns > 1 else { return 1 }

        if let preferredByGrid = preferredSpanFromGridOptions(for: card, maxColumns: maxColumns) {
            return preferredByGrid
        }

        switch card.type {
        case "heading", "custom:mushroom-chips-card":
            return maxColumns
        case "weather-forecast", "custom:hourly-weather", "custom:weather-chart-card", "custom:weather-radar-card", "custom:horizon-card", "logbook", "media-control", "custom:better-thermostat-ui-card", "energy-usage-graph":
            return min(maxColumns, 2)
        case "grid", "horizontal-stack", "vertical-stack":
            return min(maxColumns, 2)
        case "entities":
            return card.entities.count >= 4 ? min(maxColumns, 2) : 1
        case "glance":
            return card.entities.count >= 5 ? min(maxColumns, 2) : 1
        default:
            return 1
        }
    }

    private func shouldPromoteToFullWidth(_ card: HAAnyConfig, maxColumns: Int) -> Bool {
        guard maxColumns > 1 else { return false }

        if let preferredByGrid = preferredSpanFromGridOptions(for: card, maxColumns: maxColumns) {
            return preferredByGrid == maxColumns
        }

        switch card.type {
        case "heading", "weather-forecast", "custom:hourly-weather", "custom:weather-chart-card", "custom:weather-radar-card", "custom:horizon-card", "logbook", "custom:mushroom-chips-card", "media-control", "custom:better-thermostat-ui-card", "energy-usage-graph":
            return true
        case "entities":
            return card.entities.count >= 3
        default:
            return false
        }
    }

    private func shouldStretchTrailingItem(_ card: HAAnyConfig, maxColumns: Int) -> Bool {
        shouldPromoteToFullWidth(card, maxColumns: maxColumns) || card.type == "grid"
    }

    private func preferredSpanFromGridOptions(for card: HAAnyConfig, maxColumns: Int) -> Int? {
        guard let gridColumns = card.gridOptionColumns else {
            return nil
        }

        let normalizedFraction: Double
        if gridColumns >= 12 {
            normalizedFraction = 1
        } else {
            normalizedFraction = max(Double(gridColumns) / 12.0, 1.0 / Double(maxColumns))
        }

        let scaled = Int(floor(normalizedFraction * Double(maxColumns)))
        return min(max(scaled, 1), maxColumns)
    }

    private func dashboardItemWidth(for span: Int, maxColumns: Int, contentWidth: CGFloat) -> CGFloat {
        guard maxColumns > 0, contentWidth > 0 else {
            return contentWidth
        }

        let totalSpacing = CGFloat(max(maxColumns - 1, 0)) * dashboardGridSpacing
        let baseColumnWidth = max((contentWidth - totalSpacing) / CGFloat(maxColumns), 0)
        return (baseColumnWidth * CGFloat(span)) + (dashboardGridSpacing * CGFloat(max(span - 1, 0)))
    }

    private func maxDashboardColumnCount(for contentWidth: CGFloat, viewMaxColumns: Int?) -> Int {
        let automaticColumns: Int
        switch contentWidth {
        case ..<760:
            automaticColumns = 1
        case ..<1240:
            automaticColumns = 2
        default:
            automaticColumns = 3
        }

        if let viewMaxColumns, viewMaxColumns > 0 {
            return max(1, min(viewMaxColumns, automaticColumns))
        }

        return automaticColumns
    }

    private func maxVideoColumnCount(for contentWidth: CGFloat) -> Int {
        switch contentWidth {
        case ..<760:
            return 1
        case ..<1180:
            return 2
        case ..<1640:
            return 3
        default:
            return 4
        }
    }

    private var dashboardGridSpacing: CGFloat {
        18
    }
}

private struct DashboardHeaderHeightPreferenceKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct DashboardHeaderHeightReader: View {
    var body: some View {
        GeometryReader { proxy in
            Color.clear
                .preference(key: DashboardHeaderHeightPreferenceKey.self, value: proxy.size.height)
        }
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
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 18) {
                contentColumn
                Spacer(minLength: 18)
                clockColumn
            }

            VStack(alignment: .leading, spacing: 14) {
                contentColumn
                clockColumn
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(red: 0.06, green: 0.11, blue: 0.16))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(accent.opacity(0.14))
        )
    }

    private var contentColumn: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .foregroundStyle(.white)

            Text(subtitle)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.white.opacity(0.68))

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    KioskInfoPill(title: "Cameras", value: "\(cameraCount)", tint: .cyan)
                    KioskInfoPill(title: "Lights", value: "\(lightsOnCount)", tint: .yellow)
                    KioskInfoPill(title: "Climate", value: "\(activeClimateCount)", tint: .orange)
                    KioskInfoPill(title: "Media", value: "\(activeMediaCount)", tint: .pink)
                }

                LazyVGrid(
                    columns: [
                        GridItem(.flexible(minimum: 0, maximum: .infinity), spacing: 8),
                        GridItem(.flexible(minimum: 0, maximum: .infinity), spacing: 8)
                    ],
                    alignment: .leading,
                    spacing: 8
                ) {
                    KioskInfoPill(title: "Cameras", value: "\(cameraCount)", tint: .cyan)
                    KioskInfoPill(title: "Lights", value: "\(lightsOnCount)", tint: .yellow)
                    KioskInfoPill(title: "Climate", value: "\(activeClimateCount)", tint: .orange)
                    KioskInfoPill(title: "Media", value: "\(activeMediaCount)", tint: .pink)
                }
            }
        }
    }

    private var clockColumn: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            VStack(alignment: .trailing, spacing: 4) {
                Text(context.date, format: .dateTime.hour().minute())
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)

                Text(context.date, format: .dateTime.weekday(.abbreviated).month(.wide).day())
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.60))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(.white.opacity(0.06))
            )
        }
    }
}

private struct KioskInfoPill: View {
    let title: String
    let value: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.white.opacity(0.60))

            Text(value)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.white)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(.white.opacity(0.05))
        )
    }
}

private struct DashboardHeaderActionButton: View {
    @Environment(\.isFocused) private var isFocused

    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.caption.weight(.bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(backgroundColor, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(borderColor, lineWidth: isFocused ? 1.5 : 1)
                )
                .animation(.easeInOut(duration: 0.18), value: isFocused)
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
    }

    private var backgroundColor: Color {
        isFocused ? Color.white.opacity(0.16) : Color.white.opacity(0.07)
    }

    private var borderColor: Color {
        isFocused ? .white.opacity(0.28) : .white.opacity(0.07)
    }
}

private struct DashboardTopTab: View {
    @Environment(\.isFocused) private var isFocused

    let title: String
    let systemImage: String?
    let isSelected: Bool
    let fillsWidth: Bool

    init(title: String, systemImage: String? = nil, isSelected: Bool, fillsWidth: Bool = false) {
        self.title = title
        self.systemImage = systemImage
        self.isSelected = isSelected
        self.fillsWidth = fillsWidth
    }

    var body: some View {
        Group {
            if let systemImage {
                Label(title, systemImage: systemImage)
            } else {
                Text(title)
            }
        }
        .font(.subheadline.weight(.bold))
        .foregroundStyle(.white)
        .multilineTextAlignment(fillsWidth ? .center : .leading)
        .lineLimit(fillsWidth ? 2 : 1)
        .minimumScaleFactor(0.8)
        .frame(maxWidth: fillsWidth ? .infinity : nil, minHeight: fillsWidth ? 48 : 0)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(backgroundColor, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(borderColor, lineWidth: isFocused ? 1.5 : 1)
        )
        .animation(.easeInOut(duration: 0.18), value: isFocused)
    }

    private var backgroundColor: Color {
        if isFocused {
            return .white.opacity(isSelected ? 0.22 : 0.14)
        }
        return isSelected ? .white.opacity(0.12) : .white.opacity(0.04)
    }

    private var borderColor: Color {
        if isFocused {
            return .white.opacity(0.30)
        }
        return isSelected ? .white.opacity(0.12) : .white.opacity(0.05)
    }
}

private struct DashboardUtilityButtonLabel: View {
    @Environment(\.isFocused) private var isFocused

    let title: String
    let isActive: Bool

    var body: some View {
        Text(title)
            .font(.subheadline.weight(.bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(backgroundColor, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(borderColor, lineWidth: isFocused ? 1.5 : 1)
            )
            .animation(.easeInOut(duration: 0.18), value: isFocused)
    }

    private var backgroundColor: Color {
        if isFocused {
            return .white.opacity(isActive ? 0.22 : 0.14)
        }
        return isActive ? .white.opacity(0.14) : .white.opacity(0.06)
    }

    private var borderColor: Color {
        isFocused ? .white.opacity(0.30) : .white.opacity(0.06)
    }
}

private struct DashboardCardRow: Identifiable {
    let items: [DashboardCardRowItem]

    var id: String {
        items.map(\.id).joined(separator: "|")
    }
}

private struct DashboardCardRowItem: Identifiable {
    let card: HAAnyConfig
    var span: Int

    var id: String { card.id }
}

private struct DashboardNavigationItem: Identifiable {
    let id: String
    let title: String
    let systemImage: String?
    let isSelected: Bool
    let action: () -> Void
}

private struct VideoHubSection: Identifiable {
    let title: String?
    let cameras: [HAEntityState]

    var id: String {
        let sectionTitle = title ?? "all"
        return "\(sectionTitle)|\(cameras.map(\.entityID).joined(separator: ","))"
    }
}

private struct DashboardCardView: View {
    let card: HAAnyConfig
    @Bindable var viewModel: RootViewModel
    let openCamera: (String, String) -> Void

    var body: some View {
        Group {
            if card.usesStandaloneFocusSurface {
                DashboardStandaloneFocusCard {
                    DashboardCardContent(card: card, viewModel: viewModel, openCamera: openCamera)
                }
            } else {
                DashboardCardContent(card: card, viewModel: viewModel, openCamera: openCamera)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

private enum VideoHubManageMode {
    case hide
    case favorite
}

private struct DashboardDiagnosticsView: View {
    @Bindable var viewModel: RootViewModel
    @Environment(\.dismiss) private var dismiss

    private var appVersion: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "\(version) (\(build))"
    }

    var body: some View {
        ZStack {
            Color(red: 0.04, green: 0.08, blue: 0.12)
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    HStack(alignment: .top, spacing: 16) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Diagnostics")
                                .font(.system(size: 34, weight: .bold, design: .rounded))
                                .foregroundStyle(.white)

                            Text("Connection health, kiosk behavior, and quick recovery actions.")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.white.opacity(0.68))
                        }

                        Spacer()

                        Button("Close") {
                            dismiss()
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.white.opacity(0.18))
                    }

                    LazyVGrid(
                        columns: [
                            GridItem(.flexible(minimum: 0, maximum: .infinity), spacing: 14),
                            GridItem(.flexible(minimum: 0, maximum: .infinity), spacing: 14)
                        ],
                        alignment: .leading,
                        spacing: 14
                    ) {
                        DiagnosticsMetricCard(title: "Server", value: viewModel.serverURLString)
                        DiagnosticsMetricCard(title: "Dashboard", value: viewModel.selectedDashboard?.title ?? "Not selected")
                        DiagnosticsMetricCard(title: "View", value: viewModel.isShowingVideoHub ? "Video Wall" : (viewModel.currentView?.displayTitle ?? "Unknown"))
                        DiagnosticsMetricCard(title: "App", value: appVersion)
                        DiagnosticsMetricCard(title: "Cameras", value: "\(viewModel.visibleCameraStates.count) visible / \(viewModel.hiddenCameraStates.count) hidden")
                        DiagnosticsMetricCard(title: "Last Refresh", value: viewModel.lastSuccessfulRefreshAt?.formatted(.dateTime.hour().minute().second()) ?? "Not yet")
                    }

                    VStack(alignment: .leading, spacing: 14) {
                        Toggle(
                            "Open last dashboard on launch",
                            isOn: Binding(
                                get: { viewModel.autoLaunchDashboard },
                                set: { viewModel.setAutoLaunchDashboardPreference($0) }
                            )
                        )
                        .toggleStyle(.switch)
                        .foregroundStyle(.white)

                        Toggle(
                            "Use minimal chrome in kiosk mode",
                            isOn: Binding(
                                get: { viewModel.prefersMinimalChrome },
                                set: { viewModel.setMinimalChromePreference($0) }
                            )
                        )
                        .toggleStyle(.switch)
                        .foregroundStyle(.white)

                        Text("Auto-launch skips the picker and reopens your last dashboard or video wall. Minimal chrome keeps the interface hidden until you need it.")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.white.opacity(0.58))
                    }
                    .padding(18)
                    .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(.white.opacity(0.08))
                    )

                    HStack(spacing: 12) {
                        Button("Refresh Dashboard") {
                            Task { await viewModel.refreshDashboard() }
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.white.opacity(0.18))

                        Button("Reconnect Session") {
                            Task { await viewModel.reconnectCurrentSession() }
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.white.opacity(0.12))
                    }
                }
                .padding(32)
            }
        }
    }
}

private struct DiagnosticsMetricCard: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.weight(.bold))
                .foregroundStyle(.white.opacity(0.56))

            Text(value)
                .font(.headline.weight(.bold))
                .foregroundStyle(.white)
                .lineLimit(3)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, minHeight: 92, alignment: .leading)
        .padding(16)
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(.white.opacity(0.08))
        )
    }
}

private struct PresentedCamera: Identifiable, Equatable {
    let cameraEntityIDs: [String]
    let currentIndex: Int
    let autoAdvance: Bool

    var id: String {
        "\(cameraEntityIDs.joined(separator: "|"))|\(autoAdvance)"
    }

    var currentEntityID: String {
        cameraEntityIDs[currentIndex]
    }

    func withCurrentIndex(_ nextIndex: Int) -> PresentedCamera {
        PresentedCamera(
            cameraEntityIDs: cameraEntityIDs,
            currentIndex: min(max(nextIndex, 0), cameraEntityIDs.count - 1),
            autoAdvance: autoAdvance
        )
    }
}

private struct CameraFullScreenView: View {
    let presentation: PresentedCamera
    @Bindable var viewModel: RootViewModel
    let advance: (Int) -> Void
    let close: () -> Void
    @State private var streamURL: URL?
    @State private var playbackState: CameraPlaybackState = .loading
    @State private var errorMessage: String?
    @State private var reloadToken = UUID()
    @State private var isChromeVisible = true
    @State private var chromeAutoHideTask: Task<Void, Never>?
    @State private var autoAdvanceTask: Task<Void, Never>?

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
            cancelAutoAdvance()
        }
        .onChange(of: playbackState) { _, newValue in
            updateChromeVisibility(for: newValue)
        }
        .onChange(of: presentation.currentIndex) { _, _ in
            reloadToken = UUID()
        }
        .onMoveCommand { direction in
            guard presentation.cameraEntityIDs.count > 1 else { return }

            switch direction {
            case .left:
                advance(max(presentation.currentIndex - 1, 0))
            case .right:
                advance(min(presentation.currentIndex + 1, presentation.cameraEntityIDs.count - 1))
            default:
                break
            }
        }
        .onExitCommand {
            close()
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

                if presentation.cameraEntityIDs.count > 1 {
                    Text("\(presentation.currentIndex + 1) / \(presentation.cameraEntityIDs.count)")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white.opacity(0.60))
                }
            }

            Spacer()

            HStack(spacing: 12) {
                if presentation.cameraEntityIDs.count > 1 {
                    Button("Previous") {
                        advance(max(presentation.currentIndex - 1, 0))
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.white.opacity(0.12))

                    Button("Next") {
                        advance(min(presentation.currentIndex + 1, presentation.cameraEntityIDs.count - 1))
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.white.opacity(0.12))
                }

                Button("Refresh") {
                    reloadToken = UUID()
                }
                .buttonStyle(.borderedProminent)
                .tint(.white.opacity(0.18))

                Button("Close") {
                    close()
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
            scheduleAutoAdvanceIfNeeded()
        case .idle, .loading, .failed:
            revealChrome()
            cancelAutoAdvance()
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

    private func scheduleAutoAdvanceIfNeeded() {
        cancelAutoAdvance()
        guard presentation.autoAdvance, presentation.cameraEntityIDs.count > 1 else {
            return
        }

        autoAdvanceTask = Task {
            try? await Task.sleep(for: .seconds(12))
            guard !Task.isCancelled else { return }

            await MainActor.run {
                let nextIndex = (presentation.currentIndex + 1) % presentation.cameraEntityIDs.count
                advance(nextIndex)
            }
        }
    }

    private func cancelAutoAdvance() {
        autoAdvanceTask?.cancel()
        autoAdvanceTask = nil
    }

    private var entityID: String {
        presentation.currentEntityID
    }

    private var title: String {
        viewModel.state(for: entityID)?.friendlyName ?? entityID
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
