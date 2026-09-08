<p align="center">
  <img src="assets/logo.png" width="128" alt="Blitz logo">
</p>

# Blitz

A macOS menu bar utility that transforms selected text using AI. Select any text in any app, press a keyboard shortcut, choose a transformation, and the result replaces your selection — without leaving the app you're working in.

---

## Features

- **Global keyboard shortcut** — press ⌥Space (configurable) from anywhere to trigger Blitz
- **Floating overlay** — a lightweight panel appears near your selected text; dismisses automatically after transformation
- **Preview before replacing** — optionally review the AI result before it replaces your text, with the ability to retry or revise
- **AI-powered transformations** — Fix Grammar, Make Formal, Make Casual, Summarize, Translate to English, Optimized for Claude, and any custom scenarios you define
- **Multiple AI providers** — OpenAI (GPT-4o mini, GPT-4o, GPT-4.1, o4-mini), Google Gemini (2.0 Flash, 2.5 Flash, 2.5 Pro), and Apple's on-device Foundation Model (Apple Intelligence, no API key or network needed)
- **Custom scenarios** — add, edit, reorder, and delete your own transformation prompts
- **Replacement history** — every transformation is logged so you can review, copy, or delete past results from Settings
- **Automatic updates** — checks GitHub Releases for new versions and installs them in one click
- **Secure API key storage** — keys stored exclusively in the macOS Keychain, never in UserDefaults, plists, or source code
- **Menu bar access** — all scenarios and settings reachable from the menu bar icon

---

## Requirements

- macOS 26.5 or later
- An API key from OpenAI or Google Gemini (or both), or an Apple Intelligence–capable Mac
- Accessibility permission (System Settings → Privacy & Security → Accessibility)

---

## Installation

### Download (recommended)

1. Grab the latest `.dmg` from the [Releases](https://github.com/Rashid-505/Blitz/releases) page.
2. Open the `.dmg` and drag **Blitz.app** into `/Applications`.
3. Launch Blitz. Since the build isn't notarized, right-click the app → **Open** the first time (or **System Settings → Privacy & Security → Open Anyway**) to bypass Gatekeeper.
4. Blitz appears as a bolt icon in the menu bar.

### Build from source

1. Clone the repository:
   ```bash
   git clone https://github.com/Rashid-505/Blitz.git
   cd Blitz
   ```

2. Open `Blitz.xcodeproj` in Xcode 26.6 or later.

3. Select the **Blitz** scheme and build (`⌘B`).

4. Run the app (`⌘R`). Blitz will appear as a bolt icon in the menu bar.

---

## Setup

### 1. Grant Accessibility permission

Blitz uses the macOS Accessibility API to read and replace selected text. On first use, macOS will prompt you automatically. You can also enable it manually:

**System Settings → Privacy & Security → Accessibility → enable Blitz**

Without this permission, text reading and replacement will not work.

### 2. Add an API key

1. Click the Blitz icon in the menu bar → **Settings…** → **Providers** tab
2. Select your preferred provider (OpenAI or Google Gemini)
3. Choose a model
4. Paste your API key and click **Save**
5. Click **Test Connection** to verify the key works

API keys are stored in the macOS Keychain with `kSecAttrAccessible = WhenUnlocked` and are never synced to iCloud.

---

## Usage

### Keyboard shortcut (primary)

1. Select text in any supported app
2. Press **⌥Space** (Option + Space)
3. The Blitz overlay appears near your selection
4. Click a scenario to transform the text
5. If preview is enabled, review the result and click **Replace** to confirm — or **Retry** / **Discard**
6. The original text is replaced with the AI result and the overlay closes

Press **Escape** or click outside the overlay to dismiss without making changes.

### Menu bar

1. Select text in another app
2. Click the ⚡ icon in the menu bar
3. Click a scenario name
4. The text is transformed and replaced in place

---

## Configuring the keyboard shortcut

**Settings → General → Activation shortcut → Change**

Click **Change**, then press any key combination with at least one modifier key (⌘, ⌥, ⌃). The new shortcut takes effect immediately and persists across restarts.

---

## Managing scenarios

**Settings → Scenarios**

| Action | How |
|---|---|
| Enable / disable | Toggle switch on each row |
| Reorder | Drag the row to a new position |
| Edit name or instruction | Click **Edit** |
| Delete | Click the trash icon (any scenario, including built-ins) |
| Add custom | Click **Add Scenario** at the bottom |

If you delete all built-in scenarios, they are re-seeded on next launch.

### Built-in scenarios

| Scenario | What it does |
|---|---|
| Fix Grammar | Corrects grammar and punctuation without changing meaning |
| Make Formal | Rewrites text in a formal, professional tone |
| Make Casual | Rewrites text in a casual, conversational tone |
| Summarize | Produces a concise summary |
| Translate to English | Translates any language to English |
| Optimized for Claude | Restructures a draft prompt for use with Claude Code |

### Writing scenario instructions

The instruction field is the system prompt sent to the AI. Blitz appends the selected text as the user message. Tips:

- Be specific: *"Fix only grammar and punctuation. Do not change the meaning, tone, or wording."*
- End with: *"Return only the result, with no commentary or explanation."*
- The AI respects these constraints across all supported models.

---

## Automatic updates

Blitz checks GitHub Releases for newer versions. To check manually:

- **Menu bar** → **Check for Updates…**
- **Settings → General → Updates → Check for Updates**

When an update is available, click **Download & Install**. Blitz will:

1. Download the `.dmg` from GitHub Releases
2. Mount the disk image
3. Launch a background installer script
4. Quit itself — the script copies the new bundle over `/Applications/Blitz.app` and relaunches

No manual downloads or drag-and-drop needed.

---

## Settings reference

### General

| Setting | Description |
|---|---|
| Activation shortcut | Global hotkey to trigger the overlay. Click **Change** to record a new one. |
| Launch at login | Toggle whether Blitz starts automatically when you log in. |
| Preview before replacing | When on, shows the AI result in the overlay before committing the replacement. |
| Version | Displays the currently installed version. |
| Updates | Check for updates and install new releases in one click. |

### Scenarios

Full list of transformation scenarios. Reorder, edit, enable/disable, or delete any entry.

### Providers

| Setting | Description |
|---|---|
| AI Provider | Choose between OpenAI, Google Gemini, and Apple Intelligence. |
| Model | Select the specific model for the active provider. |
| API Key | Paste and save your API key. Stored in Keychain. |
| Test Connection | Makes a real API call to verify the key and model are working. |

### History

Lists all past transformations in reverse chronological order. Each entry shows the scenario name, timestamp, and a preview of the result. You can copy a result to the clipboard or delete individual entries. Use **Clear All History** to wipe the entire log.

---

## Application compatibility

| App | Keyboard shortcut | Menu bar |
|---|---|---|
| TextEdit | ✅ | ✅ |
| Notes | ✅ | ✅ |
| Xcode | ✅ | ✅ |
| Terminal | ✅ | ✅ |
| Mail | ✅ | ✅ |
| Safari | ✅ | ✅ |
| Chrome / Firefox | ✅ | ✅ |
| VS Code | ✅ | ✅ |
| Slack | ✅ | ✅ |

For browsers and Electron apps, the overlay position falls back to the mouse cursor location since these apps do not expose text position through the Accessibility API.

---

## Architecture

```
BlitzApp (App entry point)
│
├── GlobalShortcutManager        — Carbon RegisterEventHotKey, ⌥Space default
├── AccessibilityTextService     — AXUIElement read/write + CGEvent Cmd+V fallback
├── TransformationOrchestrator   — Pipeline: read → AI transform → preview → replace
├── BlitzOverlayPresenter        — NSPanel lifecycle, positioning, dismissal
├── UpdateChecker                — GitHub Releases API, DMG download, shell installer
│
├── Domain
│   ├── AIProvider (protocol)    — nonisolated transform(text:instruction:)
│   ├── ProviderStore            — Active provider + model, Keychain API keys
│   ├── ScenarioStore            — SwiftData CRUD, seeding, ordering
│   ├── PreviewSettings          — Preview-before-replace toggle, persisted
│   ├── ReplacementHistoryStore  — SwiftData log of past transformations
│   └── GlobalShortcutManager    — Shortcut registration + UserDefaults persistence
│
├── Infrastructure
│   ├── OpenAIProvider           — Chat Completions API, all models
│   ├── GeminiProvider           — generateContent API, URLComponents for key encoding
│   ├── AppleFoundationModelProvider — on-device FoundationModels framework
│   ├── PromptBuilder            — System + user prompt construction
│   ├── KeychainStore            — Security framework, kSecAttrSynchronizable = false
│   └── UpdateChecker            — GitHub API, URLSession download, hdiutil, bash installer
│
└── Features
    ├── MenuBar / MenuBarView    — MenuBarExtra (.menu style)
    ├── Overlay / BlitzOverlayView — SwiftUI panel content (idle/transforming/preview/failed)
    └── Settings                 — General, Scenarios, Providers, History tabs
```

### Key design decisions

**Global shortcut via Carbon `RegisterEventHotKey`**
The only mechanism that works without requiring Input Monitoring permission. `NSEvent.addGlobalMonitorForEvents` requires that permission for keyboard events; `RegisterEventHotKey` does not.

**Floating overlay via `NSPanel` with `.nonactivatingPanel`**
Clicking inside the panel does not steal focus from the active application, so the text selection in the user's app is preserved while the overlay is visible.

**Text reading/writing via AXUIElement**
`kAXSelectedTextAttribute` (read and write) works across all AppKit-based text fields. Falls back to a clipboard-based Cmd+V paste for apps that block direct AX writes.

**API keys in Keychain only**
`kSecAttrSynchronizable: kCFBooleanFalse` prevents iCloud Keychain sync. `kSecAttrAccessibleWhenUnlocked` ensures keys are available only when the screen is unlocked. Keys are never written to UserDefaults, plists, logs, or source code.

**Self-updating via detached installer script**
Because the app is not sandboxed, `hdiutil` and `Process` are available. After downloading a DMG, Blitz mounts it, writes a bash script that polls `kill -0 <PID>` to detect when the app has quit, then `cp -Rp`s the new bundle into place and relaunches. No SPM dependencies required.

**Overlay positioning fallback chain**
1. Selected text bounding rect via AX parameterized attribute (`kAXBoundsForRangeParameterizedAttribute`) — works in NSTextView apps
2. Focused element frame via `kAXPositionAttribute` + `kAXSizeAttribute` — wider support
3. Mouse cursor position — always available
4. Screen center — final fallback

---

## Project structure

```
Blitz/
├── Blitz.xcodeproj/
└── Blitz/
    ├── App/
    │   └── AppDelegate.swift
    ├── Domain/
    │   ├── AIProvider.swift             Protocol + ProviderID + ModelOption
    │   ├── AIError.swift                Typed error cases
    │   ├── GlobalShortcutManager.swift  Carbon hotkey, persistence
    │   ├── ProviderStore.swift          Active provider, model, Keychain access
    │   ├── PreviewSettings.swift        Preview toggle, @Observable
    │   ├── Scenario.swift               SwiftData model
    │   ├── ScenarioStore.swift          CRUD + seeding
    │   ├── BuiltInScenarios.swift       6 default scenario definitions
    │   ├── ReplacementEntry.swift       SwiftData model for history entries
    │   ├── ReplacementHistoryStore.swift  History CRUD, enabled toggle
    │   ├── TextService.swift            Protocols + error enum
    │   └── TransformationOrchestrator.swift
    ├── Features/
    │   ├── MenuBar/MenuBarView.swift
    │   ├── Overlay/BlitzOverlayView.swift
    │   └── Settings/
    │       ├── GeneralSettingsView.swift
    │       ├── ProvidersSettingsView.swift
    │       ├── ScenariosSettingsView.swift
    │       ├── ScenarioEditView.swift
    │       ├── HistorySettingsView.swift
    │       └── SettingsView.swift
    ├── Infrastructure/
    │   ├── Accessibility/AccessibilityTextService.swift
    │   ├── AI/
    │   │   ├── OpenAIProvider.swift
    │   │   ├── GeminiProvider.swift
    │   │   ├── AppleFoundationModelProvider.swift
    │   │   └── PromptBuilder.swift
    │   ├── Keychain/KeychainStore.swift
    │   ├── Overlay/
    │   │   ├── BlitzOverlayWindow.swift
    │   │   └── BlitzOverlayPresenter.swift
    │   └── Update/
    │       └── UpdateChecker.swift
    ├── BlitzApp.swift
    ├── Info.plist
    └── Blitz.entitlements
```

---

## Build settings reference

| Setting | Value | Reason |
|---|---|---|
| `GENERATE_INFOPLIST_FILE` | `NO` | Manual Info.plist used |
| `INFOPLIST_FILE` | `Blitz/Info.plist` | Points to the manual plist |
| `CODE_SIGN_ENTITLEMENTS` | `Blitz/Blitz.entitlements` | Explicit entitlements file |
| `ENABLE_APP_SANDBOX` | `NO` | Sandbox disabled — required for `hdiutil`, `Process`, and the self-update installer |
| `ENABLE_HARDENED_RUNTIME` | `YES` | Required for notarization |

---

## Known limitations

| Limitation | Detail |
|---|---|
| **Text position in browsers** | Chrome, Firefox, Safari, and Electron apps do not expose text selection coordinates through the Accessibility API. The overlay falls back to the mouse cursor position. |
| **Non-AppKit text fields** | Some apps use custom renderers that block AX attribute writes. Blitz falls back to a clipboard paste (Cmd+V). This temporarily modifies the clipboard and restores it after ~250 ms. |
| **Shortcut recording** | The shortcut recorder captures the first valid combination. There is no conflict detection against system shortcuts. If a chosen shortcut conflicts with another app, the system shortcut typically takes precedence. |
| **Update requires /Applications** | The self-update installer replaces the bundle at its current path. If Blitz is run from a location other than `/Applications`, the update will install there instead. |
| **Apple Intelligence availability** | The on-device Foundation Model provider requires an Apple Intelligence–capable Mac running macOS 26 or later. The option is hidden automatically if the capability is unavailable. |

---

## License

MIT License — see [LICENSE](LICENSE) for details.
