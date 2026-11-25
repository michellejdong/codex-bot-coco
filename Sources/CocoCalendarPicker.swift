import EventKit
import SwiftUI

struct CocoCalendarPicker: View {
    let calendars: [EKCalendar]
    @Binding var selection: Set<String>
    let onCancel: () -> Void
    let onSave: () -> Void
    @State private var search = ""

    private var visibleCalendars: [EKCalendar] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        return query.isEmpty ? calendars : calendars.filter {
            $0.title.localizedStandardContains(query) || $0.source.title.localizedStandardContains(query)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            Text("Choose calendars")
                .font(.title3.bold())
                .accessibilityAddTraits(.isHeader)
            TextField("Search calendars", text: $search)
                .textFieldStyle(.roundedBorder)
                .accessibilityLabel("Search calendars")

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 1) {
                    if visibleCalendars.isEmpty {
                        Text("No matching calendars.")
                            .foregroundStyle(.secondary)
                            .padding(8)
                    }
                    ForEach(visibleCalendars, id: \.calendarIdentifier) { calendar in
                        Toggle(isOn: selected(calendar.calendarIdentifier)) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(calendar.title).font(.callout)
                                Text(calendar.source.title).font(.caption).foregroundStyle(.secondary)
                            }
                            .accessibilityElement(children: .combine)
                        }
                        .toggleStyle(.checkbox)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))

            HStack {
                Text("\(selection.count) selected")
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Cancel", action: onCancel).keyboardShortcut(.cancelAction)
                Button("Save Calendars", action: onSave)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 7)
        .padding(.bottom, 18)
    }

    private func selected(_ id: String) -> Binding<Bool> {
        Binding(get: { selection.contains(id) }, set: { enabled in
            if enabled { selection.insert(id) }
            else { selection.remove(id) }
        })
    }
}
