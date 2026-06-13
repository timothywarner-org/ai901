"""
Lesson 05 -- Text Analysis SDK Bookend
=======================================
Course:  Exam AI-901 -- Microsoft Azure AI Fundamentals (Video)
LO:      1.3.2a (text analysis), 1.3.3 (NLP continuum)
Goal:    Mirror the Language Studio portal demo in ~30 lines of Python so
         students see the SDK class + method pairs the AI-901 exam tests on
         code-fill questions.

Why this file exists:
    The portal demos in Language Studio teach the *what*. This script teaches
    the *what-it-looks-like-in-code*. The exam includes Python items that ask
    which client class and which method maps to a given task.

    Two patterns to memorize:

        Named Entity Recognition  ->  TextAnalyticsClient.recognize_entities()
        Sentiment Analysis        ->  TextAnalyticsClient.analyze_sentiment()
                                       (show_opinion_mining=True for
                                        target-aspect pairs)

Resource backing this script:
    The singleton Azure AI Language (TextAnalytics F0) resource provisioned by
    Deploy-Lesson05-Infrastructure.ps1. Auth is key + endpoint via .env -- never
    commit your .env or share your key.

How to run:
    python -m venv .venv
    .venv\\Scripts\\Activate.ps1       # Windows PowerShell
    pip install -r requirements.txt
    copy .env.example .env           # then paste YOUR endpoint and key into .env
    python lesson-05-text-analytics.py
"""

from __future__ import annotations

import os
import sys

from azure.ai.textanalytics import TextAnalyticsClient
from azure.core.credentials import AzureKeyCredential
from dotenv import load_dotenv


# ---------------------------------------------------------------------------
# 1. Load credentials from .env -- never commit your .env or share your key.
# ---------------------------------------------------------------------------
load_dotenv()

LANGUAGE_KEY = os.environ.get("LANGUAGE_KEY")
LANGUAGE_ENDPOINT = os.environ.get("LANGUAGE_ENDPOINT")

if not LANGUAGE_KEY or not LANGUAGE_ENDPOINT:
    sys.exit(
        "Missing LANGUAGE_KEY or LANGUAGE_ENDPOINT. "
        "Copy .env.example to .env and fill in your Language resource endpoint and key."
    )


# ---------------------------------------------------------------------------
# 2. Build the client. ONE class -- TextAnalyticsClient -- backs every
#    NLP task: NER, sentiment, key phrases, summarization, PII, language
#    detection. The exam will hand you a code stub; recognize this shape.
# ---------------------------------------------------------------------------
client = TextAnalyticsClient(
    endpoint=LANGUAGE_ENDPOINT,
    credential=AzureKeyCredential(LANGUAGE_KEY),
)


# ---------------------------------------------------------------------------
# 3. The same Contoso Air review shown in Language Studio during the portal
#    demo. Using the identical input lets you compare the SDK output directly
#    to what the portal painted -- they should match.
# ---------------------------------------------------------------------------
REVIEW = (
    "I flew Contoso Air from Seattle to Munich on March 12, 2026. "
    "The check-in agent at SEA was wonderful and the meal service in "
    "Premium Economy was the best I have had on any transatlantic flight "
    "this year. Unfortunately, the in-flight Wi-Fi was a disaster -- it "
    "disconnected three times during the flight and the support chat just "
    "kept apologizing. The Munich arrivals lounge was also filthy when I "
    "got off the plane. I will probably still fly Contoso Air next year, "
    "but they have to fix the Wi-Fi."
)


def demo_named_entity_recognition() -> None:
    """Mirror of Language Studio NER -- recognize_entities() returns the same
    entity list the portal painted, typed as Python objects instead of JSON."""

    print("\n" + "=" * 72)
    print(" NER  ->  TextAnalyticsClient.recognize_entities()")
    print("=" * 72)

    result = client.recognize_entities(documents=[REVIEW])[0]

    if result.is_error:
        print(f"Error: {result.error}")
        return

    for entity in result.entities:
        print(
            f"  {entity.text:<25} "
            f"category={entity.category:<14} "
            f"score={entity.confidence_score:.2f}"
        )


def demo_sentiment_with_opinion_mining() -> None:
    """Mirror of Language Studio Sentiment -- analyze_sentiment() returns
    document sentiment + sentence-level opinion->target pairs when
    show_opinion_mining=True."""

    print("\n" + "=" * 72)
    print(" Sentiment + opinion mining  ->  TextAnalyticsClient.analyze_sentiment()")
    print("=" * 72)

    result = client.analyze_sentiment(
        documents=[REVIEW],
        show_opinion_mining=True,
    )[0]

    if result.is_error:
        print(f"Error: {result.error}")
        return

    scores = result.confidence_scores
    print(
        f"\n  Document sentiment: {result.sentiment.upper()}  "
        f"(pos={scores.positive:.2f}, "
        f"neu={scores.neutral:.2f}, "
        f"neg={scores.negative:.2f})\n"
    )

    print("  Opinion -> Target pairs (the exam asks about these by name):")
    for sentence in result.sentences:
        for mined_opinion in sentence.mined_opinions:
            target = mined_opinion.target
            for assessment in mined_opinion.assessments:
                print(
                    f"    \"{assessment.text}\" ({assessment.sentiment})"
                    f"  ->  \"{target.text}\" ({target.sentiment})"
                )


def main() -> None:
    print(f"Endpoint: {LANGUAGE_ENDPOINT}")
    print(f"Key:      ****{LANGUAGE_KEY[-4:]}  (last 4 only)")
    demo_named_entity_recognition()
    demo_sentiment_with_opinion_mining()
    print("\n" + "=" * 72)
    print(" Exam pocket card:")
    print("   azure.ai.textanalytics.TextAnalyticsClient")
    print("     .recognize_entities(documents=[...])       # NER")
    print("     .analyze_sentiment(documents=[...],")
    print("                        show_opinion_mining=True)  # Sentiment")
    print("     .extract_key_phrases(documents=[...])      # Key phrases")
    print("     .recognize_pii_entities(documents=[...])   # PII")
    print("     .detect_language(documents=[...])          # Language detect")
    print("=" * 72 + "\n")


if __name__ == "__main__":
    main()
