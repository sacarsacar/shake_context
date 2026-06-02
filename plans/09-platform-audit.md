# Plan 09 — Cross-platform reality audit

## Goal

The README's "Platform support" table claims everything except shake detection works on macOS / Windows / Linux / web. Some of this is real, some is probably aspirational. Replace promises with verified truth — and fix or explicitly document any gaps found.

## Current claims to verify

| Platform | Shake | Screenshot | Device info | Gallery picker | Persistence |
|----------|-------|------------|-------------|----------------|-------------|
| Android  | ✅    | ✅         | ✅          | ✅             | ✅          |
| iOS      | ✅    | ✅         | ✅          | ✅             | ✅          |
| macOS    | ❌    | claimed ✅ | claimed ✅  | claimed ✅     | claimed ✅  |
| Windows  | ❌    | claimed ✅ | claimed ✅  | claimed ✅     | claimed ✅  |
| Linux    | ❌    | claimed ✅ | claimed ✅  | claimed ✅     | claimed ✅  |
| Web      | ❌    | claimed ✅ | claimed ✅  | claimed ✅     | ❌ (correct)|

## Method

For each platform-and-capability cell:

1. Run `example/` on the platform
2. Tap "Open overlay now" (no shake → `triggerReport`)
3. Verify each feature actually works: screenshot renders, device info populates, gallery picker opens, package_info shows app version
4. Submit a report; verify the payload arrives intact via the example's snackbar
5. Re-launch with `enableRetryQueue: true` (post-Plan 08) to confirm the queue directory works or correctly no-ops

### Platforms I can run programmatically

- **Web** — `flutter run -d chrome --target=example/lib/main.dart`
- **macOS** — `flutter run -d macos --target=example/lib/main.dart`

### Platforms the user needs to verify

- **Windows** — needs a Windows machine
- **Linux** — needs a Linux machine

Default for these: mark as "untested but expected to work; please report platform-specific issues" in the README until someone verifies.

## Known suspect areas

- **Web `image_picker`** — uses `<input type="file">` which on some browsers requires the click handler to be in the same synchronous task as a user gesture. Our `pickImageFromGallery` is called from a `ValueChanged` callback inside a `setState` → may or may not work. Test explicitly.
- **Web `RepaintBoundary.toImage`** — works in modern Chromium but has DPR quirks. Screenshot should at least produce *some* bytes; document any aspect-ratio surprises.
- **Web `package_info_plus`** — reads from a generated `assets/version.json` that needs to be in the published web bundle. Verify the example app produces a valid `appVersion` after `flutter build web`.
- **macOS `image_picker`** — `image_picker_macos` is community-maintained, not first-party. Verify it works under the example.
- **macOS sandbox** — `getApplicationSupportDirectory()` returns a sandboxed path; the queue directory must be writeable. Verify.
- **Linux/Windows `image_picker`** — also community plugins; same caveat.

## Output

### README changes

Replace the platform-support table with a verified two-table layout:

```markdown
## Platform support

### Tier 1 — first-party, verified

| Capability       | Android | iOS | macOS | Web |
|------------------|:-------:|:---:|:-----:|:---:|
| Shake detection  | ✅      | ✅  | —     | —   |
| triggerReport    | ✅      | ✅  | ✅    | ✅  |
| Screenshot       | ✅      | ✅  | ✅    | ✅* |
| Device info      | ✅      | ✅  | ✅    | ✅  |
| App version      | ✅      | ✅  | ✅    | ✅* |
| Gallery picker   | ✅      | ✅  | ✅    | ⚠️  |
| Crash recovery   | ✅      | ✅  | ✅    | —   |

\* see "Web caveats" below

### Tier 2 — community plugins, untested

Windows and Linux *should* work — every dependency
(`sensors_plus`, `device_info_plus`, `image_picker`,
`path_provider`, `package_info_plus`) ships a platform
implementation — but the maintainer hasn't verified them
end-to-end. Please report issues with platform context.
```

Plus a new "Web caveats" subsection if anything is found (likely: image_picker user-gesture requirement, package_info build step).

### Code changes (if any are needed)

Plausibly zero. Most failure modes here are already caught by the existing try/catch around plugin calls in `ContextCapturer` — the report just lands with a missing field. If any platform turns out to actually throw rather than degrade, add a narrower catch.

If anything genuinely doesn't work on a platform we claim to support, the options are:
1. Fix it (preferred)
2. Disable that capability cleanly on that platform with a documented workaround
3. Remove that platform from the support table

## Files

| Action | Path |
|--------|------|
| Modified | `README.md` — platform table rewrite + "Web caveats" subsection |
| Possibly modified | `lib/src/core/context_capturer.dart` — only if a platform issue requires a code fix |
| Modified | `CHANGELOG.md` — unreleased entry noting verified support |

## Test plan

Manual smoke tests, scripted as a checklist in this plan. Each cell in the support table must have a verified ✅, a documented ⚠️, or be removed.

No new unit tests — the verification is hands-on by design.

## Acceptance

- Every ✅ in the rewritten README table is a capability the maintainer has personally observed working in the example app
- Every ⚠️ has a corresponding "Web caveats" / "Platform caveats" entry explaining the limitation
- Windows / Linux are explicitly framed as "untested but expected to work"
- `flutter analyze` + `flutter test` still green
- CHANGELOG records the verification pass

## Risks

- **Audit may surface bugs** — possible we find a real bug on macOS or web that needs fixing before this plan can close. If the fix is larger than ~1h, spin out as a separate follow-up plan rather than blocking 0.2.
- **Platform-specific dependency drift** — `image_picker_macos` etc. version up independently and could regress. Mitigation: pin to known-good versions in `pubspec.yaml` if needed.

## Sequencing

Run **after** Plans 07 and 08 land, so the audit covers the final 0.2 surface area (including localized strings and the retry queue directory).
