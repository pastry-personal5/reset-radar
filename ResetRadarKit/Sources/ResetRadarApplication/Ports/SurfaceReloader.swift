/// Asks the system to reload widget or complication timelines; fire and forget.
public protocol SurfaceReloader: Sendable {
    func reloadWidgets()
    func reloadComplications()
}
