import SwiftUI

/// Semantic colors used by every shared YoloLedger screen.
///
/// Add future light, dark, or branded themes as separate static presets. Views
/// consume the theme from the SwiftUI environment instead of reading raw color
/// literals, so the active palette can be changed once at the app root.
public struct LedgerTheme: Sendable {
    public let ink: Color
    public let muted: Color
    public let paper: Color
    public let surface: Color
    public let primary: Color
    public let onPrimary: Color
    public let primarySoft: Color
    public let navigationBackground: Color
    public let keypadBackground: Color
    public let detailBackground: Color
    public let accent: Color
    public let expense: Color
    public let income: Color
    public let error: Color
    public let shadow: Color
    public let calendarIdle: Color
    public let artwork: LedgerArtworkPalette

    public init(
        ink: Color,
        muted: Color,
        paper: Color,
        surface: Color,
        primary: Color,
        onPrimary: Color,
        primarySoft: Color,
        navigationBackground: Color,
        keypadBackground: Color,
        detailBackground: Color,
        accent: Color,
        expense: Color,
        income: Color,
        error: Color,
        shadow: Color,
        calendarIdle: Color,
        artwork: LedgerArtworkPalette
    ) {
        self.ink = ink
        self.muted = muted
        self.paper = paper
        self.surface = surface
        self.primary = primary
        self.onPrimary = onPrimary
        self.primarySoft = primarySoft
        self.navigationBackground = navigationBackground
        self.keypadBackground = keypadBackground
        self.detailBackground = detailBackground
        self.accent = accent
        self.expense = expense
        self.income = income
        self.error = error
        self.shadow = shadow
        self.calendarIdle = calendarIdle
        self.artwork = artwork
    }
}

public struct LedgerArtworkPalette: Sendable {
    public let yellow: Color
    public let pink: Color
    public let shopping: Color
    public let transport: Color
    public let petMuzzle: Color
    public let housingRoof: Color
    public let housingDoor: Color
    public let housingWindow: Color
    public let snackCake: Color
    public let snackIcing: Color
    public let travel: Color
    public let communication: Color
    public let medical: Color
    public let pos: Color
    public let other: Color
    public let sport: Color
    public let daily: Color
    public let dailyTop: Color
    public let income: Color
    public let fallback: Color

    public init(
        yellow: Color,
        pink: Color,
        shopping: Color,
        transport: Color,
        petMuzzle: Color,
        housingRoof: Color,
        housingDoor: Color,
        housingWindow: Color,
        snackCake: Color,
        snackIcing: Color,
        travel: Color,
        communication: Color,
        medical: Color,
        pos: Color,
        other: Color,
        sport: Color,
        daily: Color,
        dailyTop: Color,
        income: Color,
        fallback: Color
    ) {
        self.yellow = yellow
        self.pink = pink
        self.shopping = shopping
        self.transport = transport
        self.petMuzzle = petMuzzle
        self.housingRoof = housingRoof
        self.housingDoor = housingDoor
        self.housingWindow = housingWindow
        self.snackCake = snackCake
        self.snackIcing = snackIcing
        self.travel = travel
        self.communication = communication
        self.medical = medical
        self.pos = pos
        self.other = other
        self.sport = sport
        self.daily = daily
        self.dailyTop = dailyTop
        self.income = income
        self.fallback = fallback
    }
}

public extension LedgerTheme {
    /// Current light theme. The shared pastel `#C6E2FF` is used for all large
    /// navigation, keypad, and detail backgrounds that were previously dark.
    static let pastel = LedgerTheme(
        ink: Color(red: 0.09, green: 0.13, blue: 0.17),
        muted: Color(red: 0.40, green: 0.45, blue: 0.50),
        paper: Color(red: 0.975, green: 0.988, blue: 1),
        surface: .white,
        primary: Color(red: 10 / 255, green: 132 / 255, blue: 1),
        onPrimary: .white,
        primarySoft: Color(red: 198 / 255, green: 226 / 255, blue: 1),
        navigationBackground: Color(red: 198 / 255, green: 226 / 255, blue: 1),
        keypadBackground: Color(red: 198 / 255, green: 226 / 255, blue: 1),
        detailBackground: Color(red: 198 / 255, green: 226 / 255, blue: 1),
        accent: Color(red: 1, green: 0.48, blue: 0.12),
        expense: Color(red: 0.96, green: 0.31, blue: 0.20),
        income: Color(red: 0.10, green: 0.62, blue: 0.38),
        error: .red,
        shadow: Color(red: 0.09, green: 0.13, blue: 0.17).opacity(0.28),
        calendarIdle: Color(white: 0.96),
        artwork: LedgerArtworkPalette(
            yellow: Color(red: 1, green: 0.85, blue: 0.36),
            pink: Color(red: 0.96, green: 0.43, blue: 0.56),
            shopping: Color(red: 1, green: 0.75, blue: 0.81),
            transport: Color(red: 0.65, green: 0.77, blue: 0.94),
            petMuzzle: Color(red: 1, green: 0.92, blue: 0.67),
            housingRoof: Color(red: 0.66, green: 0.87, blue: 0.75),
            housingDoor: Color(red: 0.76, green: 0.90, blue: 0.83),
            housingWindow: Color(red: 0.83, green: 0.94, blue: 0.96),
            snackCake: Color(red: 0.97, green: 0.69, blue: 0.50),
            snackIcing: Color(red: 1, green: 0.94, blue: 0.86),
            travel: Color(red: 0.79, green: 0.74, blue: 0.96),
            communication: Color(red: 0.65, green: 0.79, blue: 0.95),
            medical: Color(red: 0.96, green: 0.70, blue: 0.50),
            pos: Color(red: 1, green: 0.73, blue: 0.54),
            other: Color(red: 0.64, green: 0.87, blue: 0.77),
            sport: Color(red: 0.75, green: 0.69, blue: 0.91),
            daily: Color(red: 0.65, green: 0.84, blue: 0.89),
            dailyTop: Color(red: 0.81, green: 0.94, blue: 0.94),
            income: Color(red: 0.72, green: 0.88, blue: 0.78),
            fallback: Color(red: 0.91, green: 0.82, blue: 0.96)
        )
    )
}

private struct LedgerThemeKey: EnvironmentKey {
    static let defaultValue = LedgerTheme.pastel
}

extension EnvironmentValues {
    var ledgerTheme: LedgerTheme {
        get { self[LedgerThemeKey.self] }
        set { self[LedgerThemeKey.self] = newValue }
    }
}

public extension View {
    /// Applies one theme to the complete view hierarchy.
    func ledgerTheme(_ theme: LedgerTheme) -> some View {
        environment(\.ledgerTheme, theme)
    }
}
