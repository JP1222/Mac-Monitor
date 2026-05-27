// MacMonitorWidgetsBundle.swift
//
// WidgetKit extension entry point. Declares the bundle and the three widget
// families (small / medium / large). The bundle is registered to the system
// by Info.plist's `NSExtensionPointIdentifier = com.apple.widgetkit-extension`
// — there's no @main on the bundle itself; the `@main` attribute below tells
// SwiftUI to construct it on launch.

import SwiftUI
import WidgetKit

@main
struct MacMonitorWidgetsBundle: WidgetBundle {
    var body: some Widget {
        RunnersWidget()
    }
}
