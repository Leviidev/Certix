# Signet

**Signet** is a native iOS 16+ app for signing and installing IPA files using your own developer certificates — no Apple ID or Mac required at runtime.

## Features

- **Certificate Management** — Import `.p12` certificates with optional `.mobileprovision` profiles. View expiry status, team info, and certificate details.
- **IPA Library** — Import and manage IPA files. Automatically extracts app name, bundle ID, version, and icon.
- **On-Device Signing** — Re-signs IPA files using your imported certificates directly on the device. Supports both RSA and ECDSA keys.
- **OTA Installation** — Starts a local HTTP server to serve the signed IPA via the `itms-services://` protocol, triggering iOS's native install dialog.
- **iOS 26 UI** — Uses Liquid Glass effects (`glassEffect()`) when running on iOS 26+, with a clean iOS 16 fallback using materials.

## Requirements

- iOS 16.0 or later
- A valid Apple developer certificate (`.p12` file with password)
- Optionally a provisioning profile (`.mobileprovision`)

## How It Works

### 1. Import Your Certificate

Export your developer certificate from **Keychain Access** on macOS:
1. Open Keychain Access
2. Find your certificate under "My Certificates"
3. Right-click → Export → Choose `.p12` format
4. Set a strong password

Import it into Signet via the **Certificates** tab.

### 2. Import an IPA

Tap **+** in the **Apps** tab and select an `.ipa` file from Files or any file-sharing app.

### 3. Sign the App

- Go to an IPA → tap **Sign** (or swipe left)
- Select your certificate
- Tap **Sign App**
- Signet will: extract the IPA, replace the provisioning profile, re-sign all binaries, and repackage

### 4. Install

After signing:
1. Tap **Install on This Device**
2. Safari opens with iOS's native install prompt: *"website.com would like to install Signet"*
3. Tap **Install**
4. Go to **Settings → General → VPN & Device Management** → Trust the certificate

> **Note:** OTA installation via `itms-services://` requires HTTPS for remote servers. The local server works over HTTP only for same-device installation.

## Building

### Prerequisites

- Xcode 15.4 or later
- Apple Developer account (for device deployment)

### Local Build

```bash
open Signet/Signet.xcodeproj
```

Select your team in **Signing & Capabilities**, then build and run on your device.

### GitHub Actions CI

The included workflow (`.github/workflows/build.yml`) builds an unsigned IPA on every push to `main`.

For signed builds, add these repository secrets:

| Secret | Description |
|--------|-------------|
| `P12_BASE64` | Base64-encoded `.p12` certificate |
| `P12_PASSWORD` | Certificate password |
| `KEYCHAIN_PASSWORD` | Temporary keychain password |

Generate the Base64 secret:
```bash
base64 -i certificate.p12 | tr -d '\n'
```

The workflow produces an IPA artifact downloadable from the Actions tab.

## Architecture

```
Signet/
├── Models/
│   ├── Certificate.swift         # Certificate data model
│   ├── ProvisioningProfile.swift # Profile parsing
│   ├── IPAFile.swift             # IPA metadata model
│   └── SigningJob.swift          # Signing job state
├── Services/
│   ├── AppStore.swift            # Central ObservableObject store
│   ├── CertificateService.swift  # P12 import & identity extraction
│   ├── IPAService.swift          # IPA import & metadata extraction
│   ├── SigningService.swift      # Signing orchestration
│   ├── ZipService.swift          # ZIP read/write (via libz)
│   ├── MachOSigner.swift         # Mach-O binary re-signing
│   ├── DEREncoder.swift          # DER/CMS encoding for signatures
│   └── OTAServer.swift           # Local HTTP server for OTA install
├── Views/
│   ├── HomeView.swift            # Dashboard
│   ├── CertificatesView.swift    # Certificate management
│   ├── IPAsView.swift            # IPA library
│   ├── SigningView.swift         # Signing sheet
│   ├── InstallView.swift         # OTA installation
│   ├── SettingsView.swift        # Settings & about
│   └── Components/
│       ├── GlassCard.swift       # iOS 26 glass card (w/ fallback)
│       ├── StatusBadge.swift     # Status pill badges
│       └── EmptyStateView.swift  # Empty state placeholder
├── ZipCompression.c              # libz wrapper for raw DEFLATE
└── Signet-Bridging-Header.h      # ObjC/C bridging header
```

## Technical Details

### Signing Pipeline

1. **Import P12** → `SecPKCS12Import` → `SecIdentity`
2. **Unzip IPA** → Custom ZIP parser using raw DEFLATE (libz)
3. **Replace profile** → Write `embedded.mobileprovision`
4. **Build CodeDirectory** → SHA-256 hashes of all 4096-byte code pages
5. **Build Requirements blob** → Empty requirements
6. **Build Entitlements blob** → From provisioning profile
7. **CMS Sign** → DER-encoded PKCS#7 SignedData via `SecKeyCreateSignature`
8. **Write SuperBlob** → `LC_CODE_SIGNATURE` section in Mach-O
9. **Rezip IPA** → DEFLATE compressed ZIP

### iOS 26 UI

Uses `@available(iOS 26, *)` checks throughout:
- `GlassCard` uses `.glassEffect()` on iOS 26+, `.ultraThinMaterial` on iOS 16+
- Tab bar inherits system glass styling on iOS 26+

## License

MIT License — see [LICENSE](LICENSE) for details.

## Disclaimer

This tool is intended for developers to install their own apps on their own devices. Always respect software licenses and Apple's terms of service.
