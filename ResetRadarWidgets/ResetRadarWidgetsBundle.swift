import SwiftUI
import WidgetKit

@main
struct ResetRadarWidgetsBundle: WidgetBundle {
    var body: some Widget {
        PlaceholderWidget()
    }
}

/// An empty scaffold widget; the allowance widgets are designed in the iOS app design.
struct PlaceholderWidget: Widget {
    var body: some WidgetConfiguration {
        EmptyWidgetConfiguration()
    }
}
