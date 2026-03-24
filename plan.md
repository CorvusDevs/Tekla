# Plan: Bundled Word Frequency Data for All Languages

## Problem
The swipe engine relies on `PredictionEngine.wordFrequency()` to rank candidates, but most words (including common ones like "estante") have no frequency data. They fall through to a flat default score (`-5.0`), making common and rare words indistinguishable. This is the #1 remaining blocker for swipe accuracy.

## Source
**Hermit Dave's FrequencyWords** — OpenSubtitles 2018 corpus
- Repository: `github.com/hermitdave/FrequencyWords`
- License: CC-BY-SA-4.0 (content), MIT (code)
- Format: `word count` (space-separated, one per line)
- Coverage: All 14 supported languages available as `{lang}_50k.txt` (50k words each)

## Approach: Build-time Script + Bundled TSV Files

### Step 1: Download Script
Create a Swift script at `Scripts/download_frequencies.swift` that:
1. Downloads `{lang}_50k.txt` from the raw GitHub URL for each of our 14 languages
2. Converts from the source format (`word count`, space-separated) to our existing TSV format (`word\tcount`)
3. Filters: lowercase, letters-only, minimum 2 characters
4. Caps at 10,000 words per language (enough for swipe ranking; keeps bundle small)
5. Writes to `Tekla/Resources/freq_{lang}.tsv`

Languages: en, es, fr, de, it, pt, nl, sv, da, no, fi, pl, tr, ru

### Step 2: Add Resource Files to Xcode Project
- Create `Tekla/Resources/` group in the project
- Add all 14 `freq_{lang}.tsv` files to the bundle
- Files are ~100-200KB each (10k lines × ~15 bytes), total ~2MB

### Step 3: No Code Changes Needed in PredictionEngine
The existing `loadUnigrams(for:)` method already:
1. Checks for `freq_{languageCode}.tsv` in the bundle first
2. Falls through to NSSpellChecker harvest only if no file is found
3. Parses TSV format: `word\tfrequency`

So once the files are bundled, they'll be picked up automatically. The NSSpellChecker harvest becomes a dead fallback.

### Step 4: Verify
- Build the project
- Run the app, swipe "estante"
- Check debug log: estante should now have a real pFr value (not 0.1889)
- Common words like "estante" should rank above rare words like "estarse"/"estense"

## Why 10k Words Per Language?
- The swipe engine only scores candidates that pass geometric filtering (~30-50 words per swipe)
- Having frequency for the top 10k words covers the vast majority of everyday vocabulary
- Words outside the top 10k still get the NSSpellChecker `isKnownWord` fallback
- Keeps the bundle lightweight (~2MB total vs ~14MB for all 50k)

## File Format Example
```
the	69971
be	37919
of	36412
and	28946
```

## Files Changed
1. **New**: `Scripts/download_frequencies.swift` — One-time download + conversion script
2. **New**: `Tekla/Resources/freq_{lang}.tsv` × 14 — Bundled frequency data
3. **No changes** to PredictionEngine.swift, SwipeEngine.swift, or any existing code
