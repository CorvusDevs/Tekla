#!/usr/bin/env python3
"""
Generate word frequency and bigram data from Wikipedia for all 14 Tekla languages.
Uses HuggingFace datasets to stream Wikipedia articles.

Output format matches existing Tekla TSV files:
  freq_XX.tsv:    word\tcount
  bigrams_XX.tsv: word1\tword2\tlog_prob
"""

import re
import math
import os
import sys
from collections import Counter

# Map Tekla language codes to Wikipedia language codes
LANGUAGES = {
    "en": "en",
    "es": "es",
    "de": "de",
    "fr": "fr",
    "pt": "pt",
    "it": "it",
    "nl": "nl",
    "sv": "sv",
    "no": "no",   # Norwegian Bokmål = "no" in Wikipedia
    "da": "da",
    "fi": "fi",
    "tr": "tr",
    "pl": "pl",
    "ru": "ru",
}

# How many articles to process per language (20k gives excellent coverage while being fast)
ARTICLES_PER_LANG = 20_000
MAX_FREQ_WORDS = 50_000
MAX_BIGRAMS = 5_000

# Simple word pattern: letters (including accented), apostrophes within words
WORD_RE = re.compile(r"[^\W\d_]+(?:'[^\W\d_]+)*", re.UNICODE)

# Filter: skip very short or very long words, and words that are all uppercase (acronyms)
def is_valid_word(w):
    return 2 <= len(w) <= 30 and not w.isupper()

def process_language(lang_code, wiki_code, output_dir):
    """Process one language: stream Wikipedia, count words and bigrams."""
    from datasets import load_dataset

    print(f"\n{'='*60}")
    print(f"Processing: {lang_code} (Wikipedia: {wiki_code})")
    print(f"{'='*60}")

    word_counts = Counter()
    bigram_counts = Counter()
    total_words = 0

    try:
        # Use the 20231101 dump
        ds = load_dataset(
            "wikimedia/wikipedia",
            f"20231101.{wiki_code}",
            split="train",
            streaming=True,
        )
    except Exception as e:
        print(f"  ERROR loading dataset for {wiki_code}: {e}")
        return False

    for i, article in enumerate(ds):
        if i >= ARTICLES_PER_LANG:
            break

        if i % 10000 == 0 and i > 0:
            print(f"  {lang_code}: processed {i} articles, {total_words} words so far...")

        text = article.get("text", "")
        if not text:
            continue

        words = [w.lower() for w in WORD_RE.findall(text) if is_valid_word(w)]
        total_words += len(words)

        for w in words:
            word_counts[w] += 1

        for j in range(len(words) - 1):
            bigram_counts[(words[j], words[j + 1])] += 1

    print(f"  {lang_code}: finished — {total_words} total words, {len(word_counts)} unique words, {len(bigram_counts)} unique bigrams")

    if total_words == 0:
        print(f"  WARNING: no words found for {lang_code}, skipping")
        return False

    # Write frequency file
    freq_path = os.path.join(output_dir, f"freq_{lang_code}.tsv")
    top_words = word_counts.most_common(MAX_FREQ_WORDS)
    with open(freq_path, "w", encoding="utf-8") as f:
        for word, count in top_words:
            f.write(f"{word}\t{count}\n")
    print(f"  Wrote {len(top_words)} words to {freq_path}")

    # Write bigram file (log probabilities)
    bigram_path = os.path.join(output_dir, f"bigrams_{lang_code}.tsv")
    top_bigrams = bigram_counts.most_common(MAX_BIGRAMS)

    # Compute log probability: log(P(w2|w1)) = log(count(w1,w2) / count(w1))
    with open(bigram_path, "w", encoding="utf-8") as f:
        for (w1, w2), count in top_bigrams:
            w1_count = word_counts.get(w1, 1)
            log_prob = math.log10(count / w1_count)
            f.write(f"{w1}\t{w2}\t{log_prob:.6f}\n")
    print(f"  Wrote {len(top_bigrams)} bigrams to {bigram_path}")

    return True


def main():
    output_dir = os.path.join(os.path.dirname(__file__), "..", "Tekla", "Resources")
    output_dir = os.path.abspath(output_dir)
    print(f"Output directory: {output_dir}")
    os.makedirs(output_dir, exist_ok=True)

    # Allow processing a single language via CLI arg
    if len(sys.argv) > 1:
        langs = {k: v for k, v in LANGUAGES.items() if k in sys.argv[1:]}
        if not langs:
            print(f"Unknown language(s): {sys.argv[1:]}. Available: {list(LANGUAGES.keys())}")
            sys.exit(1)
    else:
        langs = LANGUAGES

    results = {}
    for lang_code, wiki_code in langs.items():
        success = process_language(lang_code, wiki_code, output_dir)
        results[lang_code] = success

    print(f"\n{'='*60}")
    print("Results:")
    for lang, ok in results.items():
        status = "OK" if ok else "FAILED"
        print(f"  {lang}: {status}")
    print(f"{'='*60}")


if __name__ == "__main__":
    main()
