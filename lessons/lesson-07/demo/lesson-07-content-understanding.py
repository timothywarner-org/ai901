"""
Lesson 07 -- Content Understanding SDK Bookend
================================================
Course:  Exam AI-901 -- Microsoft Azure AI Fundamentals (Video)
LO:      1.5.1 (cross-modality extraction), 1.5.2 (Content Understanding
         fundamentals), 1.5.3 (rule-based / ML / multimodal trade-offs)
Goal:    Show the SAME analyzer call the portal demo made -- one analyzer,
         async POST-and-poll, structured JSON envelope -- as a standalone
         ~40-line script, so students see the REST shape the AI-901 exam
         tests on code-fill questions.

Why this file exists:
    The portal demo in Content Understanding Studio teaches the *what*.
    This script teaches the *what-it-looks-like-in-code*. Two patterns
    to memorize for the exam:

        1. The REST endpoint shape:
             {endpoint}/contentunderstanding/analyzers/{analyzerId}:analyze
                 ?api-version=2025-11-01
           Memorize the ":analyze" action verb and the api-version.

        2. The async POST-and-poll pattern:
             POST returns 202 + an Operation-Location header.
             GET-poll that header until status is Succeeded / Failed.
           This pattern is shared across the heavy Azure AI operations
           (Azure AI Document Intelligence, Speech batch, Video Indexer) --
           learn it once.

Why REST and not the SDK:
    The azure-ai-contentunderstanding Python SDK is preview-only as of
    mid-2026. The cleanest, most durable teaching code calls the GA REST
    API directly with `requests` -- two standard-library imports + one
    third-party.

Resource backing this script:
    The Foundry resource provisioned by Deploy-Lesson07-Infrastructure.ps1.
    The deploy script also wires the resource-level model-deployment defaults,
    so the bare {"inputs":[...]} body below resolves the prebuilt analyzer's
    models without per-request overrides. Auth is key + endpoint via .env --
    never commit your .env or share your key.

How to run:
    python -m venv .venv
    .venv\\Scripts\\Activate.ps1       # Windows PowerShell
    pip install -r requirements.txt
    copy .env.example .env           # then paste YOUR endpoint and key into .env
    python lesson-07-content-understanding.py
"""

from __future__ import annotations

import os
import sys
import time

import requests
from dotenv import load_dotenv


# ---------------------------------------------------------------------------
# 1. Load credentials from .env -- never commit your .env or share your key.
# ---------------------------------------------------------------------------
load_dotenv()

ENDPOINT = os.environ.get("CONTENT_UNDERSTANDING_ENDPOINT")
KEY = os.environ.get("CONTENT_UNDERSTANDING_KEY")
API_VERSION = os.environ.get("CONTENT_UNDERSTANDING_API_VERSION", "2025-11-01")

if not ENDPOINT or not KEY:
    sys.exit(
        "Missing CONTENT_UNDERSTANDING_ENDPOINT or CONTENT_UNDERSTANDING_KEY. "
        "Copy .env.example to .env and fill in your Foundry resource endpoint and key."
    )

# The same official Microsoft sample invoice the portal demo uses, so
# this script visibly calls "the same analyzer you just clicked."
ANALYZER_ID = "prebuilt-invoice"
SAMPLE_URL = (
    "https://github.com/Azure-Samples/azure-ai-content-understanding-python"
    "/raw/refs/heads/main/data/invoice.pdf"
)


# ---------------------------------------------------------------------------
# 2. The whole Content Understanding pattern in one function. Endpoint shape,
#    ":analyze" verb, api-version, async POST + Operation-Location poll.
# ---------------------------------------------------------------------------
def analyze(analyzer_id: str, input_url: str) -> dict:
    """POST a file URL to a prebuilt analyzer and poll until the result is ready."""

    # --- The endpoint shape the exam tests: path + analyzer + :analyze verb --
    url = (
        f"{ENDPOINT}contentunderstanding/analyzers/"
        f"{analyzer_id}:analyze?api-version={API_VERSION}"
    )
    headers = {"Ocp-Apim-Subscription-Key": KEY, "Content-Type": "application/json"}

    # --- Step 1: POST. GA body is an ARRAY under "inputs", not a bare url. ---
    # This is a tested GA gotcha: {"url": "..."} (no "inputs" wrapper) returns
    # HTTP 400. The correct shape is {"inputs": [{"url": "..."}]}.
    resp = requests.post(url, headers=headers, json={"inputs": [{"url": input_url}]})
    resp.raise_for_status()  # 202 Accepted on success

    # --- Step 2: the async handle lives in the Operation-Location header. ----
    op_location = resp.headers["Operation-Location"]

    # --- Step 3: poll until terminal. Same loop for every modality. ----------
    while True:
        poll = requests.get(
            op_location, headers={"Ocp-Apim-Subscription-Key": KEY}
        ).json()
        status = poll.get("status")
        if status in ("Succeeded", "Failed"):
            return poll
        time.sleep(2)  # Content Understanding is asynchronous -- poll, do not block.


# ---------------------------------------------------------------------------
# 3. Run it and print the structured envelope -- the same shape the portal
#    rendered. fields + confidence scores, no browser required.
# ---------------------------------------------------------------------------
def main() -> None:
    print(f"Endpoint:   {ENDPOINT}")
    print(f"Analyzer:   {ANALYZER_ID}")
    print(f"API ver:    {API_VERSION}")
    print(f"Key:        ****{KEY[-4:]}  (last 4 only)\n")
    print("POST + poll (Content Understanding is async)...\n")

    result = analyze(ANALYZER_ID, SAMPLE_URL)

    if result.get("status") != "Succeeded":
        err = result.get("error", {})
        inner = err.get("innererror", {})
        sys.exit(f"Analyze failed: {inner.get('message') or err.get('message')}")

    contents = result["result"]["contents"]
    fields = contents[0].get("fields", {})

    print(f"status:     {result['status']}")
    print(f"analyzerId: {result['result']['analyzerId']}")
    print(f"contents:   {len(contents)}")
    print(f"fields:     {len(fields)} extracted\n")

    # Print high-signal extracted fields with confidence scores.
    # Confidence-per-field is a key teaching point for the lesson: the service
    # not only extracts values but also tells you how confident it is.
    # These four fields are reliably populated on the Microsoft sample invoice.
    for name in ("VendorName", "CustomerName", "InvoiceId", "InvoiceDate"):
        field = fields.get(name)
        if not field:
            continue
        value = (
            field.get("valueString")
            or field.get("valueDate")
            or field.get("content")
            or _currency(field.get("valueCurrency"))
        )
        confidence = field.get("confidence")
        conf_str = f"  (confidence {confidence:.2f})" if confidence is not None else ""
        print(f"  {name:14}: {value}{conf_str}")

    print("\n" + EXAM_POCKET_CARD)


def _currency(value) -> str | None:
    """Render a Content Understanding currency field as 'CODE amount'."""
    if not isinstance(value, dict):
        return None
    return f"{value.get('currencyCode', '')} {value.get('amount', '')}".strip()


# ---------------------------------------------------------------------------
# Exam pocket card -- read this to close the SDK bookend.
# ---------------------------------------------------------------------------
EXAM_POCKET_CARD = """\
=== Content Understanding -- exam pocket card =================================
 Endpoint shape : {endpoint}/contentunderstanding/analyzers/{id}:analyze
                  ?api-version=2025-11-01
 Request body   : {"inputs": [{"url": "..."}]}      <- array under "inputs"
 Async pattern  : POST -> 202 + Operation-Location header -> GET-poll until
                  status == Succeeded / Failed
 Prebuilt IDs   : prebuilt-invoice (document), prebuilt-imageSearch (image),
                  prebuilt-audioSearch (audio), prebuilt-videoSearch (video)
 One analyzer, four modalities, one JSON envelope. Swap the analyzer ID;
 the code path never changes.
==============================================================================="""


if __name__ == "__main__":
    main()
