# Changelog

All notable changes to Tekla are documented in this file.

## v1.5.1 — Add accessibility section to landing page

- Add "Built for Accessibility" section to landing page with 3 feature cards (motor accessibility, flexible input, fewer keystrokes)
- Localize accessibility section in all 14 languages

## v1.5.0 — Activation gate with unlock code

- Add activation window gating keyboard behind a license code on first launch
- ActivationView with code input, validation, shake animation on wrong code, and link to purchase page
- Persist unlock state in UserDefaults via SettingsManager
- "Enter License" menu bar item when not yet unlocked
- Show app in Dock during activation, switch to accessory mode after unlock
- Create GitHub Release with signed, notarized DMG

## v1.4.3 — Styled DMG installer

- Add custom dark gradient background image for DMG window
- Style DMG with AppleScript: 128px icons, app + Applications shortcut, no toolbar
- Update distribute.sh with DMG styling step

## v1.4.2 — Add Paddle checkout credentials

- Integrate Paddle client-side token and price ID into landing page checkout flow

## v1.4.1 — Add language picker to landing page

- Add globe icon language picker dropdown to navigation bar
- Support all 14 languages with manual switching
- Persist language choice in localStorage, auto-detect browser language on first visit

## v1.4.0 — Accessibility fixes, keyboard layout polish, prediction padding

- Fix Accessibility permission: remove debug bypass, disable App Sandbox, add continuous polling until granted
- Fix non-letter character input on non-US layouts (use Unicode injection instead of keycodes)
- Fix auto-capitalization after sentence-ending punctuation (. ? !)
- Add auto-space after sentence-ending punctuation
- Fix shift key stuck on after auto-capitalize (consume flag on first letter typed)
- Fix backspace activating shift (exclude auto-capitalize flag from action keys)
- Add space between typed word and subsequent swiped word
- Enter key always sends Return to OS (removed prediction-insert-on-Enter)
- Merge status bar icons (language picker, swipe indicator, settings) into prediction bar row
- Keyboard rows now form a flush rectangle (last key per row stretches to fill width)
- Increase Return key size in all language layouts (1.0 → 1.5)
- Fix bottom key clipping on window resize (proportional height calculation)
- Add bottom padding for symmetrical window spacing
- Always show full prediction count — pad with spell checker and frequency fallbacks
- Expand keyboard window automatically when switching to wider language layouts
- Rewrite PermissionsManager: remove debug bypass, add indefinite polling
- Rewrite SettingsWindowController: NSWindow → NSPanel, fix double onClose, self as delegate
- Remove dead code (ContentView.swift, matchSwipe, cancelSwipe)
- Fix NSSpellChecker thread safety (use @MainActor)
- Fix FileHandle closeFile() deprecation
- Replace usleep with sendRepeatedKeystroke for batch key events

## v0.4.0 — UI overhaul, localization, app icon, responsive keyboard

- Auto-capitalize predictions after sentence-ending punctuation (. ? !)
- Capitalize first word on keyboard open
- Key labels reflect shift/caps state (lowercase by default)
- Resolve shifted characters on non-English layouts (e.g., ? on Spanish keyboard)
- Fix apostrophe corrupting word prediction buffer
- Prediction bar: fix button overlap, remove dividers, proper background insets
- Settings: standalone movable window with horizontal category bar
- Settings: remove redundant dividers, tighter vertical spacing
- Localize all UI strings (13 languages via String Catalog)
- Add app icon at all 10 macOS sizes from custom artwork
- Responsive keyboard: keys fill available width, scale with window resize
- Height-constrained scaling prevents key clipping at default size
- Move status bar (language, swipe indicator, settings) to bottom of window
- Language indicator is now a picker menu (not a cycle button)
- Add horizontal padding between window borders and keys

## v0.3.0 — Bigram context, next-word prediction, smart punctuation, path order scoring

- Add bundled bigram data for all 14 languages (5000 bigrams each, extracted from OpenSubtitles sentence corpus)
- Add next-word prediction: after completing a word, the prediction bar shows bigram-predicted next words
- Add smart punctuation: typing . , ? ! ; : after an auto-inserted word+space deletes the trailing space
- Enable pathOrderScore as 8th Bayesian scoring channel (exponent 1.5) — measures letter order along swipe path
- Inject bigram completions into swipe prediction bar alternatives for contextually likely words
- Restructure swipe reranking: replace broken context normalization with explicit additive bigram bonus
- Add debug logging for typing predictions, prediction taps, next-word predictions, and smart punctuation

## v0.2.0 — Swipe accuracy overhaul: frequency data, Bayesian scoring fixes, feedback loop fix

- Bundle 50k-word frequency data for all 14 languages (OpenSubtitles 2018 corpus)
- Redesign distinct letter scoring with bidirectional coverage + precision term
- Fix length estimation: replace arc-based model with intentional-key-count + offset
- Fix accent-inherited frequency inflation: use geometric mean instead of max
- Fix re-ranker double-counting frequency: increase geometric weight to 70%
- Fix user learning feedback loop: cap bonus with log1p to prevent wrong predictions from becoming permanent
- Tune exponents: arcLength=1.5, frequency=0.5, length=1.5, distinct=1.0
- Tighten length window: upper margin +1, sigma=1.5

## v0.1.0 — Initial Commit

- Initial implementation of Tekla virtual keyboard for macOS
