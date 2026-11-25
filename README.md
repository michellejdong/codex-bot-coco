# Coco

Coco is a floating macOS desktop bot for meetings, classes, and deadlines. Drag the robot cat to move it. Click it to open the dashboard and get a heart.

- Meeting reminders appear 10 minutes before and at the start. Join Zoom, Google Meet, Teams, or Webex from the reminder when the invite includes a supported link.
- In-person reminders show the calendar’s room or address. Events without a listed location or join link show **Location unknown**.
- Add task deadlines and view a daily brief. The speech bubble follows Coco and changes sides near the edge of the screen.

## Build and run

Requires macOS 14 or later and the Xcode Command Line Tools.

```sh
./build.sh
open dist/Coco.app
```

Select **Connect Calendar** in Coco and allow access in macOS. Open **Choose Calendars…**, select as many calendars as you need, then click **Save Calendars**. To use Google Calendar, enable calendar sync for your Google account in macOS Internet Accounts. Keep Coco running for speech bubbles and calendar updates. **Enable Notifications** also makes reminders available through macOS notifications.

In Coco’s settings, **Send Zoom Test Alert** and **Send Room Test Alert** show sample reminders after 15 seconds. The Zoom button opens Zoom’s public test meeting. The room sample uses Room 204.

Coco reads calendar events and keeps tasks and preferences on your Mac.
