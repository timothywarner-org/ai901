# Lesson 07 Demo -- Information Extraction and Content Understanding

This demo provisions a Microsoft Foundry resource with three model deployments
required by Azure AI Content Understanding (GA, api-version 2025-11-01), then runs
a short Python script that calls the `prebuilt-invoice` analyzer and prints the
extracted fields with confidence scores.

**AI-901 objectives:** 1.5.1 (cross-modality extraction), 1.5.2 (Content Understanding
fundamentals), 1.5.3 (rule-based / ML / multimodal trade-offs).

---

## Prerequisites

- **Python 3.12** -- verify with `python --version`
- **PowerShell 7.4 or later** -- verify with `$PSVersionTable.PSVersion`
- **Azure CLI 2.51 or later** -- install from <https://aka.ms/install-azure-cli>
- **An Azure subscription** where you can create Cognitive Services resources
  and assign roles (Contributor + User Access Administrator, or Owner)
- **Signed in** to the correct subscription:
  ```powershell
  az login
  az account set --subscription "<your subscription name or id>"
  ```

---

## Provision the resources

Run the deploy script from the `demo/` folder:

```powershell
cd lessons\lesson-07\demo
.\Deploy-Lesson07-Infrastructure.ps1
```

The script is **idempotent** -- re-running it after a partial failure is safe.
It also runs two smoke tests at the end:

1. A chat completion to verify the `gpt-4.1` deployment is live.
2. A real Content Understanding `prebuilt-invoice` analyze to verify the full
   POST-and-poll path works end to end.

**Resources created:**

| Resource | Purpose |
| --- | --- |
| `rg-ai901-lesson07-demo` | Resource group for all lesson resources |
| `ai901-lesson07-foundry` (AIServices, S0) | Foundry resource hosting Content Understanding GA |
| `ai901-lesson07-project` | Foundry project |
| `gpt-4.1` deployment (GlobalStandard) | Powers prebuilt-invoice, prebuilt-receipt |
| `gpt-4.1-mini` deployment (GlobalStandard) | Powers prebuilt-imageSearch, audioSearch, videoSearch |
| `text-embedding-3-large` deployment (GlobalStandard) | Required by every generative analyzer |
| Cognitive Services User role (signed-in user) | Required for data-plane access |

**Why three model deployments?**
Azure AI Content Understanding GA (2025-11-01) has no managed model capacity.
Every prebuilt analyzer calls YOUR model deployments. Without the three deployments
and the resource-level alias mapping the deploy script sets, the first analyzer call
returns HTTP 400 "no model deployment configured."

**Cleanup when you are done:**

```powershell
.\Deploy-Lesson07-Infrastructure.ps1 -Cleanup
```

---

## Configure

Copy the example environment file and fill in your own values:

```powershell
copy .env.example .env
```

Open `.env` and replace the placeholder values:

```
CONTENT_UNDERSTANDING_ENDPOINT=https://YOUR-RESOURCE-NAME.cognitiveservices.azure.com/
CONTENT_UNDERSTANDING_KEY=PASTE_YOUR_FOUNDRY_KEY1_HERE
CONTENT_UNDERSTANDING_API_VERSION=2025-11-01
```

Get your endpoint and key from the deploy script output, or run:

```powershell
# Endpoint
az cognitiveservices account show `
  -g rg-ai901-lesson07-demo -n ai901-lesson07-foundry `
  --query properties.endpoint -o tsv

# Key (copy the full value into .env)
az cognitiveservices account keys list `
  -g rg-ai901-lesson07-demo -n ai901-lesson07-foundry `
  --query key1 -o tsv
```

**Do not commit `.env` to source control.** The `.gitignore` at the repo root
already excludes it.

---

## Install

```powershell
cd lessons\lesson-07\demo
python -m venv .venv
.venv\Scripts\Activate.ps1
pip install -r requirements.txt
```

---

## Run

```powershell
python lesson-07-content-understanding.py
```

---

## What you should see

```
Endpoint:   https://YOUR-RESOURCE-NAME.cognitiveservices.azure.com/
Analyzer:   prebuilt-invoice
API ver:    2025-11-01
Key:        ****XXXX  (last 4 only)

POST + poll (Content Understanding is async)...

status:     Succeeded
analyzerId: prebuilt-invoice
contents:   1
fields:     22 extracted

  VendorName    : Contoso Ltd.  (confidence 0.99)
  CustomerName  : Microsoft Corp.  (confidence 0.98)
  InvoiceId     : INV-1234  (confidence 0.97)
  InvoiceDate   : 2024-01-15  (confidence 0.99)

=== Content Understanding -- exam pocket card =================================
 Endpoint shape : {endpoint}/contentunderstanding/analyzers/{id}:analyze
                  ?api-version=2025-11-01
 ...
===============================================================================
```

---

## Practice on your own

1. **Try a different prebuilt analyzer.** Change `ANALYZER_ID` in the script from
   `prebuilt-invoice` to `prebuilt-imageSearch`. Change `SAMPLE_URL` to a publicly
   accessible image URL. Run the script. What fields does the image analyzer return?

2. **Try the confidence threshold.** The script prints a confidence score per field.
   What happens if you set a threshold -- for example, "only print fields with
   confidence > 0.90"? Add a filter to the loop and re-run.

3. **Try Content Understanding Studio.** Open <https://aka.ms/cu-studio>,
   connect the `ai901-lesson07-foundry` resource, and upload a different PDF
   (a receipt, a business card, or your own document). How does the field
   extraction change? Does the confidence score change with document quality?

4. **Compare to a rule-based approach.** Imagine extracting the same fields
   (VendorName, InvoiceDate, Total) with a regex-based parser. What would you need
   to write? How does the Content Understanding approach differ in terms of
   maintenance cost and adaptability to new document layouts?

---

## Exam connection

- **Async POST-and-poll** is the signature pattern for Content Understanding, Azure
  AI Document Intelligence, Speech batch transcription, and Azure AI Video Indexer.
  The exam tests your ability to recognize this pattern and identify the correct
  header (`Operation-Location`) and terminal states (`Succeeded`, `Failed`).
- **One analyzer, four modalities** -- the same `:analyze` endpoint and request
  body works for documents, images, audio, and video. You swap the `analyzerId`;
  the code path never changes. The exam tests this "unified envelope" concept.
- **Confidence scores** -- Content Understanding returns a confidence value per
  extracted field. The exam expects you to understand that higher confidence means
  the model is more certain about the extracted value -- and that confidence is not
  the same as accuracy.
- **GA api-version 2025-11-01** -- the exam aligns to GA features. "Pro mode"
  (multi-step cross-document reasoning) is preview-only and not tested.
