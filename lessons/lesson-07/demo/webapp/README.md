# Lesson 7 -- Azure AI Content Understanding Web App

A local Flask web app that calls the **Azure AI Content Understanding** GA REST API
(api-version 2025-11-01) and renders the structured JSON envelope for four modalities:
Document, Image, Audio, and Video.

The architectural teaching point: every tab hits the SAME `/analyze/<modality>` route
and the SAME `cu_client.analyze()` function. Only the analyzer ID changes. Study this
structure -- it is the exam answer to "how does Content Understanding handle multiple
modalities?" The raw-JSON pane shows that every modality returns the same outer
envelope shape (`analyzerId`, `contents[]`, `fields`).

| Tab | Analyzer ID | Returns |
| --- | --- | --- |
| Document | prebuilt-invoice | extracted invoice fields + per-field confidence |
| Image | prebuilt-imageSearch | natural-language Summary |
| Audio | prebuilt-audioSearch | transcript (WEBVTT) + summary |
| Video | prebuilt-videoSearch | scene segments + key frames + transcript |

---

## Prerequisites

- Python 3.12 or later
- A **Microsoft Foundry** (Azure AI services) resource in a region that supports
  Content Understanding (East US recommended)
- The resource endpoint and Key 1 or Key 2 (Azure portal > Keys and Endpoint)
- Model-deployment defaults configured on the resource:
  - `gpt-4.1` or `gpt-4.1-mini` for generative fields
  - `text-embedding-3-large` for embedding-based analyzers

  If an analyze call fails with "No deployment for model ...", set the model-deployment
  defaults in Microsoft Foundry (portal.azure.com > your AI services resource >
  Model deployments).

---

## Configure

```powershell
# From this folder (lessons/lesson-07/demo/webapp/)
Copy-Item .env.example .env
# Open .env and paste CONTENT_UNDERSTANDING_ENDPOINT and CONTENT_UNDERSTANDING_KEY
```

Never commit `.env` to source control -- it contains your resource key.

---

## Install and run

```powershell
# From this folder
python -m venv .venv
.venv\Scripts\Activate.ps1
pip install -r requirements.txt

python -m flask --app app run
```

Open **http://127.0.0.1:5000** in a browser. The app binds to loopback only and is
never exposed to the network.

Run one app at a time -- do not start two Flask servers on the same port.

---

## Using the app

### Workflow per modality tab

1. Select a tab (Document, Image, Audio, or Video).
2. Read the "What it does" and "On the AI-901 exam" panels to ground the capability
   in exam language before running it.
3. The URL field is pre-filled with the official Microsoft sample for that modality.
   Click **Preview asset** to open the raw file in a new tab and see what you are
   about to analyze.
4. Click **Analyze**. The app POST-and-polls the Content Understanding REST API until
   the operation succeeds (or times out at 120 seconds).
5. Study the **highlights** block (quick summary) and then the **raw JSON pane**
   (the actual service response). The JSON pane is the teaching surface.

### Expected timings

| Modality | Expected time |
| --- | --- |
| Document | ~25 seconds |
| Image | ~4 seconds |
| Audio | ~15 seconds |
| Video | ~49 seconds |

These are approximate. Audio and Video are long-running operations -- the status
line will say "this modality can take 30-45 seconds..." so you know the wait is normal.

### Async pattern

The client POSTs `{"inputs":[{"url":...}]}`, reads the `Operation-Location` header,
and polls until `Succeeded` or `Failed`. This is the same shape the SDK sample uses.
Understanding this pattern is part of the AI-901 exam objective.

### Rate limit note

If you see a 429 error, wait a beat and retry.

---

## File map

```text
webapp/
  app.py              -- Flask routes: GET / and POST /analyze/<modality>
  cu_client.py        -- REST client, analyzer map, and result serializer
  templates/
    index.html        -- Single-page UI (Jinja2 template)
  static/
    cu-app.js         -- Front-end controller (tab switching + fetch + JSON render)
    cu-styles.css     -- Two-column layout, accessible status states
  .env.example        -- Variable template; copy to .env and fill in values
  requirements.txt    -- Python dependencies
```
