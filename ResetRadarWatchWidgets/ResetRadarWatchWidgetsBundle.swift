import SwiftUI
import WidgetKit

@main
struct ResetRadarWatchWidgetsBundle: WidgetBundle {
    var body: some Widget {
        PlaceholderWidget()
    }
}

/// An empty scaffold widget; the allowance widgets are designed in the Watch app design.
struct PlaceholderWidget: Widget {
    var body: some WidgetConfiguration {
        EmptyWidgetConfiguration()
    }
}
