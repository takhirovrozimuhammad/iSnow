import AppKit
import ServiceManagement
import SwiftUI

private typealias R = SimConfig.Ranges
private enum WinterStyle {
    static let ink = Color(red: 0.055, green: 0.068, blue: 0.13)
    static let panel = Color(red: 0.085, green: 0.10, blue: 0.18)
    static let accent = Color(red: 0.64, green: 0.65, blue: 1)
    static let ice = Color(red: 0.68, green: 0.82, blue: 1)
}

struct SettingsView: View {
    @Bindable var settings: Settings
    let delegate: AppDelegate
    @State private var tab: Int
    private let activates: Bool
    private let titles = ["Qor yog‘ishi", "Qor qatlamlari", "Qor ustaxonasi", "Bayram kayfiyati", "Ish va quvvat"]
    private let icons = ["cloud.snow", "mountain.2", "hand.draw", "sparkles", "moon.stars"]
    private let descriptions = ["Derazangiz ortidagi qish — endi butun ekraningizda.",
        "Qor har bir deraza va Dock ustida o‘z joyini topsin.",
        "Qorni o‘z qo‘lingiz bilan yig‘ing. O‘z qor odamingizni yasang.",
        "Chiroqlar, archa va biroz bayram sehridan qo‘shing.",
        "Ish paytida sokinroq, batareyada yengilroq."]

    init(settings: Settings, delegate: AppDelegate, tab: Int = 0, activates: Bool = true) {
        self.settings = settings
        self.delegate = delegate
        _tab = State(initialValue: min(max(tab, 0), 4))
        self.activates = activates
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            VStack(spacing: 0) {
                header
                selectedTab
                    .scrollContentBackground(.hidden)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .id(tab)
                footer
            }
            .background(WinterStyle.ink)
        }
        .frame(minWidth: 860, minHeight: 660)
        .tint(WinterStyle.accent)
        .preferredColorScheme(.dark)
        .onAppear {
            settings.refreshLoginStatus()
            guard activates else { return }
            NSApp.activate()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            settings.refreshLoginStatus()
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image(nsImage: ISnowBrand.image(size: 52)).resizable().frame(width: 48, height: 48)
                VStack(alignment: .leading, spacing: 3) {
                    Text("iSnow").font(.system(size: 25, weight: .semibold, design: .rounded))
                    Text("WINTER STUDIO").font(.system(size: 8, weight: .bold)).tracking(2.2)
                        .foregroundStyle(WinterStyle.ice.opacity(0.65))
                }
            }
            .padding(.top, 28).padding(.bottom, 32)
            ForEach(0..<5, id: \.self) { index in
                Button {
                    withAnimation(.easeOut(duration: 0.16)) { tab = index }
                } label: {
                    HStack(spacing: 11) {
                        Image(systemName: icons[index]).font(.system(size: 16)).frame(width: 21)
                        Text(titles[index]).font(.system(size: 12, weight: tab == index ? .semibold : .medium))
                        Spacer(minLength: 0)
                        if tab == index { Circle().fill(WinterStyle.accent).frame(width: 5, height: 5) }
                    }
                    .foregroundStyle(tab == index ? Color.white : Color.white.opacity(0.57))
                    .padding(.horizontal, 12).padding(.vertical, 14)
                    .background(tab == index ? WinterStyle.accent.opacity(0.14) : .clear,
                                in: RoundedRectangle(cornerRadius: 12))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain).padding(.bottom, 5)
            }
            Spacer(minLength: 20)
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("⌥").font(.system(size: 20, weight: .medium, design: .rounded))
                        .frame(width: 36, height: 32)
                        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                    Text("Qish qo‘lingizda").font(.system(size: 11, weight: .semibold))
                }
                Text("Option’ni bosib qorni yurgizing. Uchta sharni ustma-ust qo‘ying.")
                    .font(.system(size: 11)).foregroundStyle(.white.opacity(0.48)).lineSpacing(3)
            }
            .padding(14).background(.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 14))
            Text("Ridzhan edition  /  2.0").font(.system(size: 10, weight: .medium))
                .foregroundStyle(.white.opacity(0.3)).padding(.top, 20).padding(.bottom, 22)
        }
        .padding(.horizontal, 16)
        .frame(width: 190)
        .background(WinterStyle.panel)
        .overlay(alignment: .trailing) { Rectangle().fill(.white.opacity(0.05)).frame(width: 1) }
    }

    private var header: some View {
        ZStack(alignment: .leading) {
            WinterLandscape(paused: settings.paused)
            VStack(alignment: .leading, spacing: 10) {
                Text("SHOSHILMANG. QISHNI HIS QILING.")
                    .font(.system(size: 9, weight: .bold)).tracking(2).foregroundStyle(WinterStyle.ice)
                Text(titles[tab]).font(.system(size: 30, weight: .medium, design: .rounded))
                Text(descriptions[tab]).font(.system(size: 12)).foregroundStyle(.white.opacity(0.62))
                    .frame(maxWidth: 420, alignment: .leading)
                HStack(spacing: 7) {
                    Circle().fill(settings.paused ? .gray : WinterStyle.ice).frame(width: 5, height: 5)
                    Text(settings.paused ? "Qor to‘xtatilgan" : "Qor yog‘moqda")
                    Text("·").foregroundStyle(.white.opacity(0.25))
                    Text(Temp.format(settings.config.temperature, fahrenheit: settings.config.fahrenheit))
                }
                .font(.system(size: 10, weight: .medium)).foregroundStyle(.white.opacity(0.55))
            }.padding(28)
        }
        .frame(height: 185).clipped()
        .overlay(alignment: .bottom) { Rectangle().fill(.white.opacity(0.07)).frame(height: 1) }
    }

    @ViewBuilder private var selectedTab: some View {
        switch tab {
        case 0: SnowTab(settings: settings)
        case 1: DriftTab(settings: settings, delegate: delegate)
        case 2: SnowmanTab(settings: settings, delegate: delegate)
        case 3: ChristmasTab(settings: settings, delegate: delegate)
        default: ExtrasTab(settings: settings, delegate: delegate)
        }
    }

    private var footer: some View {
        HStack(spacing: 16) {
            Toggle("Qor", isOn: Binding(get: { !settings.paused }, set: { settings.paused = !$0 }))
                .toggleStyle(.switch).fixedSize()
            Divider().frame(height: 20)
            Toggle("Ish rejimi", isOn: $settings.config.workMode).toggleStyle(.switch).fixedSize()
            Spacer()
            Button("Litsenziyalar") { delegate.showLicenses() }
                .buttonStyle(.plain).font(.system(size: 10)).foregroundStyle(.white.opacity(0.4))
        }
        .font(.system(size: 11, weight: .medium))
        .padding(.horizontal, 24).padding(.vertical, 16)
        .background(.white.opacity(0.025))
        .overlay(alignment: .top) { Rectangle().fill(.white.opacity(0.06)).frame(height: 1) }
    }
}

private struct WinterLandscape: View {
    let paused: Bool
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 24, paused: paused)) { timeline in
            Canvas { context, size in
                let time = paused ? 0 : timeline.date.timeIntervalSinceReferenceDate
                let sky = Path(CGRect(origin: .zero, size: size))
                context.fill(sky, with: .linearGradient(Gradient(colors: [
                    Color(red: 0.13, green: 0.15, blue: 0.31), WinterStyle.ink]),
                    startPoint: .zero, endPoint: CGPoint(x: size.width, y: size.height)))
                for layer in 0..<3 {
                    var ridge = Path()
                    let base = size.height * (0.68 + Double(layer) * 0.09)
                    ridge.move(to: CGPoint(x: 0, y: size.height))
                    ridge.addLine(to: CGPoint(x: 0, y: base))
                    ridge.addCurve(to: CGPoint(x: size.width, y: base - 12),
                        control1: CGPoint(x: size.width * 0.35, y: base - 44),
                        control2: CGPoint(x: size.width * 0.7, y: base + 42))
                    ridge.addLine(to: CGPoint(x: size.width, y: size.height)); ridge.closeSubpath()
                    context.fill(ridge, with: .color(WinterStyle.ice.opacity(0.025 + Double(layer) * 0.012)))
                }
                for i in 0..<45 {
                    let x = (Double(i * 137 % 977) / 977 * size.width + sin(time * 0.12 + Double(i)) * 8)
                    let y = (Double(i * 71 % 181) + time.truncatingRemainder(dividingBy: 1000) * (4 + Double(i % 4)))
                        .truncatingRemainder(dividingBy: size.height)
                    let r = Double(i % 3 + 1) * 0.65
                    context.fill(Path(ellipseIn: CGRect(x: x, y: y, width: r, height: r)),
                                 with: .color(.white.opacity(x < size.width * 0.65 ? 0.10 : 0.42)))
                }
            }
        }
        .accessibilityHidden(true)
    }
}

private struct WorkshopRecipe: View {
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            recipe("01", "Yig‘ing", "Option’ni bosib qor ustida yurgizing.", "hand.draw")
            recipe("02", "Dumaloqlang", "Ko‘proq qor — kattaroq shar. Option’ni qo‘yib yuboring.", "circle.dotted")
            recipe("03", "Ustma-ust", "Uchta sharni surib tering — qor odam tayyor!", "figure.wave")
        }
    }
    private func recipe(_ n: String, _ title: String, _ text: String, _ symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text(n).font(.system(size: 10, weight: .semibold, design: .monospaced)).foregroundStyle(WinterStyle.accent)
                Spacer()
                Image(systemName: symbol).foregroundStyle(WinterStyle.ice).font(.system(size: 18))
            }
            Text(title).font(.system(size: 12, weight: .semibold))
            Text(text).font(.system(size: 11)).foregroundStyle(.secondary).lineSpacing(2).fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .padding(14).background(WinterStyle.accent.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
    }
}

/// Slider with a label and a value readout.
private struct ValueSlider: View {
    let title: LocalizedStringKey
    @Binding var value: Double
    let range: ClosedRange<Double>
    var step: Double? = nil
    var format: (Double) -> String

    var body: some View {
        LabeledContent {
            HStack {
                if let step {
                    Slider(value: $value, in: range, step: step)
                } else {
                    Slider(value: $value, in: range)
                }
                Text(format(value))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(width: 80, alignment: .trailing)
            }
        } label: {
            Text(title)
        }
    }
}

/// "1.5×" / "1,5×" – the decimal separator follows the locale.
private func times(_ v: Double) -> String { v.formatted(.number.precision(.fractionLength(1))) + "×" }
private func points(_ v: Double) -> String { String(localized: "\(Int(v.rounded())) pt") }
private func count(_ v: Double) -> String { Int(v.rounded()).formatted() }

private struct SnowTab: View {
    @Bindable var settings: Settings

    var body: some View {
        Form {
            Section {
                Picker("Kayfiyat", selection: Binding<Intensity?>(
                    get: { settings.config.preset },
                    set: { if let p = $0 { settings.config.apply(p) } })) {
                    ForEach(Intensity.allCases) { Text($0.title).tag(Optional($0)) }
                    if settings.config.preset == nil { Text("O‘zim sozlayman").tag(Intensity?.none) }
                }
                .pickerStyle(.segmented)
                ValueSlider(title: "Qor zichligi", value: $settings.config.density, range: R.density, format: times)
                ValueSlider(title: "Eng ko‘p qor zarralari", value: $settings.config.maxFlakes, range: R.maxFlakes, step: 50, format: count)
                if settings.config.maxFlakes > 2500 {
                    Text("Ko‘p qor ko‘proq quvvat talab qiladi. Ish rejimi yukni kamaytiradi.")
                        .font(.callout).foregroundStyle(.secondary)
                }
            }
            Section("Harorat") {
                ValueSlider(title: "Harorat", value: temperatureBinding, range: temperatureRange, step: 1) {
                    Temp.format(fahrenheit ? Temp.toCelsius($0) : $0, fahrenheit: fahrenheit)
                }
                Text(temperatureHint)
                    .font(.callout).foregroundStyle(.secondary)
            }
            Section("Qor zarralari") {
                ValueSlider(title: "O‘lcham", value: $settings.config.flakeSize, range: R.flakeSize, format: times)
                ValueSlider(title: "Yog‘ish tezligi", value: $settings.config.fallSpeed, range: R.fallSpeed, format: times)
                ValueSlider(title: "Shamol", value: $settings.config.wind, range: R.wind) {
                    $0 < 0.05 ? String(localized: "calm") : times($0)
                }
                Toggle("Yaltiraydigan qor", isOn: $settings.config.sparkle)
                Toggle("Faol oynada qor yengillashsin", isOn: $settings.config.calmActive)
                Text("Ishlayotgan oynangiz ustida qor kamroq ko‘rinadi.")
                    .font(.callout).foregroundStyle(.secondary)
                HStack {
                    ColorPicker("Qor rangi", selection: tintBinding, supportsOpacity: false)
                    Button("Oq") { settings.config.tint = [1, 1, 1] }
                        .disabled(settings.config.tint == [1, 1, 1])
                }
            }
        }
        .formStyle(.grouped)
    }

    private var fahrenheit: Bool { settings.config.fahrenheit }

    /// The slider works in °C or °F; the config always stores °C (same physical range).
    private var temperatureRange: ClosedRange<Double> {
        let r = R.temperature
        return fahrenheit ? Temp.toFahrenheit(r.lowerBound)...Temp.toFahrenheit(r.upperBound) : r
    }

    private var temperatureBinding: Binding<Double> {
        Binding(
            get: {
                let c = settings.config.temperature
                return fahrenheit ? Temp.toFahrenheit(c).rounded() : c
            },
            set: { v in
                let c = fahrenheit ? Temp.toCelsius(v) : v
                settings.config.temperature = min(max(c, R.temperature.lowerBound), R.temperature.upperBound)
            })
    }

    private var temperatureHint: String {
        let t = settings.config.temperature
        if t > 4 { return String(localized: "Ho‘l qor: hech narsa to‘planmaydi, qor va sumalaklar tez eriydi.") }
        if t > 0 { return String(localized: "Iliq: qor va sumalaklar eriydi, qor odamlar kichrayadi.") }
        if t > -8 { return String(localized: "Sovuq: qor erimaydi, sumalak va qirov paydo bo‘ladi.") }
        return String(localized: "Qattiq sovuq: sumalaklar tez o‘sadi, oynalar chetidan muzlaydi.")
    }

    private var tintBinding: Binding<Color> {
        Binding(
            get: {
                let t = settings.config.tint
                return Color(red: t[safe: 0] ?? 1, green: t[safe: 1] ?? 1, blue: t[safe: 2] ?? 1)
            },
            set: { c in
                guard let n = NSColor(c).usingColorSpace(.sRGB) else { return }
                settings.config.tint = [Double(n.redComponent), Double(n.greenComponent), Double(n.blueComponent)]
            })
    }
}

private struct DriftTab: View {
    @Bindable var settings: Settings
    let delegate: AppDelegate

    var body: some View {
        Form {
            Section("Qor qayerga to‘plansin") {
                Toggle("Oynalarga", isOn: $settings.config.onWindows)
                Toggle("Dock ustiga", isOn: $settings.config.onDock)
                Toggle("Ish stoli ikonlariga", isOn: $settings.config.onIcons)
                Toggle("Vidjetlarga", isOn: $settings.config.onWidgets)
                if !settings.config.onWidgets {
                    Text("Qor vidjetlarda to‘planmaydi.")
                        .font(.callout).foregroundStyle(.secondary)
                }
                Toggle("Menyu paneliga", isOn: $settings.config.onMenuBar)
                if !settings.axTrusted {
                    HStack {
                        Text("Dock va ikonlarni aniq joylash uchun Accessibility ruxsati kerak.")
                            .font(.callout).foregroundStyle(.secondary)
                        Spacer()
                        Button("Ruxsat berish…") { Tracker.requestAccessibility() }
                    }
                }
            }
            Section("Qor qatlamlari") {
                Toggle("Cheklanmasin — qor to‘planishda davom etsin", isOn: $settings.config.unlimitedDrifts)
                ValueSlider(title: "Oynalardagi qor balandligi", value: $settings.config.windowDepth, range: R.windowDepth, format: points)
                    .disabled(settings.config.unlimitedDrifts)
                ValueSlider(title: "Pastdagi qor balandligi", value: $settings.config.groundDepth, range: R.groundDepth, format: points)
                    .disabled(settings.config.unlimitedDrifts)
                ValueSlider(title: "To‘planish tezligi", value: $settings.config.accumulation, range: R.accumulation, format: times)
                HStack {
                    Spacer()
                    Button("Qorlarni silkitib tushirish") { delegate.shakeAll() }
                }
            }
            Section("Ayoz") {
                Toggle("Sovuqda oynalarni qirov qoplasin", isOn: $settings.config.windowFrost)
                Toggle("Oyna va menyu ostida sumalaklar", isOn: $settings.config.icicles)
                ValueSlider(title: "Sumalak uzunligi", value: $settings.config.icicleLength, range: R.icicleLength, format: times)
                    .disabled(!settings.config.icicles)
                Text("Qor yog‘ishi bo‘limidagi harorat erish va qirovga ta’sir qiladi.")
                    .font(.callout).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

private struct SnowmanTab: View {
    @Bindable var settings: Settings
    let delegate: AppDelegate

    var body: some View {
        Form {
            Section("O‘z qo‘lingiz bilan yasang") {
                Toggle("Option bilan qor yig‘ish", isOn: $settings.config.craftSnow)
                WorkshopRecipe().padding(.vertical, 6)
                HStack(spacing: 12) {
                    Button("Yangi qor to‘kish") { delegate.prepareSnowWorkshop() }
                        .buttonStyle(.borderedProminent)
                    Button("Yasaganlarimni tozalash") { delegate.clearSnowWorkshop() }
                }
                Text("Sharlarni oddiy sichqoncha bilan suring. Moviy halqa ustiga qo‘yib yuborsangiz yopishadi. Option + Shift — qorni kurak bilan tozalash.")
                    .font(.callout).foregroundStyle(.secondary)
                if settings.config.temperature > 0 {
                    Text("Hozir qor eriydi. Qor yasash uchun haroratni 0°C yoki undan pastga tushiring.")
                        .font(.callout).foregroundStyle(WinterStyle.ice)
                }
            }
            Section {
                Toggle("Dock’da avtomatik qor odamlar", isOn: $settings.config.snowman)
                ValueSlider(title: "Qor odamlar soni", value: $settings.config.snowmanCount, range: R.snowmanCount, step: 1,
                            format: count)
                ValueSlider(title: "O‘lcham", value: $settings.config.snowmanSize, range: R.snowmanSize, format: times)
                ValueSlider(title: "Qor odamlar orasidagi tanaffus", value: $settings.config.snowmanBreak, range: R.snowmanBreak) {
                    $0 < 1 ? String(localized: "\(Int($0 * 60)) s") : String(localized: "\(Int($0.rounded())) min")
                }
                Toggle("Oynani yopsa shaffoflashsin", isOn: $settings.config.snowmanGhost)
                HStack {
                    Spacer()
                    Button("Dock’ka qaytarish") { delegate.resetSnowmen() }
                    Button("Hozir yasash") { delegate.buildSnowmanNow() }
                }
                Text("Qor odamni sichqoncha bilan istalgan joyga suring. U turgan oyna siljisa, pastga tushadi.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            .disabled(!settings.config.snowman)
            Section("Qorbo‘ron") {
                Toggle("Qor odam oynalarga qor otsin", isOn: $settings.config.snowballs)
                ValueSlider(title: "Qor otish oralig‘i", value: $settings.config.throwEvery, range: R.throwEvery) {
                    String(localized: "\(Int($0)) s")
                }
                .disabled(!settings.config.snowballs)
                Text("Qor odamni bosing — har uchinchi zarbada bitta shar tushadi. Ba’zida o‘zi ham qor otadi.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            .disabled(!settings.config.snowman)
            Section("Chang‘ichilar") {
                Toggle("Ba’zan chang‘ichilar o‘tib tursin", isOn: $settings.config.skier)
                ValueSlider(title: "Kelish oralig‘i", value: $settings.config.skierInterval, range: R.skierEvery, step: 0.5) {
                    $0 < 1 ? String(localized: "\(Int(($0 * 60).rounded())) s")
                           : ($0.truncatingRemainder(dividingBy: 1) == 0 ? String(localized: "\(Int($0)) min")
                                                                          : $0.formatted(.number.precision(.fractionLength(1))) + " min")
                }
                .disabled(!settings.config.skier)
                ValueSlider(title: "Chang‘ichilar soni", value: $settings.config.skierCount, range: 1...5, step: 1) {
                    "\(Int($0))"
                }
                .disabled(!settings.config.skier)
                HStack {
                    Spacer()
                    Button("Hozir yuborish") { delegate.sendSkier() }
                }
                Text("Chang‘ichilar ekran pastidan kelib, Dock ustiga chiqishadi va narigi tomondan sakrab tushishadi.")
                    .font(.callout).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

private struct ChristmasTab: View {
    @Bindable var settings: Settings
    let delegate: AppDelegate

    var body: some View {
        Form {
            Section {
                Toggle("Bayram rejimi", isOn: $settings.config.christmas)
            }
            Section("Bezaklar") {
                Toggle("Dock yonida archa", isOn: $settings.config.christmasTree)
                ValueSlider(title: "Archa o‘lchami", value: $settings.config.treeSize, range: R.treeSize, format: times)
                    .disabled(!settings.config.christmasTree)
                Toggle("Menyu ostida chiroqlar", isOn: $settings.config.christmasGarland)
                Toggle("Qor odamlarga bayram qalpog‘i", isOn: $settings.config.christmasHats)
                Picker("Chiroqlar", selection: $settings.config.lightStyle) {
                    Text("Rangli, miltillaydigan").tag(Christmas.LightStyle.colorful.rawValue)
                    Text("Iliq oq").tag(Christmas.LightStyle.warmWhite.rawValue)
                    Text("Ketma-ket yonadigan").tag(Christmas.LightStyle.chase.rawValue)
                }
                ValueSlider(title: "Chiroq o‘lchami", value: $settings.config.lightSize, range: 0.5...2.5, format: times)
                ValueSlider(title: "Yorqinlik", value: $settings.config.lightGlow, range: 0...2.5) {
                    $0 < 0.02 ? String(localized: "no glow") : times($0)
                }
                Toggle("Qor to‘xtasa ham chiroqlar yonsin", isOn: $settings.config.lightsWhilePaused)
                Text("Biroz qo‘shimcha quvvat sarflaydi.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            .disabled(!settings.config.christmas)
            Section("Qorbobo") {
                Toggle("Ba’zan Qorbobo uchib o‘tsin", isOn: $settings.config.santa)
                HStack {
                    Spacer()
                    Button("Qorboboni chaqirish") { delegate.launchSanta() }
                }
            }
            .disabled(!settings.config.christmas)
        }
        .formStyle(.grouped)
    }
}

private struct ExtrasTab: View {
    @Bindable var settings: Settings
    let delegate: AppDelegate

    var body: some View {
        Form {
            Section("Qo‘shimchalar") {
                Toggle("Kursor qorni sochsin va tez harakatda silkitib tushirsin", isOn: $settings.config.mouse)
                Text("Option — qor yig‘ish. Option + Shift — kurak. Sharlar va qor odamlarni oddiy sichqoncha bilan suring.")
                    .font(.callout).foregroundStyle(.secondary)
                Toggle("Qor tozalagich avtomatik ishlasin", isOn: $settings.config.snowplow)
                Text("Pastda qor qalinlashganda tozalagich ekran va Dock bo‘ylab yuradi.")
                    .font(.callout).foregroundStyle(.secondary)
                ValueSlider(title: "Qor shuncha to‘planganda kelsin", value: $settings.config.autoPlowHeight, range: 10...150, step: 5) {
                    String(localized: "\(Int($0)) pt")
                }
                .disabled(!settings.config.snowplow)
                HStack {
                    Spacer()
                    Button("Tozalagichni chaqirish") { delegate.sendPlow() }
                        .disabled(!settings.config.snowplow)
                }
                Toggle("Ekran chetlarida qirov", isOn: $settings.config.frost)
                ValueSlider(title: "Fullscreen’da qor ko‘rinishi", value: $settings.config.fullscreenSnow, range: 0...1, step: 0.05) {
                    $0 < 0.02 ? String(localized: "none") : ($0.formatted(.percent.precision(.fractionLength(0))))
                }
                Text("Fullscreen’da faqat yengil qor va yuqoridagi sumalaklar qoladi. Qolgan bezaklar yashirinadi, qaytganda tiklanadi.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            Section("Tezlik va sifat") {
                Picker("Kadrlar tezligi", selection: $settings.config.fps) {
                    Text("30 fps — tejamkor").tag(30)
                    Text("60 fps").tag(60)
                    Text("120 fps — ProMotion").tag(120)
                }
                Toggle("Sokin qor 30 fps’da ishlasin", isOn: $settings.config.calmLowerRate)
                Text("Quvvat tejash rejimida ko‘pi bilan 30 fps ishlaydi. Harakat yo‘q bo‘lsa chizish to‘xtaydi.")
                    .font(.callout).foregroundStyle(.secondary)
                Toggle("Retina sifati — ko‘proq quvvat sarflaydi", isOn: $settings.config.retina)
            }
            Section("Batareya") {
                Toggle("Batareyada quvvatni tejash", isOn: $settings.config.batterySaver)
                Text("Batareyada: 30 fps, oddiy sifat, kamroq qor va yaltirashsiz.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            Section("Umumiy") {
                Toggle("Mac yoqilganda ishga tushsin", isOn: Binding(get: { settings.launchAtLogin },
                                                       set: { settings.setLaunchAtLogin($0) }))
                if settings.loginStatus == .requiresApproval || settings.loginError != nil {
                    HStack {
                        Group {
                            if let error = settings.loginError {
                                Text(error)
                            } else {
                                Text("System Settings → General → Login Items’da iSnow’ga ruxsat bering.")
                            }
                        }
                        .font(.callout).foregroundStyle(.secondary)
                        Spacer()
                        Button("Kirish sozlamalarini ochish") { SMAppService.openSystemSettingsLoginItems() }
                    }
                }
                Toggle("Farengeyt o‘lchovi", isOn: $settings.config.fahrenheit)
                Toggle("Skrinshot va ekran ulashishda qorni yashirish", isOn: $settings.config.hideFromCapture)
                HStack {
                    Spacer()
                    Button("Boshlang‘ich holatga qaytarish") { settings.resetToDefaults() }
                }
            }
        }
        .formStyle(.grouped)
    }
}
