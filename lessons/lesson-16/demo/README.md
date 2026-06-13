# Lesson 16 Demo -- Content Understanding Multimodal Extractor

One Python script on one Azure AI Content Understanding resource that extracts
structured data from four file types -- a PDF invoice, a product image, an audio
support call, and a promotional video -- using one client and one analyze call.
Covers AI-901 exam objectives 2.4.1 -- 2.4.4.

---

## Prerequisites

- Python 3.12
- Azure CLI (`az`) with an active `az login` session
- An Azure subscription with quota for gpt-4.1 and gpt-4.1-mini (GlobalStandard)
  and text-embedding-3-large (Standard) in Sweden Central (or your chosen region)

---

## Provision the resources

Run the deploy script once. Pass a **globally unique** `-FoundryName` -- AIServices
custom subdomains are a global namespace across all Azure tenants.

```powershell
.\Deploy-Lesson16-Infrastructure.ps1 -FoundryName my-ai901-l16-foundry
```

The script provisions:

- One AIServices resource (kind=AIServices, S0) with a custom subdomain
  (required for keyless / Entra token auth AND for Content Understanding)
- Three model deployments (all required by the prebuilt analyzers):
  - `gpt-4.1` (GlobalStandard) -- backs field analyzers (prebuilt-invoice etc.)
  - `gpt-4.1-mini` (GlobalStandard) -- backs the RAG *Search analyzers
  - `text-embedding-3-large` (Standard) -- embeddings for every analyzer
- RBAC: **Cognitive Services User** on the resource for your az-login identity

**One-time default model mapping** -- after provisioning, you must run
`sample_update_defaults.py` from the `azure-ai-contentunderstanding` SDK samples
(or use the Foundry portal: Content Understanding -> Settings -> Default models)
to tell the analyzers which deployments to use. The deploy script prints the exact
copy-paste commands. Until this step runs, you will see:

```
Default model deployment not configured
```

---

## Configure

```powershell
# Copy the template; fill in the CU_ENDPOINT value from the deploy script output
copy .env.example .env
notepad .env
```

Never commit `.env`.

---

## Install

```powershell
python -m venv .venv
.venv\Scripts\Activate.ps1
pip install -r requirements.txt
```

---

## Run

The router in `lesson-16-extract.py` reads the file extension to determine the
MIME type, then picks the correct prebuilt analyzer automatically.

```powershell
# Documents (PDF) -- prebuilt-receipt (structured fields + confidence)
python lesson-16-extract.py ./samples/fabrikam-invoice.pdf

# Images (JPEG) -- prebuilt-imageSearch (one-paragraph description)
python lesson-16-extract.py ./samples/wingtip-shelf.jpg

# Audio (WAV) -- prebuilt-audioSearch (transcript + diarization + summary)
python lesson-16-extract.py ./samples/northwind-support-call.wav

# Video (MP4) -- prebuilt-video (transcript + keyframes + shot boundaries)
python lesson-16-extract.py ./samples/adventureworks-promo.mp4
```

---

## What you should see

**Invoice (PDF):**

```
[extract] File:     ./samples/fabrikam-invoice.pdf
[extract] MIME:     application/pdf  (45.2 KB)
[extract] Analyzer: prebuilt-receipt
[extract] Submitting to Content Understanding (async long-running op)...
[extract] Polling until status == Succeeded (this can take a moment)...
[extract] [ OK ] Succeeded -- 1 content block(s) returned.

[result] --- content item 1 of 1 ---
[result] Fields:
[result]   InvoiceTotal: 1234.56
[result]   CustomerName: Fabrikam Industries

[gate] Confidence gate -- floor = 0.80 (human review below this):
[gate]   [ OK ] InvoiceTotal: 0.997
[gate]   [ OK ] CustomerName: 0.970
[gate]   Summary: 2 field(s) scored, 0 flagged for review.
```

**Audio (WAV):**

```
[extract] Analyzer: prebuilt-audioSearch
[extract] [ OK ] Succeeded -- 1 content block(s) returned.
[result] Transcript (first 3 of N phrases):
[result]   [Speaker0 @ 500 ms] Thank you for calling Northwind Traders support.
[result]   [Speaker1 @ 2100 ms] Hi, I have a question about my order.
```

If a service-side error occurs (status=Failed), the script prints a clear
`[FAIL]` message -- it does NOT silently claim success on an empty result.

---

## Practice on your own

1. **Raise the confidence floor** -- open `lesson-16-extract.py` and change
   `CONFIDENCE_FLOOR = 0.80` to `0.95` and re-run on the invoice. Observe
   which fields get flagged for human review.

2. **Try your own image or audio** -- drop a JPEG or WAV into `samples/` and
   run the script. The router picks the analyzer from the file extension.

3. **Test the false-green guard** -- temporarily set `CONFIDENCE_FLOOR = 1.1`
   (above the maximum 1.0) so every scored field fails, and observe the
   `[FLAG]` output. Then restore it to 0.80.

4. **Read the Exam Pocket Card** at the bottom of `lesson-16-extract.py` --
   it lists every class, method, and result shape the exam tests.

---

## Exam connection

| AI-901 objective | What this demo shows |
| --- | --- |
| 2.4.1 Extract from documents and forms | `prebuilt-receipt` on fabrikam-invoice.pdf; field+confidence shape |
| 2.4.2 Extract from images | `prebuilt-imageSearch` on wingtip-shelf.jpg; Markdown description |
| 2.4.3 Extract from audio and video | `prebuilt-audioSearch` / `prebuilt-video`; transcript + diarization |
| 2.4.4 Build an information extraction application | `ContentUnderstandingClient`, `begin_analyze_binary`, `poller.result()` |

**Keyless pattern** -- `DefaultAzureCredential` passed directly as `credential=`
to `ContentUnderstandingClient`. Role required: **Cognitive Services User** (the
broad data-plane role CU names in MS Learn -- broader than the OpenAI-only role).

**Async pattern** -- `begin_analyze_binary` returns an LROPoller immediately;
`.result()` polls until `status == Succeeded`. The poller does NOT raise on
`Failed` -- always check `poller.status()` or inspect `result.contents`.

**Invoice exam note** -- the exam maps invoice documents to `prebuilt-invoice`.
As of mid-2026 that analyzer is down server-side (InternalServerError in all GA
regions tested); this demo substitutes `prebuilt-receipt`, which shares the same
field-extraction engine. When Microsoft resolves the defect, update `ANALYZER_BY_MIME`
to map `"application/pdf"` back to `"prebuilt-invoice"`.

**Required model deployments** -- prebuilt analyzers are NOT free-standing. They
require `gpt-4.1` + `gpt-4.1-mini` + `text-embedding-3-large` deployments mapped
as the resource defaults. The deploy script provisions all three and prints the
one-time mapping command.
