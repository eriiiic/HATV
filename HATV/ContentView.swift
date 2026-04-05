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
            Color(red: 0.03, green: 0.06, blue: 0.10)
                .ignoresSafeArea()

            LinearGradient(
                colors: [
                    Color(red: 0.04, green: 0.09, blue: 0.15),
                    Color(red: 0.05, green: 0.13, blue: 0.19),
                    Color(red: 0.03, green: 0.07, blue: 0.11)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            RadialGradient(
                colors: [Color.cyan.opacity(0.16), .clear],
                center: .topTrailing,
                startRadius: 40,
                endRadius: 700
            )
            .ignoresSafeArea()
            .offset(x: 220, y: -180)

            RadialGradient(
                colors: [Color.white.opacity(0.06), .clear],
                center: .bottomLeading,
                startRadius: 80,
                endRadius: 620
            )
            .ignoresSafeArea()
            .offset(x: -180, y: 240)

            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [.white.opacity(0.03), .clear, .black.opacity(0.08)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .ignoresSafeArea()

            switch viewModel.screen {
            case .booting:
                LaunchView(statusMessage: viewModel.statusMessage)
            case .connection:
                ConnectionSetupView(
                    viewModel: viewModel,
                    testConnection: {
                        Task {
                            await viewModel.testConnection()
                        }
                    },
                    connect: {
                        Task {
                            await viewModel.connect(modelContext: modelContext, storedConnection: storedConnection)
                        }
                    }
                )
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
        VStack(spacing: 22) {
            Text("HATV")
                .font(.system(size: 72, weight: .bold, design: .rounded))
                .foregroundStyle(.white)

            Text("Home Assistant companion for Apple TV")
                .font(.system(size: 24, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.72))

            ProgressView()
                .tint(.white)

            Text(statusMessage)
                .font(.headline.weight(.medium))
                .foregroundStyle(.white.opacity(0.68))
        }
        .padding(.horizontal, 40)
    }
}
