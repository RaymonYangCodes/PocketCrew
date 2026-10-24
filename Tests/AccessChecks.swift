import Foundation

@main
@MainActor
struct AccessChecks {
  static func main() throws {
    let legacyProductData = Data("""
      {"id":"amazon-legacy","source":"amazon","title":"A saved book",
      "detail":"Previously saved","category":"Books","symbol":"book.fill",
      "priceCents":1000,"imageURL":null,"productURL":"https://www.amazon.com/dp/example"}
      """.utf8)
    let legacyProduct = try JSONDecoder().decode(ShoppingProduct.self, from: legacyProductData)
    try expect(
      legacyProduct.source == .amazon && legacyProduct.currencyCode == nil
        && legacyProduct.merchant == nil && legacyProduct.priceCents == 1_000,
      "Existing product snapshots no longer decode")
    let shoppingProductData = Data("""
      {"id":"google-123","source":"googleShopping","title":"Art supplies",
      "detail":"Google Shopping result via SerpApi","category":"Shopping",
      "symbol":"shippingbox.fill","priceCents":1299,"imageURL":null,
      "productURL":"https://www.google.com/shopping/product/123",
      "currencyCode":"USD","merchant":"Example store"}
      """.utf8)
    let shoppingProduct = try JSONDecoder().decode(ShoppingProduct.self, from: shoppingProductData)
    try expect(
      shoppingProduct.source == .googleShopping && shoppingProduct.priceCents == 1_299
        && shoppingProduct.merchant == "Example store" && shoppingProduct.matchesCurrency("USD")
        && !shoppingProduct.matchesCurrency("CAD") && shoppingProduct.externalProductURL != nil,
      "Google Shopping snapshots lost source, integer price, merchant, or currency")
    let roundTripProduct = try JSONDecoder().decode(
      ShoppingProduct.self, from: JSONEncoder().encode(shoppingProduct))
    try expect(roundTripProduct == shoppingProduct, "Shopping snapshots changed after persistence")
    let unsafeProduct = ShoppingProduct(
      id: "unsafe", source: .googleShopping, title: "Unsafe link", detail: "Test",
      category: "Test", symbol: "shippingbox", priceCents: 100, imageURL: nil,
      productURL: "javascript:alert(1)", currencyCode: "USD")
    try expect(unsafeProduct.externalProductURL == nil, "A non-HTTPS product link was allowed")

    let token = UUID().uuidString
    let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent(
      "PocketCrew-access-\(token).json")
    guard let defaults = UserDefaults(suiteName: "PocketCrewAccess-\(token)") else {
      throw AccessFailure("Could not create isolated passcode storage")
    }
    defer {
      try? FileManager.default.removeItem(at: fileURL)
      UserDefaults.standard.removePersistentDomain(forName: "PocketCrewAccess-\(token)")
    }

    let store = AppStore(
      repository: LocalJSONRepository(fileURL: fileURL),
      credentialVault: CredentialVault(defaults: defaults))

    var blocked = false
    do { try createTestGig(store) } catch { blocked = true }
    try expect(blocked, "A locked session performed a parent action")

    try store.unlock(profileName: "  jOrDaN  ", passcode: "1212")
    try expect(store.role == .child && store.selectedChildId == DemoData.jordanId,
      "Menu-bar name matching must ignore capitalization and surrounding spaces")
    store.lock()
    var wrongNameRejected = false
    do { try store.unlock(profileName: "No such profile", passcode: "1212") }
    catch { wrongNameRejected = true }
    try expect(wrongNameRejected && !store.sessionUnlocked, "Unknown profile unlocked the session")
    var wrongPasscodeRejected = false
    do { try store.unlock(profileName: "JORDAN", passcode: "0000") }
    catch { wrongPasscodeRejected = true }
    try expect(wrongPasscodeRejected && !store.sessionUnlocked, "Wrong passcode unlocked the session")
    try store.unlock(profileName: "pArEnT", passcode: "2468")
    try expect(store.role == .parent, "Parent alias failed")
    store.lock()
    try store.unlock(profileName: "MAYA", passcode: "2468")
    try expect(store.role == .parent, "Parent display name should be case-insensitive")
    try store.updateSchedule(frequency: .custom, date: Date(), customDays: 3)
    try expect(store.state.schedule.customDays == 3, "Custom interval was not saved")
    blocked = false
    do { try store.updateSchedule(frequency: .custom, date: Date(), customDays: 0) } catch { blocked = true }
    try expect(blocked && store.state.schedule.customDays == 3, "Invalid interval changed the schedule")
    let nextCustomDate = try store.state.schedule.followingDate(after: store.state.schedule.nextPaydayAt, timezone: store.state.family.timezone)
    try expect(nextCustomDate > store.state.schedule.nextPaydayAt, "Custom payday did not advance")
    try store.addGoal(childId: DemoData.jordanId, title: "New featured goal", icon: "🎯", target: 1500, targetDate: nil, proposed: false)
    let chosenGoal = store.state.goals.last!.id
    try store.unlock(.child(DemoData.jordanId), passcode: "1212")
    let ledgerBeforeFeaturing = store.state.ledger
    try store.featureGoal(chosenGoal)
    try expect(store.goal(for: DemoData.jordanId)?.id == chosenGoal, "Child could not choose their featured goal")
    try expect(store.state.ledger == ledgerBeforeFeaturing, "Featuring moved money")
    if let siblingGoal = store.state.goals.first(where: { $0.childId == DemoData.rileyId }) {
      blocked = false
      do { try store.featureGoal(siblingGoal.id) } catch { blocked = true }
      try expect(blocked, "A child featured their sibling’s goal")
    }
    let ledgerBeforeGoal = store.state.ledger.count
    blocked = false
    do { try store.completeGoal(chosenGoal) } catch { blocked = true }
    try expect(blocked && store.state.ledger.count == ledgerBeforeGoal, "Child completed a goal")
    blocked = false
    do { try store.addMoney(childId: DemoData.jordanId, amount: 100, reason: "Child deposit") } catch { blocked = true }
    try expect(blocked && store.state.ledger.count == ledgerBeforeGoal, "Child added money")
    try store.addGoal(childId: DemoData.jordanId, title: shoppingProduct.title, icon: "🎯",
      target: shoppingProduct.priceCents, targetDate: nil, proposed: true, shoppingProduct: shoppingProduct)
    let savedGoal = try JSONDecoder().decode(SavingsGoal.self, from: JSONEncoder().encode(store.state.goals.last!))
    blocked = false
    do { try store.featureGoal(savedGoal.id) } catch { blocked = true }
    try expect(blocked, "Featuring must not approve a proposed goal")
    try expect(savedGoal.shoppingProduct == shoppingProduct, "Shopping goal lost its product photo, seller, or price")
    try expect(store.state.goals.last?.targetCents == 1299
      && store.state.goals.last?.status == .proposed
      && store.state.ledger.count == ledgerBeforeGoal,
      "Shopping goal must preserve cents, await approval, and leave money unchanged")
    blocked = false
    do {
      try store.addGoal(childId: DemoData.rileyId, title: shoppingProduct.title, icon: "🎯",
        target: shoppingProduct.priceCents, targetDate: nil, proposed: true)
    } catch { blocked = true }
    try expect(blocked, "A child proposed a shopping goal for another child")
    guard let rileyWork = store.state.assignments.first(where: { $0.childId == DemoData.rileyId })
    else { throw AccessFailure("Demo data did not include eligible Riley work") }
    blocked = false
    do { try store.start(rileyWork.id) } catch { blocked = true }
    try expect(blocked, "Jordan started Riley’s assigned work")
    guard let available = store.state.assignments.first(where: { $0.status == .available })
    else { throw AccessFailure("Demo data needs an available gig for the claim regression test") }
    try store.start(available.id)
    let claimed = store.state.assignments.first(where: { $0.id == available.id })
    try expect(claimed?.childId == DemoData.jordanId && claimed?.status == .inProgress,
      "Claim did not assign the gig and expose submission controls")
    var duplicateClaimBlocked = false
    do { try store.start(available.id) } catch { duplicateClaimBlocked = true }
    try expect(duplicateClaimBlocked, "An in-progress gig could be claimed twice")

    guard let submission = store.state.submissions.first else {
      throw AccessFailure("Demo data did not include a submission")
    }
    blocked = false
    do { try store.approve(submission.id) } catch { blocked = true }
    try expect(blocked, "A child session approved work")
    blocked = false
    do { try store.dismissWorkPresets() } catch { blocked = true }
    try expect(blocked, "A child changed the parent's preset preference")

    store.lock()
    blocked = false
    do { try store.unlock(.child(DemoData.rileyId), passcode: "1212") } catch { blocked = true }
    try expect(blocked, "Jordan’s passcode unlocked Riley’s profile")

    try store.unlock(.parent, passcode: "2468")
    try store.dismissWorkPresets()
    let beforeDeposit = JarKind.allCases.map { store.balance($0, childId: DemoData.jordanId) }
    let depositParts = try FinanceEngine.split(total: 1001, rule: store.split(for: DemoData.jordanId)!)
    try store.addMoney(childId: DemoData.jordanId, amount: 1001, reason: "Test deposit")
    let afterDeposit = JarKind.allCases.map { store.balance($0, childId: DemoData.jordanId) }
    try expect(zip(afterDeposit, beforeDeposit).map { $0 - $1 } == [depositParts.spend, depositParts.save, depositParts.give], "Add Money split is incorrect")
    blocked = false
    do { try store.addMoney(childId: DemoData.jordanId, amount: -1, reason: "Invalid") } catch { blocked = true }
    try expect(blocked, "Negative deposit accepted")
    try store.addGoal(childId: DemoData.jordanId, title: "Completion check", icon: "🎯", target: 100, targetDate: nil, proposed: false)
    let completionGoal = store.state.goals.last!.id
    let completionBalance = store.balance(.spend, childId: DemoData.jordanId)
    try store.completeGoal(completionGoal)
    try expect(store.balance(.spend, childId: DemoData.jordanId) == completionBalance - 100,
      "Goal completion did not deduct its target from Spend")
    try expect(store.state.goals.last!.status == .completed && !store.state.goals.last!.featured,
      "Goal completion did not move the goal to completed")
    blocked = false
    do { try store.completeGoal(completionGoal) } catch { blocked = true }
    try expect(blocked && store.balance(.spend, childId: DemoData.jordanId) == completionBalance - 100,
      "Goal completion charged twice")
    let syncedFamily = try JSONDecoder().decode(
      Family.self, from: JSONEncoder().encode(store.state.family))
    try expect(syncedFamily.workPresetsDismissed == true,
      "Preset completion was not included in the shared family payload")
    var legacyFamily = try JSONSerialization.jsonObject(
      with: JSONEncoder().encode(syncedFamily)) as! [String: Any]
    legacyFamily.removeValue(forKey: "workPresetsDismissed")
    let decodedLegacyFamily = try JSONDecoder().decode(
      Family.self, from: JSONSerialization.data(withJSONObject: legacyFamily))
    try expect(decodedLegacyFamily.workPresetsDismissed == nil,
      "Families created before shared preset preferences must still decode")
    try createTestGig(store)
    try expect(
      store.state.workItems.contains(where: { $0.title == "Parent-only test gig" }),
      "An unlocked parent could not create a gig")

    let wrongCurrencyProduct = ShoppingProduct(
      id: "google-cad", source: .googleShopping, title: "Canadian listing", detail: "Test",
      category: "Test", symbol: "shippingbox", priceCents: 500, imageURL: nil,
      productURL: nil, currencyCode: "CAD", merchant: "Example store")
    let stateBeforeWrongCurrency = store.state
    blocked = false
    do {
      try store.addShoppingProduct(
        wrongCurrencyProduct, for: DemoData.jordanId, destination: .awaitingApproval)
    } catch { blocked = true }
    try expect(
      blocked && store.state == stateBeforeWrongCurrency,
      "Adding a mismatched-currency product changed family data")

    let savedWrongCurrencyEntry = ShoppingEntry(
      id: UUID(), createdAt: Date(), updatedAt: Date(), createdBy: store.guardianId,
      familyId: store.state.family.id, childId: DemoData.jordanId,
      product: wrongCurrencyProduct, status: .awaitingApproval)
    var importedState = stateBeforeWrongCurrency
    importedState.shoppingEntries = (importedState.shoppingEntries ?? []) + [savedWrongCurrencyEntry]
    store.refreshCloud(state: importedState)
    blocked = false
    do { try store.approveShoppingPurchase(savedWrongCurrencyEntry.id) } catch { blocked = true }
    try expect(
      blocked && store.state == importedState,
      "Approving a saved mismatched-currency item changed a jar, ledger, or request")
    store.refreshCloud(state: stateBeforeWrongCurrency)

    guard let cartRequest = store.shoppingEntries.first(where: {
      $0.childId == DemoData.rileyId && $0.status == .awaitingApproval
    }) else { throw AccessFailure("Demo data did not include a cart request") }
    let spendBefore = store.balance(.spend, childId: DemoData.rileyId)
    let saveBefore = store.balance(.save, childId: DemoData.rileyId)
    try store.updateShoppingPrice(cartRequest.id, priceCents: 199, reason: "Parent contribution")
    try store.updateShoppingPrice(cartRequest.id, priceCents: 299, reason: "Updated total")
    try expect(store.balance(.spend, childId: DemoData.rileyId) == spendBefore,
      "Editing a price changed the balance before approval")
    store.lock()
    try store.unlock(.child(DemoData.rileyId), passcode: "0808")
    blocked = false
    do { try store.updateShoppingPrice(cartRequest.id, priceCents: 1, reason: "Child edit") } catch { blocked = true }
    try expect(blocked, "A child changed a shopping price")
    store.lock()
    try store.unlock(.parent, passcode: "2468")
    blocked = false
    do { try store.updateShoppingPrice(cartRequest.id, priceCents: -1, reason: "Invalid") } catch { blocked = true }
    try expect(blocked, "Negative shopping price allowed")
    try store.approveShoppingPurchase(cartRequest.id)
    try expect(
      store.balance(.spend, childId: DemoData.rileyId)
        == spendBefore - 299,
      "Approving a cart item did not deduct the exact price from Spend")
    try expect(
      store.balance(.save, childId: DemoData.rileyId) == saveBefore,
      "Approving a cart item changed a non-Spend jar")
    let transactionCount = store.state.ledger.count
    blocked = false
    do { try store.updateShoppingPrice(cartRequest.id, priceCents: 99, reason: "Rewrite history") } catch { blocked = true }
    try expect(blocked, "A completed purchase price was edited")
    blocked = false
    do { try store.approveShoppingPurchase(cartRequest.id) } catch { blocked = true }
    try expect(
      blocked && store.state.ledger.count == transactionCount,
      "A cart item was paid more than once")

    guard let wish = store.shoppingEntries.first(where: {
      $0.childId == DemoData.jordanId && $0.status == .wishlist
    }) else { throw AccessFailure("Demo data did not include a wishlist item") }
    let balancesBeforeGift = JarKind.allCases.map {
      store.balance($0, childId: DemoData.jordanId)
    }
    try store.giftShoppingItem(wish.id)
    try expect(
      JarKind.allCases.map { store.balance($0, childId: DemoData.jordanId) }
        == balancesBeforeGift,
      "Giving a wishlist item for free changed a jar balance")

    let authenticatedGuardianId = UUID()
    store.setAuthenticatedGuardian(id: authenticatedGuardianId, email: "parent@example.com")
    let sam = ChildSetupDraft(
      name: "Sam", ageRange: "9–12", avatarSymbol: "star.fill", avatarHex: "86BBD8",
      passcode: "8642", spendPercent: 50, savePercent: 40, givePercent: 10)
    let taylor = ChildSetupDraft(
      name: "Taylor", ageRange: "13–15", avatarSymbol: "bolt.fill", avatarHex: "F6C453",
      passcode: "7531", spendPercent: 60, savePercent: 30, givePercent: 10)
    try store.createFamily(
      familyName: "Test Family", parentName: "Alex", children: [sam, taylor], currency: "USD",
      frequency: .weekly, parentPasscode: "9753")
    try expect(
      store.guardianId == authenticatedGuardianId, "Cloud actions used the demo guardian ID")
    try expect(
      store.state.users.first(where: { $0.id == authenticatedGuardianId })?.email
        == "parent@example.com",
      "The signed-in guardian email was not attached to the family")
    try expect(store.state.children.count == 2, "Multi-child setup did not create both profiles")
    try expect(
      store.split(for: sam.id)?.spendPercent == 50
        && store.split(for: taylor.id)?.spendPercent == 60,
      "Children did not retain independent jar splits")
    try expect(
      store.state.jars.filter({ $0.childId == sam.id }).count == 3
        && store.state.jars.filter({ $0.childId == taylor.id }).count == 3,
      "Each child did not receive a complete set of jars")
    store.lock()
    var siblingCodeWasRejected = false
    do { try store.unlock(.child(taylor.id), passcode: sam.passcode) } catch {
      siblingCodeWasRejected = true
    }
    try expect(siblingCodeWasRejected, "One new child’s passcode unlocked their sibling")
    try store.unlock(.parent, passcode: "9753")
    var duplicateCodeWasRejected = false
    do {
      try store.updatePasscode(
        target: .child(taylor.id), currentParentPasscode: "9753", newPasscode: sam.passcode)
    } catch { duplicateCodeWasRejected = true }
    try expect(duplicateCodeWasRejected, "A child was allowed to reuse a sibling’s passcode")
    try store.updateChild(
      childId: taylor.id, name: "Taylor", ageRange: "13–15", avatarSymbol: "heart.fill",
      avatarHex: "EF7C6A", spend: 55, save: 35, give: 10)
    try expect(
      store.split(for: taylor.id)?.spendPercent == 55
        && store.child(taylor.id)?.avatarSymbol == "heart.fill",
      "Editing one child did not persist their independent settings")

    var refreshedState = store.state
    refreshedState.family.name = "Updated on another device"
    store.refreshCloud(state: refreshedState)
    try expect(
      store.state.family.name == "Updated on another device" && store.sessionUnlocked,
      "A live family refresh did not preserve the unlocked profile session")

    let oldLedger = store.state.ledger
    try store.viewChildAsParent(taylor.id)
    try expect(store.role == .child && store.selectedChildId == taylor.id,
      "Unlocked parent could not view a child without their passcode")
    var childCannotBypass = false
    do { try store.viewChildAsParent(sam.id) } catch { childCannotBypass = true }
    try expect(childCannotBypass, "A child bypassed another profile’s passcode")
    try store.unlock(.parent, passcode: "9753")
    var wrongRemovalPinRejected = false
    do { try store.removeChild(taylor.id, parentPasscode: "0000") }
    catch { wrongRemovalPinRejected = true }
    try expect(wrongRemovalPinRejected, "Removing a child accepted the wrong parent passcode")
    try store.removeChild(taylor.id, parentPasscode: "9753")
    try expect(store.child(taylor.id) == nil, "Removed child is still selectable")
    try expect(store.state.archivedChildren?.contains(where: { $0.id == taylor.id }) == true,
      "Removed child's identity was not preserved")
    try expect(store.state.ledger == oldLedger, "Removing a child changed the ledger")
    let realFamilyId = store.state.family.id
    vaultClear(defaults: defaults, familyId: realFamilyId)
    let restarted = AppStore(
      repository: LocalJSONRepository(fileURL: fileURL),
      credentialVault: CredentialVault(defaults: defaults))
    try expect(
      !restarted.profilePasscodesReady,
      "A real family received predictable demo passcodes after an interrupted setup")
    print("✓ 5 PocketCrew access, shopping-snapshot, shopping-ledger, cloud-identity, and live-refresh scenarios passed")
  }

  private static func createTestGig(_ store: AppStore) throws {
    try store.createWork(
      type: .gig, title: "Parent-only test gig", instructions: "Check permission boundaries",
      category: "Test", childId: DemoData.jordanId, recurrence: .once,
      dueAt: Date().addingTimeInterval(3_600), minutes: 10, reward: 1_000, proof: false,
      claimable: false, checklist: [])
  }

  private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    if !condition() { throw AccessFailure(message) }
  }

  private static func vaultClear(defaults: UserDefaults, familyId: UUID) {
    let prefix = "pocketcrew.credential.\(familyId.uuidString)."
    for key in defaults.dictionaryRepresentation().keys where key.hasPrefix(prefix) {
      defaults.removeObject(forKey: key)
    }
  }
}

struct AccessFailure: Error, CustomStringConvertible {
  let description: String
  init(_ description: String) { self.description = description }
}
