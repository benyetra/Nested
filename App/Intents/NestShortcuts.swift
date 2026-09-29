import AppIntents

/// Siri and Spotlight phrases. Every phrase must include the app name; parameters in phrases
/// must be enums, so amounts and hours are asked for (or defaulted) by the intent.
struct NestShortcuts: AppShortcutsProvider {
  static var appShortcuts: [AppShortcut] {
    AppShortcut(
      intent: LogBottleIntent(),
      phrases: [
        "Log a bottle in \(.applicationName)",
        "Repeat the last bottle in \(.applicationName)",
      ],
      shortTitle: "Log Bottle",
      systemImageName: "waterbottle.fill"
    )
    AppShortcut(
      intent: LogDiaperIntent(),
      phrases: [
        "Log a \(\.$type) diaper in \(.applicationName)",
        "Log a diaper in \(.applicationName)",
      ],
      shortTitle: "Log Diaper",
      systemImageName: "drop.fill"
    )
    AppShortcut(
      intent: StartNursingIntent(),
      phrases: [
        "Start nursing in \(.applicationName)",
        "Start nursing on \(\.$side) in \(.applicationName)",
      ],
      shortTitle: "Start Nursing",
      systemImageName: "heart.fill"
    )
    AppShortcut(
      intent: SwitchSideIntent(),
      phrases: ["Switch sides in \(.applicationName)"],
      shortTitle: "Switch Side",
      systemImageName: "arrow.left.arrow.right"
    )
    AppShortcut(
      intent: StartSleepIntent(),
      phrases: ["Start a nap in \(.applicationName)", "Baby is asleep in \(.applicationName)"],
      shortTitle: "Start Sleep",
      systemImageName: "moon.zzz.fill"
    )
    AppShortcut(
      intent: EndSleepIntent(),
      phrases: ["End the nap in \(.applicationName)", "Baby is awake in \(.applicationName)"],
      shortTitle: "End Sleep",
      systemImageName: "sun.max.fill"
    )
    AppShortcut(
      intent: StopActiveTimerIntent(),
      phrases: ["Stop the timer in \(.applicationName)"],
      shortTitle: "Stop Timer",
      systemImageName: "stop.circle.fill"
    )
    AppShortcut(
      intent: LastFeedQueryIntent(),
      phrases: [
        "When did the baby last eat in \(.applicationName)",
        "When was the last feed in \(.applicationName)",
      ],
      shortTitle: "Last Feed",
      systemImageName: "clock"
    )
    AppShortcut(
      intent: NextFeedQueryIntent(),
      phrases: ["When is the next feed in \(.applicationName)"],
      shortTitle: "Next Feed",
      systemImageName: "clock.arrow.circlepath"
    )
    AppShortcut(
      intent: SetFeedAlarmIntent(),
      phrases: ["Wake us up in \(.applicationName)", "Set the feed alarm in \(.applicationName)"],
      shortTitle: "Wake Us In…",
      systemImageName: "alarm.fill"
    )
  }
}
