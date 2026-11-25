import AppKit
import CryptoKit
import EventKit
import SwiftUI
import UserNotifications

struct CocoTask: Codable, Identifiable {
    var id = UUID()
    var title: String
    var due: Date?
    var completed = false
}

enum MeetingProvider: String, CaseIterable {
    case zoom = "Zoom", googleMeet = "Google Meet", teams = "Teams", webex = "Webex"

    var category: String { "coco.join.\(self)" }

    static func identify(_ url: URL) -> Self? {
        guard url.scheme?.lowercased() == "https", url.user == nil, url.password == nil,
              let host = url.host?.lowercased() else { return nil }
        let path = url.path.lowercased()
        if CocoMeeting.joinURL(url.absoluteString) != nil { return .zoom }
        if host == "meet.google.com",
           path.range(of: #"^/(?:[a-z]{3}-[a-z]{4}-[a-z]{3}|lookup/[a-z0-9_-]+)/?$"#, options: .regularExpression) != nil { return .googleMeet }
        if ["teams.microsoft.com", "teams.live.com", "teams.cloud.microsoft"].contains(host),
           path.range(of: #"^/(?:l/meetup-join/[^/]+(?:/[^/]+)?|meet/[0-9]+)/?$"#, options: .regularExpression) != nil { return .teams }
        if host == "webex.com" || host.hasSuffix(".webex.com") {
            let personalRoom = path.range(of: #"^/(?:meet|join)/[^/]+/?$"#, options: .regularExpression) != nil
            let meetingID = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.contains {
                $0.name.lowercased() == "mtid" && !($0.value ?? "").isEmpty
            } == true
            if personalRoom || (path.hasSuffix("/j.php") && meetingID) { return .webex }
        }
        return nil
    }
}

struct CocoMeeting: Identifiable {
    var id: String
    var title: String
    var start: Date
    var end: Date
    var location: String?
    var join: URL?
    var provider: MeetingProvider?

    var details: String {
        if let location { return location }
        if let provider, join != nil { return provider.rawValue }
        if let provider { return "Location unknown\n\(provider.rawValue) · No join link in the invite" }
        return "Location unknown"
    }

    static func joinURL(_ value: String) -> URL? {
        let decoded = value.replacingOccurrences(of: "&amp;", with: "&")
        guard let url = URL(string: decoded), url.scheme?.lowercased() == "https",
              url.user == nil, url.password == nil,
              let host = url.host?.lowercased(),
              ["zoom.us", "zoomgov.com", "zoom.com"].contains(where: { host == $0 || host.hasSuffix(".\($0)") }),
              let first = url.pathComponents.dropFirst().first?.lowercased() else { return nil }
        let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        guard !query.contains(where: { $0.name.lowercased() == "zak" }) else { return nil }
        let parts = Array(url.pathComponents.dropFirst())
        let identifier = parts.dropFirst().first ?? ""
        let number = !identifier.isEmpty && identifier.utf8.allSatisfy { (48...57).contains($0) }
        switch first {
        case "j", "w": return number && parts.count == 2 ? url : nil
        case "my": return parts.count == 2 && !identifier.isEmpty ? url : nil
        case "wc":
            let validWebJoin = parts.count == 3 && ((number && parts[2] == "join") ||
                (identifier == "join" && !parts[2].isEmpty && parts[2].utf8.allSatisfy { (48...57).contains($0) }))
            return validWebJoin ? url : nil
        default: return nil
        }
    }

    static let linkDetector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)

    static func links(in value: String) -> [URL] {
        let decoded = value.replacingOccurrences(of: "&amp;", with: "&")
        let matches = linkDetector?.matches(in: decoded, range: NSRange(decoded.startIndex..., in: decoded)) ?? []
        return matches.compactMap(\.url)
    }

    static func physicalLocation(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let links = links(in: trimmed)
        let virtual = #"(?i)\b(?:zoom(?: meeting)?|on zoom|join zoom|google meet|microsoft teams|teams meeting|webex|online|virtual|video call|video conference|dial.in)\b"#
        let fragments = trimmed.components(separatedBy: .newlines).flatMap { $0.components(separatedBy: " | ") }
        let rooms = fragments.compactMap { fragment -> String? in
            let part = fragment.trimmingCharacters(in: .whitespacesAndNewlines)
            let partLinks = Self.links(in: part)
            let withoutLinks = partLinks.reduce(part) { $0.replacingOccurrences(of: $1.absoluteString, with: "") }
            let label = withoutLinks.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
            guard !label.isEmpty else { return nil }
            let isVirtualLabel = label.range(of: virtual, options: .regularExpression) != nil
            guard !isVirtualLabel || label.range(of: #"(?i)\b(room|building|floor|suite|campus|hall)\b"#, options: .regularExpression) != nil else { return nil }
            let videoLinks = partLinks.filter { MeetingProvider.identify($0) != nil }
            guard !videoLinks.isEmpty else { return fragment }
            let location = videoLinks.reduce(fragment) { $0.replacingOccurrences(of: $1.absoluteString, with: "") }
            return location.trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: "|+")))
        }
        guard !rooms.isEmpty else { return nil }
        if rooms.count == fragments.count && links.allSatisfy({ MeetingProvider.identify($0) == nil }) {
            return value
        }
        return rooms.joined(separator: "\n")
    }

    init?(event: EKEvent) {
        guard !event.isAllDay, event.status != .canceled, event.startDate != nil, event.endDate != nil,
              event.attendees?.contains(where: { $0.isCurrentUser && $0.participantStatus == .declined }) != true else { return nil }
        let title = event.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let placeholder = #"(?i)^(?:working location|out of office|busy|focus time|remote work|working from home)(?:\s*[:–—-].*)?$"#
        guard title.range(of: placeholder, options: .regularExpression) == nil else { return nil }
        let location = event.location.flatMap { $0.isEmpty ? nil : $0 } ?? event.structuredLocation?.title ?? ""
        let notes = event.notes ?? ""
        let urls = [event.url].compactMap { $0 } + Self.links(in: location) + Self.links(in: notes)
        let eventID = event.calendarItemExternalIdentifier ?? event.calendarItemIdentifier
        self.id = "\(eventID):\(event.startDate.timeIntervalSince1970.rounded())"
        self.title = title.isEmpty ? "Untitled meeting" : title
        self.start = event.startDate
        self.end = event.endDate
        self.location = Self.physicalLocation(location.replacingOccurrences(of: "&amp;", with: "&"))
        self.join = urls.first { MeetingProvider.identify($0) != nil }
        self.provider = join.flatMap(MeetingProvider.identify)
        if provider == nil {
            let details = [title, location, notes].joined(separator: " ")
            provider = MeetingProvider.allCases.first {
                let name = NSRegularExpression.escapedPattern(for: $0 == .teams ? "Microsoft Teams" : $0.rawValue)
                return details.range(of: "(?i)\\b\(name)\\b", options: .regularExpression) != nil
            }
        }
    }
}

struct CocoSettings: Codable {
    var calendarIDs: Set<String> = []
    var meetingAlerts = true
    var taskAlerts = true
    var dailyBrief = true
    var briefHour = 9
    var briefMinute = 0
    var tint = "Sky"
}

struct CocoAlert {
    var occurrence: String
    var time: Date
    var title: String
    var body: String
    var join: URL? = nil
    var speech: CocoSpeech? = nil
    var speechID: String { "\(occurrence):\(time.timeIntervalSince1970)" }
    var identifier: String {
        let payload = "\(occurrence)\n\(time.timeIntervalSince1970)\n\(title)\n\(body)\n\(join?.absoluteString ?? "")"
        return "coco-" + SHA256.hash(data: Data(payload.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

enum CocoTest {
    case zoom, room

    var title: String { self == .zoom ? "Zoom test meeting" : "In-person test meeting" }
    var roomName: String? { self == .room ? "Room 204" : nil }
    var speech: CocoSpeech {
        CocoSpeech(text: self == .zoom ? "Your Zoom test is starting." : "Your test meeting is starting.",
                   detail: roomName, detailIcon: self == .room ? "mappin" : nil,
                   join: self == .zoom ? CocoModel.zoomTestURL : nil,
                   joinLabel: self == .zoom ? "Join Zoom Test" : nil, lifetime: 45)
    }
}

final class CocoModel: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    @Published private(set) var tasks: [CocoTask] = []
    @Published private(set) var meetings: [CocoMeeting] = []
    @Published private(set) var calendars: [EKCalendar] = []
    @Published private(set) var calendarAccess = EKEventStore.authorizationStatus(for: .event)
    @Published private(set) var notificationAccess: UNAuthorizationStatus = .notDetermined
    @Published private(set) var settings = CocoSettings()
    @Published private(set) var now = Date()
    @Published private(set) var message: String?
    @Published private(set) var activeTest: CocoTest?
    @Published private(set) var testTime: Date?

    private let events = EKEventStore()
    private let notifications = UNUserNotificationCenter.current()
    private let defaults = UserDefaults.standard
    private var timer: Timer?
    private var speechTimer: Timer?
    private var testWork: DispatchWorkItem?
    private var speechHistory: [String: TimeInterval] = [:]
    private var observers: [NSObjectProtocol] = []
    private var wakeObserver: NSObjectProtocol?
    private var scheduleRevision = 0
    var show: (() -> Void)?
    var speak: ((CocoSpeech) -> Void)?
    static let zoomTestURL = URL(string: "https://zoom.us/test")!
    private static let testID = "coco.test.meeting"

    static let clock: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Toronto") ?? .current
        return calendar
    }()

    var openTasks: [CocoTask] {
        tasks.filter { !$0.completed }.sorted { ($0.due ?? .distantFuture, $0.title) < ($1.due ?? .distantFuture, $1.title) }
    }

    var selectedCalendars: [EKCalendar] { calendars.filter { settings.calendarIDs.contains($0.calendarIdentifier) } }

    override init() {
        super.init()
        if let data = defaults.data(forKey: "coco.tasks"), let saved = try? JSONDecoder().decode([CocoTask].self, from: data) { tasks = saved }
        if let data = defaults.data(forKey: "coco.settings"), let saved = try? JSONDecoder().decode(CocoSettings.self, from: data) { settings = saved }
        speechHistory = defaults.dictionary(forKey: "coco.speechHistory") as? [String: TimeInterval] ?? [:]
        notifications.delegate = self
        var categories = Set(MeetingProvider.allCases.map { provider in
            UNNotificationCategory(identifier: provider.category, actions: [
                UNNotificationAction(identifier: "coco.join", title: "Join \(provider.rawValue)", options: [.foreground])
            ], intentIdentifiers: [])
        })
        categories.insert(UNNotificationCategory(identifier: "coco.test.zoom", actions: [
            UNNotificationAction(identifier: "coco.test.join", title: "Join Zoom Test", options: [.foreground])
        ], intentIdentifiers: []))
        notifications.setNotificationCategories(categories)
        observers.append(NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: nil, queue: .main) { [weak self] _ in self?.refresh() })
        observers.append(NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in self?.refresh() })
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in self?.refresh() }
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in self?.refresh() }
        refresh()
    }

    deinit {
        timer?.invalidate()
        speechTimer?.invalidate()
        testWork?.cancel()
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
        if let wakeObserver { NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver) }
    }

    func requestCalendar() {
        message = nil
        if calendarAccess == .denied || calendarAccess == .restricted {
            message = "Allow Coco in System Settings → Privacy & Security → Calendars."
            return
        }
        events.requestFullAccessToEvents { [weak self] granted, error in
            DispatchQueue.main.async {
                guard let self else { return }
                if let error { self.message = error.localizedDescription }
                else if !granted { self.message = "Calendar access was declined. You can enable it in System Settings." }
                self.refresh()
            }
        }
    }

    func requestNotifications() {
        message = nil
        if notificationAccess == .denied {
            message = "Allow Coco in System Settings → Notifications."
            return
        }
        notifications.requestAuthorization(options: [.alert, .sound, .badge]) { [weak self] granted, error in
            DispatchQueue.main.async {
                if let error { self?.message = error.localizedDescription }
                else if !granted { self?.message = "Notifications were declined. You can enable them in System Settings." }
                self?.refresh()
            }
        }
    }

    func scheduleTest(_ test: CocoTest, onScheduled: (() -> Void)? = nil) {
        message = nil
        activeTest = test
        let delay: TimeInterval = 15
        let time = Date().addingTimeInterval(delay)
        testTime = time
        testWork?.cancel()
        let sample = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.now = Date()
            self.speak?(test.speech)
        }
        testWork = sample
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: sample)
        onScheduled?()
        notifications.getNotificationSettings { [weak self] state in
            DispatchQueue.main.async {
                guard let self, self.testTime == time else { return }
                guard state.authorizationStatus == .authorized || state.authorizationStatus == .provisional else { return }
                let content = UNMutableNotificationContent()
                content.title = test.title
                content.body = test == .zoom ? "Starting now" : "Starting now\n\(test.roomName ?? "Location unknown")"
                content.sound = .default
                if test == .zoom { content.categoryIdentifier = "coco.test.zoom" }
                let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, time.timeIntervalSinceNow), repeats: false)
                let request = UNNotificationRequest(identifier: Self.testID, content: content, trigger: trigger)
                self.notifications.add(request) { [weak self] scheduleError in
                    guard let scheduleError else { return }
                    DispatchQueue.main.async { self?.message = scheduleError.localizedDescription }
                }
            }
        }
    }

    func change(_ edit: (inout CocoSettings) -> Void) {
        var next = settings
        edit(&next)
        settings = next
        defaults.set(try? JSONEncoder().encode(next), forKey: "coco.settings")
        refresh()
    }

    func save(_ task: CocoTask) {
        if let index = tasks.firstIndex(where: { $0.id == task.id }) { tasks[index] = task }
        else { tasks.append(task) }
        persistTasks()
    }

    func delete(id: UUID) {
        tasks.removeAll { $0.id == id }
        persistTasks()
    }

    private func persistTasks() {
        defaults.set(try? JSONEncoder().encode(tasks), forKey: "coco.tasks")
        refresh()
    }

    func refresh() {
        now = Date()
        calendarAccess = EKEventStore.authorizationStatus(for: .event)
        if calendarAccess == .fullAccess {
            calendars = events.calendars(for: .event).sorted { ($0.source.title, $0.title) < ($1.source.title, $1.title) }
            let selected = selectedCalendars
            if !selected.isEmpty {
                let from = Self.clock.startOfDay(for: now).addingTimeInterval(-86400)
                let through = now.addingTimeInterval(8 * 86400)
                let query = events.predicateForEvents(withStart: from, end: through, calendars: selected)
                var ids = Set<String>()
                meetings = events.events(matching: query).compactMap(CocoMeeting.init).filter { ids.insert($0.id).inserted }.sorted { $0.start < $1.start }
            } else { meetings = [] }
        } else {
            calendars = []
            meetings = []
        }
        scheduleSpeech()
        notifications.getNotificationSettings { [weak self] state in
            DispatchQueue.main.async {
                guard let self else { return }
                self.notificationAccess = state.authorizationStatus
                self.scheduleAlerts()
            }
        }
    }

    func brief(on date: Date) -> String {
        let day = Self.clock.startOfDay(for: date)
        let next = Self.clock.date(byAdding: .day, value: 1, to: day) ?? day.addingTimeInterval(86400)
        let todaysEvents = meetings.filter { Self.clock.isDate($0.start, inSameDayAs: day) && $0.end > date }
        let due = openTasks.filter { ($0.due ?? .distantFuture) < next }
        var lines: [String] = []
        if let first = todaysEvents.first {
            let detail = first.details.isEmpty ? "" : " · \(first.details)"
            lines.append("\(todaysEvents.count) \(todaysEvents.count == 1 ? "meeting" : "meetings") left. First: \(first.title) at \(Self.time(first.start))\(detail).")
        } else if !selectedCalendars.isEmpty {
            lines.append("Your calendar is clear for the rest of the day.")
        } else {
            lines.append("Connect a calendar to see your meetings here.")
        }
        if let first = due.first { lines.append("\(due.count) \(due.count == 1 ? "task" : "tasks") due by tonight. Start with \(first.title).") }
        else { lines.append("No task deadlines today.") }
        return lines.joined(separator: "\n")
    }

    static func time(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeZone = clock.timeZone
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    static func plannedAlerts(now: Date, settings: CocoSettings, meetings: [CocoMeeting], openTasks: [CocoTask],
                              brief: (Date) -> String) -> [CocoAlert] {
        let horizon = now.addingTimeInterval(7 * 86400)
        let recent = now.addingTimeInterval(-120)
        var result: [CocoAlert] = []
        if settings.meetingAlerts {
            for meeting in meetings where meeting.start > recent && meeting.start < horizon {
                    let details = "\n\(meeting.details)"
                for (offset, label) in [(600.0, "Starts in 10 minutes"), (0.0, "Starting now")] {
                    let time = meeting.start.addingTimeInterval(-offset)
                    let note = offset == 600 ? "“\(meeting.title)” starts in 10 minutes at \(Self.time(meeting.start))." : "“\(meeting.title)” is starting now."
                    let bubble = CocoSpeech(text: note, detail: meeting.details,
                                            detailIcon: meeting.location != nil ? "mappin" : (meeting.join != nil ? "video" : "mappin.slash"))
                    result.append(CocoAlert(occurrence: meeting.id, time: time, title: meeting.title,
                        body: "\(label) · \(Self.time(meeting.start))\(details)", join: meeting.join, speech: bubble))
                }
            }
        }
        if settings.taskAlerts {
            for task in openTasks {
                guard let due = task.due, due > recent, due < horizon else { continue }
                result.append(CocoAlert(occurrence: task.id.uuidString, time: due, title: "Task due", body: task.title,
                                        speech: CocoSpeech(text: "Your task “\(task.title)” is due now.")))
            }
        }
        if settings.dailyBrief {
            for offset in 0..<7 {
                guard let day = Self.clock.date(byAdding: .day, value: offset, to: now),
                      let time = Self.clock.date(bySettingHour: settings.briefHour, minute: settings.briefMinute, second: 0, of: Self.clock.startOfDay(for: day)) else { continue }
                let update = brief(time)
                result.append(CocoAlert(occurrence: "brief", time: time, title: "Good morning from Coco 💙", body: update,
                                        speech: CocoSpeech(text: "Good morning!", detail: update)))
            }
        }
        return Array(result.filter { $0.time > recent }.sorted { $0.time < $1.time }.prefix(60))
    }

    private func scheduleSpeech() {
        speechTimer?.invalidate()
        guard let speak else { return }
        let planned = Self.plannedAlerts(now: now, settings: settings, meetings: meetings, openTasks: openTasks, brief: brief(on:))
        let due = planned.filter { $0.time <= now && speechHistory[$0.speechID] == nil }
        if !due.isEmpty {
            let cutoff = now.timeIntervalSince1970 - 2 * 86400
            speechHistory = speechHistory.filter { $0.value >= cutoff }
            for alert in due {
                var bubble = alert.speech ?? CocoSpeech(text: alert.body)
                bubble.join = alert.join
                bubble.joinLabel = alert.join.flatMap(MeetingProvider.identify).map { "Join \($0.rawValue)" }
                speak(bubble)
                speechHistory[alert.speechID] = now.timeIntervalSince1970
            }
            defaults.set(speechHistory, forKey: "coco.speechHistory")
        }
        if let next = planned.first(where: { $0.time > now }) {
            let wake = Timer(timeInterval: max(0.05, next.time.timeIntervalSinceNow), repeats: false) { [weak self] _ in
                self?.refresh()
            }
            speechTimer = wake
            RunLoop.main.add(wake, forMode: .common)
        }
    }

    private func scheduleAlerts() {
        scheduleRevision += 1
        let revision = scheduleRevision
        let allowed = notificationAccess == .authorized || notificationAccess == .provisional
        let planned = allowed ? Self.plannedAlerts(now: now, settings: settings, meetings: meetings, openTasks: openTasks, brief: brief(on:)) : []
        let keep = Set(planned.map(\.identifier))
        notifications.getPendingNotificationRequests { [weak self] list in
            DispatchQueue.main.async {
                guard let self, self.scheduleRevision == revision else { return }
                let pending = Set(list.map(\.identifier))
                self.notifications.removePendingNotificationRequests(withIdentifiers: pending.filter { $0.hasPrefix("coco-") && !keep.contains($0) })
                for alert in planned where !pending.contains(alert.identifier) {
                    let wait = alert.time.timeIntervalSinceNow
                    guard wait > 0 else { continue }
                    let content = UNMutableNotificationContent()
                    content.title = alert.title
                    content.body = alert.body
                    content.sound = .default
                    if let join = alert.join, let provider = MeetingProvider.identify(join) {
                        content.categoryIdentifier = provider.category
                        content.userInfo = ["join": join.absoluteString]
                    }
                    let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, wait), repeats: false)
                    self.notifications.add(UNNotificationRequest(identifier: alert.identifier, content: content, trigger: trigger)) { [weak self] error in
                        guard let error else { return }
                        DispatchQueue.main.async { self?.message = "Coco couldn't schedule an alert. \(error.localizedDescription)" }
                    }
                }
            }
        }
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler done: @escaping (UNNotificationPresentationOptions) -> Void) {
        done([.banner, .list, .sound])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler done: @escaping () -> Void) {
        DispatchQueue.main.async {
            if response.actionIdentifier == "coco.test.join", response.notification.request.identifier == Self.testID {
                NSWorkspace.shared.open(Self.zoomTestURL)
            } else if response.actionIdentifier == "coco.join",
               let value = response.notification.request.content.userInfo["join"] as? String,
               let url = URL(string: value), MeetingProvider.identify(url) != nil {
                NSWorkspace.shared.open(url)
            } else if response.actionIdentifier == UNNotificationDefaultActionIdentifier {
                self.show?()
            }
            done()
        }
    }
}
