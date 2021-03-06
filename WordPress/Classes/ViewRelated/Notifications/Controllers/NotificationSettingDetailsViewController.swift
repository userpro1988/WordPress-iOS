import Foundation
import WordPressShared
import WordPressComAnalytics


/// The purpose of this class is to render a collection of NotificationSettings for a given Stream,
/// encapsulated in the class NotificationSettings.Stream, and to provide the user a simple interface
/// to update those settings, as needed.
///
open class NotificationSettingDetailsViewController: UITableViewController
{
    // MARK: - Initializers
    public convenience init(settings: NotificationSettings) {
        self.init(settings: settings, stream: settings.streams.first!)
    }

    public convenience init(settings: NotificationSettings, stream: NotificationSettings.Stream) {
        self.init(style: .grouped)
        self.settings = settings
        self.stream = stream
    }



    // MARK: - View Lifecycle
    open override func viewDidLoad() {
        super.viewDidLoad()
        setupTitle()
        setupNotifications()
        setupTableView()
        reloadTable()
    }

    open override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        WPAnalytics.track(.openedNotificationSettingDetails)
    }

    open override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        saveSettingsIfNeeded()
    }



    // MARK: - Setup Helpers
    fileprivate func setupTitle() {
        title = stream?.kind.description()
    }

    fileprivate func setupNotifications() {
        // Reload whenever the app becomes active again since Push Settings may have changed in the meantime!
        let notificationCenter = NotificationCenter.default
        notificationCenter.addObserver(self,
            selector:   #selector(NotificationSettingDetailsViewController.reloadTable),
            name:       NSNotification.Name.UIApplicationDidBecomeActive,
            object:     nil)
    }

    fileprivate func setupTableView() {
        // Register the cells
        tableView.register(SwitchTableViewCell.self, forCellReuseIdentifier: Row.Kind.Setting.rawValue)
        tableView.register(WPTableViewCell.self, forCellReuseIdentifier: Row.Kind.Text.rawValue)

        // Hide the separators, whenever the table is empty
        tableView.tableFooterView = UIView()

        // Style!
        WPStyleGuide.configureColors(for: view, andTableView: tableView)
    }

    @IBAction func reloadTable() {
        sections = isDeviceStreamDisabled() ? sectionsForDisabledDeviceStream() : sectionsForSettings(settings!, stream: stream!)
        tableView.reloadData()
    }



    // MARK: - Private Helpers
    fileprivate func sectionsForSettings(_ settings: NotificationSettings, stream: NotificationSettings.Stream) -> [Section] {
        // WordPress.com Channel requires a brief description per row.
        // For that reason, we'll render each row in its own section, with it's very own footer
        let singleSectionMode = settings.channel != .wordPressCom

        // Parse the Rows
        var rows = [Row]()

        for key in settings.sortedPreferenceKeys(stream) {
            let description = settings.localizedDescription(key)
            let value       = stream.preferences?[key] ?? true
            let row         = Row(kind: .Setting, description: description, key: key, value: value)

            rows.append(row)
        }

        // Single Section Mode: A single section will contain all of the rows
        if singleSectionMode {
            return [Section(rows: rows)]
        }

        // Multi Section Mode: We'll have one Section per Row
        var sections = [Section]()

        for row in rows {
            let unwrappedKey    = row.key ?? String()
            let footerText      = settings.localizedDetails(unwrappedKey)
            let section         = Section(rows: [row], footerText: footerText)
            sections.append(section)
        }

        return sections
    }

    fileprivate func sectionsForDisabledDeviceStream() -> [Section] {
        let description     = NSLocalizedString("Go to iOS Settings", comment: "Opens WPiOS Settings.app Section")
        let row             = Row(kind: .Text, description: description, key: nil, value: nil)

        let footerText      = NSLocalizedString("Push Notifications have been turned off in iOS Settings App. " +
                                                "Toggle \"Allow Notifications\" to turn them back on.",
                                                comment: "Suggests to enable Push Notification Settings in Settings.app")
        let section         = Section(rows: [row], footerText: footerText)

        return [section]
    }



    // MARK: - UITableView Delegate Methods
    open override func numberOfSections(in tableView: UITableView) -> Int {
        return sections.count
    }

    open override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return sections[section].rows.count
    }

    open override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let section = sections[indexPath.section]
        let row     = section.rows[indexPath.row]
        let cell    = tableView.dequeueReusableCell(withIdentifier: row.kind.rawValue)

        switch row.kind {
        case .Text:
            configureTextCell(cell as! WPTableViewCell, row: row)
        case .Setting:
            configureSwitchCell(cell as! SwitchTableViewCell, row: row)
        }

        return cell!
    }

    open override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        guard section == firstSectionIndex else {
            return nil
        }
        return siteName
    }

    open override func tableView(_ tableView: UITableView, willDisplayHeaderView view: UIView, forSection section: Int) {
        WPStyleGuide.configureTableViewSectionHeader(view)
    }

    open override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        return sections[section].footerText
    }

    open override func tableView(_ tableView: UITableView, willDisplayFooterView view: UIView, forSection section: Int) {
        WPStyleGuide.configureTableViewSectionFooter(view)
    }

    open override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectSelectedRowWithAnimation(true)

        if isDeviceStreamDisabled() {
            openApplicationSettings()
        }
    }



    // MARK: - UITableView Helpers
    fileprivate func configureTextCell(_ cell: WPTableViewCell, row: Row) {
        cell.textLabel?.text    = row.description
        WPStyleGuide.configureTableViewCell(cell)
    }

    fileprivate func configureSwitchCell(_ cell: SwitchTableViewCell, row: Row) {
        let settingKey          = row.key ?? String()

        cell.name               = row.description
        cell.on                 = newValues[settingKey] ?? (row.value ?? true)
        cell.onChange           = { [weak self] (newValue: Bool) in
            self?.newValues[settingKey] = newValue
        }
    }



    // MARK: - Disabled Push Notifications Handling
    fileprivate func isDeviceStreamDisabled() -> Bool {
        return stream?.kind == .Device && !PushNotificationsManager.sharedInstance.notificationsEnabledInDeviceSettings()
    }

    fileprivate func openApplicationSettings() {
        let targetURL = URL(string: UIApplicationOpenSettingsURLString)
        UIApplication.shared.openURL(targetURL!)
    }



    // MARK: - Service Helpers
    fileprivate func saveSettingsIfNeeded() {
        if newValues.count == 0 || settings == nil {
            return
        }

        let context = ContextManager.sharedInstance().mainContext
        let service = NotificationSettingsService(managedObjectContext: context!)

        service.updateSettings(settings!,
            stream              : stream!,
            newValues           : newValues,
            success             : {
                WPAnalytics.track(.notificationsSettingsUpdated, withProperties: ["success": true])
            },
            failure             : { (error: Error?) in
                WPAnalytics.track(.notificationsSettingsUpdated, withProperties: ["success": false])
                self.handleUpdateError()
            })
    }

    fileprivate func handleUpdateError() {
        let title       = NSLocalizedString("Oops!", comment: "")
        let message     = NSLocalizedString("There has been an unexpected error while updating your Notification Settings",
                                            comment: "Displayed after a failed Notification Settings call")
        let cancelText  = NSLocalizedString("Cancel", comment: "Cancel. Action.")
        let retryText   = NSLocalizedString("Retry", comment: "Retry. Action")

        let alertController = UIAlertController(title: title, message: message, preferredStyle: .alert)

        alertController.addCancelActionWithTitle(cancelText, handler: nil)

        alertController.addDefaultActionWithTitle(retryText) { (action: UIAlertAction) in
            self.saveSettingsIfNeeded()
        }

        alertController.presentFromRootViewController()
    }



    // MARK: - Private Nested Class'ess
    fileprivate class Section {
        var rows: [Row]
        var footerText: String?

        init(rows: [Row], footerText: String? = nil) {
            self.rows           = rows
            self.footerText     = footerText
        }
    }

    fileprivate class Row {
        let description: String
        let kind: Kind
        let key: String?
        let value: Bool?

        init(kind: Kind, description: String, key: String? = nil, value: Bool? = nil) {
            self.description    = description
            self.kind           = kind
            self.key            = key
            self.value          = value
        }

        enum Kind: String {
            case Setting        = "SwitchCell"
            case Text           = "TextCell"
        }
    }


    // MARK: - Computed Properties
    fileprivate var siteName: String {
        switch settings!.channel {
        case .wordPressCom:
            return NSLocalizedString("WordPress.com Updates", comment: "WordPress.com Notification Settings Title")
        case .other:
            return NSLocalizedString("Other Sites", comment: "Other Sites Notification Settings Title")
        default:
            return settings?.blog?.settings?.name ?? NSLocalizedString("Unnamed Site", comment: "Displayed when a site has no name")
        }
    }

    // MARK: - Private Constants
    fileprivate let firstSectionIndex = 0

    // MARK: - Private Properties
    fileprivate var settings: NotificationSettings?
    fileprivate var stream: NotificationSettings.Stream?

    // MARK: - Helpers
    fileprivate var sections = [Section]()
    fileprivate var newValues = [String: Bool]()
}
