"""
Lesson 6 -- Azure AI Vision SDK reuse layer
============================================
Course:  Exam AI-901 -- Microsoft Azure AI Fundamentals (Video)
Purpose: Wrap the SAME ImageAnalysisClient that sdk/lesson-06-vision.py
         uses, so the web app and the Python script tell one coherent story:
         "the web app and the script call the same client class."

Why a separate module:
    Flask routing (app.py) should not be tangled with Azure SDK plumbing.
    This module owns three responsibilities and nothing else:
      1. Build ONE ImageAnalysisClient from .env (key + endpoint auth).
      2. Map UI operation names -> VisualFeatures enum values.
      3. Serialize the SDK result object into the exact JSON key shapes
         the AI-901 exam tests (boundingBox x/y/w/h, boundingPolygon),
         so the raw-JSON pane IS the exam teaching surface.

Backend, never client-side: VISION_KEY stays here on the server. A
pure-static page would leak the key in browser JS -- the anti-pattern
this course teaches against.
"""

from __future__ import annotations

import os

from azure.ai.vision.imageanalysis import ImageAnalysisClient
from azure.ai.vision.imageanalysis.models import VisualFeatures
from azure.core.credentials import AzureKeyCredential
from azure.core.exceptions import HttpResponseError, ServiceRequestError
from dotenv import load_dotenv

# ---------------------------------------------------------------------------
# 1. Credentials from .env -- identical pattern to sdk/lesson-06-vision.py.
#    Never hardcode keys.
# ---------------------------------------------------------------------------
load_dotenv()

VISION_ENDPOINT = os.environ.get("VISION_ENDPOINT")
VISION_KEY = os.environ.get("VISION_KEY")


class VisionConfigError(RuntimeError):
    """Raised at startup when .env is missing the Vision credentials."""


class VisionServiceError(RuntimeError):
    """Wraps an SDK transport/service failure with a learner-friendly message.

    Carries an HTTP-ish status so app.py can pick a sensible response code
    without re-importing the Azure exception types.
    """

    def __init__(self, message: str, status: int = 502) -> None:
        super().__init__(message)
        self.status = status


def _build_client() -> ImageAnalysisClient:
    """Construct the ONE client class that backs every Lesson 6 capability.

    This is the exam-anchor shape: ImageAnalysisClient(endpoint=...,
    credential=AzureKeyCredential(...)). Same auth as every Azure AI SDK.
    """
    if not VISION_ENDPOINT or not VISION_KEY:
        raise VisionConfigError(
            "Missing VISION_KEY or VISION_ENDPOINT. Copy .env.example to .env "
            "and populate your Azure AI Vision resource key and endpoint."
        )
    return ImageAnalysisClient(
        endpoint=VISION_ENDPOINT,
        credential=AzureKeyCredential(VISION_KEY),
    )


# A single module-level client is correct here: ImageAnalysisClient is
# thread-safe for the synchronous demo workload, and rebuilding it per
# request would waste a TLS handshake on every analyze call.
_client: ImageAnalysisClient | None = None


def get_client() -> ImageAnalysisClient:
    """Lazy singleton so an unconfigured .env fails on first request with a
    clean banner instead of crashing Flask import."""
    global _client
    if _client is None:
        _client = _build_client()
    return _client


# ---------------------------------------------------------------------------
# 2. UI operation -> VisualFeatures. The front end sends these string keys;
#    the enum lives ONLY here so the browser never hardcodes SDK internals.
#    Keys mirror the four operation groups in the Lesson 6 demo.
# ---------------------------------------------------------------------------
FEATURE_MAP: dict[str, VisualFeatures] = {
    "caption": VisualFeatures.CAPTION,
    "denseCaptions": VisualFeatures.DENSE_CAPTIONS,
    "objects": VisualFeatures.OBJECTS,
    "read": VisualFeatures.READ,
    "tags": VisualFeatures.TAGS,
    "people": VisualFeatures.PEOPLE,
    "smartCrops": VisualFeatures.SMART_CROPS,
}


def resolve_features(keys: list[str]) -> list[VisualFeatures]:
    """Translate UI keys to enum values, dropping anything unrecognized.

    Caption and DenseCaptions are region-gated; ensure your Vision resource
    is in a supported region (East US qualifies).
    """
    features = [FEATURE_MAP[k] for k in keys if k in FEATURE_MAP]
    if not features:
        # The Analyze API rejects an empty feature list. Fail loud and early
        # with a 400-friendly message rather than a service round-trip.
        raise VisionServiceError(
            "No valid visual features selected. Pick at least one operation.",
            status=400,
        )
    return features


# ---------------------------------------------------------------------------
# 3. Analyze entry points -- one per input mode. analyze_url() is a
#    SERVER-SIDE fetch (Azure pulls the URL); analyze_bytes() takes local bytes.
# ---------------------------------------------------------------------------
def analyze_url(url: str, feature_keys: list[str]) -> dict:
    """Analyze a hosted image by URL. Returns the serialized result dict."""
    features = resolve_features(feature_keys)
    try:
        result = get_client().analyze_from_url(
            image_url=url, visual_features=features
        )
    except HttpResponseError as err:
        raise _wrap_http_error(err) from err
    except ServiceRequestError as err:
        raise VisionServiceError(
            f"Could not reach the Vision endpoint: {err}", status=502
        ) from err
    return serialize_result(result)


def analyze_bytes(data: bytes, feature_keys: list[str]) -> dict:
    """Analyze an uploaded local image (byte-stream path)."""
    features = resolve_features(feature_keys)
    try:
        result = get_client().analyze(
            image_data=data, visual_features=features
        )
    except HttpResponseError as err:
        raise _wrap_http_error(err) from err
    except ServiceRequestError as err:
        raise VisionServiceError(
            f"Could not reach the Vision endpoint: {err}", status=502
        ) from err
    return serialize_result(result)


def _wrap_http_error(err: HttpResponseError) -> VisionServiceError:
    """Turn an Azure HttpResponseError into a one-line learner-safe message.

    Calls out the most likely self-practice failures: 401 (bad key), 429
    (F0 throttle -- 20 calls/min cap), 400 (bad image/url).
    """
    status = err.status_code or 502
    hint = ""
    if status == 429:
        hint = " The F0 free tier caps at ~20 calls/min -- wait a few seconds and retry."
    elif status == 401:
        hint = " Check VISION_KEY / VISION_ENDPOINT in .env."
    elif status == 400:
        hint = " Check the image URL or file format (JPEG/PNG/GIF/BMP, <20 MB)."
    return VisionServiceError(
        f"Vision service rejected the call: {status} {err.reason}.{hint}",
        status=status,
    )


# ---------------------------------------------------------------------------
# Serialization -- walk the SDK result and emit the SAME key shapes the
# exam tests. Each box is normalized to {x,y,w,h}; OCR polygons stay as
# point lists. This dict is what the front end renders AND what the raw-JSON
# pane prints, so the JSON shape teaches the exam material.
# ---------------------------------------------------------------------------
def _box(bounding_box) -> dict:
    """Normalize an SDK ImageBoundingBox to the exam's {x,y,w,h} shape."""
    return {
        "x": bounding_box.x,
        "y": bounding_box.y,
        "w": bounding_box.width,
        "h": bounding_box.height,
    }


def _polygon(points) -> list[dict]:
    """OCR bounding polygons are corner points, not an x/y/w/h box."""
    return [{"x": p.x, "y": p.y} for p in points]


def serialize_result(result) -> dict:
    """Produce a clean, JSON-serializable dict from ImageAnalysisResult.

    Only includes keys for features that actually returned data, so the
    raw-JSON pane stays tight and the requested-operation shape is obvious.
    """
    out: dict = {
        "modelVersion": result.model_version,
        "metadata": {
            "width": result.metadata.width,
            "height": result.metadata.height,
        },
    }

    # CAPTION -- whole-image sentence. label + confidence shape.
    if result.caption is not None:
        out["caption"] = {
            "text": result.caption.text,
            "confidence": result.caption.confidence,
        }

    # DENSE CAPTIONS -- up to 10 region sentences, each WITH a bounding box.
    if result.dense_captions is not None:
        out["denseCaptions"] = [
            {
                "text": c.text,
                "confidence": c.confidence,
                "boundingBox": _box(c.bounding_box),
            }
            for c in result.dense_captions.list
        ]

    # OBJECTS -- the headline bounding-box shape.
    if result.objects is not None:
        objects = []
        for obj in result.objects.list:
            if not obj.tags:
                continue
            tag = obj.tags[0]
            objects.append(
                {
                    "name": tag.name,
                    "confidence": tag.confidence,
                    "boundingBox": _box(obj.bounding_box),
                }
            )
        out["objects"] = objects

    # PEOPLE -- person bounding boxes + confidence.
    if result.people is not None:
        out["people"] = [
            {"confidence": p.confidence, "boundingBox": _box(p.bounding_box)}
            for p in result.people.list
        ]

    # READ (OCR) -- blocks -> lines -> words, each with a bounding polygon.
    # This is the "lines + words + boundingPolygon" teaching shape.
    if result.read is not None:
        blocks = []
        for block in result.read.blocks:
            lines = []
            for line in block.lines:
                lines.append(
                    {
                        "text": line.text,
                        "boundingPolygon": _polygon(line.bounding_polygon),
                        "words": [
                            {
                                "text": w.text,
                                "confidence": w.confidence,
                                "boundingPolygon": _polygon(w.bounding_polygon),
                            }
                            for w in line.words
                        ],
                    }
                )
            blocks.append({"lines": lines})
        out["read"] = {"blocks": blocks}

    # TAGS -- whole-image label + confidence list (classification shape).
    if result.tags is not None:
        out["tags"] = [
            {"name": t.name, "confidence": t.confidence}
            for t in result.tags.list
        ]

    # SMART CROPS -- suggested crop rectangles per aspect ratio.
    if result.smart_crops is not None:
        out["smartCrops"] = [
            {
                "aspectRatio": c.aspect_ratio,
                "boundingBox": _box(c.bounding_box),
            }
            for c in result.smart_crops.list
        ]

    return out
