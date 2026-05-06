import AppKit
import CodexQuotaCore

@MainActor
final class StatusItemController: NSObject {
    private let statusItem: NSStatusItem
    private let presenter: QuotaStatusPresenter
    private let refreshAction: (() async -> QuotaSnapshot)?
    private var snapshot: QuotaSnapshot

    init(
        snapshot: QuotaSnapshot,
        presenter: QuotaStatusPresenter,
        refreshAction: (() async -> QuotaSnapshot)? = nil
    ) {
        self.snapshot = snapshot
        self.presenter = presenter
        self.refreshAction = refreshAction
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()
        configure()
    }

    func update(snapshot: QuotaSnapshot) {
        self.snapshot = snapshot
        configure()
    }

    private func configure() {
        statusItem.button?.title = presenter.menuBarTitle(for: snapshot)
        statusItem.button?.toolTip = presenter.tooltip(for: snapshot)
        statusItem.menu = makeMenu()
    }

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Codex Quota Manager", action: nil, keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "当前账号：\(snapshot.accountAlias)", action: nil, keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: presenter.detailLine(for: snapshot), action: nil, keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "刷新", action: #selector(refresh), keyEquivalent: "r"))
        menu.addItem(NSMenuItem(title: "打开管理窗口", action: #selector(openManagementWindow), keyEquivalent: ","))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "退出", action: #selector(quit), keyEquivalent: "q"))

        for item in menu.items {
            item.target = self
        }

        return menu
    }

    @objc private func refresh() {
        update(snapshot: .mockRefreshing)
        guard let refreshAction else {
            return
        }
        Task { [weak self] in
            let refreshed = await refreshAction()
            self?.update(snapshot: refreshed)
        }
    }

    @objc private func openManagementWindow() {
        ManagementWindowController.shared.show()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
