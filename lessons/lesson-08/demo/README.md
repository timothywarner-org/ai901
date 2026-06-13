# Lesson 8: Tour Microsoft Foundry and Deploy Your First Model

Demonstrates Azure OpenAI chat completions from Python using the `AzureOpenAI` client
against a gpt-4o-mini deployment in a Microsoft Foundry project.

**AI-901 objectives:** 2.1.1 (deploy + interact with a model), 2.1.2 (portal navigation),
2.1.3 (model selection -- gpt-4o-mini is the cost/capability default)

## Prerequisites

- Python 3.12
- Azure CLI (`az`) -- install from <https://aka.ms/azurecli>
- An Azure subscription with Microsoft.CognitiveServices registered
- `az login` completed

## Provision the resources

Run the deploy script from this folder (PowerShell):

```powershell
.\Deploy-Lesson08-Infrastructure.ps1
```

The script provisions:

- A Foundry (AIServices) resource with a gpt-4o-mini chat deployment and a
  text-embedding-3-small reference deployment.
- A legacy standalone Azure OpenAI account (kind=OpenAI, no deployments) as a
  historical-context comparison.
- A Foundry project that owns the chat deployment.

**The resource names must be globally unique.** If the defaults are taken, pass
`-FoundryName` and `-AoaiName` with names of your choosing.

To tear down when you are done:

```powershell
.\Deploy-Lesson08-Infrastructure.ps1 -Cleanup
```

## Configure

Copy `.env.example` to `.env` and paste the values printed by the deploy script:

```powershell
cp .env.example .env
# Edit .env -- paste AZURE_OPENAI_ENDPOINT and AZURE_OPENAI_KEY
```

**Never commit `.env` to source control.**

## Install

```powershell
python -m venv .venv
.venv\Scripts\Activate.ps1
pip install -r requirements.txt
```

## Run

```powershell
python lesson-08-foundry-chat.py
```

## What you should see

```
Endpoint:   https://YOUR-RESOURCE-NAME.cognitiveservices.azure.com/
Deployment: gpt-4o-mini   (the `model` argument -- a deployment name)
API ver:    2024-10-21
Key:        ****XXXX  (last 4 only)

Calling chat.completions.create against the deployed gpt-4o-mini...

model (resolved): gpt-4.1-mini-2025-04-14
finish_reason:    stop

--- response.choices[0].message.content -------------------------------
<tagline from the model>
-----------------------------------------------------------------------

--- response.usage (the billing meter) --------------------------------
  prompt_tokens:     ...
  completion_tokens: ...
  total_tokens:      ...
-----------------------------------------------------------------------

=== Azure OpenAI chat in Python -- exam pocket card ...
```

Notice that `model (resolved)` shows `gpt-4.1-mini-2025-04-14`, not `gpt-4o-mini`.
The deployment is **named** `gpt-4o-mini` (matching the exam answer), but the
underlying model running inference is the deployable successor `gpt-4.1-mini`. This
is the most-tested Python detail on the AI-901 exam: the `model` argument you pass is
the **deployment name**, not the underlying model name.

## Practice on your own

1. Change `USER_PROMPT` in the script to ask for a tagline for a different product.
   Observe how `prompt_tokens` and `completion_tokens` change.
2. Change `temperature` from `0.7` to `0.0`, run twice, and note that the responses
   become more deterministic. Then try `temperature=1.5` and compare.
3. Set `max_tokens=10` and observe the `finish_reason` change from `stop` to `length`.
4. In the Foundry portal Chat Playground, switch the **Response format** to JSON and
   compare the output to the unstructured response from this script.

## Exam connection

The AI-901 exam tests two Python shapes on code-fill questions:

| What the exam asks | Correct answer |
| --- | --- |
| Import class for Azure OpenAI chat | `from openai import AzureOpenAI` -- NOT `OpenAI` |
| What does the `model` argument name? | The **deployment name** you set in the portal wizard |
| What controls response creativity? | `temperature` (0.0 to 2.0) |
| What caps response length? | `max_tokens` (integer) |
| Where is the generated text? | `response.choices[0].message.content` |
| Where is the billing meter? | `response.usage.total_tokens` |
