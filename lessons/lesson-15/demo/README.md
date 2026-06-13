# Lesson 15 Demo -- Computer Vision and Image Generation

Two Python scripts on one Azure OpenAI Foundry resource that demonstrate both
directions of visual AI: sending an image TO the model (understanding) and
getting an image OUT of the model (generation). Covers AI-901 exam objectives
2.3.1 -- 2.3.3.

---

## Prerequisites

- Python 3.12
- Azure CLI (`az`) with an active `az login` session
- An Azure subscription with quota for gpt-4o (GlobalStandard) and
  gpt-image-2 (GlobalStandard) in Sweden Central (or your chosen region)

---

## Provision the resources

Run the deploy script once. Pass a **globally unique** `-FoundryName` -- AIServices
custom subdomains are a global namespace across all Azure tenants.

```powershell
.\Deploy-Lesson15-Infrastructure.ps1 -FoundryName my-ai901-l15-foundry
```

The script provisions:

- One AIServices resource (kind=AIServices, S0) with a custom subdomain
  (required for keyless / Entra token auth)
- A `gpt-4o` (2024-11-20, GlobalStandard) deployment -- vision-capable chat
- A `gpt-image-2` (2026-04-21, GlobalStandard) deployment -- image generation
- RBAC: **Cognitive Services OpenAI User** on the resource for your az-login
  identity -- one role covers both chat/vision AND image-gen data-plane calls

The image-model deployment is **non-fatal**: if gpt-image-2 quota is unavailable
in your region, the script WARNs and continues so the vision half still works.
Re-run with `-Location westus3` as a fallback.

---

## Configure

```powershell
# Copy the template; fill in values from the deploy script output
copy .env.example .env
notepad .env
```

Edit `.env` with the values printed by the deploy script. Never commit `.env`.

---

## Install

```powershell
python -m venv .venv
.venv\Scripts\Activate.ps1
pip install -r requirements.txt
```

---

## Run

**Vision understanding** -- Fabrikam defect inspector (image input -> gpt-4o -> JSON):

```powershell
# Default: inspects the staged sample image
python lesson-15-vision-inspect.py

# Explicit local file (always works -- bytes sent inline as a data URL)
python lesson-15-vision-inspect.py ./samples/bracket-crack.png

# Any other local image (JPEG/PNG/GIF/WEBP)
python lesson-15-vision-inspect.py ./my-part-photo.jpg

# Public https URL (works only when the service can fetch it)
python lesson-15-vision-inspect.py https://upload.wikimedia.org/wikipedia/commons/a/a9/Example.jpg
```

**Image generation** -- Contoso Marketing promo generator (text prompt -> gpt-image-2 -> PNG):

```powershell
python lesson-15-contoso-promo.py
```

---

## What you should see

**Vision script:**

```
[main] No argument -- using local default: ...\samples\bracket-crack.png
[vision] Inspecting via base64 data URL on deployment 'gpt-4o'...
[vision] Defect report (JSON):
{"defects": [{"location": "upper bracket arm", "defect_type": "crack", "severity": "high"}]}
[main] Inspection complete: image -> gpt-4o -> structured JSON.
```

**Image generation script:**

```
[gen] Run a3f1c2d8e9b0: requesting 1024x1024 high-quality image...
[gen] Saved 1,234,567 bytes to contoso_a3f1c2d8e9b0.png.
[audit] Appended run a3f1c2d8e9b0 to runs.jsonl.
[main] Done: contoso_a3f1c2d8e9b0.png created and logged in runs.jsonl.
```

If you pass a **content-safety trip prompt** (e.g. a copyright character or violent
content) to the image script, expect:

```
[blocked] Azure AI Content Safety blocked this prompt at the deployment. ...
```

---

## Practice on your own

1. **Raise the inspection bar** -- try `./samples/bracket-crack.png` then open the
   JSON and ask gpt-4o to re-inspect with a stricter prompt (e.g. "rate defect
   severity on a scale of 1-10 instead of low/medium/high").

2. **Try your own image** -- drop any JPEG or PNG into `samples/` and pass it as
   the argument. Note that TIFF and BMP are not in the gpt-4o allowlist -- the
   script will tell you to convert first.

3. **Vary the image-gen prompt** -- change ONE axis at a time (subject, composition,
   or style) using the prompts in `test-strings.txt` and compare outputs.

4. **Close the loop** -- copy the filename of a generated PNG, then feed it back
   into the vision script to generate alt-text:
   ```powershell
   python lesson-15-vision-inspect.py contoso_<run_id>.png
   ```

---

## Exam connection

| AI-901 objective | What this demo shows |
| --- | --- |
| 2.3.1 Interpret visual input with a multimodal model | `lesson-15-vision-inspect.py`: content array with `image_url`, local vs. URL input |
| 2.3.2 Create visual outputs with a generative model | `lesson-15-contoso-promo.py`: `client.images.generate`, `data[0].b64_json` decode |
| 2.3.3 Build a lightweight application with vision | Both scripts together: keyless client, MIME allowlist, audit trail |

**Keyless pattern** -- `DefaultAzureCredential` + `get_bearer_token_provider` +
`azure_ad_token_provider` on the `AzureOpenAI` client. Role required: **Cognitive
Services OpenAI User** (covers both chat/vision AND image-gen data-plane calls).

**Base64 only for gpt-image** -- `data[0].b64_json` is the ONLY output field.
There is no `url` field on gpt-image-2. The `response_format` parameter is not
supported. This is the most-tested gotcha for exam objective 2.3.2.

**Two API versions** -- chat/vision uses `2024-10-21` (GA); image generation uses
`2025-04-01-preview` (preview). A single `AzureOpenAI` client is pinned to one
version, so the scripts use separate client instances.
