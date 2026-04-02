import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var storedConnections: [StoredConnection]
    @State private var viewModel = RootViewModel()

    private var storedConnection: StoredConnection? {
        storedConnections.first(where: { $0.id == StoredConnection.defaultID }) ?? storedConnections.first
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.05, green: 0.08, blue: 0.16),
                    Color(red: 0.07, green: 0.17, blue: 0.28),
                    Color(red: 0.04, green: 0.10, blue: 0.11)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            Circle()
                .fill(Color.cyan.opacity(0.16))
                .frame(width: 720, height: 720)
                .blur(radius: 120)
                .offset(x: 520, y: -320)

            Circle()
                .fill(Color.blue.opacity(0.14))
                .frame(width: 560, height: 560)
                .blur(radius: 120)
                .offset(x: -520, y: 320)

            switch viewModel.screen {
            case .booting:
                LaunchView(statusMessage: viewModel.statusMessage)
            case .connection:
                ConnectionSetupView(viewModel: viewModel) {
                    Task {
                        await viewModel.connect(modelContext: modelContext, storedConnection: storedConnection)
                    }
                }
            case .dashboardPicker:
                DashboardPickerView(
                    viewModel: viewModel,
                    chooseDashboard: { dashboard in
                        Task {
                            await viewModel.chooseDashboard(
                                dashboard,
                                storedConnection: storedConnection,
                                modelContext: modelContext
                            )
                        }
                    },
                    changeConnection: {
                        viewModel.showConnectionEditor()
                    }
                )
            case .dashboard:
                DashboardScreen(
                    viewModel: viewModel,
                    showDashboards: {
                        viewModel.showDashboardPicker()
                    },
                    changeConnection: {
                        viewModel.showConnectionEditor()
                    }
                )
            }
        }
        .task {
            await viewModel.bootstrap(with: storedConnection, modelContext: modelContext)
        }
        .alert(
            "Something Needs Attention",
            isPresented: Binding(
                get: { viewModel.errorMessage != nil },
                set: { if !$0 { viewModel.errorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: StoredConnection.self, inMemory: true)
}

private struct LaunchView: View {
    let statusMessage: String

    var body: some View {
        VStack(spacing: 28) {
            Text("HATV")
                .font(.system(size: 84, weight: .bold, design: .rounded))
                .foregroundStyle(.white)

            Text("Home Assistant companion for Apple TV")
                .font(.title3.weight(.medium))
                .foregroundStyle(.white.opacity(0.8))

            ProgressView()
                .tint(.white)

            Text(statusMessage)
                .foregroundStyle(.white.opacity(0.75))
        }
    }
}
