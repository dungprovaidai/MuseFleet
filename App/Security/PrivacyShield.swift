import SwiftUI
import UIKit

// A separate window also covers presented browsers, upload pickers and sheets.
@MainActor
struct PrivacyShield: UIViewRepresentable {
    var isPresented: Bool
    var content: AnyView

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> UIView {
        let view = WindowAnchor()
        view.isUserInteractionEnabled = false
        view.onWindowChanged = { [weak coordinator = context.coordinator] scene in
            coordinator?.attach(to: scene)
        }
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.content = content
        context.coordinator.isPresented = isPresented
        context.coordinator.attach(to: uiView.window?.windowScene)
    }

    static func dismantleUIView(_ uiView: UIView, coordinator: Coordinator) { coordinator.attach(to: nil) }

    final class Coordinator {
        var content = AnyView(Color(uiColor: .systemBackground).ignoresSafeArea())
        var isPresented = false
        private var shield: UIWindow?

        func attach(to scene: UIWindowScene?) {
            guard let scene else {
                shield?.isHidden = true
                shield?.rootViewController = nil
                shield = nil
                return
            }
            if shield?.windowScene !== scene {
                let window = UIWindow(windowScene: scene)
                window.windowLevel = .alert + 1
                window.backgroundColor = .systemBackground
                window.rootViewController = UIHostingController(rootView: content)
                window.rootViewController?.view.accessibilityViewIsModal = true
                shield = window
            }
            (shield?.rootViewController as? UIHostingController<AnyView>)?.rootView = content
            shield?.isHidden = !isPresented
        }
    }
}

@MainActor
private final class WindowAnchor: UIView {
    var onWindowChanged: ((UIWindowScene?) -> Void)?
    override func didMoveToWindow() {
        super.didMoveToWindow()
        onWindowChanged?(window?.windowScene)
    }
}
