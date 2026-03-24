# Project Guidelines — Tekla (macOS Virtual Keyboard)

## Error Handling & Empty States

- **Always handle errors gracefully and visually.** Never let a failed permission check, missing resource, or unexpected state result in a frozen UI or silent failure. Show the user a clear, friendly message with guidance on how to resolve it (e.g., "Grant Accessibility permission in System Settings").

- **Failures should be shown gracefully, not hidden.** Use `ContentUnavailableView` or equivalent visual error states with icons, short messages, and actionable guidance. Avoid swallowing errors silently with bare `try?` unless the context already handles partial-data display.

- **Never allow silent failures on user-initiated actions.** Any action the user triggers — toggling the keyboard, changing layout, switching language, resizing — must use `do/catch` (never bare `try?`). On failure: roll back any optimistic UI update and show a visible error message. The user must always know when something they did failed. `try?` is only acceptable for background reads, prefetches, and non-critical operations.

## SwiftUI & AppKit Patterns

- **Avoid Combine entirely.** Use Swift concurrency (`async/await`, `AsyncStream`) and native SwiftUI constructs (`TimelineView`, `.task`, `.refreshable`) instead. No `Timer.publish`, no `@Published`, no `sink`. The project uses `@Observable` macro, not `ObservableObject`.

- **Break up large SwiftUI body expressions.** If a view's `body` exceeds ~200 lines, extract sections into `@ViewBuilder` private computed properties. Swift's type checker fails with "unable to type-check this expression in reasonable time" on very large bodies.

- **Use NSPanel for the keyboard window.** The keyboard must use `NSPanel` with `.nonactivatingPanel` style mask, set during `init`. Never use `NSWindow` — it steals focus from the target app. `canBecomeKey` must return `true`, `canBecomeMain` must return `false`.

- **Window level management.** The keyboard panel uses `.floating` level. Prediction/suggestion overlays use a level above floating (e.g., custom level above `.floating`). Use `.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]` so the keyboard appears on all Spaces and over full-screen apps.

- **CGEvent for keystroke injection.** Always use `CGEvent` with `.cgSessionEventTap` for posting keystrokes. Never attempt `NSEvent` injection to other apps. Use `keyboardSetUnicodeString` for non-ASCII characters. Mark synthetic events with `.eventSourceUserData` to distinguish from physical keystrokes.

## Localization

- **Localize every user-facing string.** Wrap all new text in `String(localized:)`. This includes button labels, empty-state messages, error descriptions, section headers, and any text the user sees. Never use bare string literals in views.

## Workflow

- **Never assume the user hasn't rebuilt.** When the user reports a bug, they have already rebuilt and rerun the app. Never suggest "try rebuilding" or blame stale builds. The error is real — investigate the actual root cause immediately.

- **Never delete major features without explicit user agreement.** If a feature is broken or non-functional, fix it — don't remove it. Before deleting any user-facing view, service, model, or significant code path, confirm with the user that deletion (rather than repair) is what they want.

- **Read all related files before making changes.** When fixing a system (e.g., prediction engine, keyboard layout), read the full chain: model → engine → view model → view. Understanding the complete data flow prevents fixes that break something downstream.

## Verification

- **Build and render preview after UI changes.** After modifying or creating any SwiftUI view, always run `BuildProject` to verify zero compilation errors. If the view has a `#Preview` macro, also run `RenderPreview` to capture a screenshot and visually verify the layout looks correct.

- **Check code issues for fast feedback.** When making changes to a single Swift file, use `XcodeRefreshCodeIssuesInFile` for rapid validation before doing a full build. This catches type errors, missing imports, and API misuse in seconds.

## Client-First / Offline-First Architecture

- **Everything runs locally.** This is a fully offline app. No network calls, no cloud services, no telemetry. All prediction models, dictionaries, user data, and preferences are stored on-device using UserDefaults, SwiftData/SQLite, or flat files. Never add any network dependency.

- **Minimal resource footprint.** The keyboard must be lightweight on CPU and memory. Avoid unnecessary background processing, polling, or timer-driven updates. Use event-driven architecture — only compute when the user acts. Profile regularly with Instruments to ensure the keyboard doesn't impact system performance.

- **Data stays on device.** User typing patterns, learned words, prediction models, and preferences never leave the Mac. There is no sync, no analytics, no crash reporting that phones home. Privacy is a core feature.

## Haptics & Sounds

- **Add audio feedback for key presses.** Key taps should have optional audio feedback that mimics physical keyboard sounds. Respect user preferences — provide a toggle and volume control. Use `NSSound` or `AVAudioPlayer` with pre-loaded short audio clips for minimal latency.

## Accessibility

- **VoiceOver support.** Every interactive element must have a meaningful accessibility label. Keys should announce their character/function. Group related elements where appropriate.

- **Dynamic Type.** Key labels and UI text must scale with the user's preferred text size where feasible. Use text styles (`.font(.body)`) rather than fixed sizes.

- **Minimum tap targets.** All interactive elements must have a minimum 44x44pt hit area per Apple HIG, even if the visual element is smaller.

- **Color is not the only indicator.** Never use color alone to convey meaning. Pair color with icons, labels, or shape changes.

- **Reduce Motion.** Respect `@Environment(\.accessibilityReduceMotion)`. When the user has enabled Reduce Motion, skip or simplify animations.

## UI/UX Design — Apple HIG

- **System controls and materials.** Prefer SwiftUI system controls over custom implementations. Use `.ultraThinMaterial`, `.regularMaterial`, etc. for overlays and bars instead of hard-coded semi-transparent colors.

- **Typography.** Use Dynamic Type text styles instead of fixed font sizes. Only use fixed sizes for decorative elements where scaling would break layout.

- **Color and contrast.** Use semantic colors (`.primary`, `.secondary`, `Color(.windowBackgroundColor)`) that automatically adapt to light/dark mode. Ensure at least 4.5:1 contrast ratio for body text and 3:1 for large text.

- **Layout.** Use `LazyVStack`/`LazyHStack` for large key collections where appropriate. Support both light and dark appearances.

## Energy Efficiency

- **Efficient animations.** Prefer SwiftUI's built-in animation system over manual timer-driven frame updates. Avoid animating offscreen content. Use `withAnimation` scoped to only the properties that need to change.

- **Minimize background work.** Don't schedule unnecessary background tasks or timers. The keyboard should be effectively idle when not being interacted with. CGEventTap callbacks should be fast and non-blocking.

## Permissions

- **Request permissions at the right time.** Accessibility permission is required for CGEventPost. Request it on first launch with a clear explanation of why it's needed. Never request permissions without context. Guide the user to System Settings if needed.

- **Handle permission denial gracefully.** If the user denies Accessibility permission, show a clear explanation of what won't work and how to grant it later. Never crash or show a blank screen.

## Debugging

- **Add debug logging when a problem persists.** When a bug is reported and the root cause isn't immediately clear, add targeted debug logging to the relevant code path (e.g., scoring, prediction, input handling) before attempting a fix. Write to the shared debug log at `SwipeEngine.debugLogURL` so all events appear in one file. Always ask the user to reproduce with logging enabled.

- **Clean up debug logging when the problem is fixed.** Once a bug is resolved, review any debug logging added during investigation. Remove verbose or temporary traces that are no longer needed. Keep only logging that provides ongoing diagnostic value (e.g., per-swipe scoring summaries, prediction pipeline traces).

- **Always read the debug log before diagnosing.** When the user reports incorrect behavior (wrong prediction, bad ranking, missing word), read `swipe_debug.log` first. Don't guess at causes — the log contains the actual scoring breakdown and pipeline data. Base your analysis on what the numbers show.

## Data Quality

- **Sanity-check bundled data files.** When adding or regenerating frequency, bigram, or other statistical data, always spot-check the output for the target language. Verify that common phrases rank highly (e.g., "hola como estas" in Spanish). Corpus bias (e.g., TV subtitles overrepresenting "cariño" and "papa") can silently degrade the user experience.

- **Verify the full pipeline end-to-end.** After adding a new scoring channel, data source, or prediction method, trace through the entire pipeline: data loading → scoring → reranking → display. Code that exists but is never called (dead code) is an invisible bug. Build, run, and check the debug log to confirm the new signal actually appears in the output.

## Commits

- **Always update the changelog when committing.** Every commit message should follow the pattern `vX.Y.Z — Summary` and include a bulleted list of what changed.
