"""
Lesson 13 -- Text Analysis SDK Bookend
=======================================
Course:  Exam AI-901 -- Microsoft Azure AI Fundamentals (Video)
LOs:     2.2.1 (call Azure AI Language from client code; entities, key phrases,
         sentiment + opinion mining, extractive vs. abstractive summarization)
Goal:    Run four language skills in sequence so learners see the SDK
         class + method pairs the exam tests on code-fill questions.

The method map to memorize (the exam tests these by name):
    Entities      ->  TextAnalyticsClient.recognize_entities()
    Key phrases   ->  TextAnalyticsClient.extract_key_phrases()
    Sentiment     ->  TextAnalyticsClient.analyze_sentiment(show_opinion_mining=True)
    Summarize     ->  client.begin_extract_summary()    # verbatim sentences
                      client.begin_abstract_summary()   # novel paraphrase
    (The begin_ methods are long-running -- they return a poller; call
     .result() to get the output. Extractive pulls source sentences for
     traceability; abstractive writes new text for readability.)

Auth -- KEYLESS (Lesson 13 teaches the keyless pattern):
    TextAnalyticsClient accepts a token credential as well as a key. We use
    DefaultAzureCredential so the same code authenticates as your `az login`
    locally and as a managed identity in Azure -- no key in the file. The
    Language endpoint MUST use a custom subdomain for Entra/keyless auth,
    which Deploy-Lesson13-Infrastructure.ps1 provisions (--custom-domain).
    The signed-in identity needs the "Cognitive Services User" role.

How to run:
    python -m venv .venv
    .venv\\Scripts\\Activate.ps1           # Windows
    # source .venv/bin/activate           # macOS/Linux
    pip install -r requirements.txt
    cp .env.example .env                  # paste LANGUAGE_ENDPOINT only (no key)
    az login                              # if not already signed in
    python lesson-13-text-analytics.py
"""

from __future__ import annotations

import os
import sys

from azure.ai.textanalytics import TextAnalyticsClient
from azure.identity import DefaultAzureCredential
from dotenv import load_dotenv

# ---------------------------------------------------------------------------
# 1. Configuration -- endpoint only. Keyless auth means there is no key to
#    load, leak, or rotate. override=True keeps this lesson's .env authoritative.
# ---------------------------------------------------------------------------
load_dotenv(override=True)

LANGUAGE_ENDPOINT = os.environ.get("LANGUAGE_ENDPOINT")

if not LANGUAGE_ENDPOINT:
    sys.exit(
        "Missing LANGUAGE_ENDPOINT. Copy .env.example to .env and paste the "
        "custom-subdomain endpoint of your Language resource. "
        "No key needed -- auth is keyless (DefaultAzureCredential)."
    )

# ---------------------------------------------------------------------------
# 2. Build the client. ONE class -- TextAnalyticsClient -- backs every skill
#    below. The credential is DefaultAzureCredential, not AzureKeyCredential:
#    the only line that differs from the key-based pattern in Lesson 5.
#
#    Credential guard: on a dev laptop, stray environment variables can make
#    DefaultAzureCredential try a service principal or managed identity first
#    and fail with a confusing 401. We clear those derailers and exclude managed
#    identity so the chain lands on the Azure CLI credential -- whoever ran
#    `az login`. Remove this block in production, where managed identity SHOULD win.
# ---------------------------------------------------------------------------
for _derailer in ("AZURE_TOKEN_CREDENTIALS", "AZURE_CLIENT_ID",
                  "AZURE_CLIENT_SECRET", "AZURE_TENANT_ID"):
    os.environ.pop(_derailer, None)

client = TextAnalyticsClient(
    endpoint=LANGUAGE_ENDPOINT,
    credential=DefaultAzureCredential(exclude_managed_identity_credential=True),
)

# The same customer review the Flask web app (demo/webapp/) analyzes -- identical
# input on purpose so the SDK output echoes what you see in the web UI.
REVIEW = (
    "I flew Contoso Air from Seattle to Munich on March 12, 2026. The "
    "check-in agent at SEA was wonderful and the Premium Economy meal was the "
    "best I have had on any transatlantic flight this year. Unfortunately the "
    "in-flight Wi-Fi was a disaster -- it dropped three times and the support "
    "chat just kept apologizing. The Munich arrivals lounge was filthy too. I "
    "will probably fly Contoso Air again, but they must fix the Wi-Fi."
)


def demo_entities() -> None:
    """recognize_entities() -- named entities typed as Python objects."""
    print("\n" + "=" * 72)
    print(" Entities  ->  recognize_entities()")
    print("=" * 72)
    result = client.recognize_entities(documents=[REVIEW])[0]
    if result.is_error:
        print(f"  Error: {result.error}")
        return
    for e in result.entities:
        print(f"  {e.text:<22} category={e.category:<14} score={e.confidence_score:.2f}")


def demo_key_phrases() -> None:
    """extract_key_phrases() -- the topic words, no scores, just the phrases."""
    print("\n" + "=" * 72)
    print(" Key phrases  ->  extract_key_phrases()")
    print("=" * 72)
    result = client.extract_key_phrases(documents=[REVIEW])[0]
    if result.is_error:
        print(f"  Error: {result.error}")
        return
    print("  " + " | ".join(result.key_phrases))


def demo_sentiment() -> None:
    """analyze_sentiment(show_opinion_mining=True) -- document label plus the
    aspect-based target/assessment pairs the exam asks about by name."""
    print("\n" + "=" * 72)
    print(" Sentiment + opinion mining  ->  analyze_sentiment(show_opinion_mining=True)")
    print("=" * 72)
    result = client.analyze_sentiment(documents=[REVIEW], show_opinion_mining=True)[0]
    if result.is_error:
        print(f"  Error: {result.error}")
        return
    s = result.confidence_scores
    print(
        f"  Document sentiment: {result.sentiment.upper()} "
        f"(pos={s.positive:.2f}, neu={s.neutral:.2f}, neg={s.negative:.2f})\n"
    )
    print("  Opinion -> Target pairs:")
    for sentence in result.sentences:
        for op in sentence.mined_opinions:
            for a in op.assessments:
                print(f'    "{a.text}" ({a.sentiment})  ->  "{op.target.text}" ({op.target.sentiment})')


def demo_summarization() -> None:
    """begin_extract_summary() vs. begin_abstract_summary() -- the two
    summarization shapes. Both are long-running: they return a poller, and
    .result() blocks until the service finishes. Extractive returns source
    sentences (traceable); abstractive returns new paraphrased text (readable)."""
    print("\n" + "=" * 72)
    print(" Summarization  ->  begin_extract_summary() / begin_abstract_summary()")
    print("=" * 72)

    # Extractive -- pulls the highest-ranked SOURCE sentences verbatim.
    extract_poller = client.begin_extract_summary(documents=[REVIEW])
    extract_result = next(iter(extract_poller.result()))
    if not extract_result.is_error:
        print("  Extractive (verbatim source sentences):")
        for sent in extract_result.sentences:
            print(f"    - {sent.text}")

    # Abstractive -- writes NEW sentences that paraphrase the whole document.
    abstract_poller = client.begin_abstract_summary(documents=[REVIEW])
    abstract_result = next(iter(abstract_poller.result()))
    if not abstract_result.is_error:
        print("\n  Abstractive (novel paraphrase):")
        for summary in abstract_result.summaries:
            print(f"    {summary.text}")


def main() -> None:
    print(f"Endpoint: {LANGUAGE_ENDPOINT}")
    print("Auth:     keyless (DefaultAzureCredential) -- no key in .env")
    demo_entities()
    demo_key_phrases()
    demo_sentiment()
    demo_summarization()
    print("\n" + "=" * 72)
    print(" Exam pocket card:")
    print("   azure.ai.textanalytics.TextAnalyticsClient(endpoint, DefaultAzureCredential())")
    print("     .recognize_entities(documents=[...])                      # entities")
    print("     .extract_key_phrases(documents=[...])                     # key phrases")
    print("     .analyze_sentiment(documents=[...], show_opinion_mining=True)  # sentiment")
    print("     .begin_extract_summary(documents=[...]).result()          # verbatim summary")
    print("     .begin_abstract_summary(documents=[...]).result()         # paraphrase summary")
    print("=" * 72 + "\n")


if __name__ == "__main__":
    main()
