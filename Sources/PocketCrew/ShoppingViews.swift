import SwiftUI

enum PocketCrewCatalog {
  static let starter: [ShoppingProduct] = [
    product("starter-headphones", "Colorful wireless headphones", "Comfortable volume-limited headphones", "Tech", "headphones", 2_999),
    product("starter-book", "Adventure book set", "Three page-turning chapter books", "Books", "books.vertical.fill", 1_899),
    product("starter-art", "Deluxe art kit", "Markers, pencils, paper, and a carry case", "Creative", "paintpalette.fill", 2_499),
    product("starter-lego", "Building brick set", "A creative 300-piece building set", "Toys", "building.2.fill", 2_199),
    product("starter-ball", "Outdoor soccer ball", "Durable size-five practice ball", "Sports", "soccerball", 1_699),
    product("starter-bottle", "Insulated water bottle", "Leak-resistant bottle for school and activities", "Everyday", "waterbottle.fill", 1_999),
    product("starter-game", "Family card game", "A quick strategy game for the whole crew", "Games", "suit.club.fill", 1_499),
    product("starter-light", "Reading light", "Rechargeable clip light with warm settings", "Room", "lightbulb.fill", 1_299),
    product("starter-journal", "Guided journal", "A cheerful notebook for ideas and plans", "Creative", "pencil.and.scribble", 1_099),
    product("starter-kit", "Beginner science kit", "Hands-on experiments with a reusable guide", "Learning", "flask.fill", 2_799),
    product("starter-cap", "Everyday baseball cap", "Adjustable cotton cap", "Clothing", "tshirt.fill", 1_599),
    product("starter-puzzle", "500-piece puzzle", "A colorful family puzzle", "Games", "puzzlepiece.fill", 1_299),
  ]

  static func search(_ query: String) -> [ShoppingProduct] {
    let terms = query.lowercased().split(separator: " ").map(String.init)
    guard !terms.isEmpty else { return starter }
    return starter.filter { product in
      let haystack = "\(product.title) \(product.detail) \(product.category)".lowercased()
      return terms.allSatisfy(haystack.contains)
    }
  }

  private static func product(
    _ id: String, _ title: String, _ detail: String, _ category: String, _ symbol: String,
    _ priceCents: Money
  ) -> ShoppingProduct {
    ShoppingProduct(
      id: id, source: .pocketCrew, title: title, detail: detail, category: category,
      symbol: symbol, priceCents: priceCents, imageURL: nil, productURL: nil,
      currencyCode: "USD")
  }
}

private enum ShoppingSection: String, CaseIterable, Identifiable {
  case shop, wishlist, cart, history
  var id: String { rawValue }
  var title: String {
    switch self {
    case .shop: "Shop"
    case .wishlist: "Wishlist"
    case .cart: "Cart"
    case .history: "Purchases"
    }
  }
  var icon: String {
    switch self {
    case .shop: "storefront.fill"
    case .wishlist: "heart.fill"
    case .cart: "cart.fill"
    case .history: "clock.arrow.circlepath"
    }
  }
}

private enum ShoppingDecision: Identifiable {
  case approve(ShoppingEntry)
  case gift(ShoppingEntry)

  var id: String {
    switch self {
    case .approve(let entry): "approve-\(entry.id)"
    case .gift(let entry): "gift-\(entry.id)"
    }
  }
  var entry: ShoppingEntry {
    switch self {
    case .approve(let entry), .gift(let entry): entry
    }
  }
}

struct ShoppingCenterView: View {
  @EnvironmentObject private var store: AppStore
  @EnvironmentObject private var cloud: CloudSessionStore
  @Environment(\.dismiss) private var dismiss
  @State private var section: ShoppingSection = .shop
  @State private var query = ""
  @State private var remoteProducts: [ShoppingProduct] = []
  @State private var isSearching = false
  @State private var searchMessage: String?
  @State private var activeSearchID: UUID?
  @State private var lastSuccessfulQuery: String?
  @State private var targetChildId: UUID?
  @State private var decision: ShoppingDecision?
  @State private var declineEntry: ShoppingEntry?
  @State private var priceEntry: ShoppingEntry?

  private var childId: UUID { targetChildId ?? store.selectedChildId }
  private var isDemoFamily: Bool { cloud.usingDemo }
  private var scopedEntries: [ShoppingEntry] {
    store.shoppingEntries.filter { store.role == .parent || $0.childId == store.selectedChildId }
  }
  private var displayedProducts: [ShoppingProduct] {
    let products = isDemoFamily
      ? PocketCrewCatalog.search(lastSuccessfulQuery ?? "")
      : remoteProducts.filter { $0.source != .pocketCrew }
    var seen = Set<String>()
    return products.filter {
      $0.matchesCurrency(store.state.family.currency) && seen.insert($0.id).inserted
    }
  }

  var body: some View {
    VStack(spacing: 0) {
      header
      Divider()
      Picker("Shopping section", selection: $section) {
        ForEach(ShoppingSection.allCases) { item in
          Label(item.title, systemImage: item.icon).tag(item)
        }
      }
      .pickerStyle(.segmented)
      .padding(.horizontal, 22)
      .padding(.vertical, 14)

      Group {
        switch section {
        case .shop: shop
        case .wishlist: entryList(statuses: [.wishlist])
        case .cart: entryList(statuses: [.awaitingApproval])
        case .history: entryList(statuses: [.purchased, .gifted, .declined])
        }
      }
    }
    #if os(macOS)
      .frame(minWidth: 680, idealWidth: 900, minHeight: 610, idealHeight: 760)
    #else
      .frame(maxWidth: .infinity, maxHeight: .infinity)
    #endif
    .background(Color.oat)
    .onAppear { targetChildId = store.selectedChildId }
    .onChange(of: query) { _, _ in invalidateSearch() }
    .onChange(of: store.state.family.id) { _, _ in invalidateSearch() }
    .onChange(of: cloud.usingDemo) { _, _ in invalidateSearch() }
    .onDisappear { invalidateSearch() }
    .confirmationDialog(
      decisionTitle, isPresented: Binding(
        get: { decision != nil }, set: { if !$0 { decision = nil } }),
      titleVisibility: .visible, presenting: decision
    ) { decision in
      switch decision {
      case .approve(let entry):
        Button("Approve and deduct \(price(entry.product)) from Spend") {
          perform { try store.approveShoppingPurchase(entry.id) }
        }
      case .gift(let entry):
        Button("Give as a gift — no money deducted") {
          perform { try store.giftShoppingItem(entry.id) }
        }
      }
      Button(AppLanguage.text("Cancel"), role: .cancel) {}
    } message: { decision in
      switch decision {
      case .approve:
        Text("This deducts the saved item price only, excluding shipping and tax, from the simulated Spend jar. It does not place an order or pay a store. A parent handles checkout separately.")
      case .gift:
        Text("The item will move to purchase history as a parent gift and the child’s Spend balance will stay the same.")
      }
    }
    .sheet(item: $declineEntry) { entry in
      ShoppingDeclineSheet(entry: entry)
    }
    .sheet(item: $priceEntry) { entry in
      ShoppingPriceSheet(entry: entry)
    }
  }

  private var header: some View {
    HStack(spacing: 14) {
      Image(systemName: "storefront.fill")
        .font(.title2).foregroundStyle(Color.evergreen)
        .frame(width: 48, height: 48).background(Color.evergreen.opacity(0.12), in: RoundedRectangle(cornerRadius: 15))
      VStack(alignment: .leading, spacing: 2) {
        Text("PocketCrew Shop").font(.title2.weight(.black)).fontDesign(.rounded)
        Text("Wish for it, ask for it, and let your grown-up decide.")
          .font(.subheadline).foregroundStyle(.secondary)
      }
      Spacer()
      Button(AppLanguage.text("Done")) { dismiss() }.buttonStyle(SecondaryButtonStyle())
    }.padding(22)
  }

  private var shop: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 16) {
        if store.role == .parent && store.state.children.count > 1 { targetPicker }
        HStack(spacing: 10) {
          Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
          TextField("Search books, games, art supplies…", text: $query)
            .textFieldStyle(.plain)
            .onSubmit { Task { await searchProducts() } }
          if isSearching { ProgressView().controlSize(.small) }
          Button(isDemoFamily ? "Filter" : "Search") { Task { await searchProducts() } }
            .buttonStyle(PrimaryButtonStyle()).disabled(cleanQuery.count < 2 || isSearching)
        }
        .padding(.horizontal, 15).frame(minHeight: 50).background(.white, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.ink.opacity(0.08)))

        Text(isDemoFamily
          ? "Demo catalog only. These sample products and prices help you try wishlist and cart; they are not real store listings. Sign in to a real family for live shopping."
          : "Real store listings from Google Shopping via SerpApi. Prices may change; shipping and tax are not included.")
          .font(.caption).foregroundStyle(.secondary)
        searchResults
        Text("PocketCrew records family decisions and simulated balances. It is not a bank and does not complete store checkout or shipping.")
          .font(.caption2).foregroundStyle(.secondary).padding(.top, 4)
      }.padding(22)
    }
  }

  @ViewBuilder private var searchResults: some View {
    if isSearching {
      PocketPanel(padding: 28) {
        VStack(spacing: 12) {
          ProgressView()
          Text("Finding real products…").font(.headline)
          Text("Looking for prices and photos from Google Shopping.")
            .font(.subheadline).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity).padding(.vertical, 20)
      }
    } else if let searchMessage {
      PocketPanel(padding: 24) {
        VStack(spacing: 14) {
          EmptyState(
            icon: "wifi.exclamationmark", title: "Live search couldn’t load",
            message: searchMessage)
          Button("Try search again") { Task { await searchProducts() } }
            .buttonStyle(PrimaryButtonStyle()).disabled(cleanQuery.count < 2)
        }.frame(maxWidth: .infinity)
      }
    } else if !isDemoFamily && lastSuccessfulQuery == nil {
      EmptyState(
        icon: "magnifyingglass", title: "Find something worth saving for",
        message: cleanQuery.count >= 2
          ? "Press Search to find real photos and prices for “\(cleanQuery)”."
          : "Type what you’re looking for above, then press Search. Real products will appear here.")
        .frame(maxWidth: .infinity).padding(.vertical, 44)
    } else if displayedProducts.isEmpty {
      EmptyState(
        icon: "magnifyingglass", title: isDemoFamily ? "No sample matches" : "No products found",
        message: "Try a broader search, like headphones, books, or art supplies.")
        .frame(maxWidth: .infinity).padding(.vertical, 44)
    } else {
      HStack {
        Text(isDemoFamily
          ? "\(displayedProducts.count) sample ideas"
          : "\(displayedProducts.count) real product results")
          .font(.title3.weight(.black)).fontDesign(.rounded)
        Spacer()
        Text(isDemoFamily ? "Demo prices" : "Prices are snapshots")
          .font(.caption).foregroundStyle(.secondary)
      }
      LazyVGrid(columns: [GridItem(.adaptive(minimum: 245), spacing: 14)], spacing: 14) {
        ForEach(displayedProducts) { product in
          ShoppingProductCard(product: product, childId: childId)
        }
      }
    }
  }

  private var targetPicker: some View {
    HStack {
      Label("Shopping for", systemImage: "person.crop.circle")
        .font(.subheadline.weight(.bold))
      Picker("Child", selection: Binding(
        get: { targetChildId ?? store.selectedChildId },
        set: { targetChildId = $0 }
      )) {
        ForEach(store.state.children) { child in Text(child.name).tag(child.id) }
      }.labelsHidden().frame(maxWidth: 220)
      Spacer()
      Text("Spend: \(store.balance(.spend, childId: childId).currency(code: store.state.family.currency, locale: store.state.family.locale))")
        .font(.subheadline.weight(.bold)).foregroundStyle(Color.evergreen)
    }
    .padding(13).background(Color.sunny.opacity(0.22), in: RoundedRectangle(cornerRadius: 14))
  }

  private func entryList(statuses: Set<ShoppingEntryStatus>) -> some View {
    let entries = scopedEntries.filter { statuses.contains($0.status) }
    return ScrollView {
      VStack(alignment: .leading, spacing: 14) {
        if section == .cart && store.role == .parent {
          Label(
            "Approval records the saved item price in the family ledger, excluding shipping and tax. It deducts Spend but does not order or pay a store. Giving it free leaves Spend unchanged.",
            systemImage: "checkmark.shield.fill")
            .font(.caption).foregroundStyle(.secondary)
            .padding(13).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.sky.opacity(0.18), in: RoundedRectangle(cornerRadius: 14))
        }
        if entries.isEmpty {
          EmptyState(
            icon: section.icon,
            title: section == .history ? "No purchase history yet" : "Nothing here yet",
            message: emptyMessage)
          .frame(maxWidth: .infinity).padding(.vertical, 70)
        } else {
          ForEach(entries) { entry in shoppingEntryCard(entry) }
        }
      }.padding(22)
    }
  }

  private func shoppingEntryCard(_ entry: ShoppingEntry) -> some View {
    PocketPanel(padding: 16) {
      HStack(alignment: .top, spacing: 14) {
        ShoppingProductArt(product: entry.product, size: 64)
        VStack(alignment: .leading, spacing: 5) {
          Text(entry.product.title).font(.headline.weight(.bold))
          HStack(spacing: 6) {
            Text(price(entry.product)).font(.subheadline.weight(.black))
            if store.role == .parent || store.state.children.count > 1 {
              Text("· \(store.child(entry.childId)?.name ?? "Child")")
                .font(.subheadline).foregroundStyle(.secondary)
            }
          }
          Label(entry.status.title, systemImage: statusIcon(entry.status))
            .font(.caption.weight(.bold)).foregroundStyle(statusColor(entry.status))
          if [.wishlist, .awaitingApproval].contains(entry.status) {
            ShoppingGoalButton(product: entry.product, childId: entry.childId)
            if store.role == .parent {
              Button(AppLanguage.text("Edit price")) { priceEntry = entry }
                .buttonStyle(SecondaryButtonStyle())
            }
          }
          if let note = entry.parentNote {
            Text(note).font(.caption).foregroundStyle(.secondary)
          }
          if store.role == .parent, let url = entry.product.externalProductURL {
            Link("Check current store details", destination: url)
              .font(.caption.weight(.bold))
          }
          if [.purchased, .gifted, .declined].contains(entry.status) {
            Text((entry.resolvedAt ?? entry.updatedAt).formatted(date: .abbreviated, time: .shortened))
              .font(.caption2).foregroundStyle(.secondary)
          }
        }
        Spacer(minLength: 8)
        entryActions(entry)
      }
    }
  }

  @ViewBuilder private func entryActions(_ entry: ShoppingEntry) -> some View {
    if entry.status == .wishlist {
      VStack(alignment: .trailing, spacing: 8) {
        Button(store.role == .child ? "Ask to buy" : "Move to cart") {
          perform { try store.moveShoppingEntryToCart(entry.id) }
        }.buttonStyle(PrimaryButtonStyle())
        if store.role == .parent {
          Button(AppLanguage.text("Give free")) { decision = .gift(entry) }.buttonStyle(SecondaryButtonStyle())
        }
        Button("Remove", role: .destructive) {
          perform { try store.removeShoppingEntry(entry.id) }
        }.font(.caption.weight(.bold))
      }
    } else if entry.status == .awaitingApproval {
      if store.role == .parent {
        VStack(alignment: .trailing, spacing: 8) {
          Button(AppLanguage.text("Approve")) { decision = .approve(entry) }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(!entry.product.matchesCurrency(store.state.family.currency))
          if !entry.product.matchesCurrency(store.state.family.currency) {
            Text("The item currency must match your family currency.")
              .font(.caption).foregroundStyle(.secondary)
          }
          Button(AppLanguage.text("Give free")) { decision = .gift(entry) }.buttonStyle(SecondaryButtonStyle())
          Button("Not now") { declineEntry = entry }.font(.caption.weight(.bold))
        }
      } else {
        VStack(alignment: .trailing, spacing: 8) {
          Text("Waiting for parent").font(.caption.weight(.bold)).foregroundStyle(.secondary)
          Button(AppLanguage.text("Remove request"), role: .destructive) {
            perform { try store.removeShoppingEntry(entry.id) }
          }.font(.caption.weight(.bold))
        }
      }
    }
  }

  private var decisionTitle: String {
    guard let decision else { return "Confirm" }
    switch decision {
    case .approve(let entry): return "Record a purchase of \(entry.product.title)?"
    case .gift(let entry): return "Give \(entry.product.title) for free?"
    }
  }

  private var emptyMessage: String {
    switch section {
    case .shop: ""
    case .wishlist: "Save ideas from the Shop, then decide later."
    case .cart: store.role == .parent ? "A child’s ask-to-buy requests will appear here." : "Add an item in Shop when you’re ready to ask."
    case .history: "Approved purchases and parent gifts will stay here for both parent and child."
    }
  }

  private func statusIcon(_ status: ShoppingEntryStatus) -> String {
    switch status {
    case .wishlist: "heart.fill"
    case .awaitingApproval: "clock.fill"
    case .purchased: "checkmark.circle.fill"
    case .gifted: "gift.fill"
    case .declined: "bubble.left.fill"
    case .removed: "xmark.circle.fill"
    }
  }

  private func statusColor(_ status: ShoppingEntryStatus) -> Color {
    switch status {
    case .wishlist: .coral
    case .awaitingApproval: .evergreen
    case .purchased: .evergreen
    case .gifted: .coral
    case .declined, .removed: .secondary
    }
  }

  private func perform(_ action: () throws -> Void) {
    do { try action() } catch { store.show(error: error) }
    decision = nil
  }

  private var cleanQuery: String {
    String(query.trimmingCharacters(in: .whitespacesAndNewlines).prefix(120))
  }

  private func price(_ product: ShoppingProduct) -> String {
    product.formattedPrice(
      fallbackCurrency: store.state.family.currency, locale: store.state.family.locale)
  }

  private func invalidateSearch() {
    activeSearchID = nil
    isSearching = false
    remoteProducts = []
    searchMessage = nil
    lastSuccessfulQuery = nil
  }

  @MainActor private func searchProducts() async {
    let clean = cleanQuery
    guard clean.count >= 2, !isSearching, lastSuccessfulQuery != clean else { return }
    guard !isDemoFamily else {
      lastSuccessfulQuery = clean
      return
    }
    guard cloud.signedInUser != nil else {
      searchMessage = "Ask a parent to sign in to your cloud family, then search again. Your saved wishlist and cart are still available."
      return
    }
    let requestID = UUID()
    activeSearchID = requestID
    isSearching = true
    remoteProducts = []
    searchMessage = nil
    do {
      let products = try await cloud.searchShoppingProducts(
        query: clean, currency: store.state.family.currency, locale: store.state.family.locale)
      guard activeSearchID == requestID, cleanQuery == clean else { return }
      isSearching = false
      activeSearchID = nil
      lastSuccessfulQuery = clean
      remoteProducts = products.filter { $0.source != .pocketCrew }
    } catch {
      guard activeSearchID == requestID, cleanQuery == clean else { return }
      isSearching = false
      activeSearchID = nil
      remoteProducts = []
      searchMessage = "\(error.localizedDescription) Your saved wishlist and cart are still available."
    }
  }
}

private struct ShoppingProductCard: View {
  @EnvironmentObject private var store: AppStore
  let product: ShoppingProduct
  let childId: UUID

  var body: some View {
    PocketPanel(padding: 15) {
      VStack(alignment: .leading, spacing: 11) {
        HStack {
          Spacer()
          ShoppingProductArt(product: product, size: product.source == .pocketCrew ? 66 : 120)
          Spacer()
        }.padding(.vertical, product.source == .pocketCrew ? 0 : 8)
        if product.source != .googleShopping {
          Text(product.source.title.uppercased())
            .font(.system(size: 9, weight: .black)).tracking(0.8)
            .padding(.horizontal, 7).padding(.vertical, 5)
            .background(Color.sunny.opacity(0.24), in: Capsule())
        }
        Text(product.title).font(.headline.weight(.bold)).lineLimit(2)
        Text(product.detail).font(.caption).foregroundStyle(.secondary).lineLimit(2)
        if let merchant = product.merchant, !merchant.isEmpty {
          Text("Sold by \(merchant)").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
        }
        if store.role == .parent, let url = product.externalProductURL {
          Link(destination: url) {
            Label("Check current store details", systemImage: "arrow.up.right.square")
              .font(.caption.weight(.bold))
          }
        }
        HStack {
          Text(product.formattedPrice(
            fallbackCurrency: store.state.family.currency, locale: store.state.family.locale))
            .font(.title3.weight(.black)).monospacedDigit()
          Spacer()
          if product.source != .googleShopping {
            Text(product.category).font(.caption.weight(.bold)).foregroundStyle(.secondary)
          }
        }
        HStack(spacing: 8) {
          Button {
            add(.awaitingApproval)
          } label: {
            Label(store.role == .child ? "Ask to buy" : "Add to cart", systemImage: "cart.badge.plus")
              .frame(maxWidth: .infinity)
          }.buttonStyle(PrimaryButtonStyle())
            .disabled(!product.matchesCurrency(store.state.family.currency))
          Button { add(.wishlist) } label: {
            Image(systemName: "heart").frame(width: 44, height: 44)
          }.buttonStyle(SecondaryButtonStyle()).accessibilityLabel("Add \(product.title) to wishlist")
            .disabled(!product.matchesCurrency(store.state.family.currency))
        }
        ShoppingGoalButton(product: product, childId: childId)
      }
    }
  }

  private func add(_ destination: ShoppingEntryStatus) {
    do { try store.addShoppingProduct(product, for: childId, destination: destination) }
    catch { store.show(error: error) }
  }
}

private struct ShoppingGoalButton: View {
  @EnvironmentObject private var store: AppStore
  let product: ShoppingProduct
  let childId: UUID
  @State private var showingGoal = false

  var body: some View {
    Button { showingGoal = true } label: {
      Label(AppLanguage.text("Make a savings goal"), systemImage: "target")
        .font(.subheadline.weight(.bold)).frame(minHeight: 44)
    }
    .buttonStyle(.plain).foregroundStyle(Color.evergreen)
    .disabled(product.priceCents <= 0 || !product.matchesCurrency(store.state.family.currency))
    .sheet(isPresented: $showingGoal) {
      GoalSheet(proposed: store.role == .child, childId: childId, product: product)
    }
  }
}

struct ShoppingProductArt: View {
  let product: ShoppingProduct
  let size: CGFloat

  var body: some View {
    Group {
      if let imageURL = product.imageURL, let url = URL(string: imageURL),
        url.scheme?.lowercased() == "https", url.host != nil {
        AsyncImage(url: url) { phase in
          if let image = phase.image {
            image.resizable().scaledToFit()
              .accessibilityLabel("\(product.title), product photo from \(product.source.title)")
          } else if phase.error != nil {
            fallback
          } else {
            ProgressView()
          }
        }
      } else {
        fallback
      }
    }
    .frame(width: size, height: size)
    .background(Color.sky.opacity(0.16), in: RoundedRectangle(cornerRadius: 16))
    .clipShape(RoundedRectangle(cornerRadius: 16))
  }

  private var fallback: some View {
    Image(systemName: product.symbol.isEmpty ? "shippingbox.fill" : product.symbol)
      .font(.system(size: size * 0.36, weight: .semibold)).foregroundStyle(Color.evergreen)
      .accessibilityLabel("\(product.title), placeholder illustration")
  }
}

private struct ShoppingPriceSheet: View {
  @EnvironmentObject private var store: AppStore
  @Environment(\.dismiss) private var dismiss
  let entry: ShoppingEntry
  @State private var amount: String
  @State private var reason = ""
  @State private var error = ""

  init(entry: ShoppingEntry) {
    self.entry = entry
    _amount = State(initialValue: "\(entry.product.priceCents / 100).\(String(format: "%02d", entry.product.priceCents % 100))")
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      Text("Edit item price").font(.title2.weight(.black)).fontDesign(.rounded)
      Text(entry.product.title).font(.headline)
      Text("Set the amount your child will pay from Spend when you approve. This does not change the store’s price, existing goals, or any balance now.")
        .foregroundStyle(.secondary)
      TextField("Price (\(store.state.family.currency)) — e.g. 12.99", text: $amount)
        .textFieldStyle(.roundedBorder)
      TextField("Reason — e.g. Sale price or parent contribution", text: $reason)
        .textFieldStyle(.roundedBorder)
      if !error.isEmpty { Text(error).foregroundStyle(Color.coral).accessibilityLabel(error) }
      HStack {
        Button(AppLanguage.text("Cancel")) { dismiss() }.buttonStyle(SecondaryButtonStyle())
        Spacer()
        Button("Save price") { save() }.buttonStyle(PrimaryButtonStyle())
          .disabled(reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
      }
    }.padding(24)
    #if os(macOS)
      .frame(width: 480)
    #endif
  }

  private func save() {
    let clean = amount.trimmingCharacters(in: .whitespacesAndNewlines)
    guard clean.range(of: "^[0-9]+([.][0-9]{1,2})?$", options: .regularExpression) != nil,
      let value = Decimal(string: clean, locale: Locale(identifier: "en_US_POSIX")),
      value > 0, value <= 1_000_000 else {
      error = "Enter a positive price with up to two decimal places, like 12.99."
      return
    }
    do {
      try store.updateShoppingPrice(entry.id, priceCents: NSDecimalNumber(decimal: value * 100).intValue, reason: reason)
      dismiss()
    } catch { self.error = error.localizedDescription }
  }
}

private struct ShoppingDeclineSheet: View {
  @EnvironmentObject private var store: AppStore
  @Environment(\.dismiss) private var dismiss
  let entry: ShoppingEntry
  @State private var reason = ""

  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      Text(AppLanguage.text("Not this time")).font(.title2.weight(.black)).fontDesign(.rounded)
      Text("Give a kind, specific reason for \(entry.product.title).")
        .foregroundStyle(.secondary)
      TextField("For example: Let’s save a little more first.", text: $reason, axis: .vertical)
        .textFieldStyle(.roundedBorder).lineLimit(3...5)
      HStack {
        Button(AppLanguage.text("Cancel")) { dismiss() }.buttonStyle(SecondaryButtonStyle())
        Spacer()
        Button("Send decision") {
          do {
            try store.declineShoppingItem(entry.id, reason: reason)
            dismiss()
          } catch { store.show(error: error) }
        }.buttonStyle(PrimaryButtonStyle()).disabled(reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
      }
    }.padding(24)
    #if os(macOS)
      .frame(minWidth: 420)
    #endif
  }
}
