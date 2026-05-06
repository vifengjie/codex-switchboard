import CodexQuotaCore
import SwiftUI

struct QuickDetailView: View {
    let snapshot: QuotaSnapshot
    let presenter = QuotaStatusPresenter()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Codex Quota Manager")
                .font(.headline)
            Text("当前账号：\(snapshot.accountAlias)")
            Text(presenter.detailLine(for: snapshot))
            Text("本会话 tokens：M0 mock")
                .foregroundStyle(.secondary)
        }
        .padding()
        .frame(width: 320)
    }
}
