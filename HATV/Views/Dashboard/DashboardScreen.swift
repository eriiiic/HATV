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

    private var moreInfoBinding: Binding<RootViewModel.MoreInfoPresentation?> {
        Binding(
            get: { viewModel.moreInfoPresentation },
            set: { presentation in
                viewModel.moreInfoPresentation = presentation
            }
        )
    }

    var body: some View {
        GeometryReader { proxy in
            let contentWidth = max(proxy.size.width - 56, 0)

            ZStack(alignment: .top) {
                dashboardContent(contentWidth: contentWidth)
                    .padding(.top, isChromeVisible ? headerHeight + 10 : 8)

                if isChromeVisible {
                    header(contentWidth: contentWidth)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
            .padding(.horizontal, 28)
            .padding(.vertical, 18)
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
            viewModel.dismissMoreInfo()
            revealChrome()
        }
        .onChange(of: viewModel.isShowingVideoHub) { _, _ in
            viewModel.dismissMoreInfo()
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
                viewModel.dismissMoreInfo()
                cancelChromeAutoHide()
            }
        }
        .onChange(of: viewModel.moreInfoPresentation) { _, presentation in
            if presentation != nil {
                cancelChromeAutoHide()
                withAnimation(.easeOut(duration: 0.24)) {
                    isChromeVisible = true
                }
            } else {
                scheduleChromeAutoHide()
            }
        }
        .onPlayPauseCommand {
            revealChrome()
        }
        .onExitCommand {
            if viewModel.moreInfoPresentation != nil {
                viewModel.dismissMoreInfo()
                revealChrome()
                return
            }
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
        .fullScreenCover(item: moreInfoBinding) { presentation in
            DashboardMoreInfoTooltip(
                presentation: presentation,
                viewModel: viewModel,
                openCamera: { entityID, title in
                    viewModel.dismissMoreInfo()
                    presentCamera(entityID: entityID, title: title)
                },
                close: {
                    viewModel.dismissMoreInfo()
                    revealChrome()
                }
            )
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
        let maxColumns = maxDashboardColumnCount(
            for: contentWidth,
            viewMaxColumns: viewMaxColumns,
            cardCount: visibleCards.count
        )
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
                            .hoverEffectDisabled()
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
                            .hoverEffectDisabled()
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
                        .hoverEffectDisabled()
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
                        .hoverEffectDisabled()

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
                            .hoverEffectDisabled()
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
                            .hoverEffectDisabled()
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
                        .hoverEffectDisabled()

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
                        .hoverEffectDisabled()
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

        viewModel.dismissMoreInfo()
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
                        .hoverEffectDisabled()
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
                            .hoverEffectDisabled()
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
            repeating: GridItem(.flexible(minimum: 0, maximum: .infinity), spacing: 16, alignment: .top),
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

        let totalSpacing = CGFloat(max(columnCount - 1, 0)) * 16
        let tileWidth = (contentWidth - totalSpacing) / CGFloat(columnCount)
        return max(184, floor(tileWidth * 0.5625))
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
        case "heading":
            return card.headingStyle?.lowercased() == "subtitle" ? min(maxColumns, 2) : maxColumns
        case "custom:mushroom-chips-card":
            return min(maxColumns, 2)
        case "weather-forecast", "custom:hourly-weather", "custom:weather-chart-card", "custom:weather-radar-card", "custom:horizon-card", "logbook", "energy-usage-graph":
            return min(maxColumns, 2)
        case "media-control", "custom:better-thermostat-ui-card":
            return min(maxColumns, 2)
        case "grid", "horizontal-stack", "vertical-stack":
            return min(maxColumns, 2)
        case "entities":
            return card.entities.count >= 4 ? min(maxColumns, 2) : 1
        case "glance":
            return card.entities.count >= 5 ? min(maxColumns, 2) : 1
        case "picture-entity", "picture-glance":
            return min(maxColumns, 2)
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
        case "heading":
            return card.headingStyle?.lowercased() != "subtitle"
        case "weather-forecast", "custom:hourly-weather", "custom:weather-chart-card", "custom:weather-radar-card", "custom:horizon-card", "logbook", "energy-usage-graph":
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

    private func maxDashboardColumnCount(for contentWidth: CGFloat, viewMaxColumns: Int?, cardCount: Int) -> Int {
        let automaticColumns: Int
        switch contentWidth {
        case ..<760:
            automaticColumns = 1
        case ..<1100:
            automaticColumns = 2
        case ..<1400:
            automaticColumns = 3
        default:
            automaticColumns = 4
        }

        if let viewMaxColumns, viewMaxColumns > 0 {
            if viewMaxColumns <= 1, automaticColumns > 1, cardCount >= 3 {
                return automaticColumns
            }

            return max(1, min(viewMaxColumns, automaticColumns))
        }

        return automaticColumns
    }

    private func maxVideoColumnCount(for contentWidth: CGFloat) -> Int {
        switch contentWidth {
        case ..<760:
            return 1
        case ..<1140:
            return 2
        case ..<1620:
            return 3
        default:
            return 4
        }
    }

    private var dashboardGridSpacing: CGFloat {
        16
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
            HStack(alignment: .top, spacing: 14) {
                contentColumn
                Spacer(minLength: 14)
                clockColumn
            }

            VStack(alignment: .leading, spacing: 12) {
                contentColumn
                clockColumn
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(red: 0.06, green: 0.10, blue: 0.15))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(accent.opacity(0.10))
        )
    }

    private var contentColumn: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(.white)

            Text(subtitle)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white.opacity(0.64))

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
            VStack(alignment: .trailing, spacing: 2) {
                Text(context.date, format: .dateTime.hour().minute())
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)

                Text(context.date, format: .dateTime.weekday(.abbreviated).month(.wide).day())
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.60))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(accent.opacity(0.06), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
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
        .padding(.vertical, 7)
        .background(tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
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
                .padding(.horizontal, 11)
                .padding(.vertical, 6)
                .background(backgroundColor, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .strokeBorder(borderColor, lineWidth: isFocused ? 1.5 : 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
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
        .frame(maxWidth: fillsWidth ? .infinity : nil, minHeight: fillsWidth ? 44 : 0)
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(backgroundColor, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(borderColor, lineWidth: isFocused ? 1.5 : 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        .animation(.easeInOut(duration: 0.18), value: isFocused)
    }

    private var backgroundColor: Color {
        if isFocused {
            return .white.opacity(isSelected ? 0.18 : 0.10)
        }
        return isSelected ? .white.opacity(0.10) : .white.opacity(0.035)
    }

    private var borderColor: Color {
        if isFocused {
            return .white.opacity(0.22)
        }
        return isSelected ? .white.opacity(0.10) : .white.opacity(0.05)
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
                DashboardStandaloneFocusCard(
                    action: !card.hasPrimaryInteraction ? nil : {
                        Task { await viewModel.executePrimaryAction(for: card) }
                    }
                ) {
                    DashboardCardContent(card: card, viewModel: viewModel, openCamera: openCamera)
                }
            } else {
                DashboardCardContent(card: card, viewModel: viewModel, openCamera: openCamera)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

private struct DashboardMoreInfoTooltip: View {
    private enum TooltipFocusField: Hashable {
        case close
    }

    let presentation: RootViewModel.MoreInfoPresentation
    @Bindable var viewModel: RootViewModel
    let openCamera: (String, String) -> Void
    let close: () -> Void
    @FocusState private var focusedField: TooltipFocusField?

    private var state: HAEntityState? {
        viewModel.state(for: presentation.entityID)
    }

    private var historyHours: Int {
        switch state?.domain {
        case "weather":
            return 48
        default:
            return 24
        }
    }

    private var historySamples: [HAHistorySample] {
        viewModel.historySamples(for: presentation.entityID, hours: historyHours)
    }

    private var isLoadingHistory: Bool {
        viewModel.isLoadingHistory(for: presentation.entityID, hours: historyHours)
    }

    private var historyAccent: Color {
        switch state?.domain {
        case "camera":
            return .cyan
        case "climate":
            return .orange
        case "light":
            return .yellow
        case "media_player":
            return .pink
        case "sensor":
            return .mint
        case "weather":
            return .blue
        default:
            return .white
        }
    }

    private var historyChartStyle: DashboardTrendChartStyle {
        let distinctValues = Set(historySamples.map(\.value))
        guard distinctValues.count <= 2, distinctValues.isSubset(of: Set([0.0, 1.0])) else {
            return .line
        }

        return .step
    }

    private var title: String {
        presentation.preferredTitle ?? state?.friendlyName ?? presentation.entityID
    }

    private var subtitle: String {
        if let state, state.domain == "camera", let areaName = viewModel.cameraAreaName(for: state.entityID) {
            return areaName
        }

        if let subtitle = state?.subtitle, !subtitle.isEmpty {
            return subtitle
        }

        return state?.formattedStateDescription ?? "Home Assistant details"
    }

    private var metricRows: [DashboardMoreInfoMetric] {
        var usedKeys = Set<String>()
        var metrics: [DashboardMoreInfoMetric] = []

        if let state {
            metrics.append(.init(title: "State", value: state.displayState))
            metrics.append(.init(title: "Entity", value: state.entityID))
            usedKeys.insert("friendly_name")
            usedKeys.insert("entity_id")

            if let date = state.lastUpdatedDate {
                metrics.append(.init(title: "Updated", value: date.formatted(.dateTime.hour().minute().day().month(.abbreviated))))
            }

            switch state.domain {
            case "climate":
                if let current = state.currentTemperature {
                    metrics.append(.init(title: "Current", value: "\(current.formatted(.number.precision(.fractionLength(0...1))))°"))
                    usedKeys.insert("current_temperature")
                }
                if let target = state.targetTemperature {
                    metrics.append(.init(title: "Target", value: "\(target.formatted(.number.precision(.fractionLength(0...1))))°"))
                    usedKeys.insert("temperature")
                }
                if let humidity = state.humidity {
                    metrics.append(.init(title: "Humidity", value: "\(humidity)%"))
                    usedKeys.insert("humidity")
                }
            case "light":
                if let brightness = state.brightnessPercent {
                    metrics.append(.init(title: "Brightness", value: "\(brightness)%"))
                    usedKeys.insert("brightness")
                }
            case "media_player":
                if let volume = state.volumePercent {
                    metrics.append(.init(title: "Volume", value: "\(volume)%"))
                    usedKeys.insert("volume_level")
                }
                if let appName = state.appName {
                    metrics.append(.init(title: "App", value: appName))
                    usedKeys.insert("app_name")
                }
                if let mediaTitle = state.mediaTitle {
                    metrics.append(.init(title: "Now Playing", value: mediaTitle))
                    usedKeys.insert("media_title")
                }
            case "cover":
                if let position = state.attributes["current_position"]?.compactDisplayString {
                    metrics.append(.init(title: "Position", value: position + "%"))
                    usedKeys.insert("current_position")
                }
            case "weather":
                if let humidity = state.humidity {
                    metrics.append(.init(title: "Humidity", value: "\(humidity)%"))
                    usedKeys.insert("humidity")
                }
                if let windSpeed = state.windSpeed {
                    metrics.append(.init(title: "Wind", value: "\(windSpeed.formatted(.number.precision(.fractionLength(0...1)))) \(state.windSpeedUnit ?? "")"))
                    usedKeys.insert("wind_speed")
                    usedKeys.insert("wind_speed_unit")
                }
                if let precipitation = state.precipitation {
                    metrics.append(.init(title: "Precipitation", value: "\(precipitation.formatted(.number.precision(.fractionLength(0...1)))) \(state.precipitationUnit ?? "")"))
                    usedKeys.insert("precipitation")
                    usedKeys.insert("precipitation_unit")
                }
            default:
                break
            }

            let reservedKeys: Set<String> = [
                "attribution",
                "editable",
                "entity_picture",
                "friendly_name",
                "icon",
                "supported_features"
            ]

            let extraMetrics = state.attributes
                .keys
                .sorted { lhs, rhs in
                    lhs.localizedCaseInsensitiveCompare(rhs) == .orderedAscending
                }
                .filter { key in
                    !reservedKeys.contains(key) && !usedKeys.contains(key)
                }
                .compactMap { key -> DashboardMoreInfoMetric? in
                    guard let value = state.attributes[key]?.compactDisplayString,
                          !value.isEmpty,
                          value != "—" else {
                        return nil
                    }

                    return DashboardMoreInfoMetric(
                        title: prettifiedIdentifier(key),
                        value: value
                    )
                }
                .prefix(8)

            metrics.append(contentsOf: extraMetrics)
        } else {
            metrics = [
                .init(title: "Entity", value: presentation.entityID),
                .init(title: "State", value: "Unavailable")
            ]
        }

        return metrics
    }

    private var historySectionTitle: String {
        historyChartStyle == .step ? "Activity" : "History"
    }

    private var historySectionSubtitle: String {
        "Last \(historyHours) hours"
    }

    private var historyPlaceholderTitle: String {
        if isLoadingHistory {
            return "Loading history…"
        }

        return "No history yet"
    }

    private var historyPlaceholderSubtitle: String {
        if isLoadingHistory {
            return "Pulling recorder data from Home Assistant."
        }

        return "Home Assistant has not returned enough recorder data for this entity yet."
    }

    private var actions: [DashboardMoreInfoAction] {
        guard let state else { return [] }

        switch state.domain {
        case "camera":
            return [
                .init(title: "Open Feed", systemImage: "video.fill") {
                    openCamera(state.entityID, state.friendlyName)
                }
            ]
        case "light":
            return [
                .init(title: state.isActive ? "Turn Off" : "Turn On", systemImage: state.isActive ? "lightbulb.slash.fill" : "lightbulb.fill") {
                    Task { await viewModel.toggleEntity(state.entityID) }
                },
                .init(title: "Dim", systemImage: "minus") {
                    Task { await viewModel.adjustLightBrightness(for: state.entityID, deltaPercent: -15) }
                },
                .init(title: "Brighten", systemImage: "plus") {
                    Task { await viewModel.adjustLightBrightness(for: state.entityID, deltaPercent: 15) }
                }
            ]
        case "climate":
            return [
                .init(title: state.state.lowercased() == "off" ? "Turn On" : "Turn Off", systemImage: state.state.lowercased() == "off" ? "power" : "power.circle.fill") {
                    Task { await viewModel.toggleClimatePower(for: state.entityID) }
                },
                .init(title: "Cooler", systemImage: "minus") {
                    Task { await viewModel.adjustClimateTemperature(for: state.entityID, delta: -0.5) }
                },
                .init(title: "Warmer", systemImage: "plus") {
                    Task { await viewModel.adjustClimateTemperature(for: state.entityID, delta: 0.5) }
                }
            ]
        case "media_player":
            var items = [
                DashboardMoreInfoAction(
                    title: state.state.lowercased() == "playing" ? "Pause" : "Play",
                    systemImage: state.state.lowercased() == "playing" ? "pause.fill" : "play.fill"
                ) {
                    Task { await viewModel.toggleMediaPlayback(for: state.entityID) }
                }
            ]

            if state.volumePercent != nil {
                items.append(
                    .init(title: "Quieter", systemImage: "speaker.wave.1.fill") {
                        Task { await viewModel.adjustMediaVolume(for: state.entityID, deltaPercent: -10) }
                    }
                )
                items.append(
                    .init(title: "Louder", systemImage: "speaker.wave.3.fill") {
                        Task { await viewModel.adjustMediaVolume(for: state.entityID, deltaPercent: 10) }
                    }
                )
            }
            return items
        case "cover":
            return [
                .init(title: "Open", systemImage: "door.left.hand.open") {
                    Task { await viewModel.performCoverCommand(for: state.entityID, action: .open) }
                },
                .init(title: "Stop", systemImage: "pause.fill") {
                    Task { await viewModel.performCoverCommand(for: state.entityID, action: .stop) }
                },
                .init(title: "Close", systemImage: "door.right.hand.closed") {
                    Task { await viewModel.performCoverCommand(for: state.entityID, action: .close) }
                }
            ]
        case "lock":
            return [
                .init(title: state.state.lowercased() == "locked" ? "Unlock" : "Lock", systemImage: state.state.lowercased() == "locked" ? "lock.open.fill" : "lock.fill") {
                    Task {
                        await viewModel.performLockCommand(
                            for: state.entityID,
                            action: state.state.lowercased() == "locked" ? .unlock : .lock
                        )
                    }
                }
            ]
        default:
            if state.isToggleLike {
                return [
                    .init(title: state.isActive ? "Turn Off" : "Turn On", systemImage: state.isActive ? "power.circle.fill" : "power") {
                        Task { await viewModel.toggleEntity(state.entityID) }
                    }
                ]
            }

            return []
        }
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.54)
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HStack(alignment: .top, spacing: 18) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(title)
                                .font(.system(size: 28, weight: .bold, design: .rounded))
                                .foregroundStyle(.white)
                                .lineLimit(2)

                            Text(subtitle)
                                .font(.headline.weight(.semibold))
                                .foregroundStyle(.white.opacity(0.68))
                                .lineLimit(2)

                            Text(presentation.entityID)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.white.opacity(0.46))
                                .lineLimit(1)
                        }

                        Spacer(minLength: 16)

                        Button("Close", action: close)
                            .buttonStyle(.plain)
                            .focusEffectDisabled()
                            .hoverEffectDisabled()
                            .focused($focusedField, equals: .close)
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .strokeBorder(.white.opacity(0.08))
                            )
                    }
                    .focusSection()

                    if !actions.isEmpty {
                        LazyVGrid(
                            columns: [
                                GridItem(.flexible(minimum: 0, maximum: .infinity), spacing: 10),
                                GridItem(.flexible(minimum: 0, maximum: .infinity), spacing: 10),
                                GridItem(.flexible(minimum: 0, maximum: .infinity), spacing: 10)
                            ],
                            alignment: .leading,
                            spacing: 10
                        ) {
                            ForEach(actions) { action in
                                DashboardMoreInfoControlButton(action: action)
                            }
                        }
                        .focusSection()
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        HStack(alignment: .center, spacing: 10) {
                            Text(historySectionTitle)
                                .font(.headline.weight(.bold))
                                .foregroundStyle(.white)

                            Text(historySectionSubtitle)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.white.opacity(0.52))
                        }

                        if historySamples.count > 1 {
                            DashboardTrendChart(
                                samples: historySamples,
                                accent: historyAccent,
                                style: historyChartStyle,
                                height: 180,
                                showsXAxis: true
                            )
                            .padding(.horizontal, 4)
                            .padding(.top, 4)
                        } else {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color.white.opacity(0.04))
                                .frame(height: 176)
                                .overlay {
                                    VStack(spacing: 8) {
                                        Text(historyPlaceholderTitle)
                                            .font(.headline.weight(.bold))
                                            .foregroundStyle(.white)

                                        Text(historyPlaceholderSubtitle)
                                            .font(.subheadline.weight(.medium))
                                            .foregroundStyle(.white.opacity(0.58))
                                            .multilineTextAlignment(.center)
                                            .frame(maxWidth: 360)
                                    }
                                    .padding(.horizontal, 24)
                                }
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .strokeBorder(.white.opacity(0.06))
                                )
                        }
                    }
                    .padding(16)
                    .background(Color.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(.white.opacity(0.06))
                    )

                    LazyVGrid(
                        columns: [
                            GridItem(.flexible(minimum: 0, maximum: .infinity), spacing: 10),
                            GridItem(.flexible(minimum: 0, maximum: .infinity), spacing: 10)
                        ],
                        alignment: .leading,
                        spacing: 10
                    ) {
                        ForEach(metricRows) { metric in
                            DashboardMoreInfoMetricRow(metric: metric)
                        }
                    }
                }
                .padding(22)
            }
            .frame(maxWidth: 820, maxHeight: 640)
            .background(Color(red: 0.07, green: 0.10, blue: 0.14), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(.white.opacity(0.08))
            )
            .shadow(color: .black.opacity(0.30), radius: 28, y: 18)
        }
        .task(id: presentation.id) {
            focusedField = .close
            await viewModel.loadHistoryIfNeeded(for: presentation.entityID, hours: historyHours)
        }
        .onExitCommand {
            close()
        }
    }

    private func prettifiedIdentifier(_ rawValue: String) -> String {
        rawValue
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .split(separator: " ")
            .map { $0.capitalized }
            .joined(separator: " ")
    }
}

private struct DashboardMoreInfoMetric: Identifiable {
    let id = UUID()
    let title: String
    let value: String
}

private struct DashboardMoreInfoAction: Identifiable {
    let id = UUID()
    let title: String
    let systemImage: String
    let action: () -> Void
}

private struct DashboardMoreInfoMetricRow: View {
    let metric: DashboardMoreInfoMetric

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(metric.title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.58))

            Text(metric.value)
                .font(.headline.weight(.bold))
                .foregroundStyle(.white)
                .lineLimit(3)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, minHeight: 74, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(.white.opacity(0.05))
        )
    }
}

private struct DashboardMoreInfoControlButton: View {
    @Environment(\.isFocused) private var isFocused

    let action: DashboardMoreInfoAction

    var body: some View {
        Button(action: action.action) {
            HStack(spacing: 10) {
                Image(systemName: action.systemImage)
                    .font(.subheadline.weight(.bold))
                    .frame(width: 28, height: 28)
                    .background(Color.white.opacity(isFocused ? 0.16 : 0.10), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                Text(action.title)
                    .font(.subheadline.weight(.bold))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(backgroundColor, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(borderColor, lineWidth: isFocused ? 1.5 : 1)
            )
            .animation(.easeInOut(duration: 0.18), value: isFocused)
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .hoverEffectDisabled()
    }

    private var backgroundColor: Color {
        isFocused ? .white.opacity(0.14) : .white.opacity(0.08)
    }

    private var borderColor: Color {
        isFocused ? .white.opacity(0.22) : .white.opacity(0.06)
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
