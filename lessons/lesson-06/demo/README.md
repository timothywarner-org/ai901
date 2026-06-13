# Lesson 06 Demo -- Computer Vision Concepts

This demo provisions Azure AI Vision, a Foundry multimodal chat deployment, and
an image-generation deployment, then runs a short Python script that mirrors
the Vision Studio portal walkthrough in code.

**AI-901 objectives:** 1.4.1 (computer vision tasks), 1.4.2 (vision service
capabilities -- image analysis, OCR, face detection), 1.4.3 (image generation).

---

## Prerequisites

- **Python 3.12** -- verify with `python --version`
- **PowerShell 7.4 or later** -- verify with `$PSVersionTable.PSVersion`
- **Azure CLI 2.51 or later** -- install from <https://aka.ms/install-azure-cli>
- **An Azure subscription** where you can create Cognitive Services resources
- **Signed in** to the correct subscription:
  ```powershell
  az login
  az account set --subscription "<your subscription name or id>"
  ```

---

## Provision the resources

Run the deploy script from the `demo/` folder:

```powershell
cd lessons\lesson-06\demo
.\Deploy-Lesson06-Infrastructure.ps1
```

The script is **idempotent** -- re-running it after a partial failure is safe.

**Resources created:**

| Resource | Purpose |
| --- | --- |
| `rg-ai901-lesson06-demo` | Resource group for all lesson resources |
| `ai901-lesson06-foundry` (AIServices, S0) | Foundry umbrella for chat and image-gen |
| `ai901-lesson06-vision` (ComputerVision, F0) | Singleton for Vision Studio and Python SDK |
| `gpt-4o` deployment (Standard, 10K TPM) | Multimodal vision chat (portal) |
| `gpt-image-1-5` deployment (GlobalStandard) | Image generation (portal) |

**Why Vision goes in East US:**
The `Caption` visual feature is region-gated. East US 2 returns "feature not
supported in this region." The deploy script places the Vision resource in
East US automatically.

**Cleanup when you are done:**

```powershell
.\Deploy-Lesson06-Infrastructure.ps1 -Cleanup
```

---

## Configure

Copy the example environment file and fill in your own values:

```powershell
copy .env.example .env
```

Open `.env` and replace the placeholder values:

```
VISION_ENDPOINT=https://YOUR-RESOURCE-NAME.cognitiveservices.azure.com/
VISION_KEY=PASTE_YOUR_VISION_KEY1_HERE
```

Get your endpoint and key from the deploy script output, or run:

```powershell
# Endpoint
az cognitiveservices account show `
  -g rg-ai901-lesson06-demo -n ai901-lesson06-vision `
  --query properties.endpoint -o tsv

# Key (copy the full value into .env)
az cognitiveservices account keys list `
  -g rg-ai901-lesson06-demo -n ai901-lesson06-vision `
  --query key1 -o tsv
```

**Do not commit `.env` to source control.** The `.gitignore` at the repo root
already excludes it.

---

## Install

```powershell
cd lessons\lesson-06\demo
python -m venv .venv
.venv\Scripts\Activate.ps1
pip install -r requirements.txt
```

---

## Run

```powershell
python lesson-06-vision.py
```

---

## What you should see

```
Endpoint: https://YOUR-RESOURCE-NAME.cognitiveservices.azure.com/
Key:      ****XXXX  (last 4 only)

========================================================================
 Image analysis  ->  ImageAnalysisClient.analyze_from_url()
========================================================================
 Image: https://aka.ms/azsdk/image-analysis/sample.jpg

  Caption: "a person sitting at a table with a laptop"  (confidence=0.82)

  Objects detected:
    person               confidence=0.91  box=(x=10, y=5, w=200, h=400)
    laptop               confidence=0.88  box=(x=90, y=180, w=310, h=200)
    ...

  Text extracted (OCR):
    "Surface Pro"
    ...
```

The script closes with an **Exam pocket card** listing all `VisualFeatures`
enum values the AI-901 exam tests.

---

## Practice on your own

1. **Add the TAGS feature.** Add `VisualFeatures.TAGS` to the `visual_features`
   list and re-run. Tags are broader labels than objects -- what tags does the
   service return? How do they differ from the detected objects?

2. **Try a different image URL.** Replace `SAMPLE_IMAGE_URL` with a URL to any
   publicly accessible image. Run the script again. Does the Caption change as
   you would expect? What happens if the image has no text -- does the READ
   section return anything?

3. **Try the multimodal chat in the Foundry portal.** Open
   <https://ai.azure.com>, switch to `ai901-lesson06-project`, and open the
   chat playground against the `gpt-4o` deployment. Upload the same sample
   image and ask "What is in this image?" Compare the natural-language response
   to the structured Caption output from the Vision SDK.

4. **Try image generation in the Foundry portal.** In the same project, open
   Images -> Image generation. Use the `gpt-image-1-5` deployment and enter
   a prompt like "A watercolor painting of the Northwind Traders logo on a
   coffee mug." What content-safety filters does the portal surface?

---

## Exam connection

- **ImageAnalysisClient** is the Azure AI Vision SDK class the exam tests.
  The `visual_features` parameter drives what the service analyzes -- the exam
  tests which enum value maps to which task (e.g., `READ` -> OCR).
- **analyze_from_url vs. analyze** -- the service fetches the URL server-side
  for `analyze_from_url`; `analyze` takes a local byte stream. The exam may
  test which method to use given a scenario.
- **Image generation vs. image analysis** -- these are opposite directions:
  analysis extracts information *from* an image; generation creates an image
  *from* a text prompt. The exam expects you to match the task to the right
  service (Azure AI Vision for analysis, Azure OpenAI gpt-image-* for generation).
