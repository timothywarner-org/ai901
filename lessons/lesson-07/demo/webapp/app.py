"""
Lesson 7 -- Azure AI Content Understanding web app (Flask backend)
==================================================================
Course:  Exam AI-901 -- Microsoft Azure AI Fundamentals (Video)
Role:    Local lab surface for Lesson 7. This app talks straight to the
         GA Content Understanding REST API (key auth from .env) and renders
         the JSON envelope -- one analyzer per modality, four tabs, one
         response shape.

         The architectural teaching point: every tab hits the SAME
         /analyze/<modality> route and the SAME cu_client.analyze() function;
         only the analyzer ID changes. That single-path-for-every-modality
         structure is the Lesson 7 teaching point in code form.

Two route groups only:
    GET  /                  -> the single-page four-tab UI.
    POST /analyze/<modality> -> run the matching prebuilt analyzer against
                                the official Microsoft sample for that
                                modality (or a URL the learner supplies) and
                                return the serialized envelope.

Run (local only -- never exposed):
    python -m flask --app app run
    open http://127.0.0.1:5000
"""

from __future__ import annotations

from flask import Flask, jsonify, render_template, request

import cu_client

app = Flask(__name__)

# Content Understanding pulls the input by URL server-side, so this app never
# receives large uploads. A small cap keeps any accidental POST body bounded.
app.config["MAX_CONTENT_LENGTH"] = 1 * 1024 * 1024


@app.get("/")
def index():
    """Render the single-page Content Understanding lab surface.

    Passes the modality -> sample-URL map so each tab can pre-fill its input
    with the official Microsoft sample for zero-typing self-practice.
    """
    return render_template(
        "index.html",
        samples=cu_client.SAMPLE_URLS,
        analyzers=cu_client.ANALYZER_MAP,
        modality_info=cu_client.MODALITY_INFO,
        api_version=cu_client.CU_API_VERSION,
    )


@app.post("/analyze/<modality>")
def analyze(modality: str):
    """Run the prebuilt analyzer for one modality and return the envelope.

    Body (JSON, optional): {"url": "..."} to override the modality's default
    Microsoft sample. With no body, the official sample for that modality is
    used -- so the lab works with a single button click and no typing.

    Returns the serialized envelope (200) or a learner-friendly
    {"error": "..."} with a sensible status code.
    """
    try:
        body = request.get_json(silent=True) or {}
        url = (body.get("url") or "").strip() or cu_client.SAMPLE_URLS.get(
            modality
        )
        if not url:
            return (
                jsonify(
                    {
                        "error": (
                            f"No URL provided and no sample registered for "
                            f"modality '{modality}'."
                        )
                    }
                ),
                400,
            )
        envelope = cu_client.analyze(modality, url)
        return jsonify(envelope)
    except cu_client.CUServiceError as err:
        # Service/transport failure (401, 429, 400, 404, network) -- one line.
        return jsonify({"error": str(err)}), err.status
    except cu_client.CUConfigError as err:
        # .env not populated -- configuration problem, not a service problem.
        return jsonify({"error": str(err)}), 500


if __name__ == "__main__":
    # Bind to loopback only -- local lab, never a public server.
    # debug=False so a stray exception shows our clean banner, not Werkzeug's
    # interactive debugger.
    app.run(host="127.0.0.1", port=5000, debug=False)
