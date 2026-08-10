import SwiftUI
import RoundPlayEngine

/// The minimum-cash-flow breakdown of who pays who — a themed bottom sheet, not another trip
/// through the native share sheet, since this is something the group looks at together.
struct SettleUpSheet: View {
    let round: RoundRecord
    let course: Course

    @Environment(\.dismiss) private var dismiss
    @State private var isSharingText = false

    private var payments: [SettlementPayment] {
        RoundShareContent.settlementPayments(round: round, course: course)
    }

    var body: some View {
        NavigationStack {
            RoundPlayList.plain {
                if payments.isEmpty {
                    ContentUnavailableView(
                        "Everyone's settled up",
                        systemImage: "checkmark.seal",
                        description: Text("No money owed for this round.")
                    )
                } else {
                    Section {
                        ForEach(payments) { payment in
                            paymentRow(payment)
                        }
                    } header: {
                        Text("Who Owes Who")
                            .font(RoundPlayFont.archivo(17, .bold))
                            .foregroundStyle(RoundPlayColors.accent)
                    } footer: {
                        RoundPlayTypography.caption("The fewest payments that settle every game — RoundPlay never holds or moves money.")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Settle Up")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                if !payments.isEmpty {
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            isSharingText = true
                        } label: {
                            Image(systemName: "square.and.arrow.up")
                        }
                    }
                }
            }
            .sheet(isPresented: $isSharingText) {
                ShareSheet(items: [RoundShareContent.settlementSummaryText(round: round, course: course)])
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func paymentRow(_ payment: SettlementPayment) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(payment.debtorName)
                    .font(RoundPlayFont.archivo(19, .bold))
                HStack(spacing: 5) {
                    Image(systemName: "arrow.right")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(RoundPlayColors.accent)
                    Text(payment.creditorName)
                        .font(RoundPlayFont.archivo(16, .semiBold))
                        .foregroundStyle(.primary.opacity(0.7))
                }
            }
            Spacer()
            // Deliberately *not* red. A payment isn't a loss — half the people reading this sheet
            // are collecting — and a column of red amounts made settling up look like a problem
            // to fix rather than the good part of the round.
            RoundPlayTypography.money(payment.amount.formatted(.currency(code: "USD")), size: 21)
                .foregroundStyle(.primary)
        }
        .padding(.vertical, 6)
        .roundPlayListRowSeparatorFullWidth()
    }
}

#Preview("Light") {
    Text("Preview host")
        .sheet(isPresented: .constant(true)) {
            SettleUpSheet(round: PreviewData.sampleRound, course: .previewCourse)
        }
        .modelContainer(PreviewData.container)
}
