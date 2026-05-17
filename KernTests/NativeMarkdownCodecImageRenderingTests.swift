import XCTest
@testable import KernTextKit

final class NativeMarkdownCodecImageRenderingTests: XCTestCase {
    override func tearDown() {
        URLProtocol.unregisterClass(MockRemoteImageURLProtocol.self)
        MarkdownImageAttachment.configureRemoteImageProtocolClassesForTesting(nil)
        MarkdownImageAttachment.configureDecodeLimitsForTesting()
        MarkdownImageAttachment.resetImageCacheForTesting()
        MockRemoteImageURLProtocol.responseHeaders = ["Content-Type": "image/png"]
        MockRemoteImageURLProtocol.statusCode = 200
        super.tearDown()
    }

    @MainActor
    func testLocalImagesFromStressFixtureResolveAndRender() throws {
        let fixtureURL = repoRoot()
            .appendingPathComponent("test-fixtures", isDirectory: true)
            .appendingPathComponent("stress-test.md", isDirectory: false)
        let markdown = try String(contentsOf: fixtureURL, encoding: .utf8)

        let defaultsName = "\(type(of: self)).testLocalImagesFromStressFixtureResolveAndRender"
        guard let defaults = UserDefaults(suiteName: defaultsName) else {
            XCTFail("Expected isolated UserDefaults suite")
            return
        }
        defaults.removePersistentDomain(forName: defaultsName)
        defer { defaults.removePersistentDomain(forName: defaultsName) }

        var options = NativeMarkdownCodec.Options.fromUserDefaults(defaults)
        options.remoteImageLoadingEnabled = false

        let attributed = NativeMarkdownCodec.importMarkdown(markdown, options: options, baseURL: fixtureURL)
        let images = collectImageAttachments(in: attributed)

        XCTAssertFalse(images.isEmpty, "Expected image attachments in stress fixture")

        guard let local = images.first(where: { $0.destination.contains("screenshots/01-default-sample.png") }) else {
            XCTFail("Missing local stress-fixture image attachment")
            return
        }

        XCTAssertNotNil(local.resolvedURL)
        XCTAssertTrue(local.resolvedURL?.isFileURL == true)

        // Local images load asynchronously off the main thread; spin the run loop
        // briefly to let the background read + main-queue callback complete.
        let ready = expectation(description: "Local image loads asynchronously")
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            ready.fulfill()
        }
        waitForExpectations(timeout: 3.0)

        XCTAssertTrue(local.debugHasRenderedImage, "Local file image should have loaded")
        XCTAssertEqual(local.loadState, .ready)
    }

    @MainActor
    func testRemoteImageAttachmentRespectsDisabledRemoteLoading() {
        let markdown = "![Remote](https://upload.wikimedia.org/wikipedia/commons/thumb/3/3f/Fronalpstock_big.jpg/640px-Fronalpstock_big.jpg)"
        var options = NativeMarkdownCodec.Options.fromUserDefaults()
        options.remoteImageLoadingEnabled = false

        let attributed = NativeMarkdownCodec.importMarkdown(markdown, options: options, baseURL: nil)
        let images = collectImageAttachments(in: attributed)
        XCTAssertEqual(images.count, 1)

        guard let image = images.first else { return }
        XCTAssertFalse(image.allowsRemoteLoading)
        XCTAssertEqual(image.loadState, .failed)
        XCTAssertFalse(image.debugHasRenderedImage)
    }

    @MainActor
    func testRemoteHTTPSImageLoadsDeterministicallyViaMockProtocol() throws {
        MarkdownImageAttachment.resetImageCacheForTesting()
        MockRemoteImageURLProtocol.responseData = try sampleImageData()
        MockRemoteImageURLProtocol.responseHeaders = ["Content-Type": "image/png"]
        MockRemoteImageURLProtocol.statusCode = 200
        URLProtocol.registerClass(MockRemoteImageURLProtocol.self)
        MarkdownImageAttachment.configureRemoteImageProtocolClassesForTesting([MockRemoteImageURLProtocol.self])
        defer {
            URLProtocol.unregisterClass(MockRemoteImageURLProtocol.self)
            MarkdownImageAttachment.configureRemoteImageProtocolClassesForTesting(nil)
            MarkdownImageAttachment.resetImageCacheForTesting()
        }

        let markdown = "![Remote](https://example.com/mock-remote-image.png)"
        var options = NativeMarkdownCodec.Options.fromUserDefaults()
        options.remoteImageLoadingEnabled = true

        let attributed = NativeMarkdownCodec.importMarkdown(markdown, options: options, baseURL: nil)
        let images = collectImageAttachments(in: attributed)
        XCTAssertEqual(images.count, 1)

        guard let image = images.first else { return }
        XCTAssertEqual(image.resolvedURL?.absoluteString, "https://example.com/mock-remote-image.png")
        XCTAssertTrue(image.allowsRemoteLoading)

        let deadline = Date().addingTimeInterval(2.0)
        while Date() < deadline, !image.debugHasRenderedImage, image.loadState == .loading {
            RunLoop.main.run(until: Date().addingTimeInterval(0.02))
        }

        XCTAssertTrue(image.debugHasRenderedImage, "Mocked remote HTTPS image should load deterministically")
        XCTAssertEqual(image.loadState, .ready)
    }

    @MainActor
    func testRemoteImageLoadingIsDisabledByDefault() {
        let attributed = NativeMarkdownCodec.importMarkdown("![Remote](https://example.com/mock-remote-image.png)")
        let images = collectImageAttachments(in: attributed)
        XCTAssertEqual(images.count, 1)
        XCTAssertFalse(images[0].allowsRemoteLoading)
        XCTAssertEqual(images[0].loadState, .failed)
    }

    @MainActor
    func testRemoteHTTPSImageRejectsNonImageContentType() throws {
        MarkdownImageAttachment.resetImageCacheForTesting()
        MockRemoteImageURLProtocol.responseData = Data("not an image".utf8)
        MockRemoteImageURLProtocol.responseHeaders = ["Content-Type": "text/plain"]
        MockRemoteImageURLProtocol.statusCode = 200
        URLProtocol.registerClass(MockRemoteImageURLProtocol.self)
        MarkdownImageAttachment.configureRemoteImageProtocolClassesForTesting([MockRemoteImageURLProtocol.self])
        defer {
            URLProtocol.unregisterClass(MockRemoteImageURLProtocol.self)
            MarkdownImageAttachment.configureRemoteImageProtocolClassesForTesting(nil)
            MarkdownImageAttachment.resetImageCacheForTesting()
        }

        var options = NativeMarkdownCodec.Options.fromUserDefaults()
        options.remoteImageLoadingEnabled = true

        let attributed = NativeMarkdownCodec.importMarkdown("![Remote](https://example.com/mock-remote-image.png)", options: options)
        guard let image = collectImageAttachments(in: attributed).first else {
            return XCTFail("Expected remote image attachment")
        }

        let deadline = Date().addingTimeInterval(1.0)
        while Date() < deadline, image.loadState == .loading {
            RunLoop.main.run(until: Date().addingTimeInterval(0.02))
        }

        XCTAssertEqual(image.loadState, .failed)
        XCTAssertFalse(image.debugHasRenderedImage)
    }

    @MainActor
    func testRemoteHTTPSImageRejectsDecodedPixelBombs() throws {
        MarkdownImageAttachment.resetImageCacheForTesting()
        MarkdownImageAttachment.configureDecodeLimitsForTesting(maxPixelCount: 1)
        MockRemoteImageURLProtocol.responseData = try sampleImageData()
        MockRemoteImageURLProtocol.responseHeaders = ["Content-Type": "image/png"]
        MockRemoteImageURLProtocol.statusCode = 200
        URLProtocol.registerClass(MockRemoteImageURLProtocol.self)
        MarkdownImageAttachment.configureRemoteImageProtocolClassesForTesting([MockRemoteImageURLProtocol.self])
        defer {
            URLProtocol.unregisterClass(MockRemoteImageURLProtocol.self)
            MarkdownImageAttachment.configureRemoteImageProtocolClassesForTesting(nil)
            MarkdownImageAttachment.configureDecodeLimitsForTesting()
            MarkdownImageAttachment.resetImageCacheForTesting()
        }

        var options = NativeMarkdownCodec.Options.fromUserDefaults()
        options.remoteImageLoadingEnabled = true

        let attributed = NativeMarkdownCodec.importMarkdown("![Remote](https://example.com/mock-remote-image.png)", options: options)
        guard let image = collectImageAttachments(in: attributed).first else {
            return XCTFail("Expected remote image attachment")
        }

        let deadline = Date().addingTimeInterval(1.0)
        while Date() < deadline, image.loadState == .loading {
            RunLoop.main.run(until: Date().addingTimeInterval(0.02))
        }

        XCTAssertEqual(image.loadState, .failed)
        XCTAssertFalse(image.debugHasRenderedImage)
    }

    @MainActor
    func testRelativeImageTraversalOutsideDocumentRootStaysUnresolvedAndNotLinked() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("kern-image-security-\(UUID().uuidString)", isDirectory: true)
        let docsDir = tempDir.appendingPathComponent("docs", isDirectory: true)
        try FileManager.default.createDirectory(at: docsDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let markdownURL = docsDir.appendingPathComponent("note.md", isDirectory: false)
        let markdown = "![Escape](../outside.png)"
        try markdown.write(to: markdownURL, atomically: true, encoding: .utf8)

        let attributed = NativeMarkdownCodec.importMarkdown(markdown, options: .fromUserDefaults(), baseURL: markdownURL)
        guard let image = collectImageAttachments(in: attributed).first else {
            return XCTFail("Expected image attachment")
        }

        XCTAssertNil(image.resolvedURL)

        var sawFileLink = false
        attributed.enumerateAttributes(in: NSRange(location: 0, length: attributed.length), options: []) { attrs, _, _ in
            if let linkURL = attrs[.link] as? URL, linkURL.isFileURL {
                sawFileLink = true
            }
        }
        XCTAssertFalse(sawFileLink)
    }

    @MainActor
    func testImagesFixtureOutOfRootLocalsStayUnresolvedAndRemoteImagesStayDisabledByDefault() throws {
        let fixtureURL = repoRoot()
            .appendingPathComponent("test-fixtures", isDirectory: true)
            .appendingPathComponent("native-editor-golden", isDirectory: true)
            .appendingPathComponent("images.fixture.md", isDirectory: false)
        let markdown = try String(contentsOf: fixtureURL, encoding: .utf8)

        let suiteName = "NativeMarkdownCodecImageRenderingTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let attributed = NativeMarkdownCodec.importMarkdown(
            markdown,
            options: .fromUserDefaults(defaults),
            baseURL: fixtureURL
        )
        let images = collectImageAttachments(in: attributed)
        XCTAssertEqual(images.count, 4)

        let localImages = images.filter { $0.destination.hasPrefix("../screenshots/") }
        XCTAssertEqual(localImages.count, 2)
        XCTAssertTrue(localImages.allSatisfy { $0.resolvedURL == nil })
        XCTAssertTrue(localImages.allSatisfy { $0.loadState == .failed })

        let remoteImages = images.filter { $0.destination.hasPrefix("https://") }
        XCTAssertEqual(remoteImages.count, 2)
        XCTAssertTrue(remoteImages.allSatisfy { $0.resolvedURL?.scheme == "https" })
        XCTAssertTrue(remoteImages.allSatisfy { $0.allowsRemoteLoading == false })
        XCTAssertTrue(remoteImages.allSatisfy { $0.loadState == .failed })

        var sawFileLink = false
        attributed.enumerateAttributes(in: NSRange(location: 0, length: attributed.length), options: []) { attrs, _, _ in
            if let linkURL = attrs[.link] as? URL, linkURL.isFileURL {
                sawFileLink = true
            }
        }
        XCTAssertFalse(sawFileLink)
    }

    @MainActor
    func testRelativeImageSymlinkEscapeOutsideDocumentRootStaysUnresolvedAndNotLinked() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("kern-image-symlink-\(UUID().uuidString)", isDirectory: true)
        let docsDir = tempDir.appendingPathComponent("docs", isDirectory: true)
        try FileManager.default.createDirectory(at: docsDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let outsideImage = tempDir.appendingPathComponent("outside.png", isDirectory: false)
        try Data().write(to: outsideImage)

        let symlinkURL = docsDir.appendingPathComponent("inside.png", isDirectory: false)
        try FileManager.default.createSymbolicLink(at: symlinkURL, withDestinationURL: outsideImage)

        let markdownURL = docsDir.appendingPathComponent("note.md", isDirectory: false)
        let markdown = "![Escape](inside.png)"
        try markdown.write(to: markdownURL, atomically: true, encoding: .utf8)

        let attributed = NativeMarkdownCodec.importMarkdown(markdown, options: .fromUserDefaults(), baseURL: markdownURL)
        guard let image = collectImageAttachments(in: attributed).first else {
            return XCTFail("Expected image attachment")
        }

        XCTAssertNil(image.resolvedURL)

        var sawFileLink = false
        attributed.enumerateAttributes(in: NSRange(location: 0, length: attributed.length), options: []) { attrs, _, _ in
            if let linkURL = attrs[.link] as? URL, linkURL.isFileURL {
                sawFileLink = true
            }
        }
        XCTAssertFalse(sawFileLink)
    }

    @MainActor
    func testRelativeImageSymlinkInsideDocumentRootStillResolves() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("kern-image-symlink-safe-\(UUID().uuidString)", isDirectory: true)
        let docsDir = tempDir.appendingPathComponent("docs", isDirectory: true)
        let assetsDir = docsDir.appendingPathComponent("assets", isDirectory: true)
        try FileManager.default.createDirectory(at: assetsDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let realImage = assetsDir.appendingPathComponent("real.png", isDirectory: false)
        try Data().write(to: realImage)

        let symlinkURL = docsDir.appendingPathComponent("inside.png", isDirectory: false)
        try FileManager.default.createSymbolicLink(at: symlinkURL, withDestinationURL: realImage)

        let markdownURL = docsDir.appendingPathComponent("note.md", isDirectory: false)
        let markdown = "![Safe](inside.png)"
        try markdown.write(to: markdownURL, atomically: true, encoding: .utf8)

        let attributed = NativeMarkdownCodec.importMarkdown(markdown, options: .fromUserDefaults(), baseURL: markdownURL)
        guard let image = collectImageAttachments(in: attributed).first else {
            return XCTFail("Expected image attachment")
        }

        XCTAssertNotNil(image.resolvedURL)
        XCTAssertTrue(image.resolvedURL?.isFileURL == true)
    }

    @MainActor
    func testAbsoluteLocalImagePathStaysUnresolvedAndNotLinked() throws {
        let markdown = "![Abs](/tmp/secret.png)"
        let attributed = NativeMarkdownCodec.importMarkdown(markdown, options: .fromUserDefaults(), baseURL: repoRoot())
        guard let image = collectImageAttachments(in: attributed).first else {
            return XCTFail("Expected image attachment")
        }

        XCTAssertNil(image.resolvedURL)

        var sawFileLink = false
        attributed.enumerateAttributes(in: NSRange(location: 0, length: attributed.length), options: []) { attrs, _, _ in
            if let linkURL = attrs[.link] as? URL, linkURL.isFileURL {
                sawFileLink = true
            }
        }
        XCTAssertFalse(sawFileLink)
    }

    @MainActor
    func testAbsoluteFileURLImageStaysUnresolvedAndNotLinked() throws {
        let markdown = "![Abs](file:///tmp/secret.png)"
        let attributed = NativeMarkdownCodec.importMarkdown(markdown, options: .fromUserDefaults(), baseURL: repoRoot())
        guard let image = collectImageAttachments(in: attributed).first else {
            return XCTFail("Expected image attachment")
        }

        XCTAssertNil(image.resolvedURL)

        var sawFileLink = false
        attributed.enumerateAttributes(in: NSRange(location: 0, length: attributed.length), options: []) { attrs, _, _ in
            if let linkURL = attrs[.link] as? URL, linkURL.isFileURL {
                sawFileLink = true
            }
        }
        XCTAssertFalse(sawFileLink)
    }

    @MainActor
    func testCustomSchemeImageStaysUnresolvedAndNotLinked() throws {
        let markdown = "![Scheme](zoommtg://join)"
        let attributed = NativeMarkdownCodec.importMarkdown(markdown, options: .fromUserDefaults(), baseURL: repoRoot())
        guard let image = collectImageAttachments(in: attributed).first else {
            return XCTFail("Expected image attachment")
        }

        XCTAssertNil(image.resolvedURL)

        var sawLink = false
        attributed.enumerateAttributes(in: NSRange(location: 0, length: attributed.length), options: []) { attrs, _, _ in
            if attrs[.link] != nil {
                sawLink = true
            }
        }
        XCTAssertFalse(sawLink)
    }

    @MainActor
    func testTildeLocalImagePathStaysUnresolvedAndNotLinked() throws {
        let markdown = "![Home](~/secret.png)"
        let attributed = NativeMarkdownCodec.importMarkdown(markdown, options: .fromUserDefaults(), baseURL: repoRoot())
        guard let image = collectImageAttachments(in: attributed).first else {
            return XCTFail("Expected image attachment")
        }

        XCTAssertNil(image.resolvedURL)

        var sawFileLink = false
        attributed.enumerateAttributes(in: NSRange(location: 0, length: attributed.length), options: []) { attrs, _, _ in
            if let linkURL = attrs[.link] as? URL, linkURL.isFileURL {
                sawFileLink = true
            }
        }
        XCTAssertFalse(sawFileLink)
    }

    @MainActor
    func testImageAttachmentsCarryClickableLinkAttributes() throws {
        let fixtureURL = repoRoot()
            .appendingPathComponent("test-fixtures", isDirectory: true)
            .appendingPathComponent("stress-test.md", isDirectory: false)

        let markdown = """
        ![Local sample](screenshots/01-default-sample.png)

        ![Remote sample](https://upload.wikimedia.org/wikipedia/commons/thumb/0/02/Oia%2C_Santorini_HDR_sunset.jpg/640px-Oia%2C_Santorini_HDR_sunset.jpg)
        """

        var options = NativeMarkdownCodec.Options.fromUserDefaults()
        options.remoteImageLoadingEnabled = false

        let attributed = NativeMarkdownCodec.importMarkdown(markdown, options: options, baseURL: fixtureURL)

        var sawLocal = false
        var sawRemote = false
        attributed.enumerateAttributes(in: NSRange(location: 0, length: attributed.length), options: []) { attrs, _, _ in
            guard let attachment = attrs[.attachment] as? MarkdownImageAttachment else { return }
            if attachment.destination.contains("screenshots/01-default-sample.png") {
                sawLocal = true
                guard let linkURL = attrs[.link] as? URL else {
                    XCTFail("Local image attachment missing .link attribute")
                    return
                }
                XCTAssertTrue(linkURL.isFileURL, "Local image should expose file:// link target")
            } else if attachment.destination.contains("upload.wikimedia.org") {
                sawRemote = true
                XCTAssertNil(attrs[.link], "Remote image should not be clickable when remote loading is disabled")
            }
        }

        XCTAssertTrue(sawLocal, "Expected local image attachment with link target")
        XCTAssertTrue(sawRemote, "Expected remote image attachment placeholder")
    }

    @MainActor
    func testAsyncLocalImageLoadInvalidatesLayoutAndExpandsRenderedBlock() throws {
        let sourceImage = repoRoot()
            .appendingPathComponent("test-fixtures", isDirectory: true)
            .appendingPathComponent("screenshots", isDirectory: true)
            .appendingPathComponent("01-default-sample.png", isDirectory: false)

        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("kern-image-layout-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let copiedImage = tempDir.appendingPathComponent("sample.png", isDirectory: false)
        try FileManager.default.copyItem(at: sourceImage, to: copiedImage)

        let markdownURL = tempDir.appendingPathComponent("fixture.md", isDirectory: false)
        let markdown = "![Local sample](sample.png)\n\nTail\n"
        try markdown.write(to: markdownURL, atomically: true, encoding: .utf8)

        let vc = NativeEditorViewController()
        _ = vc.view
        vc.documentURL = markdownURL
        vc.stringValue = markdown
        let window = hostInWindow(vc: vc, size: NSSize(width: 960, height: 640), appearance: .init(named: .darkAqua))
        window.displayIfNeeded()

        let textView = vc.textViewForTesting()
        guard let textStorage = textView.textStorage,
              let textContainer = textView.textContainer,
              let layoutManager = textView.layoutManager,
              let attachment = collectImageAttachments(in: textStorage).first else {
            XCTFail("Missing local image attachment in rendered editor")
            return
        }

        layoutManager.ensureLayout(for: textContainer)
        XCTAssertEqual(attachment.loadState, .loading, "Fresh local image should begin in loading state before async decode finishes")
        let initialBounds = attachmentBounds(
            for: attachment,
            at: 0,
            in: textView,
            layoutManager: layoutManager,
            textContainer: textContainer
        )

        let deadline = Date().addingTimeInterval(2.0)
        while Date() < deadline, !attachment.debugHasRenderedImage {
            RunLoop.main.run(until: Date().addingTimeInterval(0.02))
            window.displayIfNeeded()
            layoutManager.ensureLayout(for: textContainer)
        }

        XCTAssertTrue(attachment.debugHasRenderedImage, "Local image should eventually decode")
        XCTAssertEqual(attachment.loadState, .ready)

        let settleDeadline = Date().addingTimeInterval(0.4)
        var finalBounds = initialBounds
        while Date() < settleDeadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.02))
            window.displayIfNeeded()
            layoutManager.ensureLayout(for: textContainer)
            finalBounds = attachmentBounds(
                for: attachment,
                at: 0,
                in: textView,
                layoutManager: layoutManager,
                textContainer: textContainer
            )
        }

        XCTAssertGreaterThan(
            finalBounds.height,
            initialBounds.height + 80,
            "Attachment bounds should expand after the async local image load invalidates placeholder bounds"
        )
    }

    // MARK: - Helpers

    private func collectImageAttachments(in attributed: NSAttributedString) -> [MarkdownImageAttachment] {
        var out: [MarkdownImageAttachment] = []
        let full = NSRange(location: 0, length: attributed.length)
        attributed.enumerateAttribute(.attachment, in: full, options: []) { value, _, _ in
            if let attachment = value as? MarkdownImageAttachment {
                out.append(attachment)
            }
        }
        return out
    }

    private func repoRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // KernTests
            .deletingLastPathComponent() // repo root
    }

    private func sampleImageData() throws -> Data {
        try Data(contentsOf: repoRoot()
            .appendingPathComponent("test-fixtures", isDirectory: true)
            .appendingPathComponent("screenshots", isDirectory: true)
            .appendingPathComponent("01-default-sample.png", isDirectory: false))
    }

    @MainActor
    private func hostInWindow(vc: NSViewController, size: NSSize, appearance: NSAppearance?) -> NSWindow {
        let rect = NSRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: rect, styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.backgroundColor = NSColor.windowBackgroundColor
        window.appearance = appearance
        window.contentViewController = vc
        window.setFrame(rect, display: true)
        window.contentView?.layoutSubtreeIfNeeded()
        return window
    }

    @MainActor
    private func attachmentBounds(
        for attachment: MarkdownImageAttachment,
        at location: Int,
        in textView: NSTextView,
        layoutManager: NSLayoutManager,
        textContainer: NSTextContainer
    ) -> NSRect {
        let glyphRange = layoutManager.glyphRange(forCharacterRange: NSRange(location: location, length: 1), actualCharacterRange: nil)
        let lineFragment = glyphRange.length > 0
            ? layoutManager.lineFragmentRect(forGlyphAt: glyphRange.location, effectiveRange: nil)
            : NSRect(origin: .zero, size: textContainer.containerSize)
        return attachment.attachmentBounds(
            for: textContainer,
            proposedLineFragment: lineFragment,
            glyphPosition: .zero,
            characterIndex: location
        )
    }
}

private final class MockRemoteImageURLProtocol: URLProtocol {
    nonisolated(unsafe) static var responseData = Data()
    nonisolated(unsafe) static var responseHeaders: [String: String] = ["Content-Type": "image/png"]
    nonisolated(unsafe) static var statusCode = 200

    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.host == "example.com"
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let url = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }

        let response = HTTPURLResponse(
            url: url,
            statusCode: Self.statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: Self.responseHeaders
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.responseData)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
