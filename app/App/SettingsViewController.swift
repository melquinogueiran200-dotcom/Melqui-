import UIKit

/// Graphics and control options. Before launch every change applies on Play;
/// during play only resolution and controls apply live, the rest on restart.
final class SettingsViewController: UITableViewController {
    private let settings = GameSettings.shared
    private let engineRunning: Bool
    private let bootPreset: GraphicsPreset
    /// The mode the running engine started in (nil before Play).
    private let runningMode: GameMode?
    var resolutionChanged: (() -> Void)?
    var controlsChanged: (() -> Void)?
    var editLayout: (() -> Void)?
    var targetingChanged: (() -> Void)?
    var gameModeChanged: (() -> Void)?

    private enum Section: Int, CaseIterable { case language, mode, graphics, controls, gyro, files, device }
    // The switch controls both the visible settings group and the active
    // camera input. It does NOT spoof the engine's last-input-device flag:
    // that flag is shared by the game's own aim-assist logic.
    private enum ControlsTab: Int { case stick = 0, swipe = 1 }
    private enum ControlsRow {
        case tab, swipeLook, swipeAim, stickLook, stickAim
        case targeting, fireAlsoAims, buttonSize, buttonOpacity, editLayout
        case hideTouchWithController, keyboardMouse, inputState
    }
    private var controlsTab: ControlsTab {
        settings.cameraTouchMode == .stick ? .stick : .swipe
    }
    /// The camera choice only swaps its two speed rows; every other control setting is always there.
    private var controlsRows: [ControlsRow] {
        let camera: [ControlsRow] = controlsTab == .stick ? [.stickLook, .stickAim] : [.swipeLook, .swipeAim]
        return [.tab] + camera + [.targeting, .fireAlsoAims, .buttonSize, .buttonOpacity,
                                  .editLayout, .hideTouchWithController, .keyboardMouse]
    }

    @objc private func controlsTabChanged(_ sender: UISegmentedControl) {
        if sender.selectedSegmentIndex == ControlsTab.swipe.rawValue {
            settings.cameraTouchMode = .swipeMouse
        } else {
            settings.cameraTouchMode = .stick
        }
        controlsChanged?()
        UIView.performWithoutAnimation {
            tableView.reloadSections(IndexSet(integer: Section.controls.rawValue), with: .none)
        }
    }

    private let preloader = AssetPreloader.shared
    /// Rows shown in the Game files section, rebuilt from the preloader's phase.
    private enum FileRow { case status, start, pause, resume, cancel, remove }
    private var fileRows: [FileRow] = []
    private var fileStateKey = ""
    private var fileMessage: String?

    init(engineRunning: Bool, runningMode: GameMode? = nil) {
        self.engineRunning = engineRunning
        self.runningMode = engineRunning ? runningMode : nil
        self.bootPreset = GameSettings.shared.graphicsPreset
        super.init(style: .insetGrouped)
        title = AppLanguage.choose("Settings")
        modalPresentationStyle = .formSheet
        overrideUserInterfaceStyle = .dark
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        navigationItem.rightBarButtonItem = UIBarButtonItem(title: AppLanguage.choose("Done"), primaryAction: UIAction { [weak self] _ in self?.dismiss(animated: true) })
        navigationItem.rightBarButtonItem?.tintColor = Theme.accent
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "cell")
        tableView.backgroundView = Theme.dimmedBackdrop(image: "SettingsBackground")
        tableView.separatorColor = UIColor(white: 1, alpha: 0.1)
        fileRows = makeFileRows()
        NotificationCenter.default.addObserver(self, selector: #selector(preloadChanged), name: .assetPreloadChanged, object: nil)
        preloader.refresh()
        let arguments = ProcessInfo.processInfo.arguments
        if let i = arguments.firstIndex(of: "--settings-section"), i + 1 < arguments.count,
           let section = ["files": Section.files, "graphics": Section.graphics, "resolution": Section.graphics][arguments[i + 1]] {
            let row = arguments[i + 1] == "resolution" ? settings.tier.allowed.count : 0
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                self.tableView.scrollToRow(at: IndexPath(row: row, section: section.rawValue), at: .middle, animated: false)
            }
        }
    }

    override func numberOfSections(in tableView: UITableView) -> Int { Section.allCases.count }

    // The app's look: rows as glass on the darkened art, headers in the display font.
    override func tableView(_ tableView: UITableView, willDisplay cell: UITableViewCell, forRowAt indexPath: IndexPath) {
        cell.backgroundColor = Theme.rowBackground
        let selected = UIView()
        selected.backgroundColor = Theme.rowSelected
        cell.selectedBackgroundView = selected
    }
    override func tableView(_ tableView: UITableView, willDisplayHeaderView view: UIView, forSection section: Int) {
        guard let header = view as? UITableViewHeaderFooterView else { return }
        var content = header.defaultContentConfiguration()
        content.text = self.tableView(tableView, titleForHeaderInSection: section)
        content.textProperties.font = Theme.display(15, .bold)
        content.textProperties.color = Theme.text
        content.textProperties.transform = .uppercase
        header.contentConfiguration = content
    }
    override func tableView(_ tableView: UITableView, willDisplayFooterView view: UIView, forSection section: Int) {
        (view as? UITableViewHeaderFooterView)?.textLabel?.textColor = Theme.tertiaryText
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch Section(rawValue: section)! {
        case .mode: return GameMode.allCases.count + (settings.gameModeChoice == .sandbox ? 1 : 0)
        case .graphics: return settings.tier.allowed.count + 4
        case .controls: return controlsRows.count
        case .gyro: return (settings.gyroAim == .off ? 1 : 3) + (settings.tiltSteer == .off ? 1 : 2)
        case .files: return fileRows.count
        case .device: return 3
        case .language: return 1
        }
    }

    override func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        // The full-width segmented control needs more space than a standard row.
        if indexPath.section == Section.controls.rawValue,
           controlsRows[indexPath.row] == .tab { return 58 }
        return UITableView.automaticDimension
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        [AppLanguage.choose("Language"), AppLanguage.choose("Game mode"), AppLanguage.choose("Graphics"), AppLanguage.choose("Touch controls"), AppLanguage.choose("Gyro"), AppLanguage.choose("Game files"), AppLanguage.choose("This device")][section]
    }

    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        switch Section(rawValue: section)! {
        case .mode:
            var text = AppLanguage.choose("Story mode saves stay on this phone between launches. Sandbox keeps its own separate files.")
            if let runningMode {
                text = AppLanguage.choose("Changes apply the next time you start the game. ") + text
                if settings.gameMode != runningMode { text += AppLanguage.interpolate(AppLanguage.choose(" Close and reopen the app to play {arg0}."), [String(describing: settings.gameMode.title)]) }
            }
            return text
        case .graphics:
            var text = AppLanguage.choose("Resolution changes apply right away. ")
            text += engineRunning ? AppLanguage.choose("Preset and frame rate changes apply the next time you start the game.") : AppLanguage.choose("Presets apply when you press Play.")
            if settings.graphicsPreset != bootPreset && engineRunning { text += AppLanguage.interpolate(AppLanguage.choose(" Restart needed for {arg0}."), [String(describing: settings.graphicsPreset.title)]) }
            if settings.tier.risky(settings.graphicsPreset) { text += AppLanguage.choose(" Presets above the recommended one can run out of memory or overheat on this phone; if a launch fails, the game falls back automatically.") }
            return text
        case .controls:
            return AppLanguage.choose("Switching tabs changes the camera control and the settings below. It does not force GTA V's in-game button prompt icons.")
        case .gyro:
            return AppLanguage.choose("Move the phone to fine-tune your aim; turning your body turns the camera. Tilt steering turns the phone like a steering wheel: Assist adds fine control on top of the touch steering, Tilt to steer replaces it. The straight-ahead angle is however you hold the phone when you get in.")
        case .files: return filesFooter()
        case .device: return AppLanguage.choose("GTA V Port") + " \(Theme.appVersion). " + AppLanguage.choose("Quote this version when you report a problem.")
        case .language:
            return AppLanguage.choose("Menus change right away. The game itself switches language the next time it starts.")
        }
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .subtitle, reuseIdentifier: nil)
        cell.selectionStyle = .default
        var content = cell.defaultContentConfiguration()
        content.secondaryTextProperties.color = .secondaryLabel
        let presets = settings.tier.allowed
        switch Section(rawValue: indexPath.section)! {
        case .mode where indexPath.row == GameMode.allCases.count:
            // Sandbox only: which map.
            content.text = AppLanguage.choose("Sandbox map")
            content.secondaryText = settings.sandboxMap == 1 ? AppLanguage.choose("The test level that comes with the game files") : AppLanguage.choose("The full GTA V map")
            let button = UIButton(configuration: .gray())
            button.configuration?.title = GameSettings.sandboxMapTitles[settings.sandboxMap]
            button.menu = UIMenu(children: GameSettings.sandboxMapTitles.enumerated().map { index, title in
                UIAction(title: title, state: index == settings.sandboxMap ? .on : .off) { [weak self] _ in
                    self?.settings.sandboxMap = index
                    self?.gameModeChanged?()
                    UIView.performWithoutAnimation { self?.tableView.reloadSections([Section.mode.rawValue], with: .none) }
                }
            })
            button.showsMenuAsPrimaryAction = true
            button.sizeToFit()
            cell.accessoryView = button
            cell.selectionStyle = .none
        case .mode:
            let mode = GameMode.allCases[indexPath.row]
            content.text = mode.title + (mode == runningMode ? AppLanguage.choose(" (playing now)") : "")
            content.secondaryText = mode.detail
            cell.accessoryType = settings.gameModeChoice == mode ? .checkmark : .none
        case .graphics:
            if indexPath.row < presets.count {
                let preset = presets[indexPath.row]
                content.text = preset.title + (preset == settings.tier.recommended ? AppLanguage.choose(" (recommended)") : "")
                content.secondaryText = AppLanguage.interpolate(AppLanguage.choose("Detail level, default {arg0}p · "), [String(describing: preset.height)]) + preset.detail + (settings.tier.risky(preset) ? AppLanguage.choose("\n⚠︎ Heavier than this phone's recommended setting: may run out of memory or overheat.") : "")
                if settings.tier.risky(preset) { content.secondaryTextProperties.color = .systemOrange }
                cell.accessoryType = preset == settings.graphicsPreset ? .checkmark : .none
            } else {
                let row = indexPath.row - presets.count
                cell.selectionStyle = .none
                if row == 0 {
                    content.text = AppLanguage.choose("Resolution")
                    content.secondaryText = currentSizeText() + AppLanguage.choose(" · changes right away")
                    let button = UIButton(type: .system)
                    button.setTitle(resolutionTitle(settings.renderHeight) + " ▾", for: .normal)
                    button.showsMenuAsPrimaryAction = true
                    button.accessibilityLabel = AppLanguage.choose("Resolution")
                    let choices = [0] + GraphicsConfiguration.resolutionChoices
                    button.menu = UIMenu(children: choices.map { height in
                        UIAction(title: resolutionTitle(height), state: height == settings.renderHeight ? .on : .off) { [weak self] _ in
                            guard let self else { return }
                            self.settings.renderHeight = height
                            self.resolutionChanged?()
                            self.reloadFooters()
                        }
                    })
                    button.sizeToFit()
                    cell.accessoryView = button
                } else if row == 1 {
                    content.text = AppLanguage.choose("Fill the screen")
                    content.secondaryText = AppLanguage.choose("Render at the screen's shape instead of stretching 16:9")
                    cell.accessoryView = toggle(settings.matchScreenShape, label: AppLanguage.choose("Fill the screen")) { [weak self] in
                        self?.settings.matchScreenShape = $0; self?.resolutionChanged?(); self?.tableView.reloadData()
                    }
                } else if row == 3 {
                    content.text = AppLanguage.choose("Show FPS counter")
                    cell.accessoryView = toggle(settings.showFPS, label: AppLanguage.choose("Show FPS counter")) { [weak self] in
                        self?.settings.showFPS = $0
                    }
                } else {
                    content.text = AppLanguage.choose("Frame rate")
                    content.secondaryText = AppLanguage.choose("Higher uses more power and heat; 30 FPS is steadiest. Unlocked goes up to 120 on ProMotion iPhones.")
                    let button = UIButton(type: .system)
                    button.setTitle(GameSettings.frameRateTitle(settings.frameRateCap) + " ▾", for: .normal)
                    button.showsMenuAsPrimaryAction = true
                    button.accessibilityLabel = AppLanguage.choose("Frame rate")
                    button.menu = UIMenu(children: [30, 60, 0].map { cap in
                        UIAction(title: GameSettings.frameRateTitle(cap), state: cap == settings.frameRateCap ? .on : .off) { [weak self] _ in
                            self?.settings.frameRateCap = cap; self?.reloadFooters(); self?.tableView.reloadData()
                        }
                    })
                    button.sizeToFit()
                    cell.accessoryView = button
                }
            }
        case .controls:
            cell.selectionStyle = .none
            switch controlsRows[indexPath.row] {
            case .tab:
                // Full-width, persistent-feeling tabs; the actual input mode
                // changes only on an intentional tap, never during a swipe.
                let tabs = UISegmentedControl(items: [
                    AppLanguage.choose("Camera: right stick"),
                    AppLanguage.choose("Camera: swipe")
                ])
                tabs.selectedSegmentIndex = controlsTab.rawValue
                tabs.selectedSegmentTintColor = Theme.accent
                // Keep both labels legible against the dark Settings sheet.
                tabs.backgroundColor = UIColor(white: 1, alpha: 0.12)
                tabs.setTitleTextAttributes([.foregroundColor: UIColor.white], for: .normal)
                tabs.setTitleTextAttributes([.foregroundColor: UIColor.black], for: .selected)
                tabs.accessibilityLabel = AppLanguage.choose("Camera control")
                tabs.addTarget(self, action: #selector(controlsTabChanged(_:)), for: .valueChanged)
                tabs.translatesAutoresizingMaskIntoConstraints = false
                cell.contentView.addSubview(tabs)
                NSLayoutConstraint.activate([
                    tabs.leadingAnchor.constraint(equalTo: cell.contentView.layoutMarginsGuide.leadingAnchor),
                    tabs.trailingAnchor.constraint(equalTo: cell.contentView.layoutMarginsGuide.trailingAnchor),
                    tabs.topAnchor.constraint(equalTo: cell.contentView.topAnchor, constant: 11),
                    tabs.bottomAnchor.constraint(equalTo: cell.contentView.bottomAnchor, constant: -11),
                    tabs.heightAnchor.constraint(greaterThanOrEqualToConstant: 34)
                ])
            case .swipeLook:
                let mouse = settings.cameraTouchMode == .swipeMouse
                let value = mouse ? settings.mouseLookSensitivity : settings.swipeLookSensitivity
                content.text = AppLanguage.choose("Swipe look sensitivity")
                cell.accessoryView = sensitivitySlider(value, low: GameSettings.swipeSensitivityMinimum, high: GameSettings.swipeSensitivityMaximum,
                    label: AppLanguage.choose("Swipe look sensitivity")) { [weak self] v in
                    guard let self else { return }
                    if mouse { self.settings.mouseLookSensitivity = v } else { self.settings.swipeLookSensitivity = v }
                }
            case .swipeAim:
                let mouse = settings.cameraTouchMode == .swipeMouse
                let value = mouse ? settings.mouseAimSensitivity : settings.swipeAimSensitivity
                content.text = AppLanguage.choose("Swipe aim sensitivity")
                cell.accessoryView = sensitivitySlider(value, low: GameSettings.swipeSensitivityMinimum, high: GameSettings.swipeSensitivityMaximum,
                    label: AppLanguage.choose("Swipe aim sensitivity")) { [weak self] v in
                    guard let self else { return }
                    if mouse { self.settings.mouseAimSensitivity = v } else { self.settings.swipeAimSensitivity = v }
                }
            case .stickLook:
                content.text = AppLanguage.choose("Camera stick speed")
                content.secondaryText = AppLanguage.choose("Virtual right stick")
                cell.accessoryView = sensitivitySlider(settings.lookSensitivity, low: 0.3, high: 3,
                    label: AppLanguage.choose("Look speed")) { [weak self] v in self?.settings.lookSensitivity = v }
            case .stickAim:
                content.text = AppLanguage.choose("Aim stick speed")
                content.secondaryText = AppLanguage.choose("Virtual right stick")
                cell.accessoryView = sensitivitySlider(settings.aimSensitivity, low: 0.3, high: 4,
                    label: AppLanguage.choose("Aim look speed")) { [weak self] v in self?.settings.aimSensitivity = v }
            case .targeting:
                content.text = AppLanguage.choose("Targeting")
                let button = UIButton(configuration: .gray())
                button.configuration?.title = GameSettings.targetingTitles[settings.targetingMode]
                button.menu = UIMenu(children: GameSettings.targetingTitles.enumerated().map { index, title in
                    UIAction(title: title, state: index == settings.targetingMode ? .on : .off) { [weak self] _ in
                        self?.settings.targetingMode = index
                        self?.targetingChanged?()
                        UIView.performWithoutAnimation { self?.tableView.reloadSections(IndexSet(integer: Section.controls.rawValue), with: .none) }
                    }
                })
                button.showsMenuAsPrimaryAction = true
                button.sizeToFit()
                cell.accessoryView = button
            case .fireAlsoAims:
                content.text = AppLanguage.choose("Fire also aims")
                content.secondaryText = AppLanguage.choose("Fire locks on first, like the classic mobile GTA games")
                cell.accessoryView = toggle(settings.fireAlsoAims, label: AppLanguage.choose("Fire also aims")) { [weak self] in self?.settings.fireAlsoAims = $0 }
            case .buttonSize:
                content.text = AppLanguage.choose("Button size")
                cell.accessoryView = slider(settings.controlScale, 0.7, 1.5, label: AppLanguage.choose("Button size")) { [weak self] in
                    self?.settings.controlScale = $0; self?.controlsChanged?()
                }
            case .buttonOpacity:
                content.text = AppLanguage.choose("Button opacity")
                cell.accessoryView = slider(settings.controlOpacity, 0.2, 1, label: AppLanguage.choose("Button opacity")) { [weak self] in
                    self?.settings.controlOpacity = $0; self?.controlsChanged?()
                }
            case .editLayout:
                content.text = AppLanguage.choose("Edit controls layout")
                content.secondaryText = ControlsLayout.isCustomized ? AppLanguage.choose("Customized") : AppLanguage.choose("Move, resize or hide buttons")
                content.textProperties.color = .systemBlue
                cell.selectionStyle = .default
            case .hideTouchWithController:
                content.text = AppLanguage.choose("Hide when a controller is connected")
                content.secondaryText = AppLanguage.choose("Touch controls come back as soon as the controller disconnects")
                cell.accessoryView = toggle(settings.hideTouchWithController,
                    label: AppLanguage.choose("Hide touch controls with a controller")) { [weak self] in
                    self?.settings.hideTouchWithController = $0
                }
            case .keyboardMouse:
                content.text = AppLanguage.choose("Keyboard and mouse")
                content.secondaryText = AppLanguage.choose("Play with the PC controls (WASD, mouse look). With both connected, touch controls hide")
                cell.accessoryView = toggle(settings.keyboardMouse, label: AppLanguage.choose("Keyboard and mouse")) { [weak self] in
                    self?.settings.keyboardMouse = $0
                    if !$0 { KeyboardMouse.shared.releaseAll() }
                }
            case .inputState:
                content.text = AppLanguage.choose("Input device (live test)")
                let device = PGLastInputDevice()
                let kind = device == -4 ? AppLanguage.choose("Mouse/keyboard") : (0...3).contains(device) ? AppLanguage.choose("Controller") : AppLanguage.choose("Unknown")
                content.secondaryText = AppLanguage.interpolate(AppLanguage.choose("{arg0} [{arg1}] · Aim mode: {arg2}"), [kind, String(device), String(PGTargetingMode())])
            }
        case .gyro:
            let aimRows = settings.gyroAim == .off ? 1 : 3
            if indexPath.row == aimRows {
                content.text = AppLanguage.choose("Tilt steering")
                let button = UIButton(configuration: .gray())
                button.configuration?.title = settings.tiltSteer.title
                button.menu = UIMenu(children: TiltSteerMode.allCases.map { mode in
                    UIAction(title: mode.title, state: mode == settings.tiltSteer ? .on : .off) { [weak self] _ in
                        self?.settings.tiltSteer = mode; UIView.performWithoutAnimation { self?.tableView.reloadSections([Section.gyro.rawValue], with: .none) }
                    }
                })
                button.showsMenuAsPrimaryAction = true
                button.sizeToFit()
                cell.accessoryView = button
                cell.selectionStyle = .none
            } else if indexPath.row == aimRows + 1 {
                content.text = AppLanguage.interpolate(AppLanguage.choose("Full lock at {arg0}°"), [String(describing: Int(settings.tiltFullLock))])
                cell.accessoryView = slider(settings.tiltFullLock, 10, 45, label: AppLanguage.choose("Tilt for full steering")) { [weak self] in self?.settings.tiltFullLock = $0.rounded() }
                cell.selectionStyle = .none
            } else if indexPath.row == 0 {
                content.text = AppLanguage.choose("Gyro")
                content.secondaryText = settings.gyroAim.title
                let menu = UIMenu(children: GyroAimMode.allCases.map { mode in
                    UIAction(title: mode.title, state: mode == settings.gyroAim ? .on : .off) { [weak self] _ in
                        self?.settings.gyroAim = mode; UIView.performWithoutAnimation { self?.tableView.reloadSections([Section.gyro.rawValue], with: .none) }
                    }
                })
                let button = UIButton(configuration: .gray())
                button.configuration?.title = settings.gyroAim.title
                button.menu = menu
                button.showsMenuAsPrimaryAction = true
                button.sizeToFit()
                cell.accessoryView = button
                cell.selectionStyle = .none
            } else if indexPath.row == 1 {
                content.text = String(format: AppLanguage.choose("Sensitivity %.1f×"), settings.gyroSensitivity)
                let slider = UISlider()
                slider.minimumValue = 0.2; slider.maximumValue = 3
                slider.value = Float(settings.gyroSensitivity)
                slider.frame.size.width = 150
                slider.accessibilityLabel = AppLanguage.choose("Gyro sensitivity")
                slider.addAction(UIAction { [weak self, weak slider] _ in
                    guard let self, let slider else { return }
                    self.settings.gyroSensitivity = (Double(slider.value) * 10).rounded() / 10
                    var updated = cell.defaultContentConfiguration()
                    updated.text = String(format: AppLanguage.choose("Sensitivity %.1f×"), self.settings.gyroSensitivity)
                    cell.contentConfiguration = updated
                }, for: .valueChanged)
                cell.accessoryView = slider
                cell.selectionStyle = .none
            } else {
                content.text = AppLanguage.choose("Invert vertical")
                cell.accessoryView = toggle(settings.gyroInvertY, label: AppLanguage.choose("Invert vertical gyro")) { [weak self] in self?.settings.gyroInvertY = $0 }
                cell.selectionStyle = .none
            }
        case .files:
            configureFileCell(cell, &content, fileRows[indexPath.row])
        case .language:
            cell.selectionStyle = .none
            content.text = AppLanguage.choose("App language")
            content.secondaryText = AppLanguage.choose("Language for menus and settings")
            let button = UIButton(type: .system)
            button.setTitle(AppLanguage.current.name + " ▾", for: .normal)
            button.accessibilityLabel = AppLanguage.choose("App language")
            button.showsMenuAsPrimaryAction = true
            button.menu = UIMenu(children: AppLanguage.allCases.map { language in
                UIAction(title: language.name, state: language == AppLanguage.current ? .on : .off) { [weak self] _ in
                    AppLanguage.select(language)
                    self?.title = AppLanguage.choose("Settings")
                    self?.navigationItem.rightBarButtonItem?.title = AppLanguage.choose("Done")
                    self?.tableView.reloadData()
                }
            })
            button.sizeToFit()
            cell.accessoryView = button
        case .device:
            if indexPath.row == 0 {
                content.text = settings.tier.displaySummary
                content.secondaryText = settings.tier.increasedMemoryStatus
                content.secondaryTextProperties.color = DeviceTier.increasedMemoryGranted == false ? .systemOrange : .secondaryLabel
                content.textProperties.font = .preferredFont(forTextStyle: .footnote)
                content.textProperties.color = .secondaryLabel
                cell.selectionStyle = .none
            } else if indexPath.row == 1 {
                content.text = AppLanguage.choose("Send log to the developer")
                content.secondaryText = AppLanguage.choose("One tap. Helps fix crashes and loading problems")
                content.textProperties.color = .systemBlue
            } else {
                content.text = AppLanguage.choose("Share log")
                content.secondaryText = AppLanguage.choose("Save or send this run's log and the previous one yourself")
                content.textProperties.color = .systemBlue
            }
        }
        // The tab row uses its own full-width UISegmentedControl.  Assigning
        // UIListContentConfiguration here creates a managed content view on top
        // of the custom subview, hiding it and swallowing touches.
        if indexPath.section == Section.controls.rawValue,
           controlsRows[indexPath.row] == .tab { return cell }
        cell.contentConfiguration = content
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        if indexPath.section == Section.device.rawValue, indexPath.row == 1 { sendLog(); return }
        if indexPath.section == Section.device.rawValue, indexPath.row == 2 { shareLogs(from: tableView.cellForRow(at: indexPath)); return }
        if indexPath.section == Section.controls.rawValue,
           controlsRows[indexPath.row] == .editLayout { editLayout?(); return }
        if indexPath.section == Section.mode.rawValue {
            guard indexPath.row < GameMode.allCases.count else { return }
            settings.gameMode = GameMode.allCases[indexPath.row]
            gameModeChanged?()
            UIView.performWithoutAnimation { tableView.reloadSections([Section.mode.rawValue], with: .none) }
            return
        }
        if indexPath.section == Section.files.rawValue { selectFileRow(fileRows[indexPath.row]); return }
        let presets = settings.tier.allowed
        guard indexPath.section == Section.graphics.rawValue, indexPath.row < presets.count else { return }
        settings.graphicsPreset = presets[indexPath.row]
        resolutionChanged?()
        UIView.performWithoutAnimation { tableView.reloadSections([Section.graphics.rawValue], with: .none) }
    }

    // MARK: Game files

    private func makeFileRows() -> [FileRow] {
        let phase = preloader.phase
        let hasFiles = preloader.cachedBytes > 0
        switch phase {
        case .unavailable: return [.status]
        case .idle: return hasFiles ? [.start, .remove] : [.start]
        case .downloading: return [.status, .pause, .cancel]
        case .paused: return [.status, .resume, .cancel] + (hasFiles ? [.remove] : [])
        case .complete: return [.status, .remove]
        }
    }

    @objc private func preloadChanged() {
        let rows = makeFileRows()
        let section = Section.files.rawValue
        // Footer text depends on these; a footer only resizes on a reload.
        let key = "\(rows)|\(preloader.phase)|\(preloader.removing)|\(preloader.lastError ?? "")|\(fileMessage ?? "")|\(preloader.measured)|\(preloader.cachedBytes > 0)"
        if rows != fileRows || key != fileStateKey {
            fileRows = rows
            fileStateKey = key
            UIView.performWithoutAnimation { tableView.reloadSections([section], with: .none) }
            return
        }
        // Same rows: refresh the visible text in place (no flicker).
        for (row, kind) in rows.enumerated() {
            guard let cell = tableView.cellForRow(at: IndexPath(row: row, section: section)) else { continue }
            var content = cell.defaultContentConfiguration()
            content.secondaryTextProperties.color = .secondaryLabel
            configureFileCell(cell, &content, kind)
            cell.contentConfiguration = content
        }
    }

    private func progressText() -> String {
        let percent = Int((preloader.fraction * 100).rounded(.down))
        var text = AppLanguage.interpolate(AppLanguage.choose("{arg0}% · {arg1} of {arg2}"), [String(describing: percent), String(describing: AssetPreloader.format(preloader.cachedBytes)), String(describing: AssetPreloader.format(preloader.totalBytes))])
        if preloader.phase == .downloading {
            if let rate = preloader.bytesPerSecond { text += " · \(AssetPreloader.format(UInt64(rate)))/s" }
            if let seconds = preloader.secondsRemaining { text += " · " + AssetPreloader.formatDuration(seconds) }
        }
        return text
    }

    private func configureFileCell(_ cell: UITableViewCell, _ content: inout UIListContentConfiguration, _ row: FileRow) {
        let total = preloader.measured ? AssetPreloader.format(preloader.totalBytes) : AppLanguage.choose("Checking size")
        switch row {
        case .status:
            cell.selectionStyle = .none
            switch preloader.phase {
            case .unavailable(let reason):
                content.text = AppLanguage.choose("Download all game files")
                content.secondaryText = reason
                content.textProperties.color = .secondaryLabel
            case .complete:
                content.text = AppLanguage.choose("All files on device")
                content.secondaryText = AppLanguage.interpolate(AppLanguage.choose("{arg0} · plays without streaming"), [String(describing: total)])
                content.image = UIImage(systemName: "checkmark.circle.fill")
                content.imageProperties.tintColor = Theme.ok
            case .downloading:
                content.text = AppLanguage.choose("Downloading game files")
                content.secondaryText = progressText()
                cell.accessoryView = progressView()
            default:
                content.text = preloader.lastError == nil ? AppLanguage.choose("Download paused") : AppLanguage.choose("Download stopped")
                content.secondaryText = progressText()
                cell.accessoryView = progressView()
            }
        case .start:
            content.text = AppLanguage.choose("Download all game files")
            content.textProperties.color = .tintColor
            if preloader.cachedBytes > 0 && preloader.measured {
                content.secondaryText = AppLanguage.interpolate(AppLanguage.choose("{arg0} · {arg1} already on this iPhone"), [String(describing: total), String(describing: AssetPreloader.format(preloader.cachedBytes))])
            } else {
                content.secondaryText = total
            }
            content.image = UIImage(systemName: "arrow.down.circle")
        case .pause:
            content.text = AppLanguage.choose("Pause")
            content.textProperties.color = .tintColor
            content.image = UIImage(systemName: "pause.circle")
        case .resume:
            content.text = AppLanguage.choose("Resume download")
            content.textProperties.color = .tintColor
            content.image = UIImage(systemName: "arrow.down.circle")
        case .cancel:
            content.text = AppLanguage.choose("Cancel download")
            content.secondaryText = AppLanguage.choose("Keeps what is already downloaded")
            content.textProperties.color = .systemRed
            content.image = UIImage(systemName: "xmark.circle")
            content.imageProperties.tintColor = .systemRed
        case .remove:
            content.text = preloader.removing ? AppLanguage.choose("Removing files…") : AppLanguage.choose("Remove downloaded files")
            content.secondaryText = engineRunning ? AppLanguage.choose("Available after restarting the app") : AppLanguage.interpolate(AppLanguage.choose("Frees {arg0}"), [String(describing: AssetPreloader.format(preloader.cachedBytes))])
            content.textProperties.color = engineRunning ? .secondaryLabel : .systemRed
            content.image = UIImage(systemName: "trash")
            content.imageProperties.tintColor = engineRunning ? .secondaryLabel : .systemRed
            cell.selectionStyle = engineRunning ? .none : .default
        }
    }

    private func progressView() -> UIProgressView {
        let bar = UIProgressView(progressViewStyle: .default)
        bar.frame.size.width = 110
        bar.progress = Float(preloader.fraction)
        bar.accessibilityLabel = AppLanguage.choose("Download progress")
        return bar
    }

    private func filesFooter() -> String {
        var text = ""
        if let message = fileMessage ?? preloader.lastError { text = message + "\n\n" }
        switch preloader.phase {
        case .unavailable: return text
        case .complete:
            text += AppLanguage.choose("The game reads everything from this iPhone. Removing the files frees the space; the game then streams again.")
        default:
            let size = preloader.measured ? AssetPreloader.format(preloader.totalBytes) : AppLanguage.choose("about 21 GB")
            text += AppLanguage.interpolate(AppLanguage.choose("Saves the whole game on this iPhone ({arg0}) so it no longer streams from the server. Tailscale must be connected while it downloads. Keep the app open: in the background the download pauses after a short while and continues when you come back. You can play while it downloads."), [size])
            if preloader.cachedBytes > 0 && preloader.phase != .downloading {
                text += AppLanguage.choose(" Removing files also clears the startup set; the next Play prepares it again.")
            }
        }
        return text
    }

    private func selectFileRow(_ row: FileRow) {
        fileMessage = nil
        switch row {
        case .status: return
        case .start, .resume:
            let start = { [weak self] in
                guard let self else { return }
                if let message = self.preloader.start() { self.showAlert(AppLanguage.choose("Can't download"), message) }
            }
            if row == .start {
                let alert = UIAlertController(title: AppLanguage.choose("Download all game files?"),
                    message: AppLanguage.interpolate(AppLanguage.choose("This saves {arg0} more on this iPhone ({arg1} free). Wi-Fi and Tailscale recommended."), [String(describing: AssetPreloader.format(preloader.missingBytes)), String(describing: AssetPreloader.format(preloader.availableBytes()))]),
                    preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: AppLanguage.choose("Cancel"), style: .cancel))
                alert.addAction(UIAlertAction(title: AppLanguage.choose("Download"), style: .default) { _ in start() })
                present(alert, animated: true)
            } else { start() }
        case .pause: preloader.pause()
        case .cancel: preloader.cancel()
        case .remove:
            guard !engineRunning else { return }
            let alert = UIAlertController(title: AppLanguage.choose("Remove downloaded files?"),
                message: AppLanguage.interpolate(AppLanguage.choose("Frees {arg0}. The game will stream from the server again."), [String(describing: AssetPreloader.format(preloader.cachedBytes))]),
                preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: AppLanguage.choose("Cancel"), style: .cancel))
            alert.addAction(UIAlertAction(title: AppLanguage.choose("Remove"), style: .destructive) { [weak self] _ in
                guard let self else { return }
                self.preloader.removeDownloads { message in
                    if let message { self.showAlert(AppLanguage.choose("Can't remove files"), message) }
                }
            })
            present(alert, animated: true)
        }
        preloadChanged()
    }

    private func showAlert(_ title: String, _ message: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: AppLanguage.choose("OK"), style: .default))
        present(alert, animated: true)
    }

    private func currentSizeText() -> String {
        let screen = view.window?.windowScene?.screen.bounds.size ?? UIScreen.main.bounds.size
        let (w, h) = GraphicsConfiguration.size(for: engineRunning ? bootPreset : settings.graphicsPreset, renderHeight: settings.renderHeight,
                                                screen: screen, matchScreenShape: settings.matchScreenShape)
        return AppLanguage.interpolate(AppLanguage.choose("Renders at {arg0}×{arg1}"), [String(describing: w), String(describing: h)])
    }
    /// Uploads the logs after the player confirms, with an optional note (its own screen, so the
    /// keyboard never covers Send in landscape).
    private func sendLog() {
        let screen = SendLogViewController()
        screen.finished = { [weak self] title, message in self?.showAlert(title, message) }
        let nav = UINavigationController(rootViewController: screen)
        nav.modalPresentationStyle = .fullScreen
        present(nav, animated: true)
    }
    private func shareLogs(from cell: UITableViewCell?) {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let logs = ["native-port.log", "native-port-previous.log"].map { documents.appendingPathComponent($0) }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
        guard !logs.isEmpty else { showAlert(AppLanguage.choose("No log yet"), AppLanguage.choose("Start the game once, then try again.")); return }
        let sheet = UIActivityViewController(activityItems: logs, applicationActivities: nil)
        sheet.popoverPresentationController?.sourceView = cell ?? view
        present(sheet, animated: true)
    }
    private func resolutionTitle(_ height: Int) -> String {
        if height == 0 {
            let screen = view.window?.windowScene?.screen.bounds.size ?? UIScreen.main.bounds.size
            let (_, h) = GraphicsConfiguration.size(for: engineRunning ? bootPreset : settings.graphicsPreset, renderHeight: 0, screen: screen, matchScreenShape: settings.matchScreenShape)
            return AppLanguage.interpolate(AppLanguage.choose("Auto ({arg0}p)"), [String(describing: h)])
        }
        return height == GraphicsConfiguration.nativeHeight ? AppLanguage.interpolate(AppLanguage.choose("Native ({arg0}p)"), [String(describing: height)]) : "\(height)p"
    }
    private func reloadFooters() {
        UIView.performWithoutAnimation { tableView.reloadSections([Section.graphics.rawValue], with: .none) }
    }
    /// Compact slider plus a live numeric readout; unlike a secondaryText
    /// snapshot the displayed value follows the finger without reloading rows.
    private func sensitivitySlider(_ value: Double, low: Double, high: Double,
                                   label: String, changed: @escaping (Double) -> Void) -> UIView {
        let view = UIStackView()
        view.axis = .horizontal
        view.alignment = .center
        view.spacing = 7
        view.frame.size = CGSize(width: 175, height: 32)
        let slider = UISlider()
        slider.minimumValue = Float(low)
        slider.maximumValue = Float(high)
        slider.value = Float(value)
        slider.accessibilityLabel = label
        let number = UILabel()
        number.text = String(format: "%.1f×", value)
        number.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        number.textColor = .secondaryLabel
        number.textAlignment = .right
        number.widthAnchor.constraint(equalToConstant: 43).isActive = true
        slider.addAction(UIAction { [weak slider, weak number] _ in
            guard let slider else { return }
            let rounded = (Double(slider.value) * 10).rounded() / 10
            number?.text = String(format: "%.1f×", rounded)
            changed(rounded)
        }, for: .valueChanged)
        view.addArrangedSubview(slider)
        view.addArrangedSubview(number)
        return view
    }
    private func slider(_ value: Double, _ low: Float, _ high: Float, label: String, changed: @escaping (Double) -> Void) -> UISlider {
        let control = UISlider()
        control.minimumValue = low; control.maximumValue = high
        control.value = Float(value)
        control.frame.size.width = 160
        control.accessibilityLabel = label
        control.addAction(UIAction { [weak control] _ in changed(Double(control?.value ?? 0)) }, for: .valueChanged)
        return control
    }
    private func toggle(_ on: Bool, label: String, changed: @escaping (Bool) -> Void) -> UISwitch {
        let control = UISwitch()
        control.isOn = on
        control.accessibilityLabel = label
        control.addAction(UIAction { [weak control] _ in changed(control?.isOn ?? false) }, for: .valueChanged)
        return control
    }
}
