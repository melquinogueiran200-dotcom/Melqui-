import Foundation

/// How the engine starts: the same two choices as the web build's loading
/// screen (Story Mode / Sandbox Mode). Raw values are the engine's start mode.
enum GameMode: Int, CaseIterable {
    case story = 1
    case sandbox = 2

    var title: String { self == .story ? AppLanguage.choose("Story mode") : AppLanguage.choose("Sandbox") }
    var detail: String {
        switch self {
        case .story: return AppLanguage.choose("The campaign with missions. Continues your latest save, or starts from the Prologue.")
        case .sandbox: return AppLanguage.choose("Free roam anywhere on the map with every weapon. No missions.")
        }
    }
}

/// Player preferences, kept in UserDefaults across launches.
final class GameSettings {
    static let shared = GameSettings()
    private let defaults = UserDefaults.standard

    var gyroAim: GyroAimMode {
        get { GyroAimMode(rawValue: defaults.integer(forKey: "gyroAim")) ?? .off }
        set { defaults.set(newValue.rawValue, forKey: "gyroAim") }
    }
    var gyroSensitivity: Double {
        get { defaults.object(forKey: "gyroSensitivity") as? Double ?? 1.0 }
        set { defaults.set(newValue, forKey: "gyroSensitivity") }
    }
    var gyroInvertY: Bool {
        get { defaults.bool(forKey: "gyroInvertY") }
        set { defaults.set(newValue, forKey: "gyroInvertY") }
    }

    var tiltSteer: TiltSteerMode {
        get { TiltSteerMode(rawValue: defaults.integer(forKey: "tiltSteer")) ?? .off }
        set { defaults.set(newValue.rawValue, forKey: "tiltSteer") }
    }
    /// Phone rotation, in degrees, for full steering lock.
    var tiltFullLock: Double {
        get { defaults.object(forKey: "tiltFullLock") as? Double ?? 22 }
        set { defaults.set(min(max(newValue, 10), 45), forKey: "tiltFullLock") }
    }

    /// Your own server with the game files, e.g. https://my-pc.tailnet.ts.net.
    /// A cloud build can bake in a default (Info.plist PGDefaultAssetServer).
    var assetServer: String {
        get {
            if let saved = defaults.string(forKey: "assetServer"), !saved.isEmpty { return saved }
            return Bundle.main.object(forInfoDictionaryKey: "PGDefaultAssetServer") as? String ?? ""
        }
        set { defaults.set(newValue.trimmingCharacters(in: .whitespacesAndNewlines), forKey: "assetServer") }
    }

    // Touch controls.
    var controlOpacity: Double {
        get { defaults.object(forKey: "controlOpacity") as? Double ?? 0.8 }
        set { defaults.set(min(max(newValue, 0.2), 1), forKey: "controlOpacity") }
    }
    var controlScale: Double {
        get { defaults.object(forKey: "controlScale") as? Double ?? 1.0 }
        set { defaults.set(min(max(newValue, 0.7), 1.5), forKey: "controlScale") }
    }
    // Independent experimental controls; original v1.3 stick is the default.
    // Do not conflate swipes with input device classification: the mouse path
    // is intentionally tested as a separate option, not assumed to retain auto-aim.
    enum CameraTouchMode: Int, CaseIterable {
        case stick = 0
        case swipePad = 1
        case swipeMouse = 2

        var title: String {
            switch self {
            case .stick: return AppLanguage.choose("Virtual right stick")
            case .swipePad: return AppLanguage.choose("Swipe (controller)")
            case .swipeMouse: return AppLanguage.choose("Swipe (mouse experiment)")
            }
        }
    }
    var cameraTouchMode: CameraTouchMode {
        // Swipe always drives the game's mouse: the controller swipe felt choppy, worst on the
        // vertical axis, because a finger can only tilt the stick up to the game's max turn speed.
        get { (CameraTouchMode(rawValue: defaults.integer(forKey: "cameraTouchMode")) ?? .stick) == .stick ? .stick : .swipeMouse }
        set {
            defaults.set(newValue.rawValue, forKey: "cameraTouchMode")
            // Remember the chosen swipe variant while the user switches to the
            // controller tab. Never overwrite it when selecting the stick.
            if newValue != .stick { defaults.set(newValue.rawValue, forKey: "preferredSwipeMode") }
        }
    }
    var preferredSwipeMode: CameraTouchMode {
        let saved = CameraTouchMode(rawValue: defaults.integer(forKey: "preferredSwipeMode"))
        return saved == .swipePad ? .swipePad : .swipeMouse
    }
    static let swipeSensitivityMinimum = 0.2
    static let swipeSensitivityMaximum = 15.0
    static let swipeSensitivityDefault = 3.0
    var swipeLookSensitivity: Double {
        get { defaults.object(forKey: "swipeLookSensitivity") as? Double ?? Self.swipeSensitivityDefault }
        set { defaults.set(min(max(newValue, Self.swipeSensitivityMinimum), Self.swipeSensitivityMaximum), forKey: "swipeLookSensitivity") }
    }
    var swipeAimSensitivity: Double {
        get { defaults.object(forKey: "swipeAimSensitivity") as? Double ?? Self.swipeSensitivityDefault }
        set { defaults.set(min(max(newValue, Self.swipeSensitivityMinimum), Self.swipeSensitivityMaximum), forKey: "swipeAimSensitivity") }
    }

    // Swipe moves the game's mouse by relative pixels; 1x was far too slow on a phone screen.
    static let mouseSensitivityDefault = 5.0
    var mouseLookSensitivity: Double {
        get { defaults.object(forKey: "mouseLookSensitivity") as? Double ?? Self.mouseSensitivityDefault }
        set { defaults.set(min(max(newValue, Self.swipeSensitivityMinimum), Self.swipeSensitivityMaximum), forKey: "mouseLookSensitivity") }
    }
    var mouseAimSensitivity: Double {
        get { defaults.object(forKey: "mouseAimSensitivity") as? Double ?? Self.mouseSensitivityDefault }
        set { defaults.set(min(max(newValue, Self.swipeSensitivityMinimum), Self.swipeSensitivityMaximum), forKey: "mouseAimSensitivity") }
    }
    var lookSensitivity: Double {
        get { defaults.object(forKey: "lookSensitivity") as? Double ?? 2.0 }
        set { defaults.set(min(max(newValue, 0.3), 3), forKey: "lookSensitivity") }
    }
    /// Camera speed while aiming (the game slows the camera when aiming).
    var aimSensitivity: Double {
        get { defaults.object(forKey: "aimSensitivity") as? Double ?? 1.3 }
        set { defaults.set(min(max(newValue, 0.3), 4), forKey: "aimSensitivity") }
    }
    /// Fire also locks on, like the classic mobile GTA ports.
    var fireAlsoAims: Bool {
        get { defaults.object(forKey: "fireAlsoAims") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "fireAlsoAims") }
    }

    /// GTA's targeting preference: 0 traditional lock, 1 assisted aim,
    /// 2 assisted free aim, 3 free aim. Touch play defaults to assisted.
    var targetingMode: Int {
        get { defaults.object(forKey: "targetingMode") as? Int ?? 1 }
        set { defaults.set(newValue, forKey: "targetingMode") }
    }
    static var targetingTitles: [String] { [AppLanguage.choose("Traditional lock-on"), AppLanguage.choose("Assisted aim"), AppLanguage.choose("Assisted free aim"), AppLanguage.choose("Free aim")] }

    /// nil until the player has chosen on the launch screen.
    /// Sandbox map: 0 the GTA V map, 1 the test level the game files include (env_test).
    var sandboxMap: Int {
        get { defaults.integer(forKey: "sandboxMap") == 1 ? 1 : 0 }
        set { defaults.set(newValue == 1 ? 1 : 0, forKey: "sandboxMap") }
    }
    static var sandboxMapTitles: [String] { ["GTA V", AppLanguage.choose("GTA VI test map")] }
    var gameModeChoice: GameMode? {
        get { (defaults.object(forKey: "gameMode") as? Int).flatMap(GameMode.init) }
        set { defaults.set(newValue?.rawValue, forKey: "gameMode") }
    }
    /// Sandbox was the only mode before the choice existed.
    var gameMode: GameMode {
        get { gameModeChoice ?? .sandbox }
        set { gameModeChoice = newValue }
    }

    // Graphics. The default comes from the measured device tier.
    lazy var tier = DeviceTier.probe()
    var graphicsPreset: GraphicsPreset {
        // integer(forKey:) also reads "-graphicsPreset 4" given as a launch argument (a string).
        get { defaults.object(forKey: "graphicsPreset") != nil ? GraphicsPreset(rawValue: defaults.integer(forKey: "graphicsPreset")) ?? tier.recommended : tier.recommended }
        set { defaults.set(newValue.rawValue, forKey: "graphicsPreset") }
    }
    var resolutionScale: Double {
        get { defaults.object(forKey: "resolutionScale") as? Double ?? 1.0 }
        set { defaults.set(min(max(newValue, 0.5), 1.0), forKey: "resolutionScale") }
    }
    /// Render at the screen's shape instead of a stretched 16:9 picture.
    /// Render height in pixels, changeable while playing; 0 follows the detail preset.
    var renderHeight: Int {
        get { defaults.integer(forKey: "renderHeight") }
        set { defaults.set(max(0, newValue), forKey: "renderHeight") }
    }
    var matchScreenShape: Bool {
        get { defaults.object(forKey: "matchScreenShape") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "matchScreenShape") }
    }
    /// A hardware keyboard and mouse play through the game's own PC controls (on by default).
    var showFPS: Bool {
        get { defaults.object(forKey: "showFPS") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "showFPS") }
    }
    var keyboardMouse: Bool {
        get { defaults.object(forKey: "keyboardMouse") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "keyboardMouse") }
    }
    /// Hide the touch controls while a game controller is connected (on by default).
    var hideTouchWithController: Bool {
        get { defaults.object(forKey: "hideTouchWithController") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "hideTouchWithController") }
    }
    var sixtyFPS: Bool { frameRateCap != 30 }
    /// Frame rate cap: 30, 60, or 0 for unlocked (up to the screen's refresh rate, 120 on ProMotion).
    var frameRateCap: Int {
        get {
            if let cap = defaults.object(forKey: "frameRateCap") as? Int, [0, 30, 60].contains(cap) { return cap }
            return defaults.bool(forKey: "sixtyFPS") ? 60 : 30 // older versions stored a 60 FPS switch
        }
        set { defaults.set(newValue, forKey: "frameRateCap") }
    }
    static func frameRateTitle(_ cap: Int) -> String { cap == 0 ? AppLanguage.choose("Unlocked") : "\(cap) FPS" }

    // Crash fallback: a launch that never reached a stable world is treated
    // as a memory kill, and the last preset that worked is restored.
    private var bootPending: Bool {
        get { defaults.bool(forKey: "graphicsBootPending") }
        set { defaults.set(newValue, forKey: "graphicsBootPending") }
    }
    private var lastGoodPreset: GraphicsPreset? {
        get { (defaults.object(forKey: "lastGoodPreset") as? Int).flatMap(GraphicsPreset.init) }
        set { defaults.set(newValue?.rawValue, forKey: "lastGoodPreset") }
    }
    /// What changed after a launch that did not finish (shown once, in a popup, on the next start).
    struct BootRecovery {
        let failed: GraphicsPreset
        let fallback: GraphicsPreset
        /// The custom resolution that was set back to Auto, if any.
        let resetHeight: Int?
        let memoryLimitMB: Int
    }
    /// Lowers the settings when the previous launch failed. Returns what changed, or nil.
    func recoverFromFailedBoot() -> BootRecovery? {
        #if targetEnvironment(simulator)
        // Simulator runs are often stopped from Xcode; only phones need this (unless testing it).
        if !ProcessInfo.processInfo.arguments.contains("--simulate-failed-boot") { bootPending = false; return nil }
        #endif
        guard bootPending else { return nil }
        bootPending = false
        let failed = graphicsPreset
        // A preset that already ran stably on this phone is not the problem (the app was more likely
        // closed by an update or by Xcode): keep it, and only undo a resolution raised above it.
        let fallback = lastGoodPreset == failed ? failed
            : lastGoodPreset.flatMap { $0.rawValue < failed.rawValue ? $0 : nil }
            ?? GraphicsPreset(rawValue: max(0, min(failed.rawValue - 1, tier.recommended.rawValue))) ?? .performance
        // A custom resolution above the fallback's own also costs memory: back to Auto (unless that
        // resolution already ran stably with this preset).
        let provenHeight = fallback == lastGoodPreset ? defaults.integer(forKey: "lastGoodRenderHeight") : 0
        let resetHeight = renderHeight > max(fallback.height, provenHeight) ? renderHeight : nil
        guard fallback != failed || resetHeight != nil else { return nil }
        graphicsPreset = fallback
        if resetHeight != nil { renderHeight = 0 }
        return BootRecovery(failed: failed, fallback: fallback, resetHeight: resetHeight, memoryLimitMB: tier.memoryLimitMB)
    }
    /// "Try again anyway" in the popup: put the settings back as they were.
    func undoRecovery(_ recovery: BootRecovery) {
        graphicsPreset = recovery.failed
        if let height = recovery.resetHeight { renderHeight = height }
    }
    func markBootStarted() { bootPending = true }
    /// Leaving the app is not a crash.
    func markBootInterrupted() { bootPending = false }
    func markBootStable() {
        bootPending = false
        lastGoodPreset = graphicsPreset
        defaults.set(renderHeight == 0 ? graphicsPreset.height : renderHeight, forKey: "lastGoodRenderHeight")
    }
}
