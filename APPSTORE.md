# Mac App Store — submission checklist

Everything required to get **Windchime** verified and listed on the Mac App
Store, with our current status. Researched Aug 2026.

Legend:  ✅ done · 🔨 I can do (no account needed) · 🔑 needs your Apple Developer account · ⚠️ risk to plan for

## Prepped now (no account needed) — Aug 2026

- ✅ **App Sandbox + microphone entitlements** (`Windchime.entitlements`), signed
  in via `make-app.sh`. Verified: launches sandboxed, no violations.
- ✅ **Privacy manifest** (`PrivacyInfo.xcprivacy`) — declares no data collection
  + the UserDefaults required-reason (CA92.1). Bundled into the app.
- ✅ **Universal binary** — now builds `x86_64 + arm64` (Intel + Apple Silicon).
- ✅ **App icon** bundled.
- ✅ **Privacy policy page** — `docs/privacy.html` (host free via GitHub Pages →
  `https://shivam230.github.io/windchime-mac/privacy.html`).
- 🟡 **Screenshots** — a reference capture is in `docs/screenshots/`; final
  marketing shots want a clean desktop at an approved size (see §2).

Still requires your account: distribution signing, App Store Connect listing,
and wrapping the build as an uploadable archive (§1, §2, §4).

---

---

## 0. Prerequisite

- 🔑 **Apple Developer Program** — $99/yr. Only you can enrol (Apple ID +
  payment + identity verification, can take 1–2 days). Everything below that
  needs signing or App Store Connect is blocked until this exists.

## 1. Technical requirements (the app bundle)

- ✅ **No private APIs** — verified: the app links only AppKit / Foundation /
  SwiftUI. (This is the whole reason we went native instead of Tauri.)
- ✅ **Built with a current SDK** — Xcode 26.6 / macOS 26 SDK. Apple requires a
  recent SDK for new submissions.
- ✅ **App icon** — brass-bell `icon.icns` bundled. App Store Connect also wants
  a **1024×1024** PNG (we have `build/icon-1024.png`).
- 🔨 **App Sandbox** — *mandatory* for the App Store. Add entitlement
  `com.apple.security.app-sandbox = true`. (Not enabled yet.)
- 🔨 **Microphone entitlement** — `com.apple.security.device.audio-input = true`
  plus the `NSMicrophoneUsageDescription` we already ship. Needed for the blow
  detection to work inside the sandbox.
- 🔨 **Privacy manifest** (`PrivacyInfo.xcprivacy`) — *hard gate since May 2024*.
  Must declare:
  - Microphone use (and that data isn't collected/sent).
  - **Required-reason API: `UserDefaults`** — we use it for window-position
    persistence; reason code `CA92.1` (accessing our own app's defaults).
- 🔨 **Universal binary** — currently arm64-only (SwiftPM). Add an `x86_64` slice
  so Intel Macs are supported (App Store expects universal).
- 🔑 **Code signing for distribution** — sign with the **3rd Party Mac Developer
  Application/Installer** certificates from your account, with a provisioning
  profile for the App Store. (Ad-hoc signing we use for dev won't upload.)
- 🔨 **Build/archive flow** — the SwiftPM setup needs wrapping in an Xcode
  project (or an `xcodebuild archive` flow) to produce an uploadable archive.
  This is bookkeeping, not a rewrite.

## 2. App Store Connect (the listing)

- 🔑 **Register the bundle ID** — `com.shivami.windchime`.
- 🔑 **Create the app record** in App Store Connect.
- 🔨 **Screenshots** — macOS requires at least one, sized **1280×800, 1440×900,
  2560×1600, or 2880×1800**. I can capture these of the widget on a desktop.
- 🔨 **Metadata** — name, subtitle, description, keywords, promo text, **category
  (Lifestyle)**, support URL.
- 🔑 **Age rating** questionnaire (this app: 4+).
- 🔑 **App Privacy "nutrition label"** — declare data practices. Ours is the
  simplest case: **"Data Not Collected"** (mic is analysed on-device and
  discarded; nothing is stored or sent).
- 🔨 **Privacy policy URL** — a *live* page is required. I can generate a short
  one and we host it (e.g. GitHub Pages) — it just has to state we collect
  nothing and the mic stays on-device.
- 🔑 **Pricing & availability** — Free.

## 3. Review-guideline risks to plan for

- ⚠️ **4.2 Minimum Functionality** — Apple sometimes rejects simple/novelty apps
  as "not enough functionality / could be a web page." A windchime widget is
  exactly the kind of app a reviewer might question. Mitigations: lean into the
  genuine native features (live mic-reactive audio, always-on-top desktop
  presence, multiple interactions) and a polished listing. Worth being ready
  with a short reviewer note explaining the interactive, always-running nature.
- ✅ **Fully functional, no placeholders** — the app is complete.
- ✅ **No third-party SDKs** — so no blocked-manifest problem from dependencies.

## 4. What I'd do once you have the account

1. Add the sandbox + mic entitlements and `PrivacyInfo.xcprivacy`.
2. Make the build universal (arm64 + x86_64) and wrap it for archiving.
3. Wire distribution signing with your certificates.
4. Capture App Store screenshots + draft all the listing text.
5. Generate a privacy policy page to host.
6. Walk you through the App Store Connect record and the upload.

Steps 1, 2, 4, 5 I can do **now** without your account (they just can't be
*submitted* until the account and signing exist). Say the word and I'll get
those in place so that the day your account is active, we're one upload away.
