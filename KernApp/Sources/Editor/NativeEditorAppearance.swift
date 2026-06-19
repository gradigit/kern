import AppKit
import Foundation

enum NativeEditorThemeMode: String, CaseIterable {
    case system
    case kernDark
    case kernLight
    case turbodraftDark
    case turbodraftLight
    case turbodraftIce
    case oneDark
    case githubDark
    case githubLight
    case dracula
    case solarizedDark
    case solarizedLight
    case nordDark
    case tokyoNight
    case rosePine
    case gruvboxDark
    case gruvboxLight
    case catppuccinMocha
    case catppuccinLatte
    case monokaiPro
    case materialDark
    case vscodeDarkPlus
    case sublimeMariana
    case custom
}

enum NativeEditorFontDesign: String {
    case system
    case rounded
    case serif
    case monospaced
}

enum NativeEditorFontFamilyPreset: String, CaseIterable {
    case system
    case sfProText
    case inter
    case jetBrainsMono
    case firaCode
    case menlo
    case sourceSerif
    case atkinsonHyperlegible
    case custom
}

enum NativeEditorTableOverflowMode: String {
    case wrap
    case horizontal
}

enum NativeEditorAppearance {
    static let themeModeKey = "nativeEditor.themeMode"
    static let customThemeJSONKey = "nativeEditor.customThemeJSON"
    static let fontDesignKey = "nativeEditor.fontDesign"
    static let fontFamilyKey = "nativeEditor.fontFamily"
    static let customFontFamilyKey = "nativeEditor.customFontFamily"
    static let fontSizeKey = "nativeEditor.fontSize"
    static let tableOverflowModeKey = "nativeEditor.tableOverflowMode"

    enum ThemeImportError: LocalizedError {
        case fileTooLarge
        case unreadableFile
        case invalidJSON
        case invalidSchema(String)

        var errorDescription: String? {
            switch self {
            case .fileTooLarge:
                return "Theme file is too large. Keep it under 64 KB."
            case .unreadableFile:
                return "Couldn't read the selected theme file."
            case .invalidJSON:
                return "Theme file is not valid JSON."
            case .invalidSchema(let message):
                return "Theme JSON schema error: \(message)"
            }
        }
    }

    struct CustomThemeDefinition: Codable, Equatable {
        var version: Int?
        var name: String?
        var appearance: String?
        var textColor: String?
        var linkColor: String?
        var codeBlockBackground: String?
        var codeBlockStroke: String?
        var inlineCodeBackground: String?
        var fontFamily: String?
        var fontSize: Double?

        func validate() throws {
            let hasUsableField = [
                textColor,
                linkColor,
                codeBlockBackground,
                codeBlockStroke,
                inlineCodeBackground,
                fontFamily,
            ].contains { value in
                guard let value else { return false }
                return !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            } || fontSize != nil

            guard hasUsableField else {
                throw ThemeImportError.invalidSchema("Missing theme fields. Provide at least one color, fontFamily, or fontSize.")
            }

            if let appearance {
                let normalized = appearance.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                if !["system", "light", "dark"].contains(normalized) {
                    throw ThemeImportError.invalidSchema("appearance must be one of: system, light, dark")
                }
            }

            for (label, value) in [
                ("textColor", textColor),
                ("linkColor", linkColor),
                ("codeBlockBackground", codeBlockBackground),
                ("codeBlockStroke", codeBlockStroke),
                ("inlineCodeBackground", inlineCodeBackground),
            ] {
                guard let value else { continue }
                guard NativeEditorAppearance.colorFromHex(value) != nil else {
                    throw ThemeImportError.invalidSchema("\(label) is not a valid hex color")
                }
            }

            if let fontSize {
                guard (10...36).contains(fontSize) else {
                    throw ThemeImportError.invalidSchema("fontSize must be in range 10...36")
                }
            }
        }

        var preferredAppearanceName: NSAppearance.Name? {
            guard let appearance else { return nil }
            switch appearance.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
            case "dark":
                return .darkAqua
            case "light":
                return .aqua
            default:
                return nil
            }
        }
    }

    private struct ThemePalette {
        let preferredAppearance: NSAppearance.Name?
        let editorBackground: NSColor
        let sidebarBackground: NSColor
        let textColor: NSColor
        let secondaryTextColor: NSColor
        let linkColor: NSColor
        let codeBlockBackground: NSColor
        let codeBlockStroke: NSColor
        let inlineCodeBackground: NSColor
        let inlineCodeText: NSColor
        let tableHeaderBackground: NSColor
        let quoteBar: NSColor
        let quoteFill: NSColor
        let syntax: SyntaxPalette

        init(
            preferredAppearance: NSAppearance.Name?,
            editorBackground: NSColor? = nil,
            sidebarBackground: NSColor? = nil,
            textColor: NSColor,
            secondaryTextColor: NSColor? = nil,
            linkColor: NSColor,
            codeBlockBackground: NSColor,
            codeBlockStroke: NSColor,
            inlineCodeBackground: NSColor,
            inlineCodeText: NSColor? = nil,
            tableHeaderBackground: NSColor? = nil,
            quoteBar: NSColor? = nil,
            quoteFill: NSColor? = nil,
            syntax: SyntaxPalette? = nil
        ) {
            self.preferredAppearance = preferredAppearance
            self.editorBackground = editorBackground ?? .textBackgroundColor
            self.sidebarBackground = sidebarBackground ?? .controlBackgroundColor
            self.textColor = textColor
            self.secondaryTextColor = secondaryTextColor ?? .secondaryLabelColor
            self.linkColor = linkColor
            self.codeBlockBackground = codeBlockBackground
            self.codeBlockStroke = codeBlockStroke
            self.inlineCodeBackground = inlineCodeBackground
            self.inlineCodeText = inlineCodeText ?? textColor
            self.tableHeaderBackground = tableHeaderBackground ?? codeBlockBackground.withAlphaComponent(max(0.04, min(1.0, codeBlockBackground.alphaComponent)))
            self.quoteBar = quoteBar ?? .separatorColor
            self.quoteFill = quoteFill ?? codeBlockBackground.withAlphaComponent(max(0.08, min(0.18, codeBlockBackground.alphaComponent)))
            self.syntax = syntax ?? SyntaxPalette.defaultPalette
        }
    }

    struct SyntaxPalette {
        let keyword: NSColor
        let builtin: NSColor
        let string: NSColor
        let number: NSColor
        let comment: NSColor
        let variable: NSColor

        static let defaultPalette = SyntaxPalette(
            keyword: .systemBlue,
            builtin: .systemTeal,
            string: .systemRed,
            number: .systemPurple,
            comment: .secondaryLabelColor,
            variable: .systemOrange
        )
    }

    struct CalloutStyle {
        let fill: NSColor
        let stroke: NSColor
        let accent: NSColor
    }

    private struct ThemePreset {
        let title: String
        let mode: NativeEditorThemeMode
        let palette: ThemePalette
    }

    private static let presetThemes: [NativeEditorThemeMode: ThemePreset] = {
        let defaultDarkBg = NSColor(white: 1.0, alpha: 0.12)
        let defaultDarkStroke = NSColor(white: 1.0, alpha: 0.18)
        let defaultDarkInline = NSColor(white: 1.0, alpha: 0.16)
        let defaultLightBg = NSColor(white: 0.0, alpha: 0.08)
        let defaultLightStroke = NSColor(white: 0.0, alpha: 0.10)
        let defaultLightInline = NSColor(white: 0.0, alpha: 0.08)
        func hex(_ raw: String) -> NSColor {
            NativeEditorAppearance.colorFromHex(raw) ?? .labelColor
        }
        func hexA(_ raw: String, _ alpha: CGFloat) -> NSColor {
            hex(raw).withAlphaComponent(alpha)
        }
        func importedTheme(
            title: String,
            mode: NativeEditorThemeMode,
            dark: Bool,
            background: String,
            foreground: String,
            heading: String,
            code: String,
            codeBackground: String,
            inlineCodeBackground: String,
            link: String,
            quote: String,
            secondary: String,
            highlight: String,
            marker: String? = nil
        ) -> ThemePreset {
            let bg = hex(background)
            let fg = hex(foreground)
            let headingColor = hex(heading)
            let codeColor = hex(code)
            let codeBg = hex(codeBackground)
            let inlineBg = hex(inlineCodeBackground)
            let linkColor = hex(link)
            let quoteColor = hex(quote)
            let secondaryColor = hex(secondary)
            let markerColor = marker.map(hex) ?? secondaryColor
            return ThemePreset(
                title: title,
                mode: mode,
                palette: ThemePalette(
                    preferredAppearance: dark ? .darkAqua : .aqua,
                    editorBackground: bg,
                    sidebarBackground: dark ? codeBg : bg.blended(withFraction: 0.45, of: codeBg) ?? codeBg,
                    textColor: fg,
                    secondaryTextColor: secondaryColor,
                    linkColor: linkColor,
                    codeBlockBackground: codeBg,
                    codeBlockStroke: markerColor.withAlphaComponent(dark ? 0.65 : 0.55),
                    inlineCodeBackground: inlineBg,
                    inlineCodeText: codeColor,
                    tableHeaderBackground: codeBg.blended(withFraction: dark ? 0.18 : 0.08, of: fg) ?? codeBg,
                    quoteBar: quoteColor,
                    quoteFill: quoteColor.withAlphaComponent(dark ? 0.13 : 0.10),
                    syntax: SyntaxPalette(
                        keyword: headingColor,
                        builtin: linkColor,
                        string: codeColor,
                        number: hex(highlight),
                        comment: quoteColor,
                        variable: dark ? hexA(highlight, 0.92) : headingColor
                    )
                )
            )
        }

        return [
            .kernDark: ThemePreset(
                title: "Kern Dark",
                mode: .kernDark,
                palette: ThemePalette(
                    preferredAppearance: .darkAqua,
                    textColor: .labelColor,
                    linkColor: NSColor(calibratedRed: 0.35, green: 0.65, blue: 1.0, alpha: 1.0),
                    codeBlockBackground: defaultDarkBg,
                    codeBlockStroke: defaultDarkStroke,
                    inlineCodeBackground: defaultDarkInline
                )
            ),
            .kernLight: ThemePreset(
                title: "Kern Light",
                mode: .kernLight,
                palette: ThemePalette(
                    preferredAppearance: .aqua,
                    textColor: .labelColor,
                    linkColor: NSColor(calibratedRed: 0.06, green: 0.35, blue: 0.87, alpha: 1.0),
                    codeBlockBackground: defaultLightBg,
                    codeBlockStroke: defaultLightStroke,
                    inlineCodeBackground: defaultLightInline
                )
            ),
            .turbodraftDark: importedTheme(
                title: "TurboDraft Dark", mode: .turbodraftDark, dark: true,
                background: "1d1f21", foreground: "c5c9c6", heading: "e0e2e0",
                code: "c5c9c6", codeBackground: "222425", inlineCodeBackground: "272829",
                link: "60a5fa", quote: "8a8d8a", secondary: "707272", highlight: "60a5fa",
                marker: "454749"
            ),
            .turbodraftLight: importedTheme(
                title: "TurboDraft Light", mode: .turbodraftLight, dark: false,
                background: "f5f6f6", foreground: "424242", heading: "1a1a1a",
                code: "424242", codeBackground: "eaecec", inlineCodeBackground: "e4e6e6",
                link: "1088c8", quote: "686a6c", secondary: "888a8c", highlight: "1088c8",
                marker: "c4c6c8"
            ),
            .turbodraftIce: importedTheme(
                title: "TurboDraft Ice", mode: .turbodraftIce, dark: true,
                background: "09090b", foreground: "e4e6ea", heading: "93c5fd",
                code: "7dd3fc", codeBackground: "050507", inlineCodeBackground: "111114",
                link: "60a5fa", quote: "8a8a94", secondary: "52525b", highlight: "93c5fd",
                marker: "27272a"
            ),
            .oneDark: importedTheme(
                title: "One Dark", mode: .oneDark, dark: true,
                background: "282c34", foreground: "abb2bf", heading: "e5c07b",
                code: "98c379", codeBackground: "21252b", inlineCodeBackground: "2c313a",
                link: "61afef", quote: "8b929e", secondary: "8b929e", highlight: "e5c07b",
                marker: "5c6370"
            ),
            .githubDark: ThemePreset(
                title: "GitHub Dark",
                mode: .githubDark,
                palette: ThemePalette(
                    preferredAppearance: .darkAqua,
                    editorBackground: hex("0d1117"),
                    sidebarBackground: hex("161b22"),
                    textColor: NSColor(calibratedWhite: 0.92, alpha: 1.0),
                    secondaryTextColor: hex("8b949e"),
                    linkColor: NSColor(calibratedRed: 0.35, green: 0.67, blue: 1.0, alpha: 1.0),
                    codeBlockBackground: NSColor(calibratedWhite: 1.0, alpha: 0.10),
                    codeBlockStroke: NSColor(calibratedWhite: 1.0, alpha: 0.16),
                    inlineCodeBackground: NSColor(calibratedWhite: 1.0, alpha: 0.14),
                    inlineCodeText: hex("a5d6ff"),
                    tableHeaderBackground: hex("161b22"),
                    quoteBar: hex("8b949e"),
                    quoteFill: hexA("8b949e", 0.12)
                )
            ),
            .githubLight: ThemePreset(
                title: "GitHub Light",
                mode: .githubLight,
                palette: ThemePalette(
                    preferredAppearance: .aqua,
                    editorBackground: hex("ffffff"),
                    sidebarBackground: hex("f6f8fa"),
                    textColor: NSColor(calibratedRed: 0.15, green: 0.17, blue: 0.20, alpha: 1.0),
                    secondaryTextColor: hex("57606a"),
                    linkColor: NSColor(calibratedRed: 0.03, green: 0.36, blue: 0.84, alpha: 1.0),
                    codeBlockBackground: NSColor(calibratedRed: 0.95, green: 0.96, blue: 0.97, alpha: 1.0),
                    codeBlockStroke: NSColor(calibratedRed: 0.88, green: 0.89, blue: 0.90, alpha: 1.0),
                    inlineCodeBackground: NSColor(calibratedRed: 0.95, green: 0.95, blue: 0.95, alpha: 1.0),
                    inlineCodeText: hex("0a3069"),
                    tableHeaderBackground: hex("f6f8fa"),
                    quoteBar: hex("57606a"),
                    quoteFill: hexA("57606a", 0.09)
                )
            ),
            .dracula: ThemePreset(
                title: "Dracula",
                mode: .dracula,
                palette: ThemePalette(
                    preferredAppearance: .darkAqua,
                    textColor: NSColor(calibratedRed: 0.97, green: 0.97, blue: 0.98, alpha: 1.0),
                    linkColor: NSColor(calibratedRed: 0.49, green: 0.78, blue: 0.94, alpha: 1.0),
                    codeBlockBackground: NSColor(calibratedRed: 0.17, green: 0.18, blue: 0.24, alpha: 1.0),
                    codeBlockStroke: NSColor(calibratedRed: 0.25, green: 0.27, blue: 0.35, alpha: 1.0),
                    inlineCodeBackground: NSColor(calibratedRed: 0.24, green: 0.25, blue: 0.33, alpha: 1.0)
                )
            ),
            .solarizedDark: ThemePreset(
                title: "Solarized Dark",
                mode: .solarizedDark,
                palette: ThemePalette(
                    preferredAppearance: .darkAqua,
                    textColor: NSColor(calibratedRed: 0.51, green: 0.58, blue: 0.59, alpha: 1.0),
                    linkColor: NSColor(calibratedRed: 0.15, green: 0.55, blue: 0.82, alpha: 1.0),
                    codeBlockBackground: NSColor(calibratedRed: 0.03, green: 0.21, blue: 0.26, alpha: 1.0),
                    codeBlockStroke: NSColor(calibratedRed: 0.35, green: 0.43, blue: 0.46, alpha: 1.0),
                    inlineCodeBackground: NSColor(calibratedRed: 0.06, green: 0.26, blue: 0.31, alpha: 1.0)
                )
            ),
            .solarizedLight: ThemePreset(
                title: "Solarized Light",
                mode: .solarizedLight,
                palette: ThemePalette(
                    preferredAppearance: .aqua,
                    textColor: NSColor(calibratedRed: 0.40, green: 0.48, blue: 0.51, alpha: 1.0),
                    linkColor: NSColor(calibratedRed: 0.15, green: 0.55, blue: 0.82, alpha: 1.0),
                    codeBlockBackground: NSColor(calibratedRed: 0.95, green: 0.91, blue: 0.84, alpha: 1.0),
                    codeBlockStroke: NSColor(calibratedRed: 0.88, green: 0.82, blue: 0.73, alpha: 1.0),
                    inlineCodeBackground: NSColor(calibratedRed: 0.93, green: 0.88, blue: 0.80, alpha: 1.0)
                )
            ),
            .nordDark: ThemePreset(
                title: "Nord Dark",
                mode: .nordDark,
                palette: ThemePalette(
                    preferredAppearance: .darkAqua,
                    textColor: NSColor(calibratedRed: 0.85, green: 0.88, blue: 0.92, alpha: 1.0),
                    linkColor: NSColor(calibratedRed: 0.53, green: 0.75, blue: 0.95, alpha: 1.0),
                    codeBlockBackground: NSColor(calibratedRed: 0.18, green: 0.20, blue: 0.25, alpha: 1.0),
                    codeBlockStroke: NSColor(calibratedRed: 0.29, green: 0.33, blue: 0.41, alpha: 1.0),
                    inlineCodeBackground: NSColor(calibratedRed: 0.23, green: 0.26, blue: 0.33, alpha: 1.0)
                )
            ),
            .gruvboxDark: ThemePreset(
                title: "Gruvbox Dark",
                mode: .gruvboxDark,
                palette: ThemePalette(
                    preferredAppearance: .darkAqua,
                    textColor: NSColor(calibratedRed: 0.93, green: 0.86, blue: 0.70, alpha: 1.0),
                    linkColor: NSColor(calibratedRed: 0.53, green: 0.76, blue: 0.30, alpha: 1.0),
                    codeBlockBackground: NSColor(calibratedRed: 0.20, green: 0.18, blue: 0.14, alpha: 1.0),
                    codeBlockStroke: NSColor(calibratedRed: 0.32, green: 0.29, blue: 0.22, alpha: 1.0),
                    inlineCodeBackground: NSColor(calibratedRed: 0.25, green: 0.22, blue: 0.16, alpha: 1.0)
                )
            ),
            .catppuccinMocha: ThemePreset(
                title: "Catppuccin Mocha",
                mode: .catppuccinMocha,
                palette: ThemePalette(
                    preferredAppearance: .darkAqua,
                    textColor: NSColor(calibratedRed: 0.80, green: 0.84, blue: 0.96, alpha: 1.0),
                    linkColor: NSColor(calibratedRed: 0.54, green: 0.67, blue: 0.99, alpha: 1.0),
                    codeBlockBackground: NSColor(calibratedRed: 0.19, green: 0.20, blue: 0.27, alpha: 1.0),
                    codeBlockStroke: NSColor(calibratedRed: 0.30, green: 0.31, blue: 0.40, alpha: 1.0),
                    inlineCodeBackground: NSColor(calibratedRed: 0.23, green: 0.24, blue: 0.33, alpha: 1.0)
                )
            ),
            .catppuccinLatte: importedTheme(
                title: "Catppuccin Latte", mode: .catppuccinLatte, dark: false,
                background: "eff1f5", foreground: "4c4f69", heading: "1e66f5",
                code: "40a02b", codeBackground: "e6e9ef", inlineCodeBackground: "dce0e8",
                link: "1e66f5", quote: "6c6f85", secondary: "6c6f85", highlight: "df8e1d",
                marker: "9ca0b0"
            ),
            .tokyoNight: importedTheme(
                title: "Tokyo Night", mode: .tokyoNight, dark: true,
                background: "1a1b26", foreground: "a9b1d6", heading: "7aa2f7",
                code: "9ece6a", codeBackground: "16161e", inlineCodeBackground: "232433",
                link: "7dcfff", quote: "9099b7", secondary: "9099b7", highlight: "e0af68",
                marker: "565f89"
            ),
            .rosePine: importedTheme(
                title: "Rose Pine", mode: .rosePine, dark: true,
                background: "191724", foreground: "e0def4", heading: "c4a7e7",
                code: "9ccfd8", codeBackground: "1f1d2e", inlineCodeBackground: "26233a",
                link: "ebbcba", quote: "b4b1cc", secondary: "b4b1cc", highlight: "f6c177",
                marker: "6e6a86"
            ),
            .gruvboxLight: importedTheme(
                title: "Gruvbox Light", mode: .gruvboxLight, dark: false,
                background: "fbf1c7", foreground: "3c3836", heading: "d79921",
                code: "79740e", codeBackground: "f2e5bc", inlineCodeBackground: "ebdbb2",
                link: "458588", quote: "504945", secondary: "504945", highlight: "d79921",
                marker: "928374"
            ),
            .monokaiPro: importedTheme(
                title: "Monokai Pro", mode: .monokaiPro, dark: true,
                background: "2d2a2e", foreground: "fcfcfa", heading: "ffd866",
                code: "a9dc76", codeBackground: "221f22", inlineCodeBackground: "3a373b",
                link: "78dce8", quote: "c1c0c0", secondary: "c1c0c0", highlight: "ffd866",
                marker: "727072"
            ),
            .materialDark: importedTheme(
                title: "Material Dark", mode: .materialDark, dark: true,
                background: "212121", foreground: "eeffff", heading: "c792ea",
                code: "c3e88d", codeBackground: "1a1a1a", inlineCodeBackground: "2c2c2c",
                link: "82aaff", quote: "b0bec5", secondary: "b0bec5", highlight: "ffcb6b",
                marker: "545454"
            ),
            .vscodeDarkPlus: importedTheme(
                title: "VS Code Dark+", mode: .vscodeDarkPlus, dark: true,
                background: "1e1e1e", foreground: "d4d4d4", heading: "569cd6",
                code: "ce9178", codeBackground: "1a1a1a", inlineCodeBackground: "2d2d2d",
                link: "4ec9b0", quote: "9e9e9e", secondary: "9e9e9e", highlight: "dcdcaa",
                marker: "808080"
            ),
            .sublimeMariana: importedTheme(
                title: "Sublime Mariana", mode: .sublimeMariana, dark: true,
                background: "303841", foreground: "d8dee9", heading: "ee932b",
                code: "99c794", codeBackground: "272d35", inlineCodeBackground: "3c444e",
                link: "6699cc", quote: "a6acb5", secondary: "a6acb5", highlight: "fac761",
                marker: "6d7a8a"
            ),
        ]
    }()

    static var builtInThemeChoices: [(title: String, value: String)] {
        [
            ("System", NativeEditorThemeMode.system.rawValue),
            ("Kern Dark", NativeEditorThemeMode.kernDark.rawValue),
            ("Kern Light", NativeEditorThemeMode.kernLight.rawValue),
            ("TurboDraft Dark", NativeEditorThemeMode.turbodraftDark.rawValue),
            ("TurboDraft Light", NativeEditorThemeMode.turbodraftLight.rawValue),
            ("TurboDraft Ice", NativeEditorThemeMode.turbodraftIce.rawValue),
            ("One Dark", NativeEditorThemeMode.oneDark.rawValue),
            ("GitHub Dark", NativeEditorThemeMode.githubDark.rawValue),
            ("GitHub Light", NativeEditorThemeMode.githubLight.rawValue),
            ("Dracula", NativeEditorThemeMode.dracula.rawValue),
            ("Solarized Dark", NativeEditorThemeMode.solarizedDark.rawValue),
            ("Solarized Light", NativeEditorThemeMode.solarizedLight.rawValue),
            ("Nord Dark", NativeEditorThemeMode.nordDark.rawValue),
            ("Tokyo Night", NativeEditorThemeMode.tokyoNight.rawValue),
            ("Rose Pine", NativeEditorThemeMode.rosePine.rawValue),
            ("Gruvbox Dark", NativeEditorThemeMode.gruvboxDark.rawValue),
            ("Gruvbox Light", NativeEditorThemeMode.gruvboxLight.rawValue),
            ("Catppuccin Mocha", NativeEditorThemeMode.catppuccinMocha.rawValue),
            ("Catppuccin Latte", NativeEditorThemeMode.catppuccinLatte.rawValue),
            ("Monokai Pro", NativeEditorThemeMode.monokaiPro.rawValue),
            ("Material Dark", NativeEditorThemeMode.materialDark.rawValue),
            ("VS Code Dark+", NativeEditorThemeMode.vscodeDarkPlus.rawValue),
            ("Sublime Mariana", NativeEditorThemeMode.sublimeMariana.rawValue),
            ("Custom Theme JSON", NativeEditorThemeMode.custom.rawValue),
        ]
    }

    static var fontFamilyChoices: [(title: String, value: String)] {
        [
            ("System default", NativeEditorFontFamilyPreset.system.rawValue),
            ("SF Pro Text", NativeEditorFontFamilyPreset.sfProText.rawValue),
            ("Inter", NativeEditorFontFamilyPreset.inter.rawValue),
            ("JetBrains Mono", NativeEditorFontFamilyPreset.jetBrainsMono.rawValue),
            ("Fira Code", NativeEditorFontFamilyPreset.firaCode.rawValue),
            ("Menlo", NativeEditorFontFamilyPreset.menlo.rawValue),
            ("Source Serif", NativeEditorFontFamilyPreset.sourceSerif.rawValue),
            ("Atkinson Hyperlegible", NativeEditorFontFamilyPreset.atkinsonHyperlegible.rawValue),
            ("Custom family (typed below)", NativeEditorFontFamilyPreset.custom.rawValue),
        ]
    }

    static func themeMode(defaults: UserDefaults = .standard) -> NativeEditorThemeMode {
        guard let raw = defaults.string(forKey: themeModeKey),
              let mode = NativeEditorThemeMode(rawValue: raw) else {
            return .system
        }
        return mode
    }

    static func fontDesign(defaults: UserDefaults = .standard) -> NativeEditorFontDesign {
        guard let raw = defaults.string(forKey: fontDesignKey),
              let design = NativeEditorFontDesign(rawValue: raw) else {
            return .system
        }
        return design
    }

    static func fontFamilyPreset(defaults: UserDefaults = .standard) -> NativeEditorFontFamilyPreset {
        guard let raw = defaults.string(forKey: fontFamilyKey),
              let preset = NativeEditorFontFamilyPreset(rawValue: raw) else {
            return .system
        }
        return preset
    }

    static func customFontFamily(defaults: UserDefaults = .standard) -> String? {
        guard let raw = defaults.string(forKey: customFontFamilyKey) else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    static func fontSize(defaults: UserDefaults = .standard) -> CGFloat {
        let raw = defaults.double(forKey: fontSizeKey)
        if raw == 0 {
            return 16
        }
        return CGFloat(min(24, max(12, raw)))
    }

    static func tableOverflowMode(defaults: UserDefaults = .standard) -> NativeEditorTableOverflowMode {
        guard let raw = defaults.string(forKey: tableOverflowModeKey),
              let mode = NativeEditorTableOverflowMode(rawValue: raw) else {
            return .wrap
        }
        return mode
    }

    static func baseFont(defaults: UserDefaults = .standard) -> NSFont {
        let size = fontSize(defaults: defaults)
        if let explicitFamily = resolvedExplicitFontFamily(defaults: defaults),
           let explicit = NSFont(name: explicitFamily, size: size) {
            return explicit
        }

        switch fontDesign(defaults: defaults) {
        case .system:
            return NSFont.systemFont(ofSize: size)
        case .rounded:
            if let descriptor = NSFont.systemFont(ofSize: size).fontDescriptor.withDesign(.rounded),
               let font = NSFont(descriptor: descriptor, size: size) {
                return font
            }
            return NSFont.systemFont(ofSize: size)
        case .serif:
            if let descriptor = NSFont.systemFont(ofSize: size).fontDescriptor.withDesign(.serif),
               let font = NSFont(descriptor: descriptor, size: size) {
                return font
            }
            return NSFont.systemFont(ofSize: size)
        case .monospaced:
            return NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
        }
    }

    static func headingFont(level: Int, defaults: UserDefaults = .standard) -> NSFont {
        let baseSize = baseFont(defaults: defaults).pointSize
        let lvl = max(1, min(6, level))
        let size: CGFloat
        switch lvl {
        case 1:
            size = baseSize * 1.75
        case 2:
            size = baseSize * 1.375
        case 3:
            size = baseSize * 1.125
        default:
            size = baseSize
        }

        let body = baseFont(defaults: defaults)
        let boldDescriptor = body.fontDescriptor.withSymbolicTraits([.bold])
        if let font = NSFont(descriptor: boldDescriptor, size: size) {
            return font
        }
        return NSFont.systemFont(ofSize: size, weight: .bold)
    }

    static func primaryTextColor(defaults: UserDefaults = .standard) -> NSColor {
        resolvedThemePalette(defaults: defaults).textColor
    }

    static func secondaryTextColor(defaults: UserDefaults = .standard) -> NSColor {
        resolvedThemePalette(defaults: defaults).secondaryTextColor
    }

    static func linkColor(defaults: UserDefaults = .standard) -> NSColor {
        resolvedThemePalette(defaults: defaults).linkColor
    }

    static func editorBackgroundColor(defaults: UserDefaults = .standard, appearance: NSAppearance? = nil) -> NSColor {
        resolvedThemePalette(defaults: defaults, appearance: appearance).editorBackground
    }

    static func sidebarBackgroundColor(defaults: UserDefaults = .standard, appearance: NSAppearance? = nil) -> NSColor {
        resolvedThemePalette(defaults: defaults, appearance: appearance).sidebarBackground
    }

    static func inlineCodeTextColor(defaults: UserDefaults = .standard, appearance: NSAppearance? = nil) -> NSColor {
        resolvedThemePalette(defaults: defaults, appearance: appearance).inlineCodeText
    }

    static func inlineCodeBackgroundColor(defaults: UserDefaults = .standard, appearance: NSAppearance? = nil) -> NSColor {
        let palette = resolvedThemePalette(defaults: defaults, appearance: appearance)
        return palette.inlineCodeBackground
    }

    static func codeBlockBackgroundColor(defaults: UserDefaults = .standard, appearance: NSAppearance? = nil) -> NSColor {
        let palette = resolvedThemePalette(defaults: defaults, appearance: appearance)
        return palette.codeBlockBackground
    }

    static func codeBlockStrokeColor(defaults: UserDefaults = .standard, appearance: NSAppearance? = nil) -> NSColor {
        let palette = resolvedThemePalette(defaults: defaults, appearance: appearance)
        return palette.codeBlockStroke
    }

    static func tableHeaderBackgroundColor(defaults: UserDefaults = .standard, appearance: NSAppearance? = nil) -> NSColor {
        resolvedThemePalette(defaults: defaults, appearance: appearance).tableHeaderBackground
    }

    static func quoteBarColor(defaults: UserDefaults = .standard, appearance: NSAppearance? = nil) -> NSColor {
        resolvedThemePalette(defaults: defaults, appearance: appearance).quoteBar
    }

    static func quoteFillColor(defaults: UserDefaults = .standard, appearance: NSAppearance? = nil) -> NSColor {
        resolvedThemePalette(defaults: defaults, appearance: appearance).quoteFill
    }

    static func syntaxPalette(defaults: UserDefaults = .standard, appearance: NSAppearance? = nil) -> SyntaxPalette {
        resolvedThemePalette(defaults: defaults, appearance: appearance).syntax
    }

    static func calloutStyle(kind: KernCalloutKind, defaults: UserDefaults = .standard, appearance: NSAppearance? = nil) -> CalloutStyle {
        let palette = resolvedThemePalette(defaults: defaults, appearance: appearance)
        let base: NSColor
        switch kind {
        case .note:
            base = palette.linkColor
        case .tip:
            base = palette.syntax.builtin
        case .success:
            base = NSColor.systemGreen
        case .warning:
            base = NSColor.systemYellow
        case .caution:
            base = NSColor.systemRed
        case .important:
            base = palette.syntax.keyword
        }
        return CalloutStyle(
            fill: base.withAlphaComponent(isDarkAppearance(appearance) ? 0.16 : 0.11),
            stroke: base.withAlphaComponent(isDarkAppearance(appearance) ? 0.30 : 0.22),
            accent: base
        )
    }

    static func appearanceCacheSignature(defaults: UserDefaults = .standard) -> String {
        let mode = themeMode(defaults: defaults).rawValue
        let customTheme = defaults.string(forKey: customThemeJSONKey) ?? ""
        return "\(mode)|\(customTheme.hashValue)"
    }

    static func importedCustomTheme(defaults: UserDefaults = .standard) -> CustomThemeDefinition? {
        guard let raw = defaults.string(forKey: customThemeJSONKey), !raw.isEmpty else { return nil }
        guard let data = raw.data(using: .utf8),
              let decoded = try? JSONDecoder().decode(CustomThemeDefinition.self, from: data) else {
            return nil
        }
        try? decoded.validate()
        return decoded
    }

    static func importCustomTheme(from fileURL: URL, defaults: UserDefaults = .standard) throws {
        let attrs = try? FileManager.default.attributesOfItem(atPath: fileURL.path)
        if let size = attrs?[.size] as? NSNumber, size.intValue > 64_000 {
            throw ThemeImportError.fileTooLarge
        }

        guard let data = try? Data(contentsOf: fileURL) else {
            throw ThemeImportError.unreadableFile
        }
        guard let raw = String(data: data, encoding: .utf8) else {
            throw ThemeImportError.invalidJSON
        }
        guard let decoded = try? JSONDecoder().decode(CustomThemeDefinition.self, from: data) else {
            throw ThemeImportError.invalidJSON
        }
        try decoded.validate()

        defaults.set(raw, forKey: customThemeJSONKey)
        defaults.set(NativeEditorThemeMode.custom.rawValue, forKey: themeModeKey)

        if let fontFamily = decoded.fontFamily?.trimmingCharacters(in: .whitespacesAndNewlines), !fontFamily.isEmpty {
            defaults.set(NativeEditorFontFamilyPreset.custom.rawValue, forKey: fontFamilyKey)
            defaults.set(fontFamily, forKey: customFontFamilyKey)
        }

        if let fontSize = decoded.fontSize {
            defaults.set(CGFloat(fontSize), forKey: fontSizeKey)
        }
    }

    @MainActor
    static func applyTheme(to window: NSWindow?, defaults: UserDefaults = .standard) {
        guard let window else { return }
        let palette = resolvedThemePalette(defaults: defaults, appearance: window.effectiveAppearance)
        window.appearance = palette.preferredAppearance.flatMap { NSAppearance(named: $0) }
    }

    private static func resolvedExplicitFontFamily(defaults: UserDefaults) -> String? {
        switch fontFamilyPreset(defaults: defaults) {
        case .system:
            return nil
        case .sfProText:
            return firstAvailableFontFamily(["SF Pro Text", ".SF NS Text", "Helvetica Neue"])
        case .inter:
            return firstAvailableFontFamily(["Inter", "SF Pro Text", "Helvetica Neue"])
        case .jetBrainsMono:
            return firstAvailableFontFamily(["JetBrainsMono-Regular", "JetBrains Mono", "Menlo"])
        case .firaCode:
            return firstAvailableFontFamily(["FiraCode-Regular", "Fira Code", "Menlo"])
        case .menlo:
            return firstAvailableFontFamily(["Menlo", "SF Mono", "Monaco"])
        case .sourceSerif:
            return firstAvailableFontFamily(["SourceSerif4-Regular", "Source Serif 4", "Times New Roman"])
        case .atkinsonHyperlegible:
            return firstAvailableFontFamily(["AtkinsonHyperlegible-Regular", "Atkinson Hyperlegible", "Helvetica Neue"])
        case .custom:
            return customFontFamily(defaults: defaults)
        }
    }

    private static func firstAvailableFontFamily(_ candidates: [String]) -> String? {
        for candidate in candidates {
            if NSFont(name: candidate, size: 14) != nil {
                return candidate
            }
        }
        return nil
    }

    private static func resolvedThemePalette(defaults: UserDefaults = .standard, appearance: NSAppearance? = nil) -> ThemePalette {
        let dynamicSystemPalette = dynamicSystemPalette(appearance: appearance)
        let mode = themeMode(defaults: defaults)

        if mode == .custom,
           let custom = importedCustomTheme(defaults: defaults)
        {
            let basePalette: ThemePalette = {
                if let preferred = custom.preferredAppearanceName {
                    if preferred == .darkAqua {
                        return presetThemes[.kernDark]?.palette ?? dynamicSystemPalette
                    }
                    if preferred == .aqua {
                        return presetThemes[.kernLight]?.palette ?? dynamicSystemPalette
                    }
                }
                return dynamicSystemPalette
            }()

            return ThemePalette(
                preferredAppearance: custom.preferredAppearanceName,
                editorBackground: basePalette.editorBackground,
                sidebarBackground: basePalette.sidebarBackground,
                textColor: colorFromHex(custom.textColor) ?? basePalette.textColor,
                secondaryTextColor: basePalette.secondaryTextColor,
                linkColor: colorFromHex(custom.linkColor) ?? basePalette.linkColor,
                codeBlockBackground: colorFromHex(custom.codeBlockBackground) ?? basePalette.codeBlockBackground,
                codeBlockStroke: colorFromHex(custom.codeBlockStroke) ?? basePalette.codeBlockStroke,
                inlineCodeBackground: colorFromHex(custom.inlineCodeBackground) ?? basePalette.inlineCodeBackground,
                inlineCodeText: basePalette.inlineCodeText,
                tableHeaderBackground: basePalette.tableHeaderBackground,
                quoteBar: basePalette.quoteBar,
                quoteFill: basePalette.quoteFill,
                syntax: basePalette.syntax
            )
        }

        if mode == .system {
            return dynamicSystemPalette
        }

        if let preset = presetThemes[mode] {
            return preset.palette
        }

        return dynamicSystemPalette
    }

    private static func dynamicSystemPalette(appearance: NSAppearance?) -> ThemePalette {
        let dynamicText = NSColor.labelColor
        let dynamicLink = NSColor.linkColor
        let dynamicEditorBackground = NSColor.textBackgroundColor
        let dynamicSidebarBackground = NSColor.controlBackgroundColor

        let dynamicCodeBlockBg = NSColor(name: nil) { resolvedAppearance in
            switch resolvedAppearance.bestMatch(from: [.darkAqua, .vibrantDark, .aqua, .vibrantLight]) {
            case .darkAqua, .vibrantDark:
                return NSColor(white: 1.0, alpha: 0.12)
            default:
                return NSColor(white: 0.0, alpha: 0.08)
            }
        }

        let dynamicCodeBlockStroke = NSColor(name: nil) { resolvedAppearance in
            switch resolvedAppearance.bestMatch(from: [.darkAqua, .vibrantDark, .aqua, .vibrantLight]) {
            case .darkAqua, .vibrantDark:
                return NSColor(white: 1.0, alpha: 0.18)
            default:
                return NSColor(white: 0.0, alpha: 0.10)
            }
        }

        let dynamicInlineCodeBg = NSColor(name: nil) { resolvedAppearance in
            switch resolvedAppearance.bestMatch(from: [.darkAqua, .vibrantDark, .aqua, .vibrantLight]) {
            case .darkAqua, .vibrantDark:
                return NSColor(white: 1.0, alpha: 0.16)
            default:
                return NSColor(white: 0.0, alpha: 0.08)
            }
        }
        let dynamicTableHeaderBg = NSColor(name: nil) { resolvedAppearance in
            switch resolvedAppearance.bestMatch(from: [.darkAqua, .vibrantDark, .aqua, .vibrantLight]) {
            case .darkAqua, .vibrantDark:
                return NSColor(white: 1, alpha: 0.07)
            default:
                return NSColor(white: 0, alpha: 0.04)
            }
        }

        guard let appearance else {
            return ThemePalette(
                preferredAppearance: nil,
                editorBackground: dynamicEditorBackground,
                sidebarBackground: dynamicSidebarBackground,
                textColor: dynamicText,
                linkColor: dynamicLink,
                codeBlockBackground: dynamicCodeBlockBg,
                codeBlockStroke: dynamicCodeBlockStroke,
                inlineCodeBackground: dynamicInlineCodeBg,
                tableHeaderBackground: dynamicTableHeaderBg
            )
        }

        var editorBackground = dynamicEditorBackground
        var sidebarBackground = dynamicSidebarBackground
        var textColor = dynamicText
        var linkColor = dynamicLink
        var codeBlockBackground = dynamicCodeBlockBg
        var codeBlockStroke = dynamicCodeBlockStroke
        var inlineCodeBackground = dynamicInlineCodeBg
        var tableHeaderBackground = dynamicTableHeaderBg

        appearance.performAsCurrentDrawingAppearance {
            editorBackground = dynamicEditorBackground.usingColorSpace(.deviceRGB) ?? dynamicEditorBackground
            sidebarBackground = dynamicSidebarBackground.usingColorSpace(.deviceRGB) ?? dynamicSidebarBackground
            textColor = dynamicText.usingColorSpace(.deviceRGB) ?? dynamicText
            linkColor = dynamicLink.usingColorSpace(.deviceRGB) ?? dynamicLink
            codeBlockBackground = dynamicCodeBlockBg.usingColorSpace(.deviceRGB) ?? dynamicCodeBlockBg
            codeBlockStroke = dynamicCodeBlockStroke.usingColorSpace(.deviceRGB) ?? dynamicCodeBlockStroke
            inlineCodeBackground = dynamicInlineCodeBg.usingColorSpace(.deviceRGB) ?? dynamicInlineCodeBg
            tableHeaderBackground = dynamicTableHeaderBg.usingColorSpace(.deviceRGB) ?? dynamicTableHeaderBg
        }

        return ThemePalette(
            preferredAppearance: nil,
            editorBackground: editorBackground,
            sidebarBackground: sidebarBackground,
            textColor: textColor,
            linkColor: linkColor,
            codeBlockBackground: codeBlockBackground,
            codeBlockStroke: codeBlockStroke,
            inlineCodeBackground: inlineCodeBackground,
            tableHeaderBackground: tableHeaderBackground
        )
    }

    private static func isDarkAppearance(_ appearance: NSAppearance?) -> Bool {
        guard let candidate = appearance ?? NSAppearance(named: .aqua) else { return false }
        let match = candidate.bestMatch(from: [.darkAqua, .vibrantDark, .aqua, .vibrantLight])
        return match == .darkAqua || match == .vibrantDark
    }

    fileprivate static func colorFromHex(_ maybeHex: String?) -> NSColor? {
        guard let maybeHex else { return nil }
        let trimmed = maybeHex.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "#", with: "")

        guard trimmed.count == 6 || trimmed.count == 8,
              let value = UInt64(trimmed, radix: 16) else {
            return nil
        }

        let r, g, b, a: CGFloat
        if trimmed.count == 8 {
            r = CGFloat((value & 0xFF00_0000) >> 24) / 255.0
            g = CGFloat((value & 0x00FF_0000) >> 16) / 255.0
            b = CGFloat((value & 0x0000_FF00) >> 8) / 255.0
            a = CGFloat(value & 0x0000_00FF) / 255.0
        } else {
            r = CGFloat((value & 0xFF00_00) >> 16) / 255.0
            g = CGFloat((value & 0x00FF_00) >> 8) / 255.0
            b = CGFloat(value & 0x0000_FF) / 255.0
            a = 1.0
        }

        return NSColor(calibratedRed: r, green: g, blue: b, alpha: a)
    }
}
