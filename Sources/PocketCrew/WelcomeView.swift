import SwiftUI

struct WelcomeView: View {
  @EnvironmentObject private var store: AppStore
  @EnvironmentObject private var cloud: CloudSessionStore
  @Binding var didEnter: Bool
  @State private var authMode: CloudAuthMode?

  var body: some View {
    ZStack {
      Color.oat.ignoresSafeArea()
      Circle().fill(Color.sunny.opacity(0.16)).frame(width: 420).blur(radius: 2).offset(
        x: 430, y: -300)
      Circle().fill(Color.sky.opacity(0.10)).frame(width: 360).offset(x: -430, y: 320)
      HStack(spacing: 54) {
        VStack(spacing: 24) {
          logo
          VStack(spacing: 14) {
            Text("Welcome to PocketCrew").font(
              .system(size: 38, weight: .black, design: .rounded)
            ).tracking(-1.8).foregroundStyle(Color.ink).fixedSize(horizontal: false, vertical: true)
            Text(
              "Family tasks, pocket money, and savings goals."
            ).font(.title3).foregroundStyle(Color.ink.opacity(0.66)).lineSpacing(4).frame(
              maxWidth: 520, alignment: .center)
          }
          VStack(spacing: 12) {
            Button { authMode = .signIn } label: {
              Text(AppLanguage.text("Sign in")).frame(maxWidth: .infinity)
            }.buttonStyle(PrimaryButtonStyle())
            Button { authMode = .signUp } label: {
              Text(AppLanguage.text("Create a family")).frame(maxWidth: .infinity)
            }.buttonStyle(SecondaryButtonStyle())
          }
          .frame(maxWidth: 320)
          if let notice = cloud.notice {
            Text(notice).font(.caption).foregroundStyle(Color.coral).frame(
              maxWidth: 470, alignment: .leading)
          }
          Text(
            "A learning ledger, not a bank. No real money is held or moved."
          ).font(.caption).foregroundStyle(Color.ink.opacity(0.48)).frame(
            maxWidth: 470, alignment: .leading)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: 540)
      }.padding(60)
    }
    .sheet(item: $authMode) { mode in
      CloudAuthView(initialMode: mode).environmentObject(cloud)
    }
  }

  private var logo: some View {
    HStack(spacing: 11) {
      ZStack {
        RoundedRectangle(cornerRadius: 14).fill(Color.evergreen)
        Text("PC").font(.headline.weight(.black)).foregroundStyle(.white)
      }.frame(width: 44, height: 44)
      VStack(alignment: .leading, spacing: 0) {
        Text("PocketCrew").font(.title2.weight(.black)).fontDesign(.rounded)
        Text("Earn it. Split it. Grow it.").font(.caption.weight(.bold)).foregroundStyle(
          Color.evergreen)
      }
    }
  }
  private var preview: some View {
    PocketPanel(padding: 22) {
      VStack(alignment: .leading, spacing: 20) {
        HStack {
          VStack(alignment: .leading, spacing: 4) {
            Text("FRIDAY PAYDAY").font(.caption.weight(.black)).tracking(1.2).foregroundStyle(
              Color.evergreen)
            Text("$24.00 ready").font(.title.weight(.black)).fontDesign(.rounded)
          }
          Spacer()
          Image(systemName: "sparkles").font(.title).foregroundStyle(Color.sunny)
        }
        Divider()
        ForEach(
          [(JarKind.spend, "$12.00", "50%"), (.save, "$9.60", "40%"), (.give, "$2.40", "10%")],
          id: \.0
        ) { jar, amount, percent in
          HStack(spacing: 12) {
            JarIcon(kind: jar)
            VStack(alignment: .leading) {
              Text(jar.title).fontWeight(.bold)
              Text(percent).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text(amount).font(.title3.weight(.black)).monospacedDigit()
          }
        }
        Text("Work approved ✓  →  Payday  →  Jars").font(.caption.weight(.bold)).foregroundStyle(
          Color.ink.opacity(0.55)
        ).padding(.top, 4)
      }.frame(width: 340)
    }.rotationEffect(.degrees(1.2)).shadow(color: Color.evergreen.opacity(0.13), radius: 40, y: 20)
  }
}

struct OnboardingView: View {
  @EnvironmentObject private var store: AppStore
  @Environment(\.dismiss) private var dismiss
  @Binding var didEnter: Bool
  @State private var step = 0
  @State private var familyName = "Our Family"
  @State private var parentName = ""
  @State private var children = [ChildSetupDraft.blank()]
  @State private var frequency: PaydayFrequency = .weekly
  @State private var currency = "USD"
  @State private var parentPasscode = ""
  @State private var error = ""
  let steps = ["Family", "Children", "How it works"]

  var body: some View {
    VStack(spacing: 0) {
      HStack {
        ForEach(steps.indices, id: \.self) { index in
          HStack(spacing: 8) {
            ZStack {
              Circle().fill(index <= step ? Color.evergreen : Color.ink.opacity(0.1))
              Text("\(index + 1)").font(.caption.weight(.black)).foregroundStyle(
                index <= step ? .white : Color.ink.opacity(0.5))
            }.frame(width: 28, height: 28)
            Text(steps[index]).font(.caption.weight(.bold)).foregroundStyle(
              index <= step ? Color.ink : Color.ink.opacity(0.4))
            if index < 2 {
              Rectangle().fill(index < step ? Color.evergreen : Color.ink.opacity(0.1)).frame(
                height: 2)
            }
          }
        }
      }.padding(28)
      Divider()
      Group {
        if step == 0 { familyStep } else if step == 1 { childStep } else { previewStep }
      }.padding(34).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
      Divider()
      HStack {
        if step > 0 { Button(AppLanguage.text("Back")) { step -= 1 }.buttonStyle(SecondaryButtonStyle()) }
        Spacer()
        Button(step == 2 ? "Open PocketCrew" : "Continue") {
          if step < 2 { step += 1 } else { finish() }
        }.buttonStyle(PrimaryButtonStyle()).disabled(
          (step == 0
            && (familyName.isEmpty || parentName.isEmpty || !parentPasscode.isFourDigitPasscode))
            || (step == 1 && !childrenAreValid)
        )
      }.padding(24)
    }.frame(width: 720, height: 720).background(Color.oat)
  }
  private var familyStep: some View {
    VStack(alignment: .leading, spacing: 18) {
      Text("Let’s name your crew").font(.largeTitle.weight(.black)).fontDesign(.rounded)
      Text("You can fine-tune locale, timezone, and payday later in Settings.").foregroundStyle(
        .secondary)
      Form {
        TextField(AppLanguage.text("Family name"), text: $familyName)
        TextField("Your display name", text: $parentName)
        SecureField("Choose a 4-digit parent passcode", text: $parentPasscode)
          .onChange(of: parentPasscode) { _, value in
            parentPasscode = String(value.filter(\.isNumber).prefix(4))
          }
        Picker("Payday", selection: $frequency) {
          ForEach(PaydayFrequency.allCases.filter { $0 != .custom }) { Text($0.title).tag($0) }
        }
        LabeledContent("Timezone", value: TimeZone.current.identifier)
        Picker("Currency", selection: $currency) {
          ForEach(["USD", "CAD", "GBP", "EUR"], id: \.self) { Text($0).tag($0) }
        }
      }.formStyle(.grouped)
    }
  }
  private var childStep: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 18) {
        HStack(alignment: .top) {
          VStack(alignment: .leading, spacing: 4) {
            Text("Add your children").font(.largeTitle.weight(.black)).fontDesign(.rounded)
            Text("Each child gets separate settings and a private passcode.")
              .foregroundStyle(.secondary)
          }
          Spacer()
          Button {
            children.append(.blank(position: children.count))
          } label: {
            Label(AppLanguage.text("Add Child"), systemImage: "person.badge.plus")
          }.buttonStyle(SecondaryButtonStyle())
        }
        ForEach($children) { $child in
          ChildSettingsEditor(
            child: $child, title: childTitle(child), canRemove: children.count > 1,
            onRemove: { removeChild(child.id) })
        }
        if !passcodesAreUnique {
          Label("Every profile needs a different passcode.", systemImage: "lock.trianglebadge.exclamationmark")
            .foregroundStyle(Color.coral)
        }
        Button {
          children.append(.blank(position: children.count))
        } label: {
          Label(AppLanguage.text("Add Child"), systemImage: "person.badge.plus")
        }.buttonStyle(SecondaryButtonStyle())
      }
    }
  }
  private var previewStep: some View {
    VStack(alignment: .leading, spacing: 26) {
      Text("Small steps, real lessons").font(.largeTitle.weight(.black)).fontDesign(.rounded)
      HStack(spacing: 14) {
        loopCard("1", "Do the work", "Responsibilities build habits. Gigs earn money.", .sky)
        loopCard("2", "You review", "Approve, ask for a redo, or leave a kind note.", .sunny)
        loopCard(
          "3", "Fill the jars", "Payday splits approved earnings into Spend, Save, and Give.",
          .coral)
      }
      PocketPanel {
        Label(
          "Your new family starts with a clean ledger. Add the first responsibility or gig from Home.",
          systemImage: "hand.wave.fill"
        ).foregroundStyle(Color.ink).font(.body.weight(.semibold))
      }
      if !error.isEmpty {
        Label(error, systemImage: "exclamationmark.circle.fill").foregroundStyle(Color.coral)
      }
    }
  }
  private func loopCard(_ number: String, _ title: String, _ body: String, _ color: Color)
    -> some View
  {
    VStack(alignment: .leading, spacing: 10) {
      Text(number).font(.headline.weight(.black)).foregroundStyle(Color.ink).frame(
        width: 34, height: 34
      ).background(color, in: Circle())
      Text(title).font(.headline.weight(.bold))
      Text(body).font(.caption).foregroundStyle(.secondary).fixedSize(
        horizontal: false, vertical: true)
    }.padding(18).frame(maxWidth: .infinity, minHeight: 170, alignment: .topLeading).background(
      .white, in: RoundedRectangle(cornerRadius: 18))
  }
  private func finish() {
    do {
      try store.createFamily(
        familyName: familyName, parentName: parentName, children: children, currency: currency,
        frequency: frequency, parentPasscode: parentPasscode)
      didEnter = true
      dismiss()
    } catch { self.error = error.localizedDescription }
  }

  private var passcodesAreUnique: Bool {
    let values = [parentPasscode] + children.map(\.passcode)
    return Set(values.filter({ !$0.isEmpty })).count == values.filter({ !$0.isEmpty }).count
  }
  private var childrenAreValid: Bool {
    !children.isEmpty && children.allSatisfy(\.isComplete) && passcodesAreUnique
  }
  private func childTitle(_ child: ChildSetupDraft) -> String {
    let name = child.name.trimmingCharacters(in: .whitespacesAndNewlines)
    if !name.isEmpty { return name }
    return "Child \((children.firstIndex(where: { $0.id == child.id }) ?? 0) + 1)"
  }
  private func removeChild(_ id: UUID) {
    guard children.count > 1 else { return }
    children.removeAll(where: { $0.id == id })
  }
}
