import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Text("Podium")
            .font(.largeTitle)
            .padding(80)
    }
}
