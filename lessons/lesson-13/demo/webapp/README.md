# Lesson 13 -- Azure AI Language Web App (keyless)

A local Flask web app that calls **Azure AI Language** via keyless auth
(`DefaultAzureCredential`) and renders the raw SDK JSON for four language skills.

The architectural teaching point: one `TextAnalyticsClient`, four skills, one `/analyze/<skill>`
route. Every button hits the same client dispatch; only the skill name changes. The raw-JSON
panel shows exactly what the SDK returned -- study that shape, because the JSON keys
(`document_sentiment`, `entities`, `key_phrases`, `extractive`, `abstractive`) are what
the AI-901 exam tests.

| Button | SDK method | Returns |
| --- | --- | --- |
| Entities | `recognize_entities()` | entity text, category, confidence |
| Key phrases | `extract_key_phrases()` | list of key-phrase strings |
| Sentiment + opinions | `analyze_sentiment(show_opinion_mining=True)` | document label, scores, opinion pairs |
| Summarize | `begin_extract_summary()` + `begin_abstract_summary()` | extractive sentences + abstractive text |

---

## Auth -- keyless only

This app uses `DefaultAzureCredential`, not a key. That means:

1. The `LANGUAGE_ENDPOINT` in `.env` must be the **custom-subdomain** form
   (`https://YOUR-RESOURCE-NAME.cognitiveservices.azure.com/`). The regional
   endpoint (`https://eastus.api.cognitive.microsoft.com/`) does NOT work with
   Entra auth.
2. The signed-in identity needs the **Cognitive Services User** role on the
   Language resource. Role assignment can take up to 5 minutes to propagate.
3. Run `az login` before starting Flask, or ensure another supported credential
   (managed identity, environment) is active.

---

## Prerequisites

- Python 3.12 or later
- Azure CLI (`az login`) -- required for `DefaultAzureCredential` in local development
- An **Azure AI Language** resource with a custom-subdomain endpoint
- The "Cognitive Services User" role assigned to your identity on that resource

---

## Provision the Azure resource

1. In the Azure portal, create an **Azure AI Language** resource. During creation,
   enter a unique custom name -- this becomes the subdomain in your endpoint.
2. In the resource's **Access control (IAM)** blade, add a role assignment:
   Role = "Cognitive Services User", Member = your Microsoft Entra ID account (or managed identity).
3. Copy the endpoint from the **Keys and Endpoint** blade (custom-subdomain form only).
4. Run `az login` to authenticate on your machine.

---

## Configure

```powershell
# From this folder (lessons/lesson-13/demo/webapp/)
Copy-Item .env.example .env
# Open .env and paste LANGUAGE_ENDPOINT (custom-subdomain form)
# No key needed
```

Never commit `.env` to source control.

---

## Install and run

```powershell
# From this folder
python -m venv .venv
.venv\Scripts\Activate.ps1
pip install -r requirements.txt

az login                              # authenticate for DefaultAzureCredential
python -m flask --app app run
```

Open **http://127.0.0.1:5000** in a browser. The app binds to loopback only and is
never exposed to the network.

Run one app at a time -- do not start two Flask servers on the same port.

---

## Using the app

1. Read (or modify) the sample review text in the textarea. The pre-filled text
   covers multiple sentiment polarities and named entities so all four skills
   produce interesting output.
2. Click a skill button. The button label names the SDK method being called.
3. Read the raw JSON. The `skill` and `method` keys in the response tell you
   exactly which SDK call produced the result.
4. The **Summarize** skill calls two long-running operations (`begin_extract_summary`
   and `begin_abstract_summary`) and blocks until both finish -- expect a few seconds.

### Keyless auth troubleshooting

| Symptom | Likely cause | Fix |
| --- | --- | --- |
| 403 error | Role not assigned or not propagated | Wait 5 minutes; confirm role in Azure portal IAM |
| 401 error | Wrong endpoint format | Use custom-subdomain endpoint, not regional endpoint |
| No credential found | `az login` not run | Run `az login` in the same terminal session |

---

## About lesson-13-ui.py

The source folder also contains `lesson-13-ui.py`, a **Streamlit** version of the
same lab. It is kept as a separate optional entry point for learners who prefer
Streamlit's interactive widgets over a plain HTML page.

To run the Streamlit version (same `.env`, same `ta_client.py`):

```powershell
pip install streamlit
streamlit run lesson-13-ui.py
# Streamlit opens http://localhost:8501 automatically
```

The Flask app (`app.py`) and the Streamlit app (`lesson-13-ui.py`) both import
`ta_client.py` and share `LANGUAGE_ENDPOINT` from `.env`, so you only configure once.

---

## File map

```text
webapp/
  app.py              -- Flask routes: GET / and POST /analyze/<skill>
  ta_client.py        -- TextAnalyticsClient wrapper and SKILLS dispatch table
  lesson-13-ui.py     -- Optional Streamlit entry point (same ta_client)
  templates/
    index.html        -- Single-page UI (Jinja2 template)
  static/
    app.js            -- Front-end controller (fetch + JSON render)
  .env.example        -- Variable template; copy to .env and fill in values
  requirements.txt    -- Python dependencies (Flask + SDK + identity)
```
