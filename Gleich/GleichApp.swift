import SwiftUI

@main
struct GleichApp: App {
    var body: some Scene {
        WindowGroup {
            Start()
        }
    }
}

/// Ohne sichtbare obere Leiste schaltet iOS das Zurückwischen vom linken Rand ab – hier wieder an.
extension UINavigationController: @retroactive UIGestureRecognizerDelegate {
    override open func viewDidLoad() {
        super.viewDidLoad()
        interactivePopGestureRecognizer?.delegate = self
    }

    public func gestureRecognizerShouldBegin(_ erkenner: UIGestureRecognizer) -> Bool {
        viewControllers.count > 1
    }
}
