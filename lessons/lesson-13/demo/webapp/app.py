"""
Lesson 13 -- Azure AI Language web app (Flask backend)
=======================================================
Course:  Exam AI-901 -- Microsoft Azure AI Fundamentals (Video)
Role:    Local lab surface for Lesson 13. The Lesson 13 learning objective
         is "display text-analysis results in a client UI", and this tiny
         Flask app is that client UI: four buttons, four Azure AI Language
         skills, one JSON panel.

         The architectural teaching point: every button hits the SAME
         /analyze/<skill> route and the SAME ta_client dispatch -- only the
         skill name changes. That "one client, four skills" shape is the
         Lesson 13 teaching point in code form.

Auth is KEYLESS (DefaultAzureCredential) -- the Lesson 13 pattern. The .env
holds only LANGUAGE_ENDPOINT and is never opened by the app. No key is needed;
the signed-in identity needs the "Cognitive Services User" role.

Two route groups only:
    GET  /                -> the single-page four-button UI.
    POST /analyze/<skill> -> run one Language skill against the posted text and
                             return the JSON the SDK produced.

Run (local only -- never exposed):
    python -m flask --app app run
    open http://127.0.0.1:5000
"""

from __future__ import annotations

from flask import Flask, jsonify, render_template, request

import ta_client

app = Flask(__name__)

# Text is posted in the request body; cap it so an accidental huge paste is bounded.
app.config["MAX_CONTENT_LENGTH"] = 256 * 1024


@app.get("/")
def index():
    """Render the single-page lab surface with the sample review pre-filled."""
    return render_template(
        "index.html",
        sample=ta_client.SAMPLE_REVIEW,
        skills=list(ta_client.SKILLS.keys()),
    )


@app.post("/analyze/<skill>")
def analyze(skill: str):
    """Run one Language skill against the posted text and return the JSON.

    Body (JSON): {"text": "..."}. Returns the serialized result (200) or a
    learner-friendly {"error": "..."} with a sensible status code.
    """
    fn = ta_client.SKILLS.get(skill)
    if fn is None:
        return jsonify({"error": f"Unknown skill '{skill}'."}), 404

    body = request.get_json(silent=True) or {}
    text = (body.get("text") or "").strip()
    if not text:
        return jsonify({"error": "No text supplied to analyze."}), 400

    try:
        return jsonify(fn(text))
    except ta_client.TAServiceError as err:
        return jsonify({"error": str(err)}), err.status
    except ta_client.TAConfigError as err:
        return jsonify({"error": str(err)}), 500


if __name__ == "__main__":
    # Loopback only -- local lab, never a public server. debug=False
    # so a stray exception shows our clean JSON, not Werkzeug's debugger.
    app.run(host="127.0.0.1", port=5000, debug=False)
