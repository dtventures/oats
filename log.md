# Oat — Session Log

---

## 2026-04-12

### Session 1
- Built full macOS floating panel app (GranolaFloat → renamed Oat)
- Granola API integration with 14-day note fetch + parallel loading
- Claude Haiku API for AI action item extraction (3-strategy fallback: structured parse → Claude → regex)
- TodoStore with Combine debounce persistence to ~/Library/Application Support/Oat/
- KeychainManager for API key storage (com.oat.app service)
- Floating NSPanel pinned top-right, single Space, cream UI
- Mock data with 6 meeting types for testing

## 2026-04-16 / 2026-04-17

### Session 4
- GitHub repo created at github.com/dtventures/oats (public)
- DMG built (ad-hoc signed) and uploaded as v1.0 release
- README with screenshot, features table, keyboard shortcuts, CLI docs, build instructions
- Landing page deployed to oats.dimitritrembois.com via Vercel
- Custom domain DNS added via Cloudflare (A record → 76.76.21.21)
- OG/social meta tags added: og:image (1200×630 branded), Twitter card, favicon
- Landing page hero screenshot replaced with clean panel mockup (no real names)
- Full mobile responsiveness pass: fixed padding shorthand bug (padding: 100px 0 overriding .wrap horizontal padding), 2-column feature grid on mobile, proper side buffers
- All landing page copy rewritten with real user language
- Gatekeeper install guide added (4 steps + xattr fallback)
- GitHub button with GitHub mark SVG added to hero

### Session 2
- Wired ClaudeAPI into ActionItemExtractor.extractAsync() with parallel task group in sync()
- Multi-step onboarding flow (Welcome → Granola Key → Claude Key → Profile)
- Demo mode: walks all 4 onboarding screens without requiring real inputs
- Oat bowl app icon converted to .icns from provided PNG
- AppSettingsView fixed to use Keychain (not AppStorage) for API keys; added Claude key + name fields
- ActionItemExtractor.currentUser reads from UserDefaults at runtime (falls back to mock)
- Sparkle 2.9.1 added for auto-updates; lazy init guards against crash outside .app bundle
- Info.plist, Oat.entitlements, Makefile for code signing + notarization pipeline
- Error banner in panel for sync failures with Retry button
- Re-run setup button in Settings via NotificationCenter → AppDelegate
- Traffic lights: shared hover state — all 3 icons appear when hovering any dot
- Forced .preferredColorScheme(.light) on ContentView + OnboardingView to fix dark mode rendering
- Renamed app from GranolaFloat to Oat throughout (bundle ID, Keychain service, persistence dir, binary)
