# shake_context example

A multi-page test harness for the `shake_context` package. It exercises every
knob worth verifying on a real device and ships its reports to a local backend
so you can watch the captured data render in a browser.

## What it demonstrates

- **Dual mode** — flip between the developer overlay and the production
  feedback sheet at runtime (Inspect mode toggle).
- **Shake sensitivity** — low / medium / high presets.
- **Theming** — toggle a custom `ReportTheme` on the report surfaces.
- **Log capture** — buttons that emit `debugPrint`, `print` (via the zone
  hook), and every `ShakeContext.log` level.
- **Error capture** — buttons that throw uncaught async errors and
  `FlutterError.reportError` (these print red to the console *by design* — they
  prove the package catches them).
- **Network capture** — buttons that record mock HTTP cycles (200/4xx/5xx,
  timeouts, DNS failures) into the developer overlay's Network panel.
- **Route capture** — a `/checkout` route to confirm the overlay reports it.
- **Real upload** — `onReportSubmitted` POSTs each report to the local
  [`test_backend`](../test_backend), so you can confirm the data leaves the app.

## Run it

```bash
# 1. Start the receiver (from the package root, in its own terminal)
dart run test_backend/server.dart        # dashboard at http://localhost:8080

# 2. Run the example
cd example
flutter pub get
flutter run                              # pick a device
```

Seed some data with the Logs / Errors / Mock API cards, pick a mode, then
**shake the device** (or tap **"Open overlay now"** on a simulator/desktop),
type a note, attach an image, and submit. The report appears on the dashboard
within a few seconds.

## Pointing the app at the backend

`lib/report_uploader.dart` resolves the backend host automatically:

| Where the app runs            | Host it uses                          |
| :---------------------------- | :------------------------------------ |
| iOS simulator / macOS / web   | `localhost`                           |
| Android emulator              | `10.0.2.2`                            |
| **Physical iPhone/Android**   | set `lanHostOverride` to your Mac's LAN IP (`ipconfig getifaddr en0`) |

A physical phone can't reach your computer via `localhost` (that's the phone
itself) — it must use your machine's LAN IP, and the phone and computer must be
on the same network. iOS also needs the cleartext-HTTP / local-network
allowances already added to `ios/Runner/Info.plist`, and you must tap **Allow**
on the local-network permission prompt the first time it uploads. Full details
in [test_backend/README.md](../test_backend/README.md).

> The upload wiring here is a **demo** of the README's "Sending the report"
> recipe. In a real app you'd POST to your own HTTPS endpoint and dispatch by
> `payload.mode` — see the package
> [README](../README.md#sending-the-report).
