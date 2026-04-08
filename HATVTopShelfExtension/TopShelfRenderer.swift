import TVServices
import UIKit

enum HATVTopShelfRenderer {
    private struct CardDescriptor {
        let id: String
        let title: String
        let subtitle: String
        let eyebrow: String
        let symbolName: String
        let accentColor: UIColor
        let actionURL: URL
    }

    static func makeContent(from snapshot: HATVTopShelfSnapshot?) -> TVTopShelfSectionedContent {
        let quickSection = TVTopShelfItemCollection(items: makeQuickAccessItems(from: snapshot))
        quickSection.title = "Quick Access"

        let sections: [TVTopShelfItemCollection<TVTopShelfSectionedItem>]
        if let snapshot, !snapshot.cameraShortcuts.isEmpty {
            let cameraSection = TVTopShelfItemCollection(items: makeCameraItems(from: snapshot))
            cameraSection.title = "Cameras"
            sections = [quickSection, cameraSection]
        } else {
            sections = [quickSection]
        }

        return TVTopShelfSectionedContent(sections: sections)
    }

    private static func makeQuickAccessItems(from snapshot: HATVTopShelfSnapshot?) -> [TVTopShelfSectionedItem] {
        guard let snapshot else {
            return [
                makeItem(
                    from: CardDescriptor(
                        id: "setup",
                        title: "Open HATV",
                        subtitle: "Connect HATV to Home Assistant to enable a live Apple TV shelf.",
                        eyebrow: "SETUP",
                        symbolName: "tv.fill",
                        accentColor: UIColor(red: 0.07, green: 0.62, blue: 0.86, alpha: 1),
                        actionURL: HATVTopShelfActionURLBuilder.home()
                    )
                )
            ]
        }

        let currentViewActionURL = snapshot.isShowingVideoHub
            ? HATVTopShelfActionURLBuilder.videoWall()
            : HATVTopShelfActionURLBuilder.dashboard(viewPath: snapshot.viewPath)

        let currentViewTitle = snapshot.isShowingVideoHub
            ? "Resume Video Wall"
            : (snapshot.viewTitle ?? snapshot.dashboardTitle ?? "Dashboard")

        let currentViewSubtitle = snapshot.dashboardTitle.map { "Dashboard \($0)" } ?? "Resume the last selected Home Assistant view."

        let homeStatusSubtitle = [
            "\(snapshot.lightsOnCount) lights",
            "\(snapshot.activeClimateCount) climate",
            "\(snapshot.activeMediaCount) media"
        ]
        .joined(separator: " • ")

        let descriptors = [
            CardDescriptor(
                id: "current-view",
                title: currentViewTitle,
                subtitle: currentViewSubtitle,
                eyebrow: "NOW",
                symbolName: snapshot.isShowingVideoHub ? "video.fill" : "square.grid.2x2.fill",
                accentColor: UIColor(red: 0.07, green: 0.62, blue: 0.86, alpha: 1),
                actionURL: currentViewActionURL
            ),
            CardDescriptor(
                id: "video-wall",
                title: "Video Wall",
                subtitle: "\(snapshot.visibleCameraCount) cameras ready • \(snapshot.favoriteCameraCount) favorites",
                eyebrow: "VIDEO",
                symbolName: "camera.viewfinder",
                accentColor: UIColor(red: 0.17, green: 0.78, blue: 0.70, alpha: 1),
                actionURL: HATVTopShelfActionURLBuilder.videoWall()
            ),
            CardDescriptor(
                id: "home-status",
                title: snapshot.locationName ?? "Home Assistant",
                subtitle: homeStatusSubtitle,
                eyebrow: "STATUS",
                symbolName: "house.fill",
                accentColor: UIColor(red: 0.95, green: 0.63, blue: 0.22, alpha: 1),
                actionURL: HATVTopShelfActionURLBuilder.home()
            )
        ]

        return descriptors.map(makeItem(from:))
    }

    private static func makeCameraItems(from snapshot: HATVTopShelfSnapshot) -> [TVTopShelfSectionedItem] {
        snapshot.cameraShortcuts.prefix(4).map { camera in
            makeItem(
                from: CardDescriptor(
                    id: "camera-\(camera.entityID)",
                    title: camera.title,
                    subtitle: camera.subtitle,
                    eyebrow: "LIVE",
                    symbolName: "video.fill",
                    accentColor: UIColor(red: 0.02, green: 0.76, blue: 0.93, alpha: 1),
                    actionURL: HATVTopShelfActionURLBuilder.camera(entityID: camera.entityID)
                )
            )
        }
    }

    private static func makeItem(from descriptor: CardDescriptor) -> TVTopShelfSectionedItem {
        let item = TVTopShelfSectionedItem(identifier: descriptor.id)
        item.title = descriptor.title
        item.imageShape = .hdtv
        item.displayAction = TVTopShelfAction(url: descriptor.actionURL)

        if let imageURL = renderImage(for: descriptor) {
            item.setImageURL(imageURL, for: .screenScale1x)
            item.setImageURL(imageURL, for: .screenScale2x)
        }

        return item
    }

    private static func renderImage(for descriptor: CardDescriptor) -> URL? {
        let size = TVTopShelfSectionedContent.imageSize(for: .hdtv)
        let outputDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("HATVTopShelf", isDirectory: true)
        try? FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

        let fileURL = outputDirectory.appendingPathComponent("\(descriptor.id).png")
        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { context in
            drawCard(
                in: context.cgContext,
                size: size,
                descriptor: descriptor
            )
        }

        guard let data = image.pngData() else {
            return nil
        }

        do {
            try data.write(to: fileURL, options: .atomic)
            return fileURL
        } catch {
            return nil
        }
    }

    private static func drawCard(
        in context: CGContext,
        size: CGSize,
        descriptor: CardDescriptor
    ) {
        let bounds = CGRect(origin: .zero, size: size)
        let backgroundColor = UIColor(red: 0.05, green: 0.09, blue: 0.14, alpha: 1)
        let cardColor = UIColor(red: 0.10, green: 0.14, blue: 0.20, alpha: 1)
        let secondaryTextColor = UIColor(white: 1, alpha: 0.70)

        context.setFillColor(backgroundColor.cgColor)
        context.fill(bounds)

        let gradient = CGGradient(
            colorsSpace: CGColorSpaceCreateDeviceRGB(),
            colors: [cardColor.cgColor, UIColor(red: 0.06, green: 0.10, blue: 0.16, alpha: 1).cgColor] as CFArray,
            locations: [0, 1]
        )
        context.drawLinearGradient(
            gradient!,
            start: CGPoint(x: 0, y: 0),
            end: CGPoint(x: size.width, y: size.height),
            options: []
        )

        let accentRect = CGRect(x: 0, y: 0, width: size.width, height: max(size.height * 0.08, 42))
        context.setFillColor(descriptor.accentColor.cgColor)
        context.fill(accentRect)

        let inset = size.width * 0.055
        let titleRect = CGRect(x: inset, y: size.height * 0.23, width: size.width * 0.62, height: size.height * 0.22)
        let subtitleRect = CGRect(x: inset, y: size.height * 0.50, width: size.width * 0.60, height: size.height * 0.18)
        let eyebrowRect = CGRect(x: inset, y: size.height * 0.12, width: size.width * 0.30, height: size.height * 0.08)

        let symbolPointSize = size.height * 0.18
        let symbolConfiguration = UIImage.SymbolConfiguration(pointSize: symbolPointSize, weight: .bold)
        let symbolRect = CGRect(
            x: size.width - inset - symbolPointSize * 1.35,
            y: size.height * 0.23,
            width: symbolPointSize * 1.1,
            height: symbolPointSize * 1.1
        )

        if let symbolImage = UIImage(systemName: descriptor.symbolName, withConfiguration: symbolConfiguration)?
            .withTintColor(.white, renderingMode: .alwaysOriginal) {
            symbolImage.draw(in: symbolRect)
        }

        let eyebrowAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: size.height * 0.06, weight: .bold),
            .foregroundColor: UIColor(white: 1, alpha: 0.92)
        ]
        NSString(string: descriptor.eyebrow).draw(in: eyebrowRect, withAttributes: eyebrowAttributes)

        let titleParagraph = NSMutableParagraphStyle()
        titleParagraph.lineBreakMode = .byTruncatingTail
        let titleAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: size.height * 0.14, weight: .bold),
            .foregroundColor: UIColor.white,
            .paragraphStyle: titleParagraph
        ]
        NSString(string: descriptor.title).draw(with: titleRect, options: [.usesLineFragmentOrigin], attributes: titleAttributes, context: nil)

        let subtitleParagraph = NSMutableParagraphStyle()
        subtitleParagraph.lineBreakMode = .byTruncatingTail
        let subtitleAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: size.height * 0.075, weight: .semibold),
            .foregroundColor: secondaryTextColor,
            .paragraphStyle: subtitleParagraph
        ]
        NSString(string: descriptor.subtitle).draw(with: subtitleRect, options: [.usesLineFragmentOrigin], attributes: subtitleAttributes, context: nil)

        let footerRect = CGRect(
            x: inset,
            y: size.height - size.height * 0.18,
            width: size.width * 0.38,
            height: size.height * 0.10
        )
        let footerPath = UIBezierPath(roundedRect: footerRect, cornerRadius: footerRect.height / 2)
        UIColor.white.withAlphaComponent(0.10).setFill()
        footerPath.fill()

        let footerAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: size.height * 0.055, weight: .bold),
            .foregroundColor: UIColor.white.withAlphaComponent(0.82)
        ]
        let footerText = descriptor.eyebrow == "LIVE" ? "Open full screen" : "Open in HATV"
        NSString(string: footerText).draw(
            in: footerRect.insetBy(dx: footerRect.height * 0.42, dy: footerRect.height * 0.18),
            withAttributes: footerAttributes
        )
    }
}

