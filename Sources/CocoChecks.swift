import EventKit
import Foundation

func runCocoChecks() {
    var failures: [String] = []
    func expect(_ condition: @autoclosure () -> Bool, _ name: String) {
        if !condition() { failures.append(name) }
    }

    let invite = "https://campus-example.zoom.us/j/123456789?pwd=Ab%2B123&tk=456"
    expect(CocoMeeting.joinURL(invite)?.absoluteString == invite, "Zoom passcode preserved")
    expect(CocoMeeting.joinURL("https://zoom.us/s/123456789?zak=host") == nil, "Zoom host link rejected")
    expect(CocoMeeting.joinURL("https://zoom.us/j/123456789?zak=host") == nil, "Zoom host credentials rejected")
    expect(CocoMeeting.joinURL("https://zoom.us.evil.example/j/123456789") == nil, "Zoom lookalike rejected")
    expect(CocoMeeting.joinURL("https://evil.example@zoom.us/j/123456789") == nil, "Credentials rejected")
    let links: [(String, MeetingProvider)] = [
        ("https://meet.google.com/abc-defg-hij?authuser=1", .googleMeet),
        ("https://teams.microsoft.com/l/meetup-join/19%3ameeting_test%40thread.v2/0?context=%7B%7D", .teams),
        ("https://teams.microsoft.com/meet/123456789?p=abc", .teams),
        ("https://example.webex.com/meet/room", .webex),
        ("https://example.webex.com/example/j.php?MTID=m12345678", .webex),
        (invite, .zoom)
    ]
    for (link, provider) in links { expect(URL(string: link).flatMap(MeetingProvider.identify) == provider, "\(provider.rawValue) link") }
    expect(URL(string: "https://meet.google.com/new").flatMap(MeetingProvider.identify) == nil, "Meet host link rejected")
    expect(CocoMeeting.physicalLocation("Room 204, 1 College St") == "Room 204, 1 College St", "Room preserved")
    expect(CocoMeeting.physicalLocation("Room 204, 1 College St\n\(invite)") == "Room 204, 1 College St", "Hybrid room preserved")
    expect(CocoMeeting.physicalLocation("Room 204, 1 College St + \(invite)") == "Room 204, 1 College St", "Inline hybrid room preserved")
    expect(CocoMeeting.physicalLocation(invite) == nil, "Video link excluded from location")
    expect(CocoMeeting.physicalLocation("Zoom meeting") == nil, "Zoom label excluded from location")

    let eventStore = EKEventStore()
    let event = EKEvent(eventStore: eventStore)
    event.title = "Example class"
    event.startDate = Date().addingTimeInterval(1800)
    event.endDate = Date().addingTimeInterval(5400)
    expect(CocoMeeting(event: event)?.details == "Location unknown", "Unknown location")
    event.location = "Example Hall, Room 212"
    event.notes = "Join from \(invite.replacingOccurrences(of: "&", with: "&amp;"))"
    let hybrid = CocoMeeting(event: event)
    expect(hybrid?.details == event.location, "Hybrid alert includes exact location")
    expect(hybrid?.join?.absoluteString == invite, "Hybrid alert includes the attendee link")
    if let hybrid {
        let now = Date()
        let task = CocoTask(title: "Project deadline", due: now.addingTimeInterval(1800))
        let plan = CocoModel.plannedAlerts(now: now, settings: CocoSettings(), meetings: [hybrid], openTasks: [task]) { _ in "Brief" }
        let times = plan.filter { $0.occurrence == hybrid.id }.map(\.time)
        expect(times == [hybrid.start.addingTimeInterval(-600), hybrid.start], "Two alerts at the requested times")
        expect(plan.filter { $0.occurrence == hybrid.id }.allSatisfy { $0.join == hybrid.join && $0.body.contains(hybrid.location ?? "") },
            "Both alerts contain the location and join action")
        expect(plan.contains { $0.time == task.due && $0.body == task.title }, "Task reminder at deadline")
        expect(plan.filter { $0.occurrence == "brief" }.allSatisfy { CocoModel.clock.component(.hour, from: $0.time) == 9 }, "Daily brief at 9 AM Toronto")
        expect(plan.contains { $0.occurrence == "brief" }, "Daily brief scheduled")
    } else { failures.append("Timed hybrid class parsed") }
    event.isAllDay = true
    expect(CocoMeeting(event: event) == nil, "All-day events skipped")
    event.isAllDay = false
    event.title = "Working location: Home"
    expect(CocoMeeting(event: event) == nil, "Calendar placeholders skipped")

    let start = Date(timeIntervalSince1970: 1795647600)
    let before = CocoAlert(occurrence: "a", time: start.addingTimeInterval(-600), title: "Class", body: "10 minutes")
    let at = CocoAlert(occurrence: "a", time: start, title: "Class", body: "Starting now")
    expect(before.identifier == before.identifier && before.identifier != at.identifier, "Stable IDs for two distinct alerts")
    let screen = CGRect(x: 0, y: 0, width: 1000, height: 700)
    let bubble = CGSize(width: 302, height: 80)
    let leftRobot = CGRect(x: 4, y: 600, width: 115, height: 95)
    let rightRobot = leftRobot.offsetBy(dx: 880, dy: 0)
    let nearLeft = BubblePlacement.beside(window: leftRobot, avatar: CGPoint(x: leftRobot.midX, y: leftRobot.midY), size: bubble, on: screen)
    let nearRight = BubblePlacement.beside(window: rightRobot, avatar: CGPoint(x: rightRobot.midX, y: rightRobot.midY), size: bubble, on: screen)
    expect(nearLeft.pointer == .left && nearLeft.frame.minX > leftRobot.maxX && screen.contains(nearLeft.frame), "Bubble sits to the right of a robot at the left edge")
    expect(nearRight.pointer == .right && nearRight.frame.maxX < rightRobot.minX && screen.contains(nearRight.frame), "Bubble sits to the left of a robot at the right edge")
    expect(CocoIcons.idle.count == 6 && CocoIcons.wave.count == 4, "Sprite bundled and decodable")

    if failures.isEmpty { print("Coco checks passed.") }
    else {
        for failure in failures { FileHandle.standardError.write(Data("FAIL: \(failure)\n".utf8)) }
        exit(1)
    }
}
