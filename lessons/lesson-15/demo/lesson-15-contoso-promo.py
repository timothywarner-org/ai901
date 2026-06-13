"""
Lesson 15 -- Contoso Marketing Promo Generator (image GENERATION + audit trail)
================================================================================
Course:  Exam AI-901 -- Microsoft Azure AI Fundamentals (Video)
Role:    The reference for the "get an image OUT of the model" half of Lesson 15.
         Contoso Marketing types a prompt; gpt-image-2 paints a promotional
         product image; we save the PNG and append a full audit record. Sibling
         file lesson-15-vision-inspect.py covers the input (understanding) side
         -- this file is the output (generation) side.

BASE64 ONLY -- THERE IS NO `url` FIELD (the most-tested L15 gotcha):
    DALL-E 3 used to return a temporary `url`. The gpt-image series does NOT.
    Grounded on MS Learn "Image generation models": gpt-image always returns
    base64-encoded image data, the `response_format` parameter is unsupported,
    and the bytes arrive in `result.data[0].b64_json`. So we ALWAYS base64-decode
    -- never look for a URL. We then write the bytes to a .png on disk.

THE AUDIT TRAIL (WHY runs.jsonl exists):
    Image generation is NON-deterministic. Unlike chat completions, there is NO
    `seed` parameter for gpt-image -- the same prompt yields a different picture
    every time, and you CANNOT re-create a past image. So "reproducibility" here
    means capturing the COMPLETE request that produced an output: the prompt, the
    model + version, the size, the quality, and a UTC timestamp. We append one
    JSON line per run to runs.jsonl. That log IS the audit trail -- it lets
    Contoso prove which prompt made which marketing asset, even though the pixels
    can never be regenerated identically.

CONTENT SAFETY (the responsible-AI beat the exam loves):
    Every prompt passes through Azure AI Content Safety BEFORE the model runs,
    and Prompt Shields guard against jailbreak/injection attempts. A blocked
    prompt comes back as an openai.BadRequestError with code "content_filter"
    (sometimes spelled "contentFilter"). We catch it and print a clean,
    learner-friendly explanation instead of a stack trace.

THE KEYLESS-AUTH PATTERN (same as L10-L14 -- Fundamentals keyless track):
    DefaultAzureCredential -> bearer token -> AzureOpenAI(azure_ad_token_provider).
    No API key is read or stored. The signed-in user (az login) holds the
    "Cognitive Services OpenAI User" role on the Foundry resource.

How to run:
    az login
    python lesson-15-contoso-promo.py
"""

from __future__ import annotations

import base64
import datetime
import json
import os
import uuid

import openai
from azure.identity import DefaultAzureCredential, get_bearer_token_provider
from dotenv import load_dotenv
from openai import AzureOpenAI

load_dotenv(override=True)

# Cognitive Services data-plane scope -- the audience for the keyless bearer token.
COGNITIVE_SCOPE = "https://cognitiveservices.azure.com/.default"

# The pinned model version we stamp into every audit record. It is NOT sent to
# the API (the deployment name carries the model) -- it is metadata so the log
# records exactly which model build produced the asset.
IMAGE_MODEL_VERSION = "2026-04-21"

# The append-only audit log. One JSON object per line (JSON Lines / .jsonl):
# easy to append to, easy to grep, easy to stream into a SIEM or data lake.
RUNS_LOG = "runs.jsonl"

# A Contoso Marketing creative brief. ONE scenario, concrete and brand-safe.
# Subject + composition + style axes -- the three levers for prompt experimentation.
CONTOSO_PROMPT = (
    "Promotional product photo of a hand-painted wooden steam train for Contoso "
    "Marketing, on a white seamless backdrop, soft daylight, shallow depth of "
    "field, premium toy-catalog style, no text."
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
# Keyless AzureOpenAI client (built once, reused by every generation)
# ----------------------------------------------------------------------------
# NOTE the SEPARATE api-version: image generation is on a PREVIEW api-version
# (e.g. 2025-04-01-preview), distinct from the GA chat/vision version. Pinning
# it here keeps the image client on the surface that supports gpt-image.
CREDENTIAL = build_credential()
IMAGE_DEPLOYMENT = require("AOAI_IMAGE_DEPLOYMENT")

client = AzureOpenAI(
    azure_endpoint=require("AOAI_ENDPOINT"),
    api_version=os.environ.get("AOAI_IMAGE_API_VERSION", "2025-04-01-preview"),
    azure_ad_token_provider=get_bearer_token_provider(CREDENTIAL, COGNITIVE_SCOPE),
)


def _audit(run_id: str, prompt: str, size: str, quality: str) -> None:
    """Append one JSON line to runs.jsonl capturing the full request.

    This is the reproducibility/audit pattern: since gpt-image has no seed and
    the output cannot be regenerated, the COMPLETE request is the only durable
    record. We stamp UTC ISO-8601 so logs from different machines sort correctly.
    """
    record = {
        "run_id": run_id,
        "prompt": prompt,
        "model": "gpt-image-2",
        "model_version": IMAGE_MODEL_VERSION,
        "size": size,
        "quality": quality,
        "ts": datetime.datetime.now(datetime.timezone.utc).isoformat(),
    }
    with open(RUNS_LOG, "a", encoding="utf-8") as log:
        log.write(json.dumps(record) + "\n")
    print(f"[audit] Appended run {run_id} to {RUNS_LOG}.")


def generate(prompt: str, size: str = "1024x1024", quality: str = "high") -> str | None:
    """Generate one image from a prompt, save the PNG, and log the run.

    Returns the saved filename on success, or None if Content Safety blocked the
    prompt. `quality` is one of low/medium/high (gpt-image's three tiers;
    default high). `size` for gpt-image-2 must satisfy the resolution rules --
    1024x1024 is the safe square default.
    """
    run_id = uuid.uuid4().hex[:12]
    print(f"[gen] Run {run_id}: requesting {size} {quality}-quality image...")

    try:
        result = client.images.generate(
            model=IMAGE_DEPLOYMENT,
            prompt=prompt,
            size=size,
            quality=quality,
            n=1,
        )
    except openai.BadRequestError as error:
        # Content Safety / Prompt Shields rejection. The SDK surfaces the filter
        # decision as a BadRequestError; the code is "content_filter" (the REST
        # body sometimes spells it "contentFilter"). We sniff both spellings.
        code = getattr(error, "code", "") or ""
        body = str(getattr(error, "body", "") or error)
        if "content_filter" in code or "contentFilter" in body or "content_filter" in body:
            print(
                "[blocked] Azure AI Content Safety blocked this prompt at the "
                "deployment. Prompt Shields and the content filters screen every "
                "request BEFORE the model runs -- rephrase the prompt to remove "
                "the flagged content and try again. (No image was generated.)"
            )
            return None
        # Any other 400 (bad size, bad quality, etc.) is a real bug -- re-raise.
        raise

    # gpt-image returns BASE64 ONLY -- there is no `url` field. Decode the bytes.
    b64_image = result.data[0].b64_json
    image_bytes = base64.b64decode(b64_image)

    filename = f"contoso_{run_id}.png"
    with open(filename, "wb") as handle:
        handle.write(image_bytes)
    print(f"[gen] Saved {len(image_bytes):,} bytes to {filename}.")

    # Capturing the request AFTER a successful save keeps the log truthful --
    # every line in runs.jsonl corresponds to an image that actually exists.
    _audit(run_id, prompt, size, quality)
    return filename


def main() -> None:
    """Generate one Contoso Marketing promo image."""
    filename = generate(CONTOSO_PROMPT)
    if filename:
        print(f"[main] Done: {filename} created and logged in {RUNS_LOG}.")
    else:
        print("[main] Done: prompt was blocked -- nothing saved.")


# ============================================================================
# EXAM POCKET CARD -- AI-901 2.3 Image Generation
# ============================================================================
# Memorize these and the AI-901 2.3 code-fill questions become recognition tasks.
#
#   SDK package:    openai  (+ azure-identity for keyless)
#   Client class:   AzureOpenAI(azure_endpoint=..., api_version=<PREVIEW>,
#                               azure_ad_token_provider=<token_provider>)
#                   Image gen requires api_version="2025-04-01-preview" (preview
#                   API -- distinct from the GA chat version 2024-10-21).
#
#   Generate call:
#       result = client.images.generate(
#           model=IMAGE_DEPLOYMENT,   # the deployment name, e.g. "gpt-image-2"
#           prompt="<your text prompt>",
#           size="1024x1024",         # must match gpt-image resolution rules
#           quality="high",           # low | medium | high
#           n=1,
#       )
#
#   Decode output (BASE64 ONLY -- no url field):
#       image_bytes = base64.b64decode(result.data[0].b64_json)
#       open("out.png", "wb").write(image_bytes)
#
#   Content Safety:  BadRequestError with code "content_filter" -> prompt blocked
#   Audit trail:     log prompt + model + size + quality + UTC ts (no seed exists)
#   Role on resource: Cognitive Services OpenAI User  (data-plane, keyless)
# ============================================================================


if __name__ == "__main__":
    main()
