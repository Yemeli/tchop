# Tchop — Flutter Foundation Scaffold

> **Codename notice:** `tchop` is a *working codename* (from Cameroonian slang for
> "food"). **Rename before any public launch** — see *Codename → real name*
> checklist below. The rename touches the Dart package, Android
> `applicationId`/`namespace`, iOS bundle IDs, flavors, and docs.

Multi-tenant restaurant management + delivery platform for Cameroon/Africa.
One Flutter codebase, four role-specific app flavors, offline-first,
per-restaurant white-label theming at runtime.

---

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                        FLUTTER APP (one codebase)                │
│  flavors: customer · driver · kitchen · manager                  │
│  entrypoints: lib/main_<flavor>.dart  →  bootstrap(flavor)       │
├─────────────────────────────────────────────────────────────────┤
│  lib/app.dart                                                   │
│  └─ TchopApp ──► TenantBrandingScope (InheritedNotifier)        │
│                   └─ ListenableBuilder ──► MaterialApp          │
│                        theme = buildTchopTheme(active brand)     │
├──────────────┬──────────────────┬───────────────────────────────┤
│ core/        │ design_system/    │ features/                     │
│ ├─ flavor    │ ├─ tchop_colors  │ ├─ auth        (sign-in, OTP)  │
│ └─ branding/ │ ├─ tchop_typogr. │ ├─ customer    (storefront)    │
│    ├─ tenant │ ├─ tchop_theme   │ ├─ driver      (deliveries)    │
│    │  _brand │ └─ brand_widgets │ ├─ kitchen     (ticket board)  │
│    ├─ ctrl   │                  │ ├─ manager     (dashboard)     │
│    ├─ scope  │  data/           │ └─ payments    (BYO keys UI)   │
│    └─ switcher│ ├─ database/    │                               │
│              │ │  └─ drift tbls │  assets/tenant_sample.json     │
│              │ └─ sync/         │  └─ demo workspace brand      │
│              │    └─ outbox     │                               │
│              │       engine     │                               │
└──────────────┴──────────────────┴───────────────────────────────┘
                              │
        ┌─────────────────────┼─────────────────────┐
        ▼                     ▼                     ▼
  Supabase              MQTT broker            Firebase FCM
  (Postgres + RLS,      (driver GPS            (push; free)
   Realtime, Auth,       pings — transient,
   Storage, Edge Fns)    never DB writes)
```

**Key flows**

- **White-labeling:** `TenantBrandingController` loads `{name, logoUrl, colors}`
  brand JSON (pilot: `assets/tenant_sample.json`; prod: `GET /tenant`). Every
  screen reads `TenantBrandingScope.of(context)`; switching workspaces rebuilds
  the whole `MaterialApp` theme — no restart, one binary, N brands.
- **Offline-first:** Drift/SQLite is the on-device source of truth. Every write
  also lands in `outbox_entries` with a UUID idempotency key; `SyncEngine.drain()`
  replays oldest-first with exponential backoff. Server endpoints must be
  idempotent (`INSERT … ON CONFLICT DO NOTHING`).
- **Driver GPS:** streams over MQTT (tiny binary protocol, survives flaky
  networks). Only trip milestones (pickup/delivery) are persisted — never raw
  pings (50M msgs/mo would bankrupt the realtime budget).
- **Payments:** bring-your-own credentials. Each restaurant pastes its own
  MTN MoMo / Orange Money API keys in `PaymentConnectionsScreen`; keys are
  encrypted per-tenant server-side, shown masked (`•••• 9f2a`) in UI, and money
  settles directly into the restaurant's accounts. The platform never holds funds.

---

## Getting started

> **SDK status:** this scaffold was authored on a machine *without* the Flutter
> SDK (`flutter`/`dart` not on PATH), so `flutter pub get`, codegen and
> `flutter analyze` have **not** been run here. Run the steps below on a machine
> with Flutter ≥ 3.5 installed.

```bash
cd apps/tchop

# 1. Install dependencies
flutter pub get

# 2. Generate Drift code (creates lib/data/database/tchop_database.g.dart)
dart run build_runner build --delete-conflicting-outputs

# 3. Static analysis (must be clean before merging)
flutter analyze

# 4. Unit tests
flutter test
```

### Run a flavor (Android)

```bash
flutter run --flavor customer -t lib/main_customer.dart
flutter run --flavor driver   -t lib/main_driver.dart
flutter run --flavor kitchen  -t lib/main_kitchen.dart
flutter run --flavor manager  -t lib/main_manager.dart
```

### Build release APKs (split per ABI keeps each APK ~20 MB — matters at $1.63/GB)

```bash
flutter build apk --flavor customer -t lib/main_customer.dart --split-per-abi
flutter build apk --flavor driver   -t lib/main_driver.dart   --split-per-abi
flutter build apk --flavor kitchen  -t lib/main_kitchen.dart  --split-per-abi
flutter build apk --flavor manager  -t lib/main_manager.dart  --split-per-abi
# Web dashboards (manager/secretary):
flutter build web -t lib/main_manager.dart
```

`productFlavors` live in `android/app/build.gradle.kts` (`role` dimension).
Each flavor gets its own `applicationId` suffix and OS-visible app name.

### iOS flavors

`ios/Runner/` ships `AppDelegate.swift` + `Info.plist` as reference. To get a
buildable Xcode project on a Mac:

```bash
cd apps/tchop
flutter create --platforms=ios --org cm.tchop --project-name tchop .
```

then create **four Xcode schemes** (customer/driver/kitchen/manager), each
passing `--dart-define=FLAVOR=<flavor>` — `lib/main.dart` resolves it via
`resolveFlavor()`. Per Apple Guideline 4.2.6, ship the customer app as the
single-binary "picker" (branded storefronts inside); per-restaurant native apps
are a premium upsell under the restaurant's own Apple Developer account.

### Platform support matrix

| Platform | Status | Notes |
|---|---|---|
| Android | ✅ flavors (customer/driver/kitchen/manager) | `productFlavors`, `role` dimension |
| iOS | 🟡 reference only | `AppDelegate.swift` + `Info.plist`; regen on a Mac (see above) |
| Web | ✅ scaffolded | PWA manifest + icons; manager flavor is the primary web target |
| Windows | ✅ scaffolded | runner, app name "Tchop" |
| macOS | ✅ scaffolded | bundle id `cm.tchop.app` |
| Linux | ✅ scaffolded | CMake build |

The `web/`/`windows/`/`macos/`/`linux/` folders were hand-authored from the
Flutter template (no SDK on the authoring machine — the macOS `.pbxproj` in
particular should be diffed against a regen). Verify/regenerate with:

```bash
cd apps/tchop
./tool/verify_platforms.sh          # dry-run: prints the commands
./tool/verify_platforms.sh --run    # executes: flutter create regen + builds
```

### Build per platform

```bash
# Web (PWA)
flutter build web -t lib/main_manager.dart
# Desktop — run on the target OS
flutter build windows -t lib/main_manager.dart
flutter build macos   -t lib/main_manager.dart
flutter build linux   -t lib/main_manager.dart
```

Any flavor entrypoint works — swap `-t lib/main_<flavor>.dart`
(customer/driver/kitchen/manager).

### Responsive design

`lib/core/responsive.dart` — breakpoints **mobile <600 / tablet 600–1100 /
desktop ≥1100**; `ResponsiveLayout(mobile:, tablet:, desktop:)`;
`context.isMobile/isTablet/isDesktop`;
`context.responsiveValue(mobile:, tablet:, desktop:)` (tablet falls back to
mobile, never desktop); `CenteredContent` (caps width on wide screens);
`showResponsiveDialog` (Escape closes dialogs on desktop/web).

`lib/core/adaptive_scaffold.dart` — app shell: bottom `NavigationBar` on
phones, `NavigationRail` on tablet/desktop (extended rail on desktop); a
single destination renders with no chrome. Customer/kitchen/manager flavor
homes are migrated to it; each destination keeps its own AppBar.

App-wide: mouse/trackpad drag scrolling (`TchopScrollBehavior`), desktop
windows open at 1280×800 via `window_manager` (platform-guarded in
`bootstrap.dart`), and OS text scaling is clamped to 0.85–1.25× so huge
font sizes can't break layouts.

### Build-time configuration (`--dart-define`)

No secrets are ever hardcoded. Pass these at build/run time:

| Key | Used by | Default / behavior when absent |
|---|---|---|
| `SUPABASE_URL` / `SUPABASE_ANON_KEY` | backend client | empty → offline degraded mode |
| `FLAVOR` | flavor entrypoint | `customer` |
| `MQTT_BROKER_URL` | driver GPS streaming (Feature 6) | `wss://demo.tchop.local/mqtt` (documented "unset" placeholder) → the app uses the clearly-labeled **SIMULATION** stream; the customer tracking screen works against either source |
| `MAPS_API_KEY` | customer live-tracking map (Feature 6) | empty → graceful `MapPlaceholder` ("Carte indisponible — clé API manquante") with pins list + status timeline, so the screen is never broken |

Example:

```bash
flutter run --flavor driver -t lib/main_driver.dart \
  --dart-define=SUPABASE_URL=https://xyz.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=eyJ... \
  --dart-define=MQTT_BROKER_URL=wss://mqtt.example.com/mqtt \
  --dart-define=MAPS_API_KEY=AIza...
```

---

## What's stubbed (TODOs in code)

| Area | Status | Next step |
|---|---|---|
| `TenantBrand` / theming / workspace switcher | ✅ working (sample JSON) | fetch brand JSON from `GET /tenant` |
| Role screens (4) | ✅ render w/ brand | wire to Realtime streams |
| Payments UI (BYO keys) | ✅ UI shell | backend vault + connect flows |
| Drift schema (`tenants`, `menu_snapshots`, `orders`, `outbox_entries`) | ✅ defined | run codegen; add `MigrationStrategy` |
| `SyncEngine` (outbox + idempotency + backoff) | ✅ skeleton | implement `_deliver()` → Supabase Edge Fn |
| Supabase Auth (OTP) | ❌ | `supabase_flutter` sign-in + workspace picker |
| Menu studio (draft→publish, dayparts, 86) | ❌ | versioned snapshots UI |
| Dispatch (map, MQTT, PoD) | ✅ Feature 6 (compile-plausible) | live broker URL, Maps key, Android foreground-service manifest |
| Rive animations / 3D dish viewer | ❌ | add `assets/rive/*.riv` (budget <500 KB each) |
| Fonts (Fraunces / Plus Jakarta Sans) | ❌ | add files or `google_fonts` package |
| Google Maps API key | ❌ | per-flavor key in `AndroidManifest` / iOS plist |

---

## Codename → real name checklist

- [ ] `pubspec.yaml`: `name: tchop` → real package name
- [ ] `android/app/build.gradle.kts`: `namespace` + `applicationId` (`cm.tchop.app`)
- [ ] `MainActivity.kt` package + `AndroidManifest.xml`
- [ ] iOS bundle identifiers per scheme
- [ ] `AppFlavor.appLabel` strings in `lib/core/flavor.dart`
- [ ] `TenantBrand.fallback()` name
- [ ] This README + all docs

---

## Roadmap checklist

- [ ] **Auth** — Supabase phone OTP, session storage, workspace picker
- [ ] **Tenant onboarding** — signup → workspace provisioning → brand setup → subdomain
- [ ] **Menu studio** — items/recipes, prices (RBAC), draft→review→publish, dayparts, 86 toggle, versioned snapshots
- [ ] **Orders** — intake (app/WhatsApp/phone/walk-in), state machine, KDS realtime
- [ ] **Dispatch** — driver assignment, MQTT GPS, live customer map, proof of delivery
- [ ] **Payments** — BYO MoMo/Orange keys vault, aggregator fallback, reconciliation, refunds
- [ ] **Manager analytics** — sales, staff, inventory alerts, audit log
- [ ] **Super-admin** (platform owner) — tenants, MRR, per-restaurant GMV (read-only)
- [ ] **Hardening** — lite mode (<3 GB RAM), reduced-motion, APK <40 MB, battery-optimization onboarding (TECNO/Infinix/Xiaomi)
- [ ] **Pilot** — 10–20 restaurants, Douala + Yaoundé

---

## Conventions

- French-first UI copy (locale `fr_CM`), English fallback.
- `TODO:` comments mark every stub — no silent pseudocode in `.dart` files.
- Brand tokens only from `TenantBrand`; functional colors stay in `TchopColors`.
- APK budget: **<40 MB** hard ceiling; split-per-ABI for releases.
