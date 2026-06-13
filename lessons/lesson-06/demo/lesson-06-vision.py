"""
Lesson 06 -- Vision SDK Bookend
=================================
Course:  Exam AI-901 -- Microsoft Azure AI Fundamentals (Video)
LO:      1.4.1 (computer vision tasks), 1.4.2 (vision service capabilities)
Goal:    Mirror the Vision Studio portal demo in ~40 lines of Python so
         students see the SDK class + method pairs the AI-901 exam tests on
         code-fill questions.

Why this file exists:
    The portal demos in Vision Studio teach the *what*. This script teaches
    the *what-it-looks-like-in-code*. The exam includes Python items that ask
    which client class and which method maps to a given vision task.

    Pattern to memorize:

        Image analysis  ->  ImageAnalysisClient.analyze_from_url(
                                visual_features=[
                                    VisualFeatures.CAPTION,
                                    VisualFeatures.OBJECTS,
                                    VisualFeatures.READ
                                ])

Resource backing this script:
    The singleton Azure AI Vision (ComputerVision F0) resource provisioned by
    Deploy-Lesson06-Infrastructure.ps1. Auth is key + endpoint via .env -- never
    commit your .env or share your key.

How to run:
    python -m venv .venv
    .venv\\Scripts\\Activate.ps1       # Windows PowerShell
    pip install -r requirements.txt
    copy .env.example .env           # then paste YOUR endpoint and key into .env
    python lesson-06-vision.py
"""

from __future__ import annotations

import os
import sys

from azure.ai.vision.imageanalysis import ImageAnalysisClient
from azure.ai.vision.imageanalysis.models import VisualFeatures
from azure.core.credentials import AzureKeyCredential
from azure.core.exceptions import HttpResponseError, ServiceRequestError
from dotenv import load_dotenv


# ---------------------------------------------------------------------------
# 1. Load credentials from .env -- never commit your .env or share your key.
# ---------------------------------------------------------------------------
load_dotenv()

VISION_KEY = os.environ.get("VISION_KEY")
VISION_ENDPOINT = os.environ.get("VISION_ENDPOINT")

if not VISION_KEY or not VISION_ENDPOINT:
    sys.exit(
        "Missing VISION_KEY or VISION_ENDPOINT. "
        "Copy .env.example to .env and fill in your Vision resource endpoint and key."
    )


# ---------------------------------------------------------------------------
# 2. Build the client. ONE class -- ImageAnalysisClient -- backs every
#    vision capability: captions, tags, objects, OCR (READ feature), people
#    detection, and smart-crop suggestions. The exam will hand you a code
#    stub; recognize this shape.
# ---------------------------------------------------------------------------
client = ImageAnalysisClient(
    endpoint=VISION_ENDPOINT,
    credential=AzureKeyCredential(VISION_KEY),
)


# ---------------------------------------------------------------------------
# 3. Sample image -- the official Azure AI Vision SDK sample asset. It
#    contains a person, multiple objects, AND printed text, so one call
#    demonstrates CAPTION + OBJECTS + READ together.
#
#    Why this URL (not a learn.microsoft.com path):
#      a. analyze_from_url() is a SERVER-SIDE fetch -- the Vision service
#         pulls the URL. Its fetcher is unreliable on 302 redirects, and
#         the old learn.microsoft.com doc-media path redirects to add an
#         /en-us/ locale prefix, which can fail with InvalidImageUrl.
#      b. aka.ms/azsdk/... is a stable asset contract, not a doc-media URL.
# ---------------------------------------------------------------------------
SAMPLE_IMAGE_URL = "https://aka.ms/azsdk/image-analysis/sample.jpg"


def demo_image_analysis() -> None:
    """Mirror of Vision Studio -- analyze_from_url() returns caption + objects
    + OCR in a single call, the same three features the portal demo shows."""

    print("\n" + "=" * 72)
    print(" Image analysis  ->  ImageAnalysisClient.analyze_from_url()")
    print("=" * 72)
    print(f" Image: {SAMPLE_IMAGE_URL}\n")

    # The service fetches the URL server-side; any failure surfaces here:
    # bad key (401), F0 throttling (429 -- free tier caps at 20/min),
    # or transport trouble. A clean exit message beats a raw traceback.
    try:
        result = client.analyze_from_url(
            image_url=SAMPLE_IMAGE_URL,
            visual_features=[
                VisualFeatures.CAPTION,   # whole-image natural-language description
                VisualFeatures.OBJECTS,   # bounding boxes per detected object
                VisualFeatures.READ,      # OCR -- printed + handwritten text
            ],
        )
    except HttpResponseError as err:
        # status_code + reason covers 401 (bad key), 429 (throttled), 404, etc.
        sys.exit(
            f"  Vision service rejected the call: "
            f"{err.status_code} {err.reason}. "
            "Check VISION_KEY/VISION_ENDPOINT and the F0 rate limit (20/min)."
        )
    except ServiceRequestError as err:
        # DNS, TLS, or no-network -- the service was never reached.
        sys.exit(f"  Could not reach the Vision endpoint: {err}")

    # --- CAPTION -- mirrors "Add captions to images" in Vision Studio
    if result.caption is not None:
        print(f"  Caption: \"{result.caption.text}\"  (confidence={result.caption.confidence:.2f})")
    else:
        print("  Caption: (none returned)")

    # --- OBJECTS -- mirrors "Detect common objects"
    print("\n  Objects detected:")
    if result.objects is not None:
        for obj in result.objects.list:
            # Defensive check: a detected object can theoretically have no tags.
            if not obj.tags:
                continue
            tag = obj.tags[0]
            box = obj.bounding_box
            print(
                f"    {tag.name:<20} "
                f"confidence={tag.confidence:.2f}  "
                f"box=(x={box.x}, y={box.y}, w={box.width}, h={box.height})"
            )

    # --- READ (OCR) -- mirrors "Extract text (OCR)"
    # Accessibility note: the READ feature returns structured text, not image
    # regions -- screen readers and downstream systems can consume it directly.
    print("\n  Text extracted (OCR):")
    if result.read is not None:
        for block in result.read.blocks:
            for line in block.lines:
                print(f"    \"{line.text}\"")


def main() -> None:
    print(f"Endpoint: {VISION_ENDPOINT}")
    print(f"Key:      ****{VISION_KEY[-4:]}  (last 4 only)")
    demo_image_analysis()
    print("\n" + "=" * 72)
    print(" Exam pocket card:")
    print("   azure.ai.vision.imageanalysis.ImageAnalysisClient")
    print("     .analyze_from_url(image_url=..., visual_features=[")
    print("         VisualFeatures.CAPTION,    # whole-image description")
    print("         VisualFeatures.OBJECTS,    # bounding boxes per object")
    print("         VisualFeatures.READ,       # OCR (printed + handwritten)")
    print("         VisualFeatures.TAGS,       # general label tags")
    print("         VisualFeatures.PEOPLE,     # person bounding boxes")
    print("         VisualFeatures.SMART_CROPS # auto-crop suggestions")
    print("     ])")
    print("=" * 72 + "\n")


if __name__ == "__main__":
    main()
