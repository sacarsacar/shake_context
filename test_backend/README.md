# shake_context — local test backend

A throwaway HTTP receiver for verifying shake_context end-to-end: submit a
report from the example app and watch the description, screenshots, device
info, logs, and network entries show up on a live web dashboard.

It is **not** part of the published package (excluded via `.pubignore`) and has
**zero dependencies** — it runs on the plain Dart VM.

## 1. Start the backend

From the package root:

```bash
dart run test_backend/server.dart
```

Then open the dashboard: <http://localhost:8080>

## 2. Run the example app (it POSTs here automatically)

In a second terminal:

```bash
cd example
flutter pub get
flutter run            # pick a device when prompted
```

The example's `onReportSubmitted` ships every report to this server via
`example/lib/report_uploader.dart`. The host depends on where the app runs:

| Where the app runs            | Backend URL it uses        |
| :---------------------------- | :------------------------- |
| macOS / desktop / iOS sim     | `http://localhost:8080`    |
| Android emulator              | `http://10.0.2.2:8080`     |
| **Physical iPhone / Android** | `http://<your-mac-LAN-IP>:8080` |

### Testing on a physical device (read this — `localhost` won't work)

A phone's `localhost` is the **phone itself**, not your computer, so a real
device gets `Connection refused` until you point it at your machine's LAN IP:

1. **Find your Mac's IP:** `ipconfig getifaddr en0` (e.g. `192.168.18.92`).
2. **Set it** in `example/lib/report_uploader.dart`:
   ```dart
   const String lanHostOverride = '192.168.18.92'; // '' for sims/desktop
   ```
3. **Same network:** the phone and computer must be on the same Wi-Fi/LAN. App
   traffic goes over the network even when the device is USB-tethered.
4. **iOS only:** `ios/Runner/Info.plist` already includes an ATS exception
   (`NSAllowsLocalNetworking`) so the app may use plain HTTP, and a
   `NSLocalNetworkUsageDescription`. iOS 14+ shows a **"connect to devices on
   your local network"** prompt the first time — tap **Allow** (if you miss it:
   iOS Settings → the app → Local Network → on).
5. **Full restart** (not hot restart) after changing the IP / Info.plist:
   stop `flutter run`, then run again so the device reinstalls.

> The server binds dual-stack (IPv6 + IPv4), so `localhost`, `127.0.0.1`, `::1`,
> and your LAN IP all resolve to it.

## 3. Trigger a report

- **Android / iOS device:** shake the device.
- **Emulator / simulator / desktop:** tap **"Open overlay now"** on the home
  screen (the accelerometer is unreliable there).

Use the **Logs**, **Errors**, and **Mock API calls** cards first to seed data,
flip **Inspect mode** between Dev/Prod, then open the overlay, type a note,
attach an image, and submit.

## 4. Verify

- The example shows a green **"✓ Uploaded to test backend"** SnackBar (red if
  the server isn't running).
- The dashboard at <http://localhost:8080> adds the report within ~3s
  (it polls), rendering mode, description, attachments, device info, logs, and
  network calls.
- The server console also prints a one-line summary per report.

## Smoke-test without the app

Confirm the backend ingests + renders a realistic payload using `curl`:

```bash
curl -s -X POST http://localhost:8080/report \
  -H 'Content-Type: application/json' \
  -d '{"mode":"developer","userDescription":"curl smoke test","imageCount":0,
       "metadata":{"timestamp":"2026-06-02T10:00:00.000Z","currentRoute":"/checkout",
       "deviceInfo":{"platform":"android","model":"Pixel 7","appVersion":"1.0.0"},
       "logs":[{"message":"hello","level":"info","timestamp":"2026-06-02T10:00:00.000Z"}],
       "networkLogs":[{"method":"GET","url":"https://api.example.com/me","statusCode":200,"durationMs":42,"timestamp":"2026-06-02T10:00:00.000Z"}]}}'
```

Refresh the dashboard — the report appears.

## Endpoints

| Method | Path            | Purpose                                  |
| :----- | :-------------- | :--------------------------------------- |
| `POST` | `/report`       | Ingest a `ReportPayload.toJson(includeImages: true)` |
| `GET`  | `/`             | Live HTML dashboard                      |
| `GET`  | `/reports.json` | Raw JSON of everything received          |
| `POST` | `/clear`        | Drop all stored reports                  |

Reports are held in memory only — restarting the server clears them.
