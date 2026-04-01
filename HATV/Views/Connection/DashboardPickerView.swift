import Observation
import SwiftUI

struct DashboardPickerView: View {
    @Bindable var viewModel: RootViewModel
    let chooseDashboard: (HADashboardSummary) -> Void
    let changeConnection: () -> Void

    private let columns = [
        GridItem(.adaptive(minimum: 320, maximum: 380), spacing: 28)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Choose a Dashboard")
                        .font(.system(size: 48, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)

                    if let instanceInfo = viewModel.instanceInfo {
                        Text("\(instanceInfo.locationName) • Home Assistant \(instanceInfo.version)")
                            .font(.title3.weight(.medium))
                            .foregroundStyle(.white.opacity(0.72))
                    }
                }

                Spacer()

                Button("Change Server", action: changeConnection)
                    .buttonStyle(.borderedProminent)
                    .tint(.white.opacity(0.16))
            }

            ScrollView {
                LazyVGrid(columns: columns, spacing: 28) {
                    ForEach(viewModel.dashboards) { dashboard in
                        Button {
                            chooseDashboard(dashboard)
                        } label: {
                            VStack(alignment: .leading, spacing: 16) {
                                Image(systemName: dashboard.icon == nil ? "square.grid.2x2.fill" : "sparkles.tv.fill")
                                    .font(.system(size: 28, weight: .bold))
                                    .foregroundStyle(.white)
                                    .frame(width: 64, height: 64)
                                    .background(Color.white.opacity(0.10), in: RoundedRectangle(cornerRadius: 18, style: .continuous))

                                Text(dashboard.title)
                                    .font(.title2.weight(.bold))
                                    .foregroundStyle(.white)
                                    .multilineTextAlignment(.leading)

                                Text(dashboard.mode.capitalized)
                                    .font(.headline.weight(.medium))
                                    .foregroundStyle(.white.opacity(0.72))

                                Spacer(minLength: 0)

                                if dashboard.id == viewModel.selectedDashboard?.id {
                                    Text("Selected")
                                        .font(.headline.weight(.bold))
                                        .foregroundStyle(.black)
                                        .padding(.horizontal, 16)
                                        .padding(.vertical, 10)
                                        .background(Color.white, in: Capsule())
                                }
                            }
                            .frame(maxWidth: .infinity, minHeight: 260, alignment: .topLeading)
                            .padding(28)
                            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 28, style: .continuous)
                                    .strokeBorder(.white.opacity(0.14))
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 6)
            }
        }
        .padding(.horizontal, 84)
        .padding(.vertical, 56)
    }
}
