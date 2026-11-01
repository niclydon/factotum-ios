import SwiftUI
import WidgetKit

@main
struct ARIAWidgetBundle: WidgetBundle {
    var body: some Widget {
        NextEventWidget()
        HealthWidget()
        QuickChatWidget()
        ActivityWidget()
        DashboardWidget()
        LargeWidget()
        MeetingLiveActivity()
        FactotumProgressLiveActivity()
        LockScreenWidgets()
        OneBigThingControl()
        LensControl()
    }
}
