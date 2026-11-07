import SwiftUI

@main
struct GleichApp: App {
    var body: some Scene {
        WindowGroup {
            Start()
        }
    }
}

/// Ohne sichtbare obere Leiste schaltet iOS das Zurückwischen ab – hier wieder an,
/// vom linken Rand und (seit iOS 26) von überall auf der Seite.
extension UINavigationController: @retroactive UIGestureRecognizerDelegate {
    override open func viewDidLoad() {
        super.viewDidLoad()
        interactivePopGestureRecognizer?.delegate = self
        interactiveContentPopGestureRecognizer?.delegate = self
    }

    public func gestureRecognizerShouldBegin(_ erkenner: UIGestureRecognizer) -> Bool {
        viewControllers.count > 1
    }
}
