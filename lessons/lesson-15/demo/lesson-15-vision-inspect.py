"""
Lesson 15 -- Fabrikam Defect Inspector (vision INPUT / image understanding)
===========================================================================
Course:  Exam AI-901 -- Microsoft Azure AI Fundamentals (Video)
Role:    The reference for the "send an image TO the model" half of Lesson 15.
         Fabrikam runs a factory line; a quality engineer photographs a finished
         part, and gpt-4o (a multimodal model -- text AND vision in one deployment)
         reads the photo and returns a structured defect report.

WHAT "MULTIMODAL" MEANS (grounded on MS Learn "Use GPT-4o vision"):
    The SAME chat-completions endpoint you use for text also accepts images.
    You do NOT call a separate vision service -- you add an `image_url` part to
    the user message's `content` array. The model "sees" the picture and reasons
    over it in natural language. This is image UNDERSTANDING (input); the sibling
    file lesson-15-contoso-promo.py covers image GENERATION (output).

TWO WAYS TO HAND THE MODEL A PICTURE (this file demonstrates BOTH):
    1. A LOCAL file  -> base64-encode the bytes into a `data:` URL. Use this when
       the image lives on disk and is NOT reachable from the public internet
       (the Fabrikam line camera writes to a private share).
    2. A PUBLIC https URL -> pass the URL straight through. Use this when the
       image is already hosted somewhere Azure can fetch it.
    Both land in the exact same `image_url.url` field -- a data: URL is just an
    inline-encoded image, so the API treats them identically.

SUPPORTED IMAGE FORMATS (the allowlist gpt-4o vision accepts):
    JPEG (.jpg/.jpeg), PNG (.png), GIF (.gif), and WEBP (.webp).
    Anything else (TIFF, BMP, HEIC, raw) must be converted first.

THE KEYLESS-AUTH PATTERN (same as L10-L14 -- Fundamentals keyless track):
    DefaultAzureCredential -> bearer token -> AzureOpenAI(azure_ad_token_provider).
    No API key is read or stored. The signed-in user (az login) holds the
    "Cognitive Services OpenAI User" role on the Foundry resource.

How to run:
    az login
    python lesson-15-vision-inspect.py                         # inspects samples/bracket-crack.png
    python lesson-15-vision-inspect.py ./samples/bracket-crack.png  # same, explicit path
    python lesson-15-vision-inspect.py ./my-part-photo.jpg     # inspects any LOCAL file
"""

from __future__ import annotations

import base64
import mimetypes
import os
import sys

from azure.identity import DefaultAzureCredential, get_bearer_token_provider
from dotenv import load_dotenv
from openai import AzureOpenAI, BadRequestError

load_dotenv(override=True)

# Cognitive Services data-plane scope -- the audience for the keyless bearer token.
COGNITIVE_SCOPE = "https://cognitiveservices.azure.com/.default"

# The allowlist of formats gpt-4o vision will decode. We map file extensions to
# the MIME type that goes in the data: URL prefix. Keep this in sync with the
# module docstring -- it IS the allowlist, expressed as code.
SUPPORTED_IMAGE_MIME = {
    ".jpg": "image/jpeg",
    ".jpeg": "image/jpeg",
    ".png": "image/png",
    ".gif": "image/gif",
    ".webp": "image/webp",
}

# A publicly reachable sample for the https-URL input form. WHY this one:
# Wikimedia Commons "Example.jpg" is a canonical, always-online file the Azure
# image fetcher can reliably download -- a raw.githubusercontent.com URL is NOT
# reliably reachable from the service side (it returns "Failed to download
# image"), so do not use one here.
SAMPLE_IMAGE_URL = "https://upload.wikimedia.org/wikipedia/commons/a/a9/Example.jpg"

# The instruction we pair with every image. We ask for JSON so the output is
# machine-parseable -- a real Fabrikam line would pipe this into a defect tracker.
INSPECTION_PROMPT = (
    "You are a Fabrikam factory quality inspector. Examine this photo of a "
    "manufactured part. List each visible defect: location, defect type, "
    "severity (low/medium/high). Respond as JSON."
)


def build_credential() -> DefaultAzureCredential:
    """Return a DefaultAzureCredential pinned to the az-login identity.

    Credential guard (same pattern as the L10-L14 clients): on a dev laptop,
    stray environment variables make DefaultAzureCredential try a service
    principal or managed identity FIRST and fail with a confusing 401. We clear
    those derailers and exclude managed identity so the chain lands on the
    Azure CLI credential -- i.e. whoever ran `az login`.
    """
    for derailer in (
        "AZURE_TOKEN_CREDENTIALS",
        "AZURE_CLIENT_ID",
        "AZURE_CLIENT_SECRET",
        "AZURE_TENANT_ID",
    ):
        os.environ.pop(derailer, None)
    return DefaultAzureCredential(exclude_managed_identity_credential=True)


def require(name: str) -> str:
    """Fetch a required .env value or fail with an actionable message."""
    value = os.environ.get(name)
    if not value:
        raise SystemExit(
            f"Missing {name}. Run Deploy-Lesson15-Infrastructure.ps1 and paste "
            f"its output into .env (no keys -- L15 is keyless)."
        )
    return value


# ----------------------------------------------------------------------------
# Keyless AzureOpenAI client (built once, reused by every inspection)
# ----------------------------------------------------------------------------
CREDENTIAL = build_credential()
VISION_DEPLOYMENT = require("AOAI_VISION_DEPLOYMENT")

client = AzureOpenAI(
    azure_endpoint=require("AOAI_ENDPOINT"),
    api_version=os.environ.get("AOAI_API_VERSION", "2024-10-21"),
    azure_ad_token_provider=get_bearer_token_provider(CREDENTIAL, COGNITIVE_SCOPE),
)


def file_to_data_url(image_path: str) -> str:
    """Base64-encode a LOCAL image file into a `data:` URL the API can ingest.

    WHY a data: URL: the chat endpoint's `image_url.url` field accepts either a
    public https link OR an inline `data:<mime>;base64,<bytes>` blob. For a file
    that only exists on the private Fabrikam share, inlining the bytes is the
    only way to hand it to the model without first hosting it somewhere public.

    We resolve the MIME type from the extension (with a mimetypes fallback) and
    refuse anything outside the gpt-4o vision allowlist -- a wrong prefix makes
    the service reject the request with an opaque error, so we fail early and
    clearly instead.
    """
    ext = os.path.splitext(image_path)[1].lower()
    mime = SUPPORTED_IMAGE_MIME.get(ext) or mimetypes.guess_type(image_path)[0]
    if mime not in SUPPORTED_IMAGE_MIME.values():
        raise SystemExit(
            f"Unsupported image type for {image_path!r} (resolved MIME={mime!r}). "
            f"gpt-4o vision accepts only: JPEG, PNG, GIF, WEBP."
        )

    with open(image_path, "rb") as handle:
        encoded = base64.b64encode(handle.read()).decode("utf-8")
    # The full data: URL = prefix + comma + base64 payload.
    return f"data:{mime};base64,{encoded}"


def resolve_image_reference(image_path_or_url: str) -> str:
    """Return the exact string to put in `image_url.url`.

    A public https URL passes straight through; anything else is treated as a
    local path and encoded into a data: URL. Both forms are valid `image_url`
    inputs -- the model cannot tell (and does not care) which one it received.
    """
    if image_path_or_url.startswith(("http://", "https://")):
        return image_path_or_url
    return file_to_data_url(image_path_or_url)


def inspect_image(image_path_or_url: str) -> str:
    """Send one image to gpt-4o and return its JSON defect report as text.

    The content array is the heart of multimodal: a `text` part (the
    instruction) followed by an `image_url` part (the picture). The model reads
    both together. We print and return `choices[0].message.content` -- the JSON
    the model produced.
    """
    image_url = resolve_image_reference(image_path_or_url)
    kind = "https URL" if image_url.startswith("http") else "base64 data URL"
    print(f"[vision] Inspecting via {kind} on deployment {VISION_DEPLOYMENT!r}...")

    try:
        response = client.chat.completions.create(
            model=VISION_DEPLOYMENT,
            messages=[
                {
                    "role": "user",
                    "content": [
                        {"type": "text", "text": INSPECTION_PROMPT},
                        {"type": "image_url", "image_url": {"url": image_url}},
                    ],
                }
            ],
            max_tokens=800,
        )
    except BadRequestError as exc:
        # The service fetches https URLs on ITS side. Some Foundry deployments
        # cannot reach the public internet and return "Failed to download image".
        # The data: URL (local file) path always works -- it sends bytes inline.
        if "download image" in str(exc).lower():
            raise SystemExit(
                "[vision] The service could not download that https URL -- this "
                "deployment cannot fetch remote images. Pass a LOCAL image path "
                "instead (sent inline as a data URL, always works):\n"
                "    python lesson-15-vision-inspect.py ./samples/bracket-crack.png"
            )
        raise
    report = response.choices[0].message.content
    print("[vision] Defect report (JSON):")
    print(report)
    return report


def main() -> None:
    """Run one inspection.

    With a path or URL argument, inspect that (a local path becomes a data: URL;
    an http(s) link passes straight through). With NO argument, inspect
    samples/bracket-crack.png next to this script -- the proven default, so the
    self-study never depends on a remote image being reachable. Showing both
    forms (local file and https URL) is the lesson's key point -- same call,
    two input forms.
    """
    if len(sys.argv) > 1:
        target = sys.argv[1]
        kind = "https URL" if target.startswith(("http://", "https://")) else "LOCAL file"
        print(f"[main] {kind} supplied: {target}")
    else:
        script_dir = os.path.dirname(os.path.abspath(__file__))
        target = os.path.join(script_dir, "samples", "bracket-crack.png")
        print(f"[main] No argument -- using local default: {target}")
        if not os.path.exists(target):
            print("[main] Local default missing -- falling back to the public sample URL.")
            target = SAMPLE_IMAGE_URL

    inspect_image(target)
    print("[main] Inspection complete: image -> gpt-4o -> structured JSON.")


# ============================================================================
# EXAM POCKET CARD -- AI-901 2.3 Vision (image understanding)
# ============================================================================
# Memorize these and the AI-901 2.3 code-fill questions become recognition tasks.
#
#   SDK package:    openai  (+ azure-identity for keyless)
#   Client class:   AzureOpenAI(azure_endpoint=..., api_version=...,
#                               azure_ad_token_provider=<token_provider>)
#                   keyless -> get_bearer_token_provider(DefaultAzureCredential(),
#                              "https://cognitiveservices.azure.com/.default")
#
#   Image input via CONTENT ARRAY:
#       messages=[{"role": "user", "content": [
#           {"type": "text", "text": "<your instruction>"},
#           {"type": "image_url", "image_url": {"url": "<data: or https: URL>"}},
#       ]}]
#
#   Local file -> data: URL:
#       encoded = base64.b64encode(open(path, "rb").read()).decode()
#       url = f"data:{mime};base64,{encoded}"
#
#   Public URL -> pass straight through (no encoding needed)
#
#   Supported formats:  JPEG, PNG, GIF, WEBP  (TIFF/BMP/HEIC: convert first)
#   Model used:         gpt-4o (vision-capable multimodal chat deployment)
#   Role on resource:   Cognitive Services OpenAI User  (data-plane, keyless)
#   Exam tip:           vision uses the CHAT endpoint -- NOT a separate service
# ============================================================================


if __name__ == "__main__":
    main()
