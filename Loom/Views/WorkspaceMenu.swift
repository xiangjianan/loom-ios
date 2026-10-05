import SwiftUI
import UIKit

/// Freeze momentum before UIKit snapshots the glass menu's backdrop.
struct WorkspaceMenu: UIViewRepresentable {
    var newConversation: () -> Void
    var history: () -> Void
    var settings: () -> Void
    var backup: () -> Void

    func makeUIView(context: Context) -> MenuButton {
        let button = MenuButton(type: .system)
        button.setImage(UIImage(systemName: "ellipsis", withConfiguration: UIImage.SymbolConfiguration(weight: .semibold)), for: .normal)
        button.tintColor = .label
        button.showsMenuAsPrimaryAction = true
        button.accessibilityLabel = "更多操作"
        button.accessibilityIdentifier = "workspace-menu"
        return button
    }
    func updateUIView(_ button: MenuButton, context: Context) {
        button.menu = UIMenu(children: [
            UIAction(title: "新对话", image: UIImage(systemName: "square.and.pencil")) { _ in newConversation() },
            UIAction(title: "历史对话", image: UIImage(systemName: "clock")) { _ in history() },
            UIAction(title: "模型设置", image: UIImage(systemName: "slider.horizontal.3")) { _ in settings() },
            UIAction(title: "备份（导入 / 导出）", image: UIImage(systemName: "externaldrive")) { _ in backup() }
        ])
    }
    final class MenuButton: UIButton {
        override func beginTracking(_ touch: UITouch, with event: UIEvent?) -> Bool {
            if let window { stopMomentum(in: window) }
            return super.beginTracking(touch, with: event)
        }
        private func stopMomentum(in view: UIView) {
            if let scroll = view as? UIScrollView, !(scroll is UITextView), scroll.contentSize.height > scroll.bounds.height {
                scroll.setContentOffset(scroll.contentOffset, animated: false)
            }
            for child in view.subviews { stopMomentum(in: child) }
        }
    }
}
