# Lesson 05 Demo -- Text Analysis and Speech Concepts

This demo provisions Azure AI Language and Azure AI Speech resources, then runs
a short Python script that mirrors the Language Studio portal walkthrough in code.
Together they show the **NLP continuum** -- the same tasks performed first with
classic prebuilt APIs (Language Studio, Speech Studio) and then with a generative
model (Foundry chat playground).

**AI-901 objectives:** 1.3.2a (text analysis), 1.3.3 (NLP continuum), 1.3.4 (speech).

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
cd lessons\lesson-05\demo
.\Deploy-Lesson05-Infrastructure.ps1
```

The script is **idempotent** -- re-running it after a partial failure is safe.

**Resources created:**

| Resource | Purpose |
| --- | --- |
| `rg-ai901-lesson05-demo` | Resource group for all lesson resources |
| `ai901-lesson05-foundry` (AIServices, S0) | Foundry umbrella -- Language + Speech + Translator |
| `ai901-lesson05-language` (TextAnalytics, F0) | Singleton for Language Studio |
| `ai901-lesson05-speech` (SpeechServices, F0) | Singleton for Speech Studio |
| `gpt-4-1-mini` deployment | Foundry chat -- generative sentiment comparison |

**Cleanup when you are done:**

```powershell
.\Deploy-Lesson05-Infrastructure.ps1 -Cleanup
```

---

## Configure

Copy the example environment file and fill in your own values:

```powershell
copy .env.example .env
```

Open `.env` and replace the placeholder values:

```
LANGUAGE_ENDPOINT=https://YOUR-RESOURCE-NAME.cognitiveservices.azure.com/
LANGUAGE_KEY=PASTE_YOUR_LANGUAGE_KEY1_HERE
```

Get your endpoint and key from the deploy script output, or run:

```powershell
# Endpoint
az cognitiveservices account show `
  -g rg-ai901-lesson05-demo -n ai901-lesson05-language `
  --query properties.endpoint -o tsv

# Key (last 4 only shown here for safety -- copy the full key into .env)
az cognitiveservices account keys list `
  -g rg-ai901-lesson05-demo -n ai901-lesson05-language `
  --query key1 -o tsv
```

**Do not commit `.env` to source control.** The `.gitignore` at the repo root
already excludes it. Only `.env.example` belongs in the repo.

---

## Install

```powershell
cd lessons\lesson-05\demo
python -m venv .venv
.venv\Scripts\Activate.ps1
pip install -r requirements.txt
```

---

## Run

```powershell
python lesson-05-text-analytics.py
```

---

## What you should see

```
Endpoint: https://YOUR-RESOURCE-NAME.cognitiveservices.azure.com/
Key:      ****XXXX  (last 4 only)

========================================================================
 NER  ->  TextAnalyticsClient.recognize_entities()
========================================================================
  Contoso Air               category=Organization  score=0.99
  Seattle                   category=Location      score=1.00
  Munich                    category=Location      score=1.00
  March 12, 2026            category=DateTime      score=1.00
  ...

========================================================================
 Sentiment + opinion mining  ->  TextAnalyticsClient.analyze_sentiment()
========================================================================

  Document sentiment: MIXED  (pos=0.58, neu=0.05, neg=0.37)

  Opinion -> Target pairs (the exam asks about these by name):
    "wonderful" (positive)  ->  "check-in agent" (positive)
    "best" (positive)       ->  "meal service" (positive)
    "disaster" (negative)   ->  "Wi-Fi" (negative)
    ...
```

The script closes with an **Exam pocket card** that lists every
`TextAnalyticsClient` method the AI-901 exam tests.

---

## Practice on your own

1. **Try key phrase extraction.** Add a call to
   `client.extract_key_phrases(documents=[REVIEW])` after the existing
   functions. What phrases does the service return for the Contoso Air review?
   Compare them to the Language Studio output.

2. **Try PII detection.** Paste the PII sample from `test-strings.txt` into a
   new `documents` list. Call `client.recognize_pii_entities()`. What categories
   (SSN, Email, Phone, CreditCard) does the service return?

3. **Try the generative comparison.** In the Foundry portal
   (<https://ai.azure.com>), open the `ai901-lesson05-project` chat playground
   against the `gpt-4-1-mini` deployment. Paste the generative-sentiment system
   message from `test-strings.txt`, then paste the Contoso Air review. How does
   the JSON output differ from the Language Studio sentiment analysis?

4. **Try Speech Studio.** Open <https://speech.microsoft.com>, pick the
   `ai901-lesson05-speech` resource, and use the real-time STT demo to
   transcribe the STT test sentence from `test-strings.txt`. Check the
   word-level timestamp output and the ITN field.

---

## Exam connection

- **TextAnalyticsClient** is the single Azure AI Language SDK class the exam
  tests. Each method maps to one named NLP task (NER, sentiment, key phrases,
  PII, language detection). Memorize the class name and method signatures.
- **Deployment name vs. model name** -- the Azure OpenAI / Foundry API uses the
  *deployment* name (set at resource creation), not the underlying model name.
  The exam tests this distinction on code-fill questions.
- **Classic vs. generative NLP** -- the exam expects you to match the right tool
  to the task: named, structured tasks -> prebuilt Azure AI Language;
  open-ended reasoning -> generative model. The four-way tradeoff matrix in
  `test-strings.txt` summarizes the key dimensions.
