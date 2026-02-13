import AppKit

// [macOS 14] Performance workaround: loadAXBundles can block the main thread
// for 10-30ms during app launch. This swizzle moves the loading to a background
// thread unless VoiceOver is active. Adapted from MarkEdit (ships on App Store).
extension NSObject {
    static let swizzleAccessibilityBundlesOnce: () = {
        // Load the AccessibilityBundles private framework
        let path = [
            "",
            "System",
            "Library",
            "PrivateFrameworks",
            "AccessibilityBundles.framework",
        ].joined(separator: "/")

        Bundle(path: path)?.load()

        guard let axClass = NSClassFromString("AXBBundleManager") else {
            NSLog("[AppHacks] AXBBundleManager class not found — skipping swizzle")
            return
        }

        let originalSelector = sel_getUid("loadAXBundles")
        let swizzledSelector = #selector(swizzled_loadAXBundles)

        guard let originalMethod = class_getInstanceMethod(axClass, originalSelector),
              let swizzledMethod = class_getInstanceMethod(NSObject.self, swizzledSelector) else {
            NSLog("[AppHacks] loadAXBundles method not found — skipping swizzle")
            return
        }

        if class_addMethod(
            axClass,
            originalSelector,
            method_getImplementation(swizzledMethod),
            method_getTypeEncoding(swizzledMethod)
        ) {
            class_replaceMethod(
                axClass,
                swizzledSelector,
                method_getImplementation(originalMethod),
                method_getTypeEncoding(originalMethod)
            )
        } else {
            method_exchangeImplementations(originalMethod, swizzledMethod)
        }
    }()
}

// MARK: - Private

private extension NSObject {
    enum AXLoadState {
        nonisolated(unsafe) static var loaded = false
    }

    @objc func swizzled_loadAXBundles() -> Bool {
        defer { AXLoadState.loaded = true }

        guard !AXLoadState.loaded else { return false }

        // If VoiceOver is active, load synchronously (accessibility takes priority)
        guard !NSWorkspace.shared.isVoiceOverEnabled else {
            return self.swizzled_loadAXBundles() // Calls original via swizzle
        }

        // Move to background thread to avoid blocking launch
        DispatchQueue.global(qos: .userInitiated).async {
            _ = self.swizzled_loadAXBundles() // Calls original via swizzle
        }

        return true
    }
}
