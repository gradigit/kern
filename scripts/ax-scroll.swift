import Cocoa
import Foundation

// Usage: ax-scroll <pid> <heading_index | "bottom" | "elements" <index>>
// - heading_index: scroll to the Nth heading in the AX tree
// - "bottom": iteratively scroll to the last heading, re-scanning until no new headings appear
// - "elements" <index>: scroll to the Nth content element (any type) for fine-grained scrolling

guard CommandLine.arguments.count >= 3,
      let pid = Int32(CommandLine.arguments[1]) else { exit(1) }

let target = CommandLine.arguments[2]

func findEl(_ e: AXUIElement, role r: String) -> AXUIElement? {
    var rv: CFTypeRef?
    guard AXUIElementCopyAttributeValue(e, kAXRoleAttribute as CFString, &rv) == .success,
          let role = rv as? String else { return nil }
    if role == r { return e }
    var cv: CFTypeRef?
    guard AXUIElementCopyAttributeValue(e, kAXChildrenAttribute as CFString, &cv) == .success,
          let ch = cv as? [AXUIElement] else { return nil }
    for c in ch { if let f = findEl(c, role: r) { return f } }
    return nil
}

func collectHeadings(_ e: AXUIElement, d: Int = 0) -> [AXUIElement] {
    var r: [AXUIElement] = []
    var rv: CFTypeRef?
    guard AXUIElementCopyAttributeValue(e, kAXRoleAttribute as CFString, &rv) == .success,
          let role = rv as? String else { return r }
    if role == "AXHeading" { r.append(e) }
    if d > 8 { return r }
    var cv: CFTypeRef?
    guard AXUIElementCopyAttributeValue(e, kAXChildrenAttribute as CFString, &cv) == .success,
          let ch = cv as? [AXUIElement] else { return r }
    for c in ch { r.append(contentsOf: collectHeadings(c, d: d + 1)) }
    return r
}

func collectElements(_ e: AXUIElement, d: Int = 0) -> [AXUIElement] {
    var r: [AXUIElement] = []
    var rv: CFTypeRef?
    guard AXUIElementCopyAttributeValue(e, kAXRoleAttribute as CFString, &rv) == .success,
          let role = rv as? String else { return r }
    let contentRoles: Set<String> = ["AXStaticText", "AXGroup", "AXHeading", "AXParagraph", "AXImage", "AXTable", "AXList"]
    if contentRoles.contains(role) { r.append(e) }
    if d > 8 { return r }
    var cv: CFTypeRef?
    guard AXUIElementCopyAttributeValue(e, kAXChildrenAttribute as CFString, &cv) == .success,
          let ch = cv as? [AXUIElement] else { return r }
    for c in ch { r.append(contentsOf: collectElements(c, d: d + 1)) }
    return r
}

func headingTitle(_ e: AXUIElement) -> String {
    var tv: CFTypeRef?
    if AXUIElementCopyAttributeValue(e, kAXTitleAttribute as CFString, &tv) == .success,
       let title = tv as? String { return title }
    // Try AXValue as fallback
    if AXUIElementCopyAttributeValue(e, kAXValueAttribute as CFString, &tv) == .success,
       let val = tv as? String { return val }
    return ""
}

let app = AXUIElementCreateApplication(pid)
var wv: CFTypeRef?
guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &wv) == .success,
      let w = wv as? [AXUIElement], let win = w.first,
      let wa = findEl(win, role: "AXWebArea") else {
    print("ERR:no-webarea")
    exit(1)
}

if target == "elements" {
    guard CommandLine.arguments.count >= 4,
          let idx = Int(CommandLine.arguments[3]) else {
        print("ERR:bad-elements-index")
        exit(1)
    }
    let elements = collectElements(wa)
    guard !elements.isEmpty else {
        print("ERR:no-elements")
        exit(1)
    }
    let i = min(idx, elements.count - 1)
    let res = AXUIElementPerformAction(elements[i], "AXScrollToVisible" as CFString)
    print(res == .success ? "OK:\(i)/\(elements.count-1)" : "ERR:\(res.rawValue)")
    exit(res == .success ? 0 : 1)
} else if target == "bottom" {
    // Iteratively scroll to the last visible heading, re-scan, repeat
    // until the last heading stops changing (we've reached the true bottom)
    var lastTitle = ""
    var iterations = 0
    let maxIterations = 50  // safety limit

    while iterations < maxIterations {
        let headings = collectHeadings(wa)
        guard !headings.isEmpty else { break }

        let last = headings.last!
        let title = headingTitle(last)

        // Scroll to the last heading
        let res = AXUIElementPerformAction(last, "AXScrollToVisible" as CFString)
        if res != .success { break }

        iterations += 1

        // If the last heading is the same as before, we've reached the bottom
        if title == lastTitle && !title.isEmpty {
            print("OK:bottom/\(iterations)iterations")
            exit(0)
        }
        lastTitle = title

        // Brief pause to let WKWebView update its AX tree
        usleep(200_000)  // 200ms
    }

    print("OK:bottom/\(iterations)iterations")
    exit(0)
} else {
    // Original mode: scroll to heading at index
    guard let idx = Int(target) else {
        print("ERR:bad-index")
        exit(1)
    }
    let h = collectHeadings(wa)
    guard !h.isEmpty else {
        print("ERR:no-headings")
        exit(1)
    }
    let i = min(idx, h.count - 1)
    let res = AXUIElementPerformAction(h[i], "AXScrollToVisible" as CFString)
    print(res == .success ? "OK:\(i)/\(h.count-1)" : "ERR:\(res.rawValue)")
    exit(res == .success ? 0 : 1)
}
