# Lesson 6 -- Azure AI Vision Web App

A local Flask web app that calls the **Azure AI Vision** Image Analysis 4.0 API
and renders three views of the result: bounding boxes on a canvas, a pretty summary,
and the raw JSON envelope.

The architectural teaching point: `ImageAnalysisClient` handles both a hosted image
URL (server-side fetch by Azure) and raw bytes (local file upload) -- the same client
class, two input modes. The Python SDK sample at `sdk/lesson-06-vision.py` uses the
identical `ImageAnalysisClient`, so the web app and the script tell one coherent story.

---

## Prerequisites

- Python 3.12 or later
- An **Azure AI Vision** resource (Computer Vision, any region that supports Caption --
  East US qualifies)
- The resource's endpoint and Key 1 or Key 2 (from Azure portal > Keys and Endpoint)

---

## Provision the Azure resource

1. In the Azure portal, create a **Computer Vision** resource (free F0 tier works for
   self-practice; note the ~20 calls/min rate limit on F0).
2. Copy the endpoint (format: `https://YOUR-RESOURCE-NAME.cognitiveservices.azure.com/`)
   and either key from the **Keys and Endpoint** blade.

---

## Configure

```powershell
# From this folder (lessons/lesson-06/demo/webapp/)
Copy-Item .env.example .env
# Open .env and paste VISION_ENDPOINT and VISION_KEY
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

### Operations

| Operation group | VisualFeatures enum values | Output shape |
| --- | --- | --- |
| Caption | CAPTION, DENSE_CAPTIONS | sentence + confidence (dense adds region boxes) |
| Detection | OBJECTS, PEOPLE | label + bounding box + confidence per instance |
| OCR | READ | text + bounding polygon + confidence per line/word |
| Tagging and cropping | TAGS, SMART_CROPS | label + confidence; crop rectangles |

### Three result views

- **Boxes on image** -- canvas overlay with labeled, styled bounding boxes. Each box
  type uses a distinct line style AND a text label so it is readable without relying
  on color alone.
- **Pretty results** -- human-readable summary of every detected item.
- **Raw JSON** -- the exact JSON the SDK returned. Study this pane: the key shapes
  (`boundingBox` with `x/y/w/h`, `boundingPolygon` with point arrays) are what the
  AI-901 exam tests.

### Image URL vs. file upload

- **Image URL** -- Azure fetches the image server-side. Use
  `https://aka.ms/azsdk/image-analysis/sample.jpg` as a starting point. Some image
  hosts block the canvas draw due to CORS; the app proxies the image through
  `/proxy-image` to work around this.
- **Upload local file** -- sends the raw bytes to Azure. Use this path to analyze your
  own images and to demonstrate the byte-stream SDK method.

### Rate limit note

The F0 (free) tier allows approximately 20 calls per minute. If you see a 429 error,
wait a few seconds and retry. The app displays a clear banner with the rate-limit hint.

---

## File map

```text
webapp/
  app.py              -- Flask routes: GET / and POST /analyze
  vision_client.py    -- ImageAnalysisClient wrapper and result serializer
  templates/
    index.html        -- Single-page UI (Jinja2 template)
  static/
    app.js            -- Front-end controller (canvas + tabs + fetch)
    styles.css        -- Two-column layout, accessible status states
  .env.example        -- Variable template; copy to .env and fill in values
  requirements.txt    -- Python dependencies
```
