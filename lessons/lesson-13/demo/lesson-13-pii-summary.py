"""
Lesson 13 -- PII Redaction and Summarization
=============================================
Course:  Exam AI-901 -- Microsoft Azure AI Fundamentals (Video)
LOs:     2.2.1 (Azure AI Language: PII detection and summarization)

Two language skills demonstrated here that complement the main script:

  * recognize_pii_entities  -- detect and redact personally identifiable
                               information (PII) such as names, email addresses,
                               phone numbers, and credit-card numbers.
  * begin_extract_summary / begin_abstract_summary -- condense a long support
    thread into either verbatim source sentences (extractive) or a novel
    paraphrase (abstractive).

Auth: KEYLESS (DefaultAzureCredential). Reads LANGUAGE_ENDPOINT from .env.

How to run:
    python -m venv .venv
    .venv\\Scripts\\Activate.ps1           # Windows
    # source .venv/bin/activate           # macOS/Linux
    pip install -r requirements.txt
    cp .env.example .env                  # paste LANGUAGE_ENDPOINT
    az login
    python lesson-13-pii-summary.py
"""
from __future__ import annotations

import os
import sys

from azure.ai.textanalytics import TextAnalyticsClient
from azure.identity import DefaultAzureCredential
from dotenv import load_dotenv

load_dotenv(override=True)

# Credential guard: clear variables that divert DefaultAzureCredential away
# from az login on a developer laptop. Remove in production (managed identity
# should win there).
for _d in ("AZURE_TOKEN_CREDENTIALS", "AZURE_CLIENT_ID", "AZURE_CLIENT_SECRET", "AZURE_TENANT_ID"):
    os.environ.pop(_d, None)

ENDPOINT = os.environ.get("LANGUAGE_ENDPOINT")
if not ENDPOINT:
    sys.exit(
        "Missing LANGUAGE_ENDPOINT in .env -- paste the custom-subdomain "
        "endpoint of your Language resource (no key -- this lesson is keyless)."
    )

client = TextAnalyticsClient(
    endpoint=ENDPOINT,
    credential=DefaultAzureCredential(exclude_managed_identity_credential=True),
)

# PII-rich support message -- name, email, phone, and card number all get masked.
PII_TEXT = (
    "Hi, this is Maria Rodriguez. You can reach me at maria.rodriguez@contoso.com or on "
    "(206) 555-0142. I am following up on order F-7781 -- the card ending 4242 4242 4242 4242 "
    "was charged twice. Please call me back today."
)

# Longer support thread worth summarizing.
THREAD = (
    "A customer at our Bellevue branch reported their Fabrikam Industrial Pump model FB-2200 lost "
    "prime three times during a single shift on April 18. The on-site technician inspected the suction "
    "line and found a hairline crack in the foot valve, which was replaced under warranty. The customer "
    "also noted that the integrated flow sensor had been reporting intermittent zero readings for the "
    "prior two weeks, suggesting a related issue. Engineering opened ticket FB-WARRANTY-7741 to track "
    "both the foot-valve replacement and the sensor investigation. The customer requested expedited "
    "shipping on a spare foot valve and a written summary of the incident for their internal maintenance "
    "log. Resolution is expected within ten business days."
)


def demo_pii() -> None:
    print("\n" + "=" * 72)
    print(" PII redaction  ->  recognize_pii_entities()")
    print("=" * 72)
    result = client.recognize_pii_entities(documents=[PII_TEXT])[0]
    if result.is_error:
        print("  Error:", result.error)
        return
    print("  Redacted text:")
    print("   ", result.redacted_text)
    print("  Detected PII (category -> value):")
    for e in result.entities:
        print(f"    {e.category:<24} {e.text}")


def demo_summary() -> None:
    print("\n" + "=" * 72)
    print(" Summarization  ->  extractive vs. abstractive")
    print("=" * 72)
    # begin_* are long-running: they return a poller; .result() blocks for the answer.
    extractive = next(iter(client.begin_extract_summary(documents=[THREAD]).result()))
    if not extractive.is_error:
        print("  Extractive (verbatim source sentences):")
        for s in extractive.sentences:
            print("    -", s.text)
    abstractive = next(iter(client.begin_abstract_summary(documents=[THREAD]).result()))
    if not abstractive.is_error:
        print("\n  Abstractive (novel paraphrase):")
        for s in abstractive.summaries:
            print("   ", s.text)


if __name__ == "__main__":
    print(f"Endpoint: {ENDPOINT}")
    print("Auth:     keyless (DefaultAzureCredential)")
    demo_pii()
    demo_summary()
    print()
