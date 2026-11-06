import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var app
    @Environment(TimelineStore.self) private var timeline
    @Namespace private var zoom
    @Environment(\.scenePhase) private var phase

    var body: some View {
        @Bindable var app = app
        ZStack(alignment: .bottom) {
            Color.black.ignoresSafeArea()
            Group {
                switch app.tab {
                case .library: LibraryView()
                case .collections: CollectionsView()
                }
            }
            .environment(\.zoomNamespace, zoom)
            if app.tab == .library { BottomBlur() }
            Group {
                if app.selecting { SelectionBar() } else { BottomBar() }
            }
            .padding(.horizontal, 22)
            .padding(.bottom, 4)
        }
        .overlay(alignment: .top) { VStack { BusyBadge(); ToastBadge() } }
        .actionSheets($app.sheet)
        .task {
            if timeline.buckets.isEmpty { await timeline.showCached() }
            var reloaded = false
            if let me = try? await ImmichClient.shared.me() {
                app.userID = me.id; app.userName = me.name; reloaded = await timeline.setUser(me.id)
            }
            if !reloaded { await timeline.reload() }
            BackupEngine.shared.runIfDue()
            WidgetFeeder.syncAccess()
            OfflineSync.shared.timeline = timeline
            // Widgets füllen, wenn die Zeitleiste steht (leise im Hintergrund)
            Task { try? await Task.sleep(for: .seconds(12)); await WidgetFeeder.update(timeline: timeline) }
            OfflineSync.shared.kick()
            #if DEBUG
            if ProcessInfo.processInfo.environment["FOTOS_BACKUP_NOW"] != nil { BackupEngine.shared.start() }
            #endif
        }
        .onChange(of: app.tab) { app.endSelection(); app.tabsExpanded = false }
        .onChange(of: perfScreen, initial: true) { _, s in PerfLog.setScreen(s) }
        .onChange(of: phase) { _, p in
            // erst nachladen, wenn das Konto feststeht (beim Start erledigt das .task)
            if p == .active, !app.userID.isEmpty { BackupEngine.shared.runIfDue(); Task { await timeline.reload(); OfflineSync.shared.kick() } }
            // wie Fotos: geschützte Alben sperren sich wieder, sobald die App in den Hintergrund geht
            guard p == .background else { return }
            BackupEngine.shared.schedule()
            OfflineSync.shared.stop()
            Task { await MemoryNotifications.schedule(timeline: timeline); await WidgetFeeder.update(timeline: timeline) }
            app.privateUnlocked = false
            if app.viewer?.assets.contains(where: { $0.isHidden || $0.trashedAt != nil }) == true { app.viewer = nil }
        }
        .onChange(of: app.tabsExpanded) { _, open in
            // wie bei Apple klappt die Leiste nach kurzer Zeit wieder zu
            guard open else { return }
            Task { try? await Task.sleep(for: .seconds(6)); withAnimation(.snappy) { app.tabsExpanded = false } }
        }
        .fullScreenCover(item: $app.viewer) { req in
            ViewerView(assets: req.assets, start: req.index)
                .navigationTransition(.zoom(sourceID: app.zoomID, in: zoom))
        }
        .fullScreenCover(isPresented: $app.showSearch) { SearchView() }
        // Tippen aufs Widget: homeroll://memory/<id> bzw. homeroll://asset/<id>
        .onOpenURL { url in
            guard url.scheme == "homeroll", let id = url.pathComponents.dropFirst().first else { return }
            app.viewer = nil; app.showSearch = false
            if url.host == "memory", let m = MemoryCenter.shared.items.first(where: { $0.id == id }) { app.memory = m }
            else if url.host == "asset" {
                // wie Apple: Foto direkt öffnen (mit den Nachbarn aus der Mediathek zum Weiterwischen)
                Task {
                    await timeline.loadAll()
                    // war schon ein Foto offen: erst schließen lassen, sonst bleibt die alte Einzelansicht stehen
                    try? await Task.sleep(for: .milliseconds(450))
                    let all = timeline.allLoaded
                    if let i = all.firstIndex(where: { $0.id == id }) { app.open(all, at: i) }
                    else if let dto = try? await ImmichClient.shared.asset(id) { app.open([dto.asset], at: 0) }
                }
            }
        }
        .fullScreenCover(item: $app.memory) { MemoryPlayer(memory: $0) }
    }
}

extension RootView {
    /// Für das Leistungsprotokoll: wo man gerade ist.
    private var perfScreen: String {
        if app.viewer != nil { return "Einzelansicht" }
        if app.showSearch { return "Suche" }
        if app.memory != nil { return "Rückblick" }
        if app.tab == .collections { return "Sammlungen" }
        return app.scale == .all ? "Mediathek \(app.columns) Spalten" : "Mediathek \(app.scale.rawValue)"
    }
}

/// Schwebende Glasleiste unten – in der Mediathek mit Jahre/Monate/Alle, sonst Tabs.
struct BottomBar: View {
    @Environment(AppModel.self) private var app
    @Namespace private var ns

    var body: some View {
        GlassEffectContainer(spacing: 14) {
            HStack(spacing: 12) {
                if app.tab == .library && !app.tabsExpanded {
                    Button { withAnimation(.snappy) { app.tabsExpanded = true } } label: {
                        Image(systemName: "photo.on.rectangle.angled")
                            .font(.system(size: 22, weight: .medium))
                            .symbolRenderingMode(.multicolor)
                            .foregroundStyle(.blue)
                            .frame(width: 58, height: 58)
                    }
                    .glassEffect(.regular.interactive(), in: .circle)
                    .glassEffectID("tab", in: ns)

                    ScaleSwitcher()
                        .glassEffect(.regular.interactive(), in: .capsule)
                } else {
                    TabSwitcher()
                        .glassEffect(.regular.interactive(), in: .capsule)
                        .glassEffectID("tab", in: ns)
                    Spacer(minLength: 0)
                }
                Button { app.showSearch = true } label: {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 22, weight: .medium))
                        .foregroundStyle(.white)
                        .frame(width: 58, height: 58)
                }
                .glassEffect(.regular.interactive(), in: .circle)
            }
        }
    }
}

private struct ScaleSwitcher: View {
    @Environment(AppModel.self) private var app
    @Namespace private var sel
    var body: some View {
        HStack(spacing: 0) {
            ForEach(LibraryScale.allCases) { s in
                Button {
                    // wie Apple: „Alle“ erneut antippen springt zum Neuesten ganz unten
                    if s == .all && app.scale == .all { NotificationCenter.default.post(name: .scrollToNewest, object: nil) }
                    withAnimation(.snappy(duration: 0.25)) { app.scale = s }
                } label: {
                    Text(L(s.rawValue))
                        .font(.system(size: 17, weight: app.scale == s ? .semibold : .regular))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 50)
                        .background {
                            if app.scale == s {
                                Capsule().fill(.white.opacity(0.16))
                                    .matchedGeometryEffect(id: "sel", in: sel)
                                    .padding(4)
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 4)
        .frame(height: 58)
    }
}

private struct TabSwitcher: View {
    @Environment(AppModel.self) private var app
    @Namespace private var sel
    var body: some View {
        HStack(spacing: 0) {
            item(.library, "photo.on.rectangle.angled", String(localized: "Mediathek"))
            item(.collections, "square.stack.fill", String(localized: "Sammlungen"))
        }
        .padding(4)
    }

    private func item(_ t: Tab, _ icon: String, _ title: String) -> some View {
        let on = app.tab == t
        return Button { withAnimation(.snappy) { app.tab = t; app.tabsExpanded = false } } label: {
            VStack(spacing: 3) {
                Image(systemName: icon).font(.system(size: 21, weight: .medium))
                Text(title).font(.system(size: 11, weight: .medium))
            }
            .foregroundStyle(on ? Color.blue : .white)
            .frame(width: 100, height: 54)
            .background {
                if on { Capsule().fill(.white.opacity(0.14)).matchedGeometryEffect(id: "tabsel", in: sel) }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Kleine Glas-Kapsel oben, solange etwas vorbereitet wird (Teilen, Sichern …).
struct BusyBadge: View {
    @Environment(AppModel.self) private var app
    var body: some View {
        if let text = app.busy {
            HStack(spacing: 10) {
                ProgressView().tint(.white)
                Text(text).font(.system(size: 15, weight: .semibold)).foregroundStyle(.white)
            }
            .padding(.horizontal, 18).frame(height: 44)
            .glassEffect(.regular.tint(.black.opacity(0.45)), in: .capsule)   // auf hellen Fotos lesbar
            .padding(.top, 8)
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }
}


extension Notification.Name {
    static let scrollToNewest = Notification.Name("scrollToNewest")
}
