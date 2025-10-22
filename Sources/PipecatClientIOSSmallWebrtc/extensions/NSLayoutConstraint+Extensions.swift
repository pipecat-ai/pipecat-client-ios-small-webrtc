import Foundation
import UIKit

extension NSLayoutConstraint {
    /// Sets the priority of this constraint.
    ///
    /// - Parameter priority: the priority value to set.
    /// - Returns: this constraint.
    internal func priority(_ priority: UILayoutPriority) -> Self {
        self.priority = priority

        return self
    }
}

extension NSLayoutConstraint {
    internal static func scaleAspectFit(
        _ view: UIView,
        in superview: UIView,
        aspectRatio: CGFloat
    ) -> [NSLayoutConstraint] {
        [
            view.centerXAnchor.constraint(equalTo: superview.centerXAnchor),
            view.centerYAnchor.constraint(equalTo: superview.centerYAnchor),
            view.widthAnchor.constraint(
                equalTo: view.heightAnchor,
                multiplier: aspectRatio
            ),
            view.widthAnchor.constraint(lessThanOrEqualTo: superview.widthAnchor),
            view.heightAnchor.constraint(lessThanOrEqualTo: superview.heightAnchor),
            view.widthAnchor.constraint(equalTo: superview.widthAnchor).priority(.defaultHigh),
            view.heightAnchor.constraint(equalTo: superview.heightAnchor).priority(.defaultHigh)
        ]
    }

    internal static func scaleAspectFill(
        _ view: UIView,
        in superview: UIView,
        aspectRatio: CGFloat
    ) -> [NSLayoutConstraint] {
        [
            view.centerXAnchor.constraint(equalTo: superview.centerXAnchor),
            view.centerYAnchor.constraint(equalTo: superview.centerYAnchor),
            view.widthAnchor.constraint(
                equalTo: view.heightAnchor,
                multiplier: aspectRatio
            ),
            view.widthAnchor.constraint(greaterThanOrEqualTo: superview.widthAnchor),
            view.heightAnchor.constraint(greaterThanOrEqualTo: superview.heightAnchor),
            view.widthAnchor.constraint(equalTo: superview.widthAnchor).priority(.defaultHigh),
            view.heightAnchor.constraint(equalTo: superview.heightAnchor).priority(.defaultHigh)
        ]
    }
}
