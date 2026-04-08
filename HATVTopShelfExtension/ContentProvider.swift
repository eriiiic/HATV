import TVServices

final class ContentProvider: TVTopShelfContentProvider {

    override func loadTopShelfContent() async -> (any TVTopShelfContent)? {
        HATVTopShelfRenderer.makeContent(from: HATVTopShelfSnapshotStore.read())
    }
}

