# Lesson 13 Demo -- Text Analysis Application with Foundry

Demonstrates four Azure AI Language skills from a Python SDK client, then
adds PII redaction as a fifth capability. Maps to AI-901 objective **2.2.1**:
call Azure AI Language capabilities from a client application by using the
Azure AI SDK.

A companion Flask web app version lives in
[`lessons/lesson-13/demo/webapp/`](./webapp/) -- that web app shows the
same four skills in an interactive browser UI.

---

## Prerequisites

- Python 3.12 or later
- Azure CLI (`az`) 2.60 or later -- [install guide](https://aka.ms/azurecli)
- An Azure subscription with quota for Azure AI services (S0) in one of the
  supported regions (westus2, eastus2, northcentralus, westus, japaneast,
  westeurope, northeurope, or francecentral)
- The Microsoft.CognitiveServices resource provider registered in your subscription

---

## Provision the resources

Run the PowerShell deploy script once before the first use:

```powershell
.\Deploy-Lesson13-Infrastructure.ps1
```

The script creates:

- A resource group (`rg-ai901-lesson13-demo`)
- An **Azure AI services** resource (kind=AIServices, S0) with a
  **custom subdomain** -- the custom subdomain is mandatory for keyless
  (Entra token) auth; a regional endpoint rejects token authentication
- An RBAC assignment: **Cognitive Services User** on the resource for the
  signed-in identity

At the end, the script prints the `LANGUAGE_ENDPOINT` value to paste into `.env`.

To remove all resources when you are done:

```powershell
.\Deploy-Lesson13-Infrastructure.ps1 -Cleanup
```

---

## Configure

Copy the example file and paste the endpoint printed by the deploy script:

```powershell
copy .env.example .env
```

Open `.env` and replace the placeholder with your actual endpoint. There is
**no key line** -- this lesson uses keyless authentication throughout.

**Never commit `.env` to source control.**

---

## Install

```powershell
python -m venv .venv
.venv\Scripts\Activate.ps1          # Windows
# source .venv/bin/activate         # macOS/Linux
pip install -r requirements.txt
```

---

## Run

Sign in to Azure first (needed once per session):

```powershell
az login
```

Run the main text analysis script (entities, key phrases, sentiment, summarization):

```powershell
python lesson-13-text-analytics.py
```

Run the PII redaction and summarization script:

```powershell
python lesson-13-pii-summary.py
```

Use the text strings in `test-strings.txt` as input when experimenting.

---

## What you should see

**lesson-13-text-analytics.py** prints four sections, one per SDK method:

1. **Entities** -- each named entity with its category and confidence score.
   Example: `Contoso Air` (Organization), `Seattle` (Location), `March 12, 2026`
   (DateTime).
2. **Key phrases** -- the salient topic words from the review, pipe-separated.
3. **Sentiment + opinion mining** -- document-level label (positive/negative/
   neutral/mixed) plus target/assessment pairs that explain *why*. Example:
   `"wonderful" (positive) -> "check-in agent" (positive)`.
4. **Summarization** -- extractive (verbatim source sentences ranked by
   importance) followed by abstractive (a novel paraphrase the service writes).
   Both use long-running pollers (`begin_extract_summary` /
   `begin_abstract_summary`); `.result()` blocks until complete.

The final block prints the **Exam pocket card** -- the exact class and method
names the AI-901 exam uses in code-fill questions.

**lesson-13-pii-summary.py** prints two sections:

1. **PII redaction** -- `redacted_text` with sensitive values replaced by
   category labels (e.g. `[PersonName]`, `[Email]`, `[CreditCardNumber]`),
   followed by a list of detected PII entities.
2. **Summarization** -- the same extractive/abstractive pair applied to a
   longer support-ticket paragraph.

---

## Practice on your own

1. **Swap the review text** -- paste Test String 1 from `test-strings.txt`
   (Tailspin Pro Drone review) into the `REVIEW` variable in
   `lesson-13-text-analytics.py` and run again. Compare which opinions the
   service finds vs. the Contoso Air review.

2. **Try the PII samples** -- paste Test String 3 from `test-strings.txt`
   (the PII-rich support message) as the `PII_TEXT` in
   `lesson-13-pii-summary.py`. Notice that `redacted_text` masks the credit
   card number, email, phone, and name all in one pass.

3. **Switch summarization modes** -- in `lesson-13-pii-summary.py`, change
   `begin_extract_summary` to `begin_abstract_summary` and compare outputs on
   Test String 2. Extractive is better for compliance and legal review;
   abstractive reads more naturally for executive digests.

4. **Test language detection** -- add a call to `client.detect_language()`
   using the multilingual snippets in Test String 4 of `test-strings.txt`.
   Observe the ISO 639-1 language code and confidence score the service returns.

---

## Exam connection

| AI-901 concept | Where it appears in the code |
|---|---|
| **TextAnalyticsClient** | Constructed once; reused for all five skills |
| **Keyless auth** | `DefaultAzureCredential` replaces `AzureKeyCredential`; no key in `.env` |
| **Custom subdomain requirement** | Deploy script uses `--custom-domain`; regional endpoint rejects token auth |
| **Cognitive Services User role** | RBAC gate for data-plane access; Owner does not imply it |
| **recognize_entities** | Returns typed `CategorizedEntity` objects (text, category, confidence) |
| **extract_key_phrases** | Returns untyped phrases -- no scores, just the salient words |
| **analyze_sentiment + show_opinion_mining=True** | Three tiers: document, sentence, mined opinions (target + assessment) |
| **begin_extract_summary** | Long-running operation (LRO) -- poller pattern; returns source sentences |
| **begin_abstract_summary** | LRO -- poller pattern; returns novel paraphrased text |
| **recognize_pii_entities** | Returns `redacted_text` plus entity list with PII categories |
