#!/usr/bin/env python3
"""
Generate bigram TSV files from OpenSubtitles top sentences.

Source: https://github.com/orgtre/top-open-subtitles-sentences
License: OpenSubtitles data is CC-BY-SA-4.0

Downloads the top 10k sentences per language, extracts word bigrams,
and writes them in the format expected by PredictionEngine:
    prev_word\tnext_word\tlog_probability

Output: Tekla/Resources/bigrams_{lang}.tsv
"""

import csv
import io
import math
import re
import sys
import unicodedata
import urllib.request
from collections import defaultdict

BASE_URL = "https://raw.githubusercontent.com/orgtre/top-open-subtitles-sentences/main/bld/top_sentences/{lang}_top_sentences.csv"

LANGUAGES = ["en", "es", "fr", "de", "it", "pt", "nl", "sv", "da", "no", "fi", "pl", "tr", "ru"]

# Max bigrams per language (keeps bundle small)
MAX_BIGRAMS = 5000

# Minimum count to include a bigram
MIN_COUNT = 5

def strip_accents(s: str) -> str:
    """Remove accent marks from a string, preserving ñ and ü."""
    # Decompose, remove combining marks (except for ñ → keep tilde on n)
    result = []
    for char in s:
        if char in ('ñ', 'Ñ'):
            result.append(char)
            continue
        decomposed = unicodedata.normalize('NFD', char)
        # Keep only non-combining characters
        stripped = ''.join(c for c in decomposed if unicodedata.category(c) != 'Mn')
        result.append(stripped)
    return ''.join(result)


def is_alpha_word(w: str) -> bool:
    """Check if a word is alphabetic (works for all scripts: Latin, Cyrillic, etc.)."""
    return len(w) >= 2 and all(c.isalpha() for c in w)


def download_sentences(lang: str) -> list[tuple[str, int]]:
    """Download and parse the top sentences CSV for a language."""
    url = BASE_URL.format(lang=lang)
    print(f"  Downloading {url} ...")
    try:
        with urllib.request.urlopen(url, timeout=30) as resp:
            text = resp.read().decode("utf-8")
    except Exception as e:
        print(f"  ERROR downloading {lang}: {e}")
        return []

    sentences = []
    reader = csv.reader(io.StringIO(text))
    next(reader, None)  # skip header
    for row in reader:
        if len(row) >= 2:
            sentence = row[0].strip()
            try:
                count = int(row[1])
            except ValueError:
                continue
            sentences.append((sentence, count))
    return sentences


def extract_bigrams(sentences: list[tuple[str, int]]) -> dict[tuple[str, str], int]:
    """Extract word bigrams from sentences with their weighted counts."""
    bigrams: dict[tuple[str, str], int] = defaultdict(int)
    for sentence, count in sentences:
        # Clean sentence: remove punctuation, lowercase, split
        cleaned = re.sub(r'[^\w\s]', ' ', sentence.lower())
        words = cleaned.split()
        # Filter to alphabetic words, strip accents for consistency with unigram data
        words = [strip_accents(w) for w in words if is_alpha_word(w)]
        # Extract consecutive pairs
        for i in range(len(words) - 1):
            bigrams[(words[i], words[i + 1])] += count
    return bigrams


def write_bigram_tsv(bigrams: dict[tuple[str, str], int], output_path: str):
    """Write bigrams in PredictionEngine's expected format: prev\tnext\tlog_prob."""
    # Filter by minimum count
    filtered = {k: v for k, v in bigrams.items() if v >= MIN_COUNT}
    if not filtered:
        print(f"  WARNING: No bigrams passed the minimum count filter")
        return 0

    # Sort by count descending, take top N
    sorted_bigrams = sorted(filtered.items(), key=lambda x: x[1], reverse=True)[:MAX_BIGRAMS]

    # Compute total for normalization
    total = sum(count for _, count in sorted_bigrams)

    with open(output_path, "w", encoding="utf-8") as f:
        for (prev, next_word), count in sorted_bigrams:
            # Log probability: log(count / total)
            log_prob = math.log(count / total)
            f.write(f"{prev}\t{next_word}\t{log_prob:.6f}\n")

    return len(sorted_bigrams)


def main():
    import os
    script_dir = os.path.dirname(os.path.abspath(__file__))
    resources_dir = os.path.join(script_dir, "..", "Tekla", "Resources")
    os.makedirs(resources_dir, exist_ok=True)

    for lang in LANGUAGES:
        print(f"\n[{lang}] Processing...")
        sentences = download_sentences(lang)
        if not sentences:
            print(f"  Skipping {lang} — no data")
            continue
        print(f"  Downloaded {len(sentences)} sentences")

        bigrams = extract_bigrams(sentences)
        print(f"  Extracted {len(bigrams)} unique bigrams")

        output_path = os.path.join(resources_dir, f"bigrams_{lang}.tsv")
        count = write_bigram_tsv(bigrams, output_path)
        print(f"  Wrote {count} bigrams to {output_path}")


if __name__ == "__main__":
    main()
