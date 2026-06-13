"""
Lesson 6 -- Azure AI Vision web app (Flask backend)
====================================================
Course:  Exam AI-901 -- Microsoft Azure AI Fundamentals (Video)
Role:    Local lab surface for Lesson 6. This app talks straight to
         the Azure AI Vision resource via the Image Analysis 4.0 SDK --
         no external portal dependency.

         The architectural teaching point: ImageAnalysisClient takes a
         URL (server-side fetch) OR raw bytes (file upload); the same
         client class handles both paths. The SDK sample at sdk/lesson-06-vision.py
         uses the identical client, so the web app and the script tell one
         coherent story.

Two routes only:
    GET  /          -> the single-page UI.
    POST /analyze   -> run the SDK against a URL or an uploaded file,
                       return the serialized result the front end renders.

Run (local only -- never exposed):
    python -m flask --app app run
    open http://127.0.0.1:5000
"""

from __future__ import annotations

from urllib.parse import urlparse

import requests
from flask import Flask, Response, jsonify, render_template, request

import vision_client

app = Flask(__name__)

# 20 MB matches the Image Analysis service's own image-size ceiling, so we
# reject oversize uploads before wasting a service round-trip.
app.config["MAX_CONTENT_LENGTH"] = 20 * 1024 * 1024


@app.get("/")
def index():
    """Render the single-page Vision lab surface."""
    return render_template("index.html")


@app.get("/proxy-image")
def proxy_image():
    """Re-serve a remote image from THIS origin so the canvas can draw it.

    Why this exists: the browser blocks canvas pixel access for cross-origin
    images whose host sends no CORS headers (aka.ms, learn.microsoft.com,
    most image CDNs). Without a proxy the 'Boxes on image' pane falls back to
    a blank grid. Fetching the bytes server-side and returning them same-origin
    sidesteps CORS entirely -- boxes always overlay the real image.

    Scope guard: only http(s) URLs; we stream the response back with its
    original content-type. This is a local-loopback lab aid, not a public
    open proxy.
    """
    url = (request.args.get("url") or "").strip()
    parsed = urlparse(url)
    if parsed.scheme not in ("http", "https"):
        return Response("Only http(s) image URLs are allowed.", status=400)
    try:
        upstream = requests.get(url, timeout=15, stream=True)
        upstream.raise_for_status()
    except requests.RequestException as err:
        return Response(f"Could not fetch image: {err}", status=502)

    content_type = upstream.headers.get("Content-Type", "application/octet-stream")
    if not content_type.startswith("image/"):
        # Refuse to relay non-image bodies -- keeps the proxy single-purpose.
        return Response("URL did not return an image.", status=415)
    return Response(upstream.content, content_type=content_type)


@app.post("/analyze")
def analyze():
    """Run Image Analysis against a URL or an uploaded image.

    Accepts two shapes:
      - JSON body  {"mode": "url", "url": "...", "features": [...]}
      - multipart  file=<image>, features=<comma-joined>, mode=file

    Returns the serialized result dict (200) or a learner-friendly
    {"error": "..."} with a sensible status code.
    """
    try:
        if request.content_type and request.content_type.startswith(
            "multipart/form-data"
        ):
            data = _handle_file_request()
        else:
            data = _handle_url_request()
        return jsonify(data)
    except vision_client.VisionServiceError as err:
        # Service/transport failure (401, 429, 400, network) -- one clean line.
        return jsonify({"error": str(err)}), err.status
    except vision_client.VisionConfigError as err:
        # .env not populated -- configuration problem, not a service problem.
        return jsonify({"error": str(err)}), 500


def _handle_url_request() -> dict:
    """Parse a JSON body and run the server-side-fetch analyze path."""
    body = request.get_json(silent=True) or {}
    url = (body.get("url") or "").strip()
    features = body.get("features") or []
    if not url:
        raise vision_client.VisionServiceError(
            "No image URL provided.", status=400
        )
    return vision_client.analyze_url(url, features)


def _handle_file_request() -> dict:
    """Parse a multipart upload and run the byte-stream analyze path."""
    upload = request.files.get("file")
    if upload is None or upload.filename == "":
        raise vision_client.VisionServiceError(
            "No image file uploaded.", status=400
        )
    # Front end sends features as a comma-joined string in the form field.
    raw_features = request.form.get("features", "")
    features = [f for f in raw_features.split(",") if f]
    return vision_client.analyze_bytes(upload.read(), features)


if __name__ == "__main__":
    # Bind to loopback only -- local lab, never a public server.
    # debug=False so a stray exception shows our banner, not Werkzeug's
    # interactive debugger.
    app.run(host="127.0.0.1", port=5000, debug=False)
