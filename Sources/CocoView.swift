import AppKit
import ImageIO
import SwiftUI

enum CocoIcons {
    static let idle = frames(row: 0, count: 6)
    static let wave = frames(row: 3, count: 4)

    private static func frames(row: Int, count: Int) -> [CGImage] {
        guard let url = Bundle.main.url(forResource: "CocoSprite", withExtension: "png"),
              let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let sheet = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return [] }
        return (0..<count).compactMap { column in
            sheet.cropping(to: CGRect(x: column * 192 + 18, y: row * 208, width: 156, height: 208))
        }
    }
}

final class CocoWindow: ObservableObject {
    @Published private(set) var expanded = false
    var resize: ((Bool) -> Void)?
    var rememberPosition: (() -> Void)?

    func setExpanded(_ expanded: Bool) {
        guard self.expanded != expanded else { return }
        self.expanded = expanded
        resize?(expanded)
    }
}

private struct CatEar: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        var path = Path()
        path.move(to: CGPoint(x: 0.10 * w, y: 0.92 * h))
        path.addCurve(to: CGPoint(x: 0.13 * w, y: 0.21 * h), control1: CGPoint(x: -0.01 * w, y: 0.69 * h),
                      control2: CGPoint(x: 0.02 * w, y: 0.37 * h))
        path.addCurve(to: CGPoint(x: 0.40 * w, y: 0.16 * h), control1: CGPoint(x: 0.19 * w, y: 0.10 * h),
                      control2: CGPoint(x: 0.29 * w, y: 0.10 * h))
        path.addCurve(to: CGPoint(x: 0.94 * w, y: 0.83 * h), control1: CGPoint(x: 0.67 * w, y: 0.31 * h),
                      control2: CGPoint(x: 0.87 * w, y: 0.59 * h))
        path.addQuadCurve(to: CGPoint(x: 0.10 * w, y: 0.92 * h), control: CGPoint(x: 0.51 * w, y: 1.08 * h))
        path.closeSubpath()
        return path
    }
}

private struct CatTail: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        var path = Path()
        path.move(to: CGPoint(x: 0.08 * w, y: 0.86 * h))
        path.addCurve(to: CGPoint(x: 0.82 * w, y: 0.58 * h), control1: CGPoint(x: 0.47 * w, y: 1.02 * h),
                      control2: CGPoint(x: 0.86 * w, y: 0.93 * h))
        path.addCurve(to: CGPoint(x: 0.83 * w, y: 0.14 * h), control1: CGPoint(x: 0.79 * w, y: 0.41 * h),
                      control2: CGPoint(x: 0.74 * w, y: 0.32 * h))
        return path
    }
}

private struct CocoCatDetails: View {
    var size: CGFloat
    var idleFrame: Int
    var waving: Bool

    private let shellLight = Color(red: 0.71, green: 0.84, blue: 1)
    private let shellShadow = Color(red: 0.36, green: 0.49, blue: 0.77)
    private let insideLight = Color(red: 0.92, green: 0.86, blue: 0.99)
    private let insideShadow = Color(red: 0.62, green: 0.58, blue: 0.89)

    var body: some View {
        let lift = waving ? CGFloat([0, -1, -2, -1][idleFrame]) : CGFloat([0, -2, -1, 0, -1, -2][idleFrame])
        ZStack {
            ear.flipsForRightToLeftLayoutDirection(false)
                .offset(x: -size * 0.185, y: -size * 0.318 + lift * size / 122)
            ear.scaleEffect(x: -1, y: 1)
                .offset(x: size * 0.185, y: -size * 0.318 + lift * size / 122)
            ZStack {
                CatTail().stroke(shellShadow, style: StrokeStyle(lineWidth: size * 0.083, lineCap: .round))
                CatTail().stroke(LinearGradient(colors: [shellLight, insideShadow], startPoint: .topLeading, endPoint: .bottomTrailing),
                                 style: StrokeStyle(lineWidth: size * 0.062, lineCap: .round))
                CatTail().trim(from: 0.71).stroke(insideLight.opacity(0.88), style: StrokeStyle(lineWidth: size * 0.054, lineCap: .round))
            }
            .frame(width: size * 0.35, height: size * 0.34)
            .rotationEffect(.degrees(waving ? -8 : Double(lift) * 4 - 1), anchor: .bottomLeading)
            .offset(x: size * 0.29, y: size * 0.225)
        }
        .frame(width: size, height: size)
        .allowsHitTesting(false)
    }

    private var ear: some View {
        ZStack {
            CatEar().fill(LinearGradient(colors: [shellLight, shellShadow], startPoint: .topLeading, endPoint: .bottomTrailing))
            CatEar().stroke(shellShadow.opacity(0.40), lineWidth: size * 0.007)
            CatEar().fill(LinearGradient(colors: [insideLight, insideShadow], startPoint: .topLeading, endPoint: .bottomTrailing))
                .scaleEffect(0.67, anchor: .bottom)
                .offset(x: size * 0.006, y: -size * 0.016)
        }
        .frame(width: size * 0.220, height: size * 0.225)
    }
}

struct CocoAvatar: View {
    var size: CGFloat
    var tint: Color
    var waveStart: Date?

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.075)) { context in
            let passed = waveStart.map { context.date.timeIntervalSince($0) } ?? 3
            let waving = passed >= 0 && passed < 0.92
            let frames = waving ? CocoIcons.wave : CocoIcons.idle
            ZStack {
                Ellipse()
                    .fill(tint.opacity(0.18))
                    .frame(width: size * 0.66, height: size * 0.30)
                    .offset(y: size * 0.31)
                    .blur(radius: size * 0.045)
                if !frames.isEmpty {
                    let index = waving ? min(Int(passed / 0.23), frames.count - 1)
                        : Int(context.date.timeIntervalSinceReferenceDate / 0.25) % frames.count
                    CocoCatDetails(size: size, idleFrame: index, waving: waving)
                    Image(decorative: frames[index], scale: 1)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: size * 0.86, height: size * 0.98)
                } else {
                    Image(systemName: "desktopcomputer")
                        .font(.system(size: size * 0.53))
                        .foregroundStyle(tint)
                }
                if passed >= 0 && passed < 1.45 {
                    let progress = max(0, min(1, passed / 1.45))
                    Image(systemName: "heart.fill")
                        .font(.system(size: size * 0.26, weight: .heavy))
                        .foregroundStyle(Color(red: 1, green: 0.29, blue: 0.48).gradient)
                        .shadow(color: .pink.opacity(0.27), radius: 6, y: 2)
                        .scaleEffect(0.7 + progress * 0.48)
                        .opacity(min(1, progress * 9, (1 - progress) * 3.4))
                        .offset(x: size * (0.22 + progress * 0.15), y: size * (0.14 - progress * 0.58))
                }
            }
            .frame(width: size, height: size)
        }
        .accessibilityHidden(true)
    }
}

struct CocoView: View {
    @ObservedObject var model: CocoModel
    @ObservedObject var window: CocoWindow
    @Environment(\.colorScheme) private var scheme
    @State private var tab = Tab.today
    @State private var waveStart: Date?
    @State private var draft: CocoTask?
    @State private var showCompleted = false
    @State private var calendarDraft: Set<String> = []
    @State private var choosingCalendars = false
    @State private var calendarsSaved = false

    private enum Tab: String, CaseIterable {
        case today = "Today", tasks = "Tasks", meetings = "Meetings"
        var icon: String {
            switch self {
            case .today: return "sun.max"
            case .tasks: return "checkmark.circle"
            case .meetings: return "calendar"
            }
        }
    }

    @State private var showSettings = false

    var tint: Color {
        switch model.settings.tint {
        case "Lilac": return Color(red: 0.47, green: 0.34, blue: 0.86)
        case "Mint": return Color(red: 0.02, green: 0.50, blue: 0.43)
        default: return Color(red: 0.13, green: 0.44, blue: 0.82)
        }
    }

    var canvas: Color {
        scheme == .dark ? Color(red: 0.08, green: 0.12, blue: 0.18) : Color(red: 0.95, green: 0.97, blue: 1)
    }

    var card: Color { scheme == .dark ? .white.opacity(0.07) : .white }

    var body: some View {
        Group {
            if window.expanded { dashboard }
            else { compact }
        }
        .tint(tint)
        .environment(\.timeZone, CocoModel.clock.timeZone)
    }

    private var compact: some View {
        CocoAvatar(size: 100, tint: tint, waveStart: waveStart)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityHidden(true)
        .overlay {
            CocoDragSurface(label: "Open Coco", help: "Click to open Coco and send a heart. Drag to move Coco.",
                            onClick: { waveStart = Date(); window.setExpanded(true) }, onDrop: window.rememberPosition)
        }
    }

    private var dashboard: some View {
        VStack(spacing: 0) {
            header
            if choosingCalendars {
                CocoCalendarPicker(calendars: model.calendars, selection: $calendarDraft,
                                   onCancel: { choosingCalendars = false }, onSave: saveCalendars)
            } else {
                if draft == nil && !showSettings { tabs }
                ScrollView {
                    VStack(alignment: .leading, spacing: 13) {
                        if calendarsSaved {
                            Label("Calendars saved", systemImage: "checkmark.circle.fill")
                                .font(.callout).foregroundStyle(tint)
                        }
                        if let draft { taskEditor(draft) }
                        else if showSettings { settings }
                        else {
                            switch tab {
                            case .today: today
                            case .tasks: tasks
                            case .meetings: meetings
                            }
                        }
                        if let message = model.message {
                            Text(message)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 18)
                    .padding(.top, 13)
                    .padding(.bottom, 18)
                }
                .defaultScrollAnchor(.top)
            }
        }
        .background(canvas.gradient, in: RoundedRectangle(cornerRadius: 26))
        .overlay(RoundedRectangle(cornerRadius: 26).strokeBorder(.primary.opacity(0.09), lineWidth: 1).allowsHitTesting(false))
        .shadow(color: .black.opacity(0.25), radius: 15, y: 6)
        .padding(15)
    }

    private var header: some View {
        let isBack = choosingCalendars || showSettings
        return HStack(spacing: 10) {
            HStack(spacing: 10) {
                CocoAvatar(size: 64, tint: tint, waveStart: waveStart)
                Text(model.now.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()))
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
            }
            .overlay {
                CocoDragSurface(label: "Send a heart", help: "Click to send a heart. Drag to move Coco.",
                                onClick: { waveStart = Date() }, onDrop: window.rememberPosition)
            }
            Spacer(minLength: 8)
            iconButton(isBack ? "arrow.left" : "gearshape", label: isBack ? "Back" : "Settings") {
                calendarsSaved = false
                if choosingCalendars { choosingCalendars = false }
                else {
                    draft = nil
                    showSettings.toggle()
                }
            }
            iconButton("minus", label: "Collapse Coco") { window.setExpanded(false) }
        }
        .padding(.horizontal, 17)
        .padding(.top, 9)
        .padding(.bottom, 6)
    }

    private var tabs: some View {
        HStack(spacing: 4) {
            ForEach(Tab.allCases, id: \.self) { item in
                Button {
                    tab = item
                    calendarsSaved = false
                } label: {
                    Label(item.rawValue, systemImage: item.icon)
                        .font(.system(size: 12, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background(tab == item ? card : .clear, in: RoundedRectangle(cornerRadius: 11))
                        .contentShape(Rectangle())
                        .foregroundStyle(tab == item ? tint : .secondary)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(tab == item ? .isSelected : [])
            }
        }
        .padding(4)
        .background(tint.opacity(0.08), in: RoundedRectangle(cornerRadius: 15))
        .padding(.horizontal, 18)
    }

    private var today: some View {
        let next = model.meetings.first { $0.end > model.now }
        return Group {
            if let sample = model.activeTest {
                section(sample.title, icon: sample == .zoom ? "video" : "mappin.and.ellipse") {
                    if let fire = model.testTime {
                        Text(fire > model.now ? "Test reminder at \(CocoModel.time(fire))." : "Test reminder sent.")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                    if let room = sample.roomName {
                        Text(room).font(.callout)
                    } else {
                        Button("Join Zoom Test") { NSWorkspace.shared.open(CocoModel.zoomTestURL) }
                            .buttonStyle(.borderedProminent)
                    }
                }
            }
            section("Daily brief", icon: "sun.horizon") {
                Text(model.brief(on: model.now))
                    .font(.system(size: 13))
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let next {
                section("Next meeting", icon: "calendar") { meetingRow(next) }
            }
            calendarSetup
            section("Task deadlines", icon: "clock") {
                if model.openTasks.isEmpty {
                    Text("Add a task to track its deadline here.").foregroundStyle(.secondary).font(.callout)
                } else {
                    ForEach(Array(model.openTasks.prefix(3))) { task in taskRow(task) }
                }
                Button { beginTask() } label: { Label("Add task", systemImage: "plus") }
                    .buttonStyle(.borderless)
            }
            if model.notificationAccess == .notDetermined || model.notificationAccess == .denied {
                alertSetup
            }
        }
    }

    private var tasks: some View {
        Group {
            HStack {
                Text("Tasks").font(.title3.bold())
                Spacer()
                Button { beginTask() } label: { Label("Add task", systemImage: "plus") }.buttonStyle(.borderedProminent)
            }
            section("To do", icon: "checkmark.circle") {
                if model.openTasks.isEmpty { Text("No open tasks.").font(.callout).foregroundStyle(.secondary) }
                ForEach(model.openTasks) { task in taskRow(task) }
            }
            let completed = model.tasks.filter(\.completed).reversed()
            if !completed.isEmpty {
                section("Completed", icon: "checkmark.circle.fill") {
                    DisclosureGroup("\(completed.count) completed", isExpanded: $showCompleted) {
                        ForEach(Array(completed)) { task in taskRow(task) }
                    }
                }
            }
        }
    }

    private var meetings: some View {
        Group {
            HStack {
                Text("Meetings & classes").font(.title3.bold())
                Spacer()
                Button { model.refresh() } label: { Label("Refresh", systemImage: "arrow.clockwise") }.buttonStyle(.borderless)
            }
            calendarSetup
            if !model.selectedCalendars.isEmpty {
                let future = model.meetings.filter { $0.end > model.now }
                let days = Array(Set(future.map { CocoModel.clock.startOfDay(for: $0.start) })).sorted()
                if days.isEmpty {
                    section("Upcoming", icon: "calendar") { Text("No upcoming timed meetings this week.").font(.callout).foregroundStyle(.secondary) }
                }
                ForEach(days, id: \.self) { day in
                    section(day.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()), icon: "calendar") {
                        ForEach(future.filter { CocoModel.clock.isDate($0.start, inSameDayAs: day) }) { meeting in
                            meetingRow(meeting)
                        }
                    }
                }
            }
            if model.notificationAccess == .notDetermined || model.notificationAccess == .denied { alertSetup }
        }
    }

    private var calendarSetup: some View {
        section("Calendar", icon: "calendar.badge.plus") {
            if model.calendarAccess == .fullAccess {
                if model.calendars.isEmpty {
                    Text("Add your Google account with Calendars enabled in System Settings → Internet Accounts.")
                        .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                } else {
                    HStack {
                        Text("\(model.selectedCalendars.count) selected")
                            .font(.callout).foregroundStyle(.secondary)
                        Spacer()
                        Button("Choose Calendars…", action: chooseCalendars).buttonStyle(.bordered)
                    }
                }
            } else {
                Text("Connect calendars synced to this Mac for classes, meeting links, and locations.")
                    .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Button("Connect Calendar") { model.requestCalendar() }.buttonStyle(.borderedProminent)
            }
        }
    }

    private var alertSetup: some View {
        section("Notifications", icon: "bell") {
            Text("Get meeting alerts, task deadlines, and your daily brief on your Mac.")
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Button("Enable Notifications") { model.requestNotifications() }.buttonStyle(.bordered)
        }
    }

    private var settings: some View {
        Group {
            Text("Settings").font(.title3.bold())
            section("Appearance", icon: "paintpalette") {
                Picker("Accent color", selection: binding(\.tint)) {
                    ForEach(["Sky", "Lilac", "Mint"], id: \.self) { Text($0).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
            calendarSetup
            section("Reminders", icon: "bell") {
                Toggle("Meetings & classes · 10 min before and at start", isOn: binding(\.meetingAlerts))
                Toggle("Task deadlines", isOn: binding(\.taskAlerts))
                Toggle("Daily brief", isOn: binding(\.dailyBrief))
                if model.settings.dailyBrief {
                    DatePicker("Delivery time", selection: Binding(get: {
                        CocoModel.clock.date(bySettingHour: model.settings.briefHour, minute: model.settings.briefMinute, second: 0, of: model.now) ?? model.now
                    }, set: { date in
                        let parts = CocoModel.clock.dateComponents([.hour, .minute], from: date)
                        model.change { setting in
                            setting.briefHour = parts.hour ?? 9
                            setting.briefMinute = parts.minute ?? 0
                        }
                    }), displayedComponents: .hourAndMinute)
                }
                if model.notificationAccess == .notDetermined || model.notificationAccess == .denied {
                    Button("Enable Notifications") { model.requestNotifications() }.buttonStyle(.bordered)
                }
                HStack {
                    Button("Send Zoom Test Alert") { test(.zoom) }
                    Button("Send Room Test Alert") { test(.room) }
                }
                .buttonStyle(.bordered)
                .help("Send a desktop test reminder in 15 seconds")
            }
        }
    }

    private func binding<T>(_ path: WritableKeyPath<CocoSettings, T>) -> Binding<T> {
        Binding(get: { model.settings[keyPath: path] }, set: { value in model.change { $0[keyPath: path] = value } })
    }

    private func chooseCalendars() {
        calendarsSaved = false
        calendarDraft = Set(model.selectedCalendars.map(\.calendarIdentifier))
        choosingCalendars = true
    }

    private func saveCalendars() {
        let selection = calendarDraft
        if selection != model.settings.calendarIDs {
            model.change { $0.calendarIDs = selection }
        }
        calendarsSaved = true
        choosingCalendars = false
    }

    private func test(_ sample: CocoTest) {
        showSettings = false
        tab = .today
        model.scheduleTest(sample) { window.setExpanded(false) }
    }

    private func taskEditor(_ task: CocoTask) -> some View {
        CocoTaskEditor(task: task, isNew: !model.tasks.contains(where: { $0.id == task.id }), onSave: { result in
            model.save(result)
            draft = nil
        }, onCancel: { draft = nil }, onDelete: {
            model.delete(id: task.id)
            draft = nil
        }).id(task.id)
    }

    private func beginTask() {
        tab = .tasks
        draft = CocoTask(title: "", due: model.now.addingTimeInterval(3600))
    }

    private func taskRow(_ task: CocoTask) -> some View {
        HStack(alignment: .top, spacing: 9) {
            Button {
                var updated = task
                updated.completed.toggle()
                model.save(updated)
            } label: {
                Image(systemName: task.completed ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 16))
                    .foregroundStyle(tint)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(task.completed ? "Reopen \(task.title)" : "Complete \(task.title)")
            Button { tab = .tasks; draft = task } label: {
                VStack(alignment: .leading, spacing: 3) {
                    Text(task.title).font(.system(size: 13, weight: .medium)).strikethrough(task.completed)
                    if let due = task.due {
                        let late = due < model.now && !task.completed
                        Text((late ? "Overdue · " : "Due · ") + due.formatted(.dateTime.month(.abbreviated).day().hour().minute()))
                            .font(.system(size: 11)).foregroundStyle(late ? .red : .secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Edit task")
        }
        .padding(.vertical, 3)
    }

    private func meetingRow(_ meeting: CocoMeeting) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline) {
                Text(meeting.title).font(.system(size: 13, weight: .semibold))
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 6)
                Text(CocoModel.time(meeting.start)).font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(tint).fixedSize()
            }
            if let location = meeting.location {
                Label(location, systemImage: "mappin.and.ellipse")
                    .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            if let url = meeting.join, let provider = meeting.provider {
                Button { NSWorkspace.shared.open(url) } label: { Label("Join \(provider.rawValue)", systemImage: "video") }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            } else {
                if meeting.location == nil {
                    Label("Location unknown", systemImage: "mappin.slash")
                        .font(.callout).foregroundStyle(.secondary)
                }
                if let provider = meeting.provider {
                    Label("The invite has no \(provider.rawValue) join link", systemImage: "video.slash")
                        .font(.callout).foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 3)
    }

    private func section<Content: View>(_ title: String, icon: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Label(title, systemImage: icon)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(tint)
                .accessibilityAddTraits(.isHeader)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(13)
        .background(card, in: RoundedRectangle(cornerRadius: 15))
        .overlay(RoundedRectangle(cornerRadius: 15).strokeBorder(.primary.opacity(0.05), lineWidth: 1).allowsHitTesting(false))
    }

    private func iconButton(_ icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: 12, weight: .semibold))
                .frame(width: 30, height: 30)
                .background(tint.opacity(0.09), in: Circle())
                .foregroundStyle(tint)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .help(label)
    }
}

struct CocoTaskEditor: View {
    @State var task: CocoTask
    var isNew: Bool
    var onSave: (CocoTask) -> Void
    var onCancel: () -> Void
    var onDelete: () -> Void
    @FocusState private var titleFocused: Bool
    @State private var confirmDelete = false

    var cleanTitle: String { task.title.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(isNew ? "New task" : "Edit task").font(.title3.bold())
            TextField("Task name", text: $task.title).textFieldStyle(.roundedBorder).focused($titleFocused)
                .onSubmit(save)
            Toggle("Add a deadline", isOn: Binding(get: { task.due != nil }, set: { task.due = $0 ? Date().addingTimeInterval(3600) : nil }))
            if let due = task.due {
                DatePicker("Due", selection: Binding(get: { task.due ?? due }, set: { task.due = $0 }))
            }
            HStack {
                if !isNew {
                    Button("Delete", role: .destructive) { confirmDelete = true }
                        .confirmationDialog("Delete this task?", isPresented: $confirmDelete) {
                            Button("Delete task", role: .destructive, action: onDelete)
                        }
                }
                Spacer()
                Button("Cancel", action: onCancel).keyboardShortcut(.cancelAction)
                Button("Save", action: save).buttonStyle(.borderedProminent).disabled(cleanTitle.isEmpty)
            }
        }
        .onAppear { titleFocused = true }
    }

    private func save() {
        guard !cleanTitle.isEmpty else { return }
        task.title = cleanTitle
        onSave(task)
    }
}
