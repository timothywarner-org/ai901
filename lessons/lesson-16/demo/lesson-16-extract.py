"""
Lesson 16 -- Northwind Multimodal Extractor (Azure AI Content Understanding)
============================================================================
Course:  Exam AI-901 -- Microsoft Azure AI Fundamentals (Video)
Role:    The reference for Lesson 16. Northwind Traders drowns in
         unstructured files -- scanned invoices, product photos, support-call
         recordings, training videos -- and wants ONE service that turns any of
         them into structured, machine-readable data. That service is Azure AI
         Content Understanding, and this file is its SDK demonstration.

WHAT CONTENT UNDERSTANDING IS (grounded on MS Learn "Azure AI Content
Understanding", GA API 2025-11-01):
    A single multimodal AI service that extracts semantic content from FOUR
    modalities -- documents, images, audio, and video -- through one client and
    one analyze call. You do NOT wire up a separate service per file type. You
    hand it a file, name a PREBUILT ANALYZER (a ready-made extractor tuned for a
    content category), and it returns structured fields, markdown, transcripts,
    or summaries depending on the modality.

THE PREBUILT ANALYZERS THIS FILE ROUTES TO (exact IDs, grounded):
    * prebuilt-receipt      -- documents (PDF): structured fields (CustomerName,
                               InvoiceTotal, LineItems) WITH per-field confidence.
                               NOTE: for EXAM purposes, invoices map to
                               prebuilt-invoice. As of mid-2026, prebuilt-invoice
                               throws a server-side InternalServerError in every
                               GA region tested (swedencentral AND eastus2), even
                               on Microsoft's own sample invoice. Its sibling
                               domain analyzer, prebuilt-receipt, shares the same
                               field-extraction engine and returns the SAME
                               value-plus-confidence shape. This script demos with
                               prebuilt-receipt until the service-side defect is
                               resolved. The EXAM answer for invoices remains
                               prebuilt-invoice -- the code comment teaches both.
    * prebuilt-imageSearch  -- standalone images: a one-paragraph description.
    * prebuilt-audioSearch  -- audio: transcript with speaker diarization + summary.
    * prebuilt-video        -- video: visual frames + transcript + shot boundaries.
                               NOTE: as of mid-2026, prebuilt-videoSearch throws a
                               server-side InternalServerError in every GA region
                               tested. The base prebuilt-video succeeds on the same
                               file and returns the transcript, diarization,
                               keyframe times, and shot boundaries the lesson
                               teaches. Switch back to prebuilt-videoSearch once
                               Microsoft resolves the service-side defect.

TWO WAYS TO HAND THE SERVICE A FILE (this file uses the LOCAL-FILE path):
    1. begin_analyze_binary(analyzer_id, binary_input=<bytes>) -- read the file
       off disk and send the bytes inline. Use this when the file lives locally
       and is NOT reachable from a public URL (Northwind's files are on a private
       share). THIS is the method we demonstrate.
    2. begin_analyze(analyzer_id, inputs=[AnalysisInput(url=...)]) -- pass a
       public https URL the service fetches itself. Convenient, but only works
       for already-hosted files. We mention it; we do not depend on it.
    Both return an LROPoller -- a long-running-operation handle. Content
    Understanding is ASYNCHRONOUS: the call returns immediately, then .result()
    polls the service until status == Succeeded and hands back the structured
    AnalysisResult. We never poll by hand -- the SDK's poller does it for us.

THE KEYLESS-AUTH PATTERN (same as L10-L15 -- Fundamentals keyless track):
    DefaultAzureCredential -> ContentUnderstandingClient(credential=...). No API
    key is read or stored. The signed-in user (az login) holds the "Cognitive
    Services User" role on the Foundry resource -- the data-plane role Content
    Understanding requires.

ONE-TIME RESOURCE SETUP (why a bare resource is not enough):
    Prebuilt analyzers run ON TOP OF large-language-model deployments you bring
    yourself -- gpt-4.1 + text-embedding-3-large for prebuilt-invoice, and
    gpt-4.1-mini + text-embedding-3-large for the *Search analyzers. The deploy
    script (Deploy-Lesson16-Infrastructure.ps1) creates those deployments AND
    maps them as the resource defaults. If you see "Default model deployment not
    configured", that mapping step has not run -- re-run the deploy script.

How to run:
    az login
    python lesson-16-extract.py ./samples/fabrikam-invoice.pdf        # documents
    python lesson-16-extract.py ./samples/wingtip-shelf.jpg           # images
    python lesson-16-extract.py ./samples/northwind-support-call.wav  # audio
    python lesson-16-extract.py ./samples/adventureworks-promo.mp4    # video
    (No argument prints guidance -- Content Understanding needs a REAL file;
     there is no key-free public default that proves the local-binary path.)
"""

from __future__ import annotations

import mimetypes
import os
import sys

from azure.ai.contentunderstanding import ContentUnderstandingClient
from azure.identity import DefaultAzureCredential
from dotenv import load_dotenv

load_dotenv(override=True)

# ----------------------------------------------------------------------------
# The MIME-type -> prebuilt-analyzer router.
# ----------------------------------------------------------------------------
# Content Understanding does NOT auto-detect which analyzer to use -- YOU name
# the analyzer per call. So we map the file's MIME type (resolved from its
# extension) to the right prebuilt analyzer ID. This table IS the lesson's
# "one service, four modalities" story, expressed as code. Extend it sensibly:
# every document-ish type routes to a document analyzer, every image to the
# image analyzer, and so on.
ANALYZER_BY_MIME = {
    # --- Documents -> prebuilt-receipt (structured fields + per-field confidence) ---
    # WHY prebuilt-receipt and not prebuilt-invoice: as of mid-2026 prebuilt-invoice
    # throws a server-side InternalServerError in every GA region tested
    # (swedencentral AND eastus2), even on Microsoft's own sample invoice. Its
    # sibling domain analyzer, prebuilt-receipt, shares the same field-extraction
    # engine and returns the SAME value-plus-confidence shape on the Fabrikam
    # invoice (InvoiceNumber 0.97, TotalDue 0.997, Subtotal, SalesTax, PaymentTerms,
    # PurchaseOrder, dates). For the EXAM, invoices map to prebuilt-invoice -- we
    # teach that name; we DEMO with prebuilt-receipt until the service-side defect
    # is fixed.
    "application/pdf": "prebuilt-receipt",
    # --- Images -> prebuilt-imageSearch (one-paragraph description) ---
    "image/jpeg": "prebuilt-imageSearch",
    "image/png": "prebuilt-imageSearch",
    "image/bmp": "prebuilt-imageSearch",
    "image/tiff": "prebuilt-imageSearch",
    # --- Audio -> prebuilt-audioSearch (transcript + diarization + summary) ---
    "audio/wav": "prebuilt-audioSearch",
    "audio/x-wav": "prebuilt-audioSearch",
    "audio/mpeg": "prebuilt-audioSearch",   # .mp3
    "audio/mp4": "prebuilt-audioSearch",    # .m4a
    # --- Video -> prebuilt-video (transcript + keyframes + shot boundaries) ---
    # WHY the BASE analyzer, not prebuilt-videoSearch: as of mid-2026 the RAG
    # *Search video analyzer throws a server-side InternalServerError in every
    # GA region tested (swedencentral AND eastus2), while the base prebuilt-video
    # succeeds on the same file/resource/models. Base video still returns the
    # transcript, diarization, keyframe times, and shot boundaries the lesson
    # teaches -- it just omits the RAG one-paragraph summary. Switch back to
    # prebuilt-videoSearch once Microsoft resolves the service-side defect.
    "video/mp4": "prebuilt-video",
    "video/x-msvideo": "prebuilt-video",   # .avi
    "video/quicktime": "prebuilt-video",   # .mov
}

# The confidence gate. prebuilt-receipt (and other document field analyzers)
# return a per-field `confidence` score in [0.0, 1.0]. Below this floor we flag
# the field for HUMAN REVIEW rather than trusting it blindly -- the teachable
# "responsible AI / human-in-the-loop" beat. 0.80 is a sensible Fundamentals
# default; a real Northwind pipeline would tune it per field.
CONFIDENCE_FLOOR = 0.80


def build_credential() -> DefaultAzureCredential:
    """Return a DefaultAzureCredential pinned to the az-login identity.

    Credential guard (same pattern as the L10-L15 clients): on a dev laptop,
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
            f"Missing {name}. Run Deploy-Lesson16-Infrastructure.ps1 and paste "
            f"its output into .env (no keys -- L16 is keyless)."
        )
    return value


# ----------------------------------------------------------------------------
# Keyless ContentUnderstandingClient (built once, reused by every extraction)
# ----------------------------------------------------------------------------
CREDENTIAL = build_credential()
CU_ENDPOINT = require("CU_ENDPOINT")

client = ContentUnderstandingClient(endpoint=CU_ENDPOINT, credential=CREDENTIAL)


def pick_analyzer(path: str) -> tuple[str, str]:
    """Resolve a local file path to (mime_type, analyzer_id).

    We use mimetypes (extension -> MIME) because Content Understanding cares
    about the modality, and the extension is the cheapest reliable signal on a
    local file. If we cannot map it, we fail EARLY and CLEARLY rather than send
    the bytes to the wrong analyzer and get an opaque service error.
    """
    mime, _ = mimetypes.guess_type(path)
    if mime is None:
        raise SystemExit(
            f"Could not determine the MIME type of {path!r} from its extension. "
            f"Supported families: PDF (documents), JPEG/PNG/BMP/TIFF (images), "
            f"WAV/MP3/M4A (audio), MP4/AVI/MOV (video)."
        )
    analyzer = ANALYZER_BY_MIME.get(mime)
    if analyzer is None:
        raise SystemExit(
            f"No prebuilt analyzer mapped for MIME type {mime!r} (file {path!r}). "
            f"Known types: {', '.join(sorted(ANALYZER_BY_MIME))}."
        )
    return mime, analyzer


def confidence_gate(fields: dict) -> None:
    """Walk returned fields and flag any below CONFIDENCE_FLOOR for review.

    This is the human-in-the-loop beat. Document analyzers return a per-field
    `confidence`; *Search analyzers (image/audio/video) generally do NOT, so
    when no field carries a confidence score we say so plainly instead of
    pretending everything passed. Glyphs (not color) carry the pass/flag signal
    so a red/green-colorblind reader gets the same meaning.
    """
    print(f"\n[gate] Confidence gate -- floor = {CONFIDENCE_FLOOR:.2f} (human review below this):")
    if not fields:
        print("[gate]   (no extracted fields on this result -- nothing to gate)")
        return

    scored = 0
    flagged = 0
    for name, field in fields.items():
        confidence = getattr(field, "confidence", None)
        if confidence is None:
            # This analyzer/field does not emit a confidence score (typical for
            # the *Search analyzers). Skip it rather than treat a missing score
            # as a failure.
            continue
        scored += 1
        if confidence < CONFIDENCE_FLOOR:
            flagged += 1
            print(f"[gate]   [FLAG] {name}: {confidence:.2f}  -> route to human review")
        else:
            print(f"[gate]   [ OK ] {name}: {confidence:.2f}")

    if scored == 0:
        print(
            "[gate]   (this analyzer returns no per-field confidence -- "
            "confidence gating applies to document field analyzers like "
            "prebuilt-invoice)"
        )
    else:
        print(f"[gate]   Summary: {scored} field(s) scored, {flagged} flagged for review.")


def show_result(result) -> None:
    """Print a compact, modality-aware view of the structured result.

    Content Understanding returns AnalysisResult.contents -- a list of content
    items. A document is one item with `fields` + `markdown`; audio/video may
    return several items (segments) with `markdown` + a Summary field. We print
    what is present without assuming a shape, then run the confidence gate on
    any document fields.
    """
    contents = getattr(result, "contents", None)
    if not contents:
        print("[result] No content returned -- the file may be empty or unsupported.")
        return

    for index, content in enumerate(contents, start=1):
        print(f"\n[result] --- content item {index} of {len(contents)} ---")

        # Markdown is the common denominator across every modality.
        markdown = getattr(content, "markdown", None)
        if markdown:
            preview = markdown if len(markdown) <= 600 else markdown[:600] + " ... (truncated)"
            print("[result] Markdown:")
            print(preview)

        fields = getattr(content, "fields", None) or {}

        # A one-paragraph Summary is what the *Search analyzers hang their value
        # on -- surface it explicitly when present.
        summary = fields.get("Summary") if fields else None
        if summary is not None and getattr(summary, "value", None):
            print(f"\n[result] Summary: {summary.value}")

        # Audio/video content (AudioVisualContent) exposes a transcript on the
        # content item as `transcript_phrases`; each phrase carries a speaker
        # label (diarization), a start time in milliseconds, and the text.
        phrases = getattr(content, "transcript_phrases", None)
        if phrases:
            print(f"\n[result] Transcript (first 3 of {len(phrases)} phrases):")
            for phrase in phrases[:3]:
                speaker = getattr(phrase, "speaker", "?")
                start_ms = getattr(phrase, "start_time_ms", None)
                text = getattr(phrase, "text", "")
                stamp = f"{start_ms} ms" if start_ms is not None else "--"
                print(f"[result]   [{speaker} @ {stamp}] {text}")

        # Structured fields (e.g. prebuilt-receipt). Print the simple scalar
        # ones compactly; nested object/array fields are summarized by count so
        # the terminal output stays readable.
        if fields:
            scalar = {
                name: getattr(f, "value", None)
                for name, f in fields.items()
                if name != "Summary" and getattr(f, "value", None) is not None
                and not isinstance(getattr(f, "value", None), (list, dict))
            }
            if scalar:
                print("\n[result] Fields:")
                for name, value in scalar.items():
                    print(f"[result]   {name}: {value}")

            # The confidence gate runs on the document fields.
            confidence_gate(fields)


def extract(path: str):
    """Detect the modality, pick the analyzer, submit + poll, and show results.

    This is the heart of the lesson: ONE function handles a PDF, an image, an
    audio clip, or a video, because Content Understanding is one service with a
    per-modality analyzer. We read the file as bytes and send them inline with
    begin_analyze_binary -- the local-file path that never depends on the
    service being able to reach a public URL.
    """
    if not os.path.isfile(path):
        raise SystemExit(f"File not found: {path!r}. Pass a real local file path.")

    mime, analyzer_id = pick_analyzer(path)
    size_kb = os.path.getsize(path) / 1024.0
    print(f"[extract] File:     {path}")
    print(f"[extract] MIME:     {mime}  ({size_kb:.1f} KB)")
    print(f"[extract] Analyzer: {analyzer_id}")

    with open(path, "rb") as handle:
        file_bytes = handle.read()

    print("[extract] Submitting to Content Understanding (async long-running op)...")
    # begin_analyze_binary returns immediately with a poller; .result() polls the
    # service until status == Succeeded, then returns the structured result.
    # WHY pass content_type explicitly: the binary path defaults content_type to
    # "application/octet-stream". Handing the service the real MIME type lets it
    # treat the bytes as the right modality (document vs audio/visual) instead of
    # leaning on the analyzer ID alone -- it costs nothing and removes ambiguity.
    poller = client.begin_analyze_binary(
        analyzer_id=analyzer_id,
        binary_input=file_bytes,
        content_type=mime,
    )
    print("[extract] Polling until status == Succeeded (this can take a moment)...")
    result = poller.result()

    # WHY this guard: the long-running poller returns a result object even when the
    # service terminates the operation as "Failed" -- it does NOT raise. Printing
    # "Succeeded" unconditionally is a silent false-green: you would announce
    # success, then show an empty result. So we verify the real terminal status and
    # that the service actually returned content before claiming success, and we
    # fail loudly otherwise. (Seen live: prebuilt-invoice / prebuilt-videoSearch can
    # throw a server-side InternalServerError that surfaces here as Failed + no
    # contents.) Glyphs carry the signal, not color alone.
    status = None
    try:
        status = poller.status()  # azure-core LRO poller exposes the terminal status
    except Exception:
        status = None  # some poller builds do not expose status() -- fall back to content check

    contents = getattr(result, "contents", None) or []
    if (status is not None and str(status).lower() != "succeeded") or not contents:
        raise SystemExit(
            f"[extract] [FAIL] Analyzer '{analyzer_id}' did NOT succeed "
            f"(status={status!r}, contents={len(contents)}). "
            "This is a real failure. "
            "If the status is Failed/InternalServerError, it is server-side: re-test, "
            "switch the document beat to 'prebuilt-receipt' (proven green), or move "
            "the resource to another Content Understanding GA region."
        )

    print(f"[extract] [ OK ] Succeeded -- {len(contents)} content block(s) returned.")
    show_result(result)
    return result


def main() -> None:
    """Run one extraction.

    Content Understanding has no key-free public default that proves the
    local-binary path -- it needs a REAL file on disk. So with NO argument we
    print clear guidance instead of failing obscurely. With a path argument we
    route by MIME type to the right prebuilt analyzer and extract.
    """
    if len(sys.argv) <= 1:
        print(
            "[main] No file supplied. Content Understanding needs a REAL local "
            "file to extract from -- there is no key-free public default.\n"
            "[main] Pass one of these (the router picks the analyzer for you):\n"
            "[main]   python lesson-16-extract.py ./samples/fabrikam-invoice.pdf        (documents)\n"
            "[main]   python lesson-16-extract.py ./samples/wingtip-shelf.jpg           (images)\n"
            "[main]   python lesson-16-extract.py ./samples/northwind-support-call.wav  (audio)\n"
            "[main]   python lesson-16-extract.py ./samples/adventureworks-promo.mp4    (video)"
        )
        return

    path = sys.argv[1]
    extract(path)
    print("\n[main] Extraction complete: file -> prebuilt analyzer -> structured data.")


# ============================================================================
# EXAM POCKET CARD -- AI-901 4.1 Content Understanding SDK
# ============================================================================
# Memorize these and the AI-901 4.1 code-fill questions become recognition tasks.
#
#   SDK package:    azure-ai-contentunderstanding  (+ azure-identity for keyless)
#   Client class:   ContentUnderstandingClient(endpoint=..., credential=...)
#                   keyless -> credential=DefaultAzureCredential()
#                   data-plane role on the resource: Cognitive Services User
#
#   Local file:     poller = client.begin_analyze_binary(
#                       analyzer_id="prebuilt-...", binary_input=<bytes>,
#                       content_type=<mime>)
#                   -- send the bytes inline; no public URL needed.
#   Hosted URL:     poller = client.begin_analyze(
#                       analyzer_id="prebuilt-...",
#                       inputs=[AnalysisInput(url=...)])
#                   -- the service fetches the file itself.
#   Wait:           result = poller.result()   # blocks until status == Succeeded
#
#   Result shape:   result.contents[0].markdown                 # RAG-ready Markdown
#                   result.contents[0].fields["X"].value        # the extracted value
#                   result.contents[0].fields["X"].confidence   # 0.0 - 1.0 (opt-in)
#                   audio/video -> AudioVisualContent.transcript_phrases[i]
#                                  .speaker / .start_time_ms / .text  (diarization)
#
#   Async workflow: POST -> HTTP 202 + Operation-Location header -> poll until Succeeded
#   API version:    2025-11-01 (GA)    preview versions retire 2026-07-15
#   Base analyzers: prebuilt-document | prebuilt-image | prebuilt-audio | prebuilt-video
#   RAG analyzers:  prebuilt-documentSearch | imageSearch | audioSearch | videoSearch
#   Confidence:     opt-in via estimateFieldSourceAndConfidence; gate with CONFIDENCE_FLOOR
#   Invoice exam answer: prebuilt-invoice (maps invoices to structured fields)
#   Invoice demo workaround (mid-2026): prebuilt-receipt (same engine; invoice is
#       down server-side) -- both teach the value+confidence pattern identically
# ============================================================================


if __name__ == "__main__":
    main()
