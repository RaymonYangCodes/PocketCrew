import SwiftUI

extension Color {
  init(hex: String) {
    let clean = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
    var value: UInt64 = 0
    Scanner(string: clean).scanHexInt64(&value)
    let r: Double
    let g: Double
    let b: Double
    if clean.count == 6 {
      r = Double((value >> 16) & 0xFF) / 255
      g = Double((value >> 8) & 0xFF) / 255
      b = Double(value & 0xFF) / 255
    } else {
      r = 0
      g = 0
      b = 0
    }
    self.init(red: r, green: g, blue: b)
  }
  static let oat = Color(hex: "F7F3EA")
  static let ink = Color(hex: "17251F")
  static let evergreen = Color(hex: "1F6A4A")
  static let sunny = Color(hex: "F6C453")
  static let coral = Color(hex: "EF7C6A")
  static let sky = Color(hex: "86BBD8")
}

struct PocketPanel<Content: View>: View {
  let padding: CGFloat
  @ViewBuilder let content: Content
  init(padding: CGFloat = 20, @ViewBuilder content: () -> Content) {
    self.padding = padding
    self.content = content()
  }
  var body: some View {
    content.padding(padding).background(
      .white.opacity(0.96), in: RoundedRectangle(cornerRadius: 22, style: .continuous)
    )
    .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(.black.opacity(0.055)))
    .shadow(color: .black.opacity(0.025), radius: 6, y: 2)
  }
}

struct AvatarView: View {
  let child: ChildProfile
  var size: CGFloat = 42
  var body: some View {
    ZStack {
      Circle().fill(Color(hex: child.avatarHex))
      Image(systemName: child.avatarSymbol).font(.system(size: size * 0.4, weight: .bold))
        .foregroundStyle(Color.ink)
    }
    .frame(width: size, height: size).overlay(Circle().stroke(.white, lineWidth: 3)).shadow(
      color: .black.opacity(0.08), radius: 5, y: 2
    )
    .accessibilityLabel("\(child.name)’s avatar")
  }
}

/// Shared editor used during onboarding and whenever a guardian adds or edits a child.
/// Keeping it shared ensures macOS and iOS expose the same independent profile settings.
struct ChildSettingsEditor: View {
  @Binding var child: ChildSetupDraft
  let title: String
  var showsPasscode = true
  var canRemove = false
  var onRemove: (() -> Void)?

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      HStack {
        HStack(spacing: 10) {
          avatarPreview
          Text(AppLanguage.text(title)).font(.headline.weight(.black))
        }
        Spacer()
        if canRemove {
          Button(role: .destructive) { onRemove?() } label: {
            Label("Remove", systemImage: "trash")
          }.buttonStyle(.borderless).accessibilityLabel("Remove \(title)")
        }
      }
      TextField("Child’s name", text: $child.name).textFieldStyle(.roundedBorder)
      Picker("Age range", selection: $child.ageRange) {
        ForEach(["6–8", "9–12", "13–15", "16–18"], id: \.self) { Text($0) }
      }
      if showsPasscode { passcodeField }
      VStack(alignment: .leading, spacing: 8) {
        Text("Avatar").font(.caption.weight(.bold)).foregroundStyle(.secondary)
        ScrollView(.horizontal, showsIndicators: false) {
          HStack(spacing: 9) {
            ForEach(ChildSetupDraft.avatarSymbols, id: \.self) { symbol in
              Button {
                child.avatarSymbol = symbol
              } label: {
                Image(systemName: symbol).font(.body.weight(.bold)).foregroundStyle(Color.ink)
                  .frame(width: 38, height: 38).background(
                    Color(hex: child.avatarHex).opacity(0.65), in: Circle()
                  ).overlay(
                    Circle().stroke(
                      child.avatarSymbol == symbol ? Color.evergreen : Color.clear, lineWidth: 3)
                  )
              }.buttonStyle(.plain).accessibilityLabel("Use \(symbol) avatar")
                .accessibilityAddTraits(child.avatarSymbol == symbol ? .isSelected : [])
            }
          }
        }
        HStack(spacing: 10) {
          ForEach(ChildSetupDraft.avatarColors, id: \.self) { hex in
            Button {
              child.avatarHex = hex
            } label: {
              Circle().fill(Color(hex: hex)).frame(width: 30, height: 30).overlay(
                Circle().stroke(child.avatarHex == hex ? Color.ink : .clear, lineWidth: 3)
              )
            }.buttonStyle(.plain).accessibilityLabel("Avatar color \(hex)")
              .accessibilityAddTraits(child.avatarHex == hex ? .isSelected : [])
          }
        }
      }
      Divider()
      Text("Payday jar split").font(.subheadline.weight(.black))
      splitRow("Spend", value: $child.spendPercent, color: .coral)
      splitRow("Save", value: $child.savePercent, color: .evergreen)
      splitRow("Give", value: $child.givePercent, color: .sky)
      HStack {
        Text("Total").fontWeight(.bold)
        Spacer()
        Text("\(child.splitTotal)%").font(.headline.monospacedDigit()).foregroundStyle(
          child.splitTotal == 100 ? Color.evergreen : Color.coral)
      }
      if child.splitTotal != 100 {
        Label("Spend + Save + Give must equal 100%.", systemImage: "exclamationmark.circle.fill")
          .font(.caption).foregroundStyle(Color.coral)
      }
    }.padding(18).background(.white, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
      .overlay(RoundedRectangle(cornerRadius: 18).stroke(.black.opacity(0.07)))
  }

  private var avatarPreview: some View {
    ZStack {
      Circle().fill(Color(hex: child.avatarHex))
      Image(systemName: child.avatarSymbol).font(.body.weight(.black)).foregroundStyle(Color.ink)
    }.frame(width: 42, height: 42)
  }

  @ViewBuilder private var passcodeField: some View {
    #if os(iOS)
      SecureField("Unique four-digit profile passcode", text: $child.passcode)
        .keyboardType(.numberPad).textContentType(.password).textFieldStyle(.roundedBorder)
        .onChange(of: child.passcode) { _, value in
          child.passcode = String(value.filter(\.isNumber).prefix(4))
        }
    #else
      SecureField("Unique four-digit profile passcode", text: $child.passcode)
        .textFieldStyle(.roundedBorder).onChange(of: child.passcode) { _, value in
          child.passcode = String(value.filter(\.isNumber).prefix(4))
        }
    #endif
  }

  private func splitRow(_ label: String, value: Binding<Int>, color: Color) -> some View {
    HStack(spacing: 10) {
      Circle().fill(color).frame(width: 9, height: 9)
      Text(label).frame(width: 52, alignment: .leading)
      Slider(
        value: Binding(
          get: { Double(value.wrappedValue) },
          set: { value.wrappedValue = Int($0.rounded()) }), in: 0...100, step: 5)
      TextField("Percent", value: value, format: .number)
        .textFieldStyle(.roundedBorder).multilineTextAlignment(.trailing).frame(width: 58)
      Text("%").foregroundStyle(.secondary)
    }
  }
}

struct WorkPresetLibrary: View {
  @EnvironmentObject private var store: AppStore
  let choose: (WorkPreset) -> Void
  let done: () -> Void
  @State private var selectedType: WorkType?
  @State private var presetQuery = ""

  private var presets: [WorkPreset] {
    WorkPreset.library.filter {
      (selectedType == nil || $0.type == selectedType)
        && (presetQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
          || "\($0.title) \($0.instructions) \($0.category)".localizedCaseInsensitiveContains(presetQuery))
    }
  }

  var body: some View {
    PocketPanel {
      VStack(alignment: .leading, spacing: 18) {
        HStack(alignment: .top, spacing: 12) {
          VStack(alignment: .leading, spacing: 4) {
            Label("Start with a preset", systemImage: "wand.and.stars")
              .font(.title2.weight(.black)).foregroundStyle(Color.ink).walkthroughTarget("task-presets")
            Text(
              "Choose one to fill the regular work form. You can change the name, reward, schedule, assignee, and every other detail before adding it."
            ).font(.subheadline).foregroundStyle(.secondary).fixedSize(
              horizontal: false, vertical: true)
          }
          Spacer(minLength: 0)
        }
        HStack(spacing: 8) {
          presetFilter("All", type: nil)
          presetFilter("Paid gigs", type: .gig)
          presetFilter("Responsibilities", type: .responsibility)
        }
        TextField("Search presets", text: $presetQuery).textFieldStyle(.roundedBorder)
          .accessibilityLabel("Search gig and responsibility presets")
        if presets.isEmpty {
          Text("No preset matches. Try another word or choose All.").foregroundStyle(.secondary)
          Button("Clear search") { presetQuery = ""; selectedType = nil }
        }
        ForEach(["Household", "Academic", "Outdoors", "Exercise", "Creative", "Pet care"], id: \.self) { category in
          let group = presets.filter { $0.presetCategory == category }
          if !group.isEmpty {
            Text(category).font(.title3.bold()).accessibilityAddTraits(.isHeader)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 210), spacing: 12)], spacing: 12) {
          ForEach(group) { preset in
            Button { choose(preset) } label: {
              VStack(alignment: .leading, spacing: 10) {
                HStack {
                  Image(systemName: preset.symbol).font(.title3.weight(.bold)).foregroundStyle(
                    preset.type == .gig ? Color.evergreen : Color.ink.opacity(0.7))
                  Spacer()
                  TypeBadge(type: preset.type)
                }
                Text(preset.title).font(.headline.weight(.black)).foregroundStyle(Color.ink)
                  .multilineTextAlignment(.leading)
                Text(preset.instructions).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                  .multilineTextAlignment(.leading)
                HStack {
                  Label("~\(preset.estimatedMinutes)m", systemImage: "clock")
                  Spacer()
                  if preset.type == .gig {
                    Text(
                      preset.rewardCents.currency(
                        code: store.state.family.currency, locale: store.state.family.locale)
                    ).font(.headline.weight(.black)).foregroundStyle(Color.evergreen)
                  } else {
                    Text("Unpaid").font(.caption.weight(.bold)).foregroundStyle(.secondary)
                  }
                }.font(.caption).foregroundStyle(.secondary)
              }.padding(15).frame(maxWidth: .infinity, minHeight: 150, alignment: .topLeading)
                .background(Color.oat.opacity(0.72), in: RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(.black.opacity(0.07)))
            }.buttonStyle(.plain).accessibilityHint("Opens an editable, prefilled work form")
          }
        }
          }
        }
        Divider()
        HStack {
          Text("You can reopen these presets anytime from Tasks.").font(.caption).foregroundStyle(
            .secondary)
          Spacer()
          Button("Done!") { done() }.buttonStyle(PrimaryButtonStyle())
        }
      }
    }
  }

  private func presetFilter(_ label: String, type: WorkType?) -> some View {
    Button(label) { selectedType = type }.buttonStyle(.plain).font(.caption.weight(.bold))
      .padding(.horizontal, 12).frame(minHeight: 34).foregroundStyle(
        selectedType == type ? Color.white : Color.ink.opacity(0.7)
      ).background(selectedType == type ? Color.evergreen : Color.oat, in: Capsule())
      .overlay(Capsule().stroke(Color.ink.opacity(selectedType == type ? 0 : 0.08)))
  }
}

struct StatusBadge: View {
  let status: WorkStatus
  private var tint: Color {
    switch status {
    case .approved, .paid: .evergreen
    case .redoRequested, .rejected: .coral
    case .awaitingApproval: .sky
    case .available: .sunny
    default: .ink.opacity(0.65)
    }
  }
  var body: some View {
    Text(status.title).font(.caption.weight(.bold)).padding(.horizontal, 10).padding(.vertical, 5)
      .foregroundStyle(tint == .sunny ? Color.ink : tint).background(
        tint.opacity(status == .available ? 0.55 : 0.13), in: Capsule()
      ).accessibilityLabel("Status: \(status.title)")
  }
}

struct TypeBadge: View {
  let type: WorkType
  var body: some View {
    Label(type.title, systemImage: type == .gig ? "sparkles" : "house.fill").font(
      .caption2.weight(.bold)
    ).textCase(.uppercase).tracking(0.5).foregroundStyle(
      type == .gig ? Color.evergreen : Color.ink.opacity(0.6))
  }
}

struct JarIcon: View {
  let kind: JarKind
  var size: CGFloat = 44
  var tint: Color {
    switch kind {
    case .spend: .coral
    case .save: .evergreen
    case .give: .sky
    }
  }
  var body: some View {
    Image(systemName: kind.icon).font(.system(size: size * 0.4, weight: .bold)).foregroundStyle(
      tint
    ).frame(width: size, height: size).background(
      tint.opacity(0.12), in: RoundedRectangle(cornerRadius: size * 0.32, style: .continuous))
  }
}

struct PrimaryButtonStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    configuration.label.font(.body.weight(.bold)).foregroundStyle(.white).padding(.horizontal, 18)
      .frame(minHeight: 44).background(
        Color.evergreen.opacity(configuration.isPressed ? 0.82 : 1),
        in: RoundedRectangle(cornerRadius: 12, style: .continuous)
      ).scaleEffect(configuration.isPressed ? 0.98 : 1)
  }
}
struct SecondaryButtonStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    configuration.label.font(.body.weight(.bold)).foregroundStyle(Color.evergreen).padding(
      .horizontal, 16
    ).frame(minHeight: 42).background(
      .white.opacity(configuration.isPressed ? 0.65 : 0.95),
      in: RoundedRectangle(cornerRadius: 12, style: .continuous)
    ).overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.evergreen.opacity(0.18)))
  }
}

struct PageHeader: View {
  let eyebrow: String
  let title: String
  let subtitle: String
  var body: some View {
    VStack(alignment: .leading, spacing: 5) {
      Text(AppLanguage.text(title)).font(.system(size: 28, weight: .bold, design: .rounded)).foregroundStyle(
        Color.ink)
      Text(subtitle).foregroundStyle(Color.ink.opacity(0.6))
    }.accessibilityElement(children: .combine)
  }
}

struct EmptyState: View {
  let icon: String
  let title: String
  let message: String
  var body: some View {
    VStack(spacing: 12) {
      Image(systemName: icon).font(.system(size: 30, weight: .bold)).foregroundStyle(
        Color.evergreen
      ).frame(width: 62, height: 62).background(
        Color.evergreen.opacity(0.1), in: RoundedRectangle(cornerRadius: 19))
      Text(AppLanguage.text(title)).font(.title3.weight(.bold))
      Text(message).foregroundStyle(Color.ink.opacity(0.6)).multilineTextAlignment(.center).frame(
        maxWidth: 340)
    }.frame(maxWidth: .infinity, minHeight: 210)
  }
}

struct ToastOverlay: View {
  let message: ToastMessage
  var body: some View {
    Label(
      message.text,
      systemImage: message.isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill"
    ).font(.body.weight(.bold)).foregroundStyle(.white).padding(.horizontal, 18).frame(
      minHeight: 48
    ).background(message.isError ? Color(hex: "9C3F35") : Color.evergreen, in: Capsule()).shadow(
      radius: 16, y: 5
    ).padding(24).transition(.move(edge: .bottom).combined(with: .opacity))
  }
}

struct SectionHeading: View {
  let title: String
  var action: (() -> Void)?
  var actionTitle = "See all"
  var body: some View {
    HStack {
      Text(AppLanguage.text(title)).font(.title2.weight(.black)).fontDesign(.rounded)
      Spacer()
      if let action {
        Button(actionTitle, action: action).buttonStyle(.plain).font(.body.weight(.bold))
          .foregroundStyle(Color.evergreen)
      }
    }.walkthroughTarget("heading-" + title)
  }
}

struct FlowLayout: Layout {
  var spacing: CGFloat = 8
  func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
    let width = proposal.width ?? 500
    var x: CGFloat = 0
    var y: CGFloat = 0
    var line: CGFloat = 0
    for view in subviews {
      let size = view.sizeThatFits(.unspecified)
      if x + size.width > width, x > 0 {
        x = 0
        y += line + spacing
        line = 0
      }
      x += size.width + spacing
      line = max(line, size.height)
    }
    return CGSize(width: width, height: y + line)
  }
  func placeSubviews(
    in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()
  ) {
    var x = bounds.minX
    var y = bounds.minY
    var line: CGFloat = 0
    for view in subviews {
      let size = view.sizeThatFits(.unspecified)
      if x + size.width > bounds.maxX, x > bounds.minX {
        x = bounds.minX
        y += line + spacing
        line = 0
      }
      view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
      x += size.width + spacing
      line = max(line, size.height)
    }
  }
}
