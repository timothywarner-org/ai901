"""
Lesson 7 -- Azure AI Content Understanding REST reuse layer
============================================================
Course:  Exam AI-901 -- Microsoft Azure AI Fundamentals (Video)
Purpose: Wrap the SAME Content Understanding REST flow that the Lesson 7
         SDK sample uses, so the web app and the Python script tell one
         coherent story: "the web app and the script call the same
         async POST-and-poll API."

Why a separate module:
    Flask routing (app.py) should not be tangled with the Azure REST
    plumbing. This module owns three responsibilities and nothing else:
      1. Build ONE configured session from .env (key + endpoint auth).
      2. Map UI modality names -> prebuilt analyzer IDs.
      3. Drive the async POST + Operation-Location poll, then serialize the
         result into the SAME JSON envelope shape the AI-901 exam tests
         (analyzerId, fields, markdown, confidence), so the raw-JSON pane
         IS the Lesson 7 teaching surface.

Why REST and not the SDK:
    The azure-ai-contentunderstanding Python SDK is preview-only as of
    mid-2026. The cleanest teaching code calls the GA REST API directly
    with requests and the key in a header. This is also the exact shape
    the SDK sample shows.

Backend, never client-side: CONTENT_UNDERSTANDING_KEY stays here on the
server. A pure-static page would leak the key in browser JS -- the
anti-pattern this course teaches against.

GA contract (api-version 2025-11-01):
  * Endpoint:  {endpoint}contentunderstanding/analyzers/{analyzerId}:analyze
  * Body:      {"inputs": [{"url": "..."}]}
  * Async:     POST returns 202 + an Operation-Location header; GET-poll it
               until status is Succeeded or Failed.
"""

from __future__ import annotations

import os
import time

import requests
from dotenv import load_dotenv

# ---------------------------------------------------------------------------
# 1. Credentials from .env -- identical pattern to the SDK sample.
#    Never hardcode keys.
# ---------------------------------------------------------------------------
load_dotenv()

CU_ENDPOINT = os.environ.get("CONTENT_UNDERSTANDING_ENDPOINT")
CU_KEY = os.environ.get("CONTENT_UNDERSTANDING_KEY")
CU_API_VERSION = os.environ.get("CONTENT_UNDERSTANDING_API_VERSION", "2025-11-01")

# Total seconds to poll before giving up. Video is the slowest modality and
# runs ~30-45s in practice; 120s leaves comfortable headroom.
POLL_TIMEOUT_SECONDS = 120
POLL_INTERVAL_SECONDS = 2


class CUConfigError(RuntimeError):
    """Raised when .env is missing the Content Understanding credentials."""


class CUServiceError(RuntimeError):
    """Wraps a REST transport/service failure with a learner-friendly message.

    Carries an HTTP-ish status so the Flask layer can pick a sensible
    response code without re-importing requests' exception types.
    """

    def __init__(self, message: str, status: int = 502) -> None:
        super().__init__(message)
        self.status = status


# ---------------------------------------------------------------------------
# 2. UI modality -> prebuilt analyzer ID. The front end sends these modality
#    keys; the analyzer IDs live ONLY here so the browser never hardcodes
#    service internals. These are the GA 2025-11-01 IDs (the *Search RAG
#    analyzers).
# ---------------------------------------------------------------------------
ANALYZER_MAP: dict[str, str] = {
    "document": "prebuilt-invoice",
    "image": "prebuilt-imageSearch",
    "audio": "prebuilt-audioSearch",
    "video": "prebuilt-videoSearch",
}

# Exam-framed instructional copy per modality. Each entry echoes the AI-901
# study-guide language so what the learner reads on screen matches the
# objective wording they will see on the exam.
#   title    : short human label for the tab description header.
#   api      : one-sentence "what this analyzer does."
#   exam     : the AI-901 angle -- what the exam tests about this capability.
MODALITY_INFO: dict[str, dict[str, str]] = {
    "document": {
        "title": "Documents and forms",
        "api": (
            "prebuilt-invoice extracts structured fields -- vendor, invoice ID, "
            "dates, line items, totals -- from a document, each with a confidence "
            "score and grounding back to where it was found in the file."
        ),
        "exam": (
            "AI-901: extract information from documents and forms with Content "
            "Understanding. Know that it returns per-field CONFIDENCE scores "
            "(the hook for straight-through processing vs. human review) and that "
            "it is the generative successor to Azure AI Document Intelligence "
            "(OCR / Read / Layout). Zero-shot -- no labeling required for "
            "prebuilt analyzers."
        ),
    },
    "image": {
        "title": "Images",
        "api": (
            "prebuilt-imageSearch generates a natural-language Summary of an "
            "image -- here, a description of what the chart shows -- returned in "
            "the same JSON envelope as every other modality."
        ),
        "exam": (
            "AI-901: extract information from images with Content Understanding. "
            "Contrast with Lesson 6's Image Analysis (tags, objects, OCR, "
            "captions): Content Understanding produces a generative, "
            "RAG-ready description rather than discrete feature lists."
        ),
    },
    "audio": {
        "title": "Audio",
        "api": (
            "prebuilt-audioSearch transcribes speech to text (WEBVTT with speaker "
            "labels) AND generates a summary of the conversation -- speech-to-text "
            "plus summarization in one analyzer call."
        ),
        "exam": (
            "AI-901: extract information from audio with Content Understanding. "
            "One analyzer bundles what used to be separate Speech-to-Text and "
            "summarization steps. Note the async POST-and-poll pattern -- audio "
            "and video are long-running operations."
        ),
    },
    "video": {
        "title": "Video",
        "api": (
            "prebuilt-videoSearch segments the video into scenes and returns, per "
            "segment, start/end timecodes, key-frame times, a transcript, and a "
            "generated summary -- vision on key frames plus the audio track."
        ),
        "exam": (
            "AI-901: extract information from video with Content Understanding. "
            "The heaviest modality -- it fuses computer vision (key frames) and "
            "speech (transcript) into one RAG-ready output. Same JSON envelope, "
            "just multiple scene segments inside it."
        ),
    },
}

# Official Microsoft Content Understanding sample files. Public raw URLs, so
# the lab has zero local-file dependency and uses the same bytes Microsoft tests.
SAMPLE_URLS: dict[str, str] = {
    "document": (
        "https://github.com/Azure-Samples/azure-ai-content-understanding-python"
        "/raw/refs/heads/main/data/invoice.pdf"
    ),
    "image": (
        "https://github.com/Azure-Samples/azure-ai-content-understanding-python"
        "/raw/refs/heads/main/data/pieChart.jpg"
    ),
    "audio": (
        "https://github.com/Azure-Samples/azure-ai-content-understanding-python"
        "/raw/refs/heads/main/data/audio.wav"
    ),
    "video": (
        "https://github.com/Azure-Samples/azure-ai-content-understanding-python"
        "/raw/refs/heads/main/data/FlightSimulator.mp4"
    ),
}

# Fail loud at import if the three modality dicts ever drift apart. The UI tabs
# come from ANALYZER_MAP, then read MODALITY_INFO and SAMPLE_URLS by the same
# key -- a missing key would render blank instructional copy or a missing
# sample. Better to crash on startup than to ship a silent gap.
assert (
    ANALYZER_MAP.keys() == MODALITY_INFO.keys() == SAMPLE_URLS.keys()
), "Modality dicts out of lockstep: ANALYZER_MAP / MODALITY_INFO / SAMPLE_URLS"


def _require_config() -> None:
    """Fail loud and early with a clean banner if .env is not populated."""
    if not CU_ENDPOINT or not CU_KEY:
        raise CUConfigError(
            "Missing CONTENT_UNDERSTANDING_ENDPOINT or CONTENT_UNDERSTANDING_KEY. "
            "Copy .env.example to .env and populate your Microsoft Foundry "
            "resource key and endpoint."
        )


def resolve_analyzer(modality: str) -> str:
    """Translate a UI modality key to its prebuilt analyzer ID.

    Raises a 400-friendly error for an unknown modality rather than letting
    a typo reach the service.
    """
    analyzer = ANALYZER_MAP.get(modality)
    if analyzer is None:
        raise CUServiceError(
            f"Unknown modality '{modality}'. "
            f"Expected one of: {', '.join(ANALYZER_MAP)}.",
            status=400,
        )
    return analyzer


def _headers() -> dict[str, str]:
    """Key-auth headers. The endpoint is reached with the resource key."""
    return {
        "Ocp-Apim-Subscription-Key": CU_KEY,
        "Content-Type": "application/json",
    }


def analyze(modality: str, url: str) -> dict:
    """Run a prebuilt analyzer against a hosted file and return the result.

    This is the whole Content Understanding pattern in one function:
      1. POST {"inputs":[{"url": url}]} to {analyzer}:analyze
      2. Read the Operation-Location header
      3. GET-poll it until Succeeded / Failed
      4. Serialize the result into the exam-shaped envelope

    Same code path for all four modalities -- only the analyzer ID changes.
    That single-path-for-every-modality is the Lesson 7 architectural pitch.
    """
    _require_config()
    analyzer_id = resolve_analyzer(modality)
    analyze_uri = (
        f"{CU_ENDPOINT}contentunderstanding/analyzers/"
        f"{analyzer_id}:analyze?api-version={CU_API_VERSION}"
    )
    body = {"inputs": [{"url": url}]}

    # --- Step 1 + 2: POST and capture the Operation-Location header ---------
    try:
        post = requests.post(
            analyze_uri, headers=_headers(), json=body, timeout=30
        )
    except requests.RequestException as err:
        raise CUServiceError(
            f"Could not reach the Content Understanding endpoint: {err}",
            status=502,
        ) from err

    if post.status_code not in (200, 202):
        raise _wrap_http_error(post)

    op_location = post.headers.get("Operation-Location")
    if not op_location:
        raise CUServiceError(
            "Analyze accepted but returned no Operation-Location header.",
            status=502,
        )

    # --- Step 3: poll until terminal status ---------------------------------
    deadline = time.monotonic() + POLL_TIMEOUT_SECONDS
    poll_json: dict = {}
    while time.monotonic() < deadline:
        try:
            poll = requests.get(
                op_location,
                headers={"Ocp-Apim-Subscription-Key": CU_KEY},
                timeout=30,
            )
        except requests.RequestException as err:
            raise CUServiceError(
                f"Polling the analyze operation failed: {err}", status=502
            ) from err
        if poll.status_code != 200:
            raise _wrap_http_error(poll)
        poll_json = poll.json()
        status = poll_json.get("status")
        if status == "Succeeded":
            return serialize_result(poll_json, analyzer_id)
        if status == "Failed":
            raise _wrap_failed_result(poll_json)
        time.sleep(POLL_INTERVAL_SECONDS)

    raise CUServiceError(
        f"Analyze did not finish within {POLL_TIMEOUT_SECONDS}s "
        f"(modality '{modality}'). Video can be slow -- retry once.",
        status=504,
    )


def _wrap_http_error(response: requests.Response) -> CUServiceError:
    """Turn a non-2xx REST response into a one-line learner-safe message.

    Calls out the two most likely self-practice failures explicitly: 401 (bad
    key) and 429 (throttle). 400 usually means a malformed body or an
    unreachable input URL.
    """
    status = response.status_code
    detail = ""
    try:
        payload = response.json()
        detail = (
            payload.get("error", {}).get("message")
            or payload.get("message")
            or ""
        )
    except ValueError:
        detail = (response.text or "").strip()[:200]

    hint = ""
    if status == 401:
        hint = " Check CONTENT_UNDERSTANDING_KEY / _ENDPOINT in .env."
    elif status == 429:
        hint = " Rate-limited -- wait a beat and retry."
    elif status == 404:
        hint = " Check the analyzer ID and api-version (2025-11-01)."
    return CUServiceError(
        f"Content Understanding rejected the call: {status}. {detail}{hint}".strip(),
        status=status,
    )


def _wrap_failed_result(poll_json: dict) -> CUServiceError:
    """Surface a Failed operation's inner error as a clean one-liner.

    The most common cause on a fresh resource is a missing model-deployment
    default ('No deployment for model ...').
    """
    err = poll_json.get("error", {}) or {}
    inner = err.get("innererror", {}) or {}
    message = inner.get("message") or err.get("message") or "Analyze failed."
    hint = ""
    if "No deployment for model" in message:
        hint = (
            " Set the resource model-deployment defaults "
            "(set them in Microsoft Foundry or rerun your infrastructure script)."
        )
    return CUServiceError(f"Analyze failed: {message}{hint}", status=400)


# ---------------------------------------------------------------------------
# 3. Serialization -- emit the exam-shaped envelope. Content Understanding
#    returns the SAME outer shape for every modality (analyzerId + contents[],
#    each content with fields/markdown/confidence). We surface that shape
#    verbatim plus a small per-modality "highlights" block the UI can show
#    above the raw JSON, so the JSON pane stays the real teaching surface.
# ---------------------------------------------------------------------------
def serialize_result(poll_json: dict, analyzer_id: str) -> dict:
    """Produce a clean, JSON-serializable envelope from a Succeeded poll.

    Keeps the raw `result` so the JSON pane shows exactly what the service
    returned, and adds a compact `highlights` block per modality so the lab
    has a human-readable headline without scrolling the JSON.
    """
    result = poll_json.get("result", {}) or {}
    contents = result.get("contents", []) or []
    first = contents[0] if contents else {}

    envelope: dict = {
        "analyzerId": result.get("analyzerId", analyzer_id),
        "apiVersion": result.get("apiVersion", CU_API_VERSION),
        "status": poll_json.get("status"),
        "contentCount": len(contents),
        "highlights": _highlights(analyzer_id, contents, first),
        # The raw service result -- THIS is what the Lesson 7 JSON pane teaches.
        "result": result,
    }
    return envelope


def _highlights(analyzer_id: str, contents: list, first: dict) -> dict:
    """A small, modality-aware summary for the UI header.

    Every prebuilt analyzer returns a `fields` object; the *Search analyzers
    put a generated `Summary` there, the invoice analyzer puts the extracted
    invoice fields there. We surface a couple of the highest-signal values so
    the lab reads cleanly even before the JSON pane is scrolled.
    """
    fields = first.get("fields", {}) or {}
    summary = _field_value(fields.get("Summary"))

    if analyzer_id == "prebuilt-invoice":
        return {
            "kind": "document",
            "vendorName": _field_value(fields.get("VendorName")),
            "invoiceId": _field_value(fields.get("InvoiceId")),
            "total": _field_value(fields.get("TotalAmount"))
            or _field_value(fields.get("InvoiceTotal")),
            "fieldCount": len(fields),
        }
    if analyzer_id == "prebuilt-imageSearch":
        return {"kind": "image", "summary": summary}
    if analyzer_id == "prebuilt-audioSearch":
        return {
            "kind": "audio",
            "summary": summary,
            "phraseCount": len(first.get("transcriptPhrases", []) or []),
        }
    if analyzer_id == "prebuilt-videoSearch":
        return {
            "kind": "video",
            "summary": summary,
            "segmentCount": len(contents),
            "keyFrameCount": len(first.get("KeyFrameTimesMs", []) or []),
        }
    return {"kind": "unknown", "summary": summary}


def _field_value(field) -> str | None:
    """Pull a human-readable value out of a Content Understanding field object.

    A field can carry its value under several typed keys depending on the
    field's data type (valueString, valueNumber, valueCurrency, etc.).
    """
    if not isinstance(field, dict):
        return None
    if "valueString" in field:
        return field["valueString"]
    if "valueNumber" in field:
        return str(field["valueNumber"])
    if "valueCurrency" in field:
        cur = field["valueCurrency"] or {}
        code = cur.get("currencyCode", "")
        amount = cur.get("amount", "")
        return f"{code} {amount}".strip() or None
    if "valueDate" in field:
        return field["valueDate"]
    return field.get("content")
