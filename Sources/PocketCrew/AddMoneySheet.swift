import SwiftUI

struct AddMoneySheet: View {
  @EnvironmentObject private var store: AppStore
  @Environment(\.dismiss) private var dismiss
  @State private var amount = ""
  @State private var reason = ""
  @State private var pin = ""
  @State private var error = ""
  private var cents: Int? {
    guard let value = Decimal(string: amount), value > 0, value <= 1_000_000 else { return nil }
    let scaled = NSDecimalNumber(decimal: value * 100)
    let result = scaled.intValue
    return scaled == NSDecimalNumber(value: result) ? result : nil
  }
  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      Text(AppLanguage.text("Add Money")).font(.largeTitle.bold())
      Text("Add money to \(store.selectedChild.name)’s ledger. No real money is transferred.")
      TextField(AppLanguage.text("Amount"), text: $amount).textFieldStyle(.roundedBorder)
      TextField(AppLanguage.text("Reason (optional)"), text: $reason).textFieldStyle(.roundedBorder)
      if let rule = store.split(for: store.selectedChildId) {
        Text("Spend \(rule.spendPercent)% · Save \(rule.savePercent)% · Give \(rule.givePercent)%")
        if let cents, let parts = try? FinanceEngine.split(total: cents, rule: rule) {
          Text("Spend \(parts.spend.currency()) · Save \(parts.save.currency()) · Give \(parts.give.currency())")
        }
      }
      SecureField(AppLanguage.text("Parent passcode"), text: $pin).textFieldStyle(.roundedBorder)
      if !error.isEmpty { Text(error).foregroundStyle(.red) }
      HStack {
        Button(AppLanguage.text("Cancel")) { dismiss() }.buttonStyle(SecondaryButtonStyle())
        Spacer()
        Button(AppLanguage.text("Add Money")) {
          guard store.verifyParentPasscode(pin) else { error = "The parent passcode didn’t match."; return }
          guard let cents else { return }
          do { try store.addMoney(childId: store.selectedChildId, amount: cents, reason: reason); dismiss() }
          catch { self.error = error.localizedDescription }
        }.buttonStyle(PrimaryButtonStyle()).disabled(cents == nil)
      }
    }.padding(28).frame(width: 540).background(Color.oat)
  }
}
