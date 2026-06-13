# Lesson 9: Effective System and User Prompts

Demonstrates three prompt-engineering patterns -- persona + few-shot in the system
message, Structured Outputs with JSON Schema, and Prompt Shields -- using the
`AzureOpenAI` client against a gpt-4o deployment in Microsoft Foundry.

**AI-901 objectives:** 2.2.1 (effective prompts -- persona + few-shot),
2.2.2 (system vs. user roles), 2.2.3 (advanced patterns -- structured output)

## Prerequisites

- Python 3.12
- Azure CLI (`az`) -- install from <https://aka.ms/azurecli>
- An Azure subscription with Microsoft.CognitiveServices registered
- `az login` completed

## Provision the resources

Run the deploy script from this folder (PowerShell):

```powershell
.\Deploy-Lesson09-Infrastructure.ps1
```

The script provisions a Foundry (AIServices) resource with a gpt-4o chat deployment
and a Foundry project. gpt-4o 2024-11-20 is required because Structured Outputs
(response_format json_schema, strict:true) is only available on models in the
Structured Outputs supported-models list.

**The resource name must be globally unique.** If the default is taken, pass
`-FoundryName` with a name of your choosing.

To tear down when you are done:

```powershell
.\Deploy-Lesson09-Infrastructure.ps1 -Cleanup
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
python lesson-09-prompt-patterns.py
```

## What you should see

```
Endpoint:   https://YOUR-RESOURCE-NAME.cognitiveservices.azure.com/
Deployment: gpt-4o   (the `model` argument -- a deployment name)
API ver:    2024-10-21   (GA; carries the Structured Outputs guarantee)
Key:        ****XXXX  (last 4 only)

Calling chat.completions.create with response_format=json_schema...

model (resolved): gpt-4o-2024-11-20
finish_reason:    stop

--- response.choices[0].message.content (raw) -------------------------
{"category":"product_defect","priority":"high","needs_human":true}
-----------------------------------------------------------------------

--- json.loads(content) -- guaranteed to parse, no try-except ---------
  category:    product_defect   (one of the schema enum values)
  priority:    high
  needs_human: True   (a real bool, type bool)
  -> router decision: PAGE A HUMAN NOW
-----------------------------------------------------------------------
...
```

The stove ticket maps to `product_defect`, `priority=high`, `needs_human=True` because
the system message rule ("safety issues always need a human") combines with the schema's
enum constraint to produce a schema-conformant, machine-readable decision.

## Practice on your own

1. Change `USER_PROMPT` to a billing ticket (for example:
   "I was charged twice for order #4471"). Observe that `needs_human` changes to False
   and the router routes to the queue instead of paging a human.
2. Remove `"strict": True` from `response_format` and observe that the script still
   runs -- but the schema guarantee is gone (you are now in JSON mode).
3. Add a `"reasoning"` field to `TRIAGE_SCHEMA` without adding it to `"required"`.
   Observe that Structured Outputs omits the field entirely (the schema is enforced).
4. Try running the script with `AZURE_OPENAI_API_VERSION=2024-02-01` and observe
   the error -- older versions do not support Structured Outputs.

## Exam connection

| Topic | Key fact |
| --- | --- |
| System vs. user role | System = developer-owned persona + rules; User = per-turn learner input |
| Few-shot in system message | Examples inside the system string demonstrate format without fine-tuning |
| JSON mode vs. Structured Outputs | JSON mode: valid JSON only; Structured Outputs: schema-conformant JSON |
| Structured Outputs requirements | `strict:true`, all fields in `required[]`, `additionalProperties:false` |
| Minimum api_version | `2024-08-01-preview` (preview), `2024-10-21` (GA) |
| Prompt Shields attack classes | Change system rules; conversation mockup; role-play persona swap; encoding attacks |
