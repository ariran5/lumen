import SwiftUI

public struct BrowserView: View {
    @State private var tabs = TabsStore.shared
    @State private var isAddressFocused: Bool = false
    @State private var isStartSheetPresented: Bool = false

    // Interactive swipe-from-edge state. Палец двигает текущий контент вправо,
    // на release: если за порогом — анимируем дальше и `goBack()`; иначе
    // spring обратно на 0.
    @State private var swipeOffset: CGFloat = 0
    @State private var isSwiping: Bool = false

    public init() {}

    /// Compact mode для chrome. Все случаи кроме home — bar схлопывается
    /// в маленький disc 46pt с favicon/lock-glyph'ом. Tap → разворачивается
    /// в полный вид с pre-selected URL'ом. Применимо к fast-app'ам И web —
    /// контент важнее URL bar'а, контрол всегда на экране для возврата.
    private var isCompactChrome: Bool {
        guard !isAddressFocused else { return false }
        guard let tab = tabs.activeTab else { return false }
        return tab.currentURL != TabModel.homeURL
    }

    private var canSwipeBack: Bool {
        guard let tab = tabs.activeTab else { return false }
        // Outer edge-swipe работает только если в табе есть URL-стек куда
        // возвращаться (несколько fast-app'ов или web-страниц подряд).
        // Иначе жест передаётся внутреннему UINavigationController'у
        // fast-app'а, чтобы тот поппил свою страницу — без этого на root
        // fast-app экране свайп уходил в `goHome()` и убивал таб.
        return !tab.urlStack.isEmpty
    }

    public var body: some View {
        // Outer-swipe gesture крепим только когда есть куда back'ать (urlStack
        // не пустой). На root tab fast-app'а его НЕТ — иначе SwiftUI
        // DragGesture перехватывает touch'и в полосе x < 30pt даже с
        // `.including: .subviews`, и tap'ы по элементам у левого края
        // (например первая иконка bottom tab-bar'а) не доходят до них.
        if canSwipeBack {
            mainContent.gesture(swipeBackGesture)
        } else {
            mainContent
        }
    }

    private var mainContent: some View {
        ZStack {
            // ─── content (с offset'ом от interactive swipe) ───
            ZStack {
                ForEach(tabs.tabs) { tab in
                    TabContent(tab: tab)
                        .opacity(tab.id == tabs.activeID ? 1 : 0)
                        .allowsHitTesting(tab.id == tabs.activeID)
                        .id(tab.id)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .offset(x: swipeOffset)
            .shadow(color: .black.opacity(isSwiping ? 0.35 : 0),
                    radius: 14, x: -6, y: 0)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            chromeOverlay
        }
        .background(DarkPalette.bg0.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .sheet(isPresented: $isStartSheetPresented) {
            StartSheet(tabs: tabs, isPresented: $isStartSheetPresented)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .presentationBackgroundInteraction(.disabled)
        }
    }

    @ViewBuilder
    private var chromeOverlay: some View {
        if let active = tabs.activeTab, active.chromeMode != .hidden {
            VStack(spacing: 8) {
                if isAddressFocused {
                    AddressSuggestions(query: active.addressInput) { url in
                        active.addressInput = url
                        active.commit()
                        isAddressFocused = false
                    }
                }
                // ProgressOverlay (loading indicator) только в full режиме
                if !isCompactChrome {
                    ProgressOverlay(visible: active.isLoading)
                }
                AddressBar(tab: active,
                           isFocused: $isAddressFocused,
                           onOpenLibrary: openLibrary,
                           onTapCompactPill: { isStartSheetPresented = true },
                           isCompact: isCompactChrome)
                    .onAppear(perform: applyLaunchURLIfPresent)
                    .frame(maxWidth: isCompactChrome ? 46 : .infinity, alignment: .center)
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 12)
            .padding(.top, 4)
            .animation(.spring(response: 0.32, dampingFraction: 0.86), value: isCompactChrome)
            .animation(.spring(response: 0.32, dampingFraction: 0.86), value: isAddressFocused)
        }
    }

    /// Interactive swipe-from-edge: tracking palm-driven offset в реальном
    /// времени. На release решаем: pop или snap-back.
    /// Пороги хардкод (220pt / 180pt predicted) — нормально для любого
    /// iPhone, не нужно знать точную ширину экрана.
    private var swipeBackGesture: some Gesture {
        DragGesture(minimumDistance: 6, coordinateSpace: .global)
            .onChanged { v in
                guard canSwipeBack,
                      v.startLocation.x < 30,
                      v.translation.width >= 0 else { return }
                isSwiping = true
                swipeOffset = v.translation.width
            }
            .onEnded { v in
                guard isSwiping else { return }
                let predicted = v.predictedEndTranslation.width
                let shouldPop = v.translation.width > 220 || predicted > 180

                if shouldPop {
                    withAnimation(.easeOut(duration: 0.22)) {
                        swipeOffset = 800   // off-screen для любого iPhone
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
                        tabs.activeTab?.goBack()
                        swipeOffset = 0
                        isSwiping = false
                    }
                } else {
                    withAnimation(.spring(response: 0.30, dampingFraction: 0.85)) {
                        swipeOffset = 0
                    }
                    isSwiping = false
                }
            }
    }

    private func openLibrary() {
        tabs.open(url: "lumen://library")
    }

    private func applyLaunchURLIfPresent() {
        guard let tab = tabs.activeTab,
              tab.currentURL == TabModel.homeURL,
              let raw = UserDefaults.standard.string(forKey: "url") else { return }
        tab.addressInput = raw
        tab.commit()
    }
}

private struct TabContent: View {
    @Bindable var tab: TabModel

    var body: some View {
        // Без SwiftUI .transition — на тяжёлых UIViewRepresentable (FastAppHost
        // с UINavigationController внутри, WKWebView) встроенные транзишны
        // дёргают frame во время mount'а и выглядят jerky. Outer-level
        // interactive swipe в BrowserView сам управляет offset'ом.
        Group {
            switch tab.mode {
            case .start:
                StartPage(tab: tab)
            case .web:
                WebTabView(tab: tab)
                    .ignoresSafeArea()
            case .fastApp(let url):
                FastAppHost(tab: tab, url: url)
                    .id(url.absoluteString)
                    .ignoresSafeArea()
            }
        }
    }
}

private struct ProgressOverlay: View {
    let visible: Bool
    @State private var phase: CGFloat = 0

    var body: some View {
        GeometryReader { geo in
            Rectangle()
                .fill(.tint)
                .frame(width: geo.size.width * 0.35, height: 2)
                .offset(x: geo.size.width * phase - geo.size.width * 0.35)
                .opacity(visible ? 1 : 0)
                .onChange(of: visible) { _, new in
                    if new {
                        withAnimation(.linear(duration: 1.0).repeatForever(autoreverses: false)) {
                            phase = 1.2
                        }
                    } else {
                        withAnimation(.linear(duration: 0.2)) { phase = 0 }
                    }
                }
        }
        .frame(height: 2)
    }
}

private struct StartPage: View {
    @Bindable var tab: TabModel

    private let exampleApps: [(label: String, url: String)] = [
        ("Tabs Lab — multi-tab API",   "http://192.168.0.107:8080"),
        ("HN reader — real-world demo", "http://192.168.0.107:8081"),
        ("Drag Lab — gestures + spring", "http://192.168.0.107:8082"),
        ("Glass Lab — iOS 26 Liquid Glass", "http://192.168.0.107:8083"),
        ("Scroll Lab — scroll + safe-area", "http://192.168.0.107:8084"),
        ("Input Lab — TextInput",       "http://192.168.0.107:8085"),
        ("Sheet Lab — bottomSheet",     "http://192.168.0.107:8086"),
        ("Bank Lab — full app demo",    "http://192.168.0.107:8087"),
        ("Map Lab — native MKMapView",  "http://192.168.0.107:8088"),
        ("Platform Lab — Tier 1 device APIs", "http://192.168.0.107:8089"),
        ("History — built-in fast-app", "lumen://history"),
        ("Hacker News (web fallback)",  "https://news.ycombinator.com"),
    ]

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Image(systemName: "globe.americas.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(.tint)
                    .padding(.top, 40)
                Text("Lumen")
                    .font(.largeTitle.weight(.bold))
                Text("Type a URL above to open a site. If it ships a Lumen manifest, it opens as a fast-app.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Examples")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 4)

                    ForEach(exampleApps, id: \.label) { item in
                        Button {
                            tab.addressInput = item.url
                            tab.commit()
                        } label: {
                            HStack {
                                Image(systemName: "bolt.fill")
                                    .foregroundStyle(.tint)
                                Text(item.label)
                                    .foregroundStyle(.primary)
                                Spacer()
                                Text(item.url)
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 12)
                            .background(Color(uiColor: .secondarySystemBackground),
                                        in: RoundedRectangle(cornerRadius: 10))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
            }
            .frame(maxWidth: .infinity)
            .padding(.bottom, 40)
        }
    }
}
