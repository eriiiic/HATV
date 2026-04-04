import Observation
import SwiftUI

struct DashboardPickerView: View {
    @Bindable var viewModel: RootViewModel
    let chooseDashboard: (HADashboardSummary) -> Void
    let changeConnection: () -> Void

    private let columns = [
        GridItem(.adaptive(minimum: 280, maximum: 340), spacing: 20)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Choose a Dashboard")
                        .font(.system(size: 38, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)

                    if let instanceInfo = viewModel.instanceInfo {
                        Text("\(instanceInfo.locationName) • Home Assistant \(instanceInfo.version)")
                            .font(.headline.weight(.medium))
                            .foregroundStyle(.white.opacity(0.66))
                    }
                }

                Spacer()

                Button("Change Server", action: changeConnection)
                    .buttonStyle(.bordered)
                    .tint(.white.opacity(0.18))
            }

            ScrollView {
                LazyVGrid(columns: columns, spacing: 20) {
                    ForEach(viewModel.dashboards) { dashboard in
                        Button {
                            chooseDashboard(dashboard)
                        } label: {
                            VStack(alignment: .leading, spacing: 14) {
                                Image(systemName: dashboard.icon == nil ? "square.grid.2x2.fill" : "sparkles.tv.fill")
                                    .font(.system(size: 22, weight: .bold))
                                    .foregroundStyle(.white)
                                    .frame(width: 52, height: 52)
                                    .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))

                                Text(dashboard.title)
                                    .font(.title3.weight(.bold))
                                    .foregroundStyle(.white)
                                    .multilineTextAlignment(.leading)

                                Text(dashboard.mode.capitalized)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.white.opacity(0.62))

                                Spacer(minLength: 0)

                                if dashboard.id == viewModel.selectedDashboard?.id {
                                    Text("Selected")
                                        .font(.subheadline.weight(.bold))
                                        .foregroundStyle(.black)
                                        .padding(.horizontal, 14)
                                        .padding(.vertical, 8)
                                        .background(Color.white, in: Capsule())
                                }
                            }
                            .frame(maxWidth: .infinity, minHeight: 210, alignment: .topLeading)
                            .padding(22)
                            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 24, style: .continuous)
                                    .strokeBorder(.white.opacity(0.10))
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 6)
            }
        }
        .padding(.horizontal, 72)
        .padding(.vertical, 42)
    }
}
