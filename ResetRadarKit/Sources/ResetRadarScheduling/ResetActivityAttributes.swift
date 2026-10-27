#if os(iOS)
    import ActivityKit
    import Foundation
    import ResetRadarApplication
    import ResetRadarDomain

    @available(iOS 16.1, *)
    public struct ResetActivityAttributes: ActivityAttributes {
        public struct ContentState: Codable, Hashable {
            public let usedPercent: Double
            public let resetsAt: Date
            public let observedAt: Date
            public let accountLabel: String
            public let product: ProductID?
            public let window: WindowDisplayDescriptor
            public let sourceState: SourceState
            public let fractionDigits: Int?

            public init(
                usedPercent: Double, resetsAt: Date, observedAt: Date, accountLabel: String,
                product: ProductID?, window: WindowDisplayDescriptor, sourceState: SourceState,
                fractionDigits: Int?
            ) {
                self.usedPercent = usedPercent
                self.resetsAt = resetsAt
                self.observedAt = observedAt
                self.accountLabel = accountLabel
                self.product = product
                self.window = window
                self.sourceState = sourceState
                self.fractionDigits = fractionDigits
            }
        }

        public let accountWindow: AccountWindow
        public let windowID: WindowID
        public let startedAt: Date

        public init(accountWindow: AccountWindow, windowID: WindowID, startedAt: Date) {
            self.accountWindow = accountWindow
            self.windowID = windowID
            self.startedAt = startedAt
        }
    }
#endif
