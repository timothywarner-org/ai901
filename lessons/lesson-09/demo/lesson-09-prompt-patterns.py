"""
Lesson 9 -- Prompt Patterns SDK Bookend
=========================================
Course:  Exam AI-901 -- Microsoft Azure AI Fundamentals (Video)
LO:      2.2.1 (effective prompts -- persona + few-shot), 2.2.2 (system vs user
         roles), 2.2.3 (advanced patterns -- structured output)
Goal:    Show the same three prompt patterns from the portal demo -- a strong system
         message, in-context few-shot examples, and Structured Outputs
         (response_format=json_schema, strict) -- as a standalone script against
         the deployed gpt-4o endpoint, so learners see the exact AzureOpenAI
         shapes the AI-901 exam tests on Python code-fill questions.

Why this file exists:
    The portal beats are pure Foundry Chat Playground click-by-click. This script
    is the one runnable artifact: it proves the deployed endpoint is real by calling
    it from code, and it drills the two patterns the exam fills in the blanks on
    for prompt engineering:

        1. The messages array shape -- system message carries persona + few-shot,
           user message carries the per-turn ask:
             messages=[
                 {"role": "system", "content": "<persona + few-shot examples>"},
                 {"role": "user",   "content": "<the actual ask>"},
             ]

        2. Structured Outputs -- response_format with json_schema + strict:
             response_format={
                 "type": "json_schema",
                 "json_schema": {"name": "x", "strict": True, "schema": {...}},
             }
           The exam-favorite distinction: JSON mode guarantees VALID json;
           Structured Outputs guarantees SCHEMA-CONFORMANT json. Pick Structured
           Outputs for production.

api_version note (exam-relevant):
    Structured Outputs support was first added in api-version 2024-08-01-preview
    and is available in the GA api-version 2024-10-21. We pin 2024-10-21 here --
    it is GA, it is the version every other lesson in this course uses, and it
    carries the schema guarantee. An older version silently falls back to JSON
    mode with no schema guarantee.

Resource backing this script:
    The Foundry (AIServices) resource provisioned by
    Deploy-Lesson09-Infrastructure.ps1 -- ai901-lesson09-foundry
    (rg-ai901-lesson09-demo, East US 2), with a gpt-4o Standard deployment.
    Auth is key + endpoint via .env (never hardcode keys in source).

How to run:
    python -m venv .venv
    .venv\\Scripts\\Activate.ps1
    pip install -r requirements.txt
    cp .env.example .env      # paste AZURE_OPENAI_ENDPOINT + _KEY from deploy output
    python lesson-09-prompt-patterns.py
"""

from __future__ import annotations

import json
import os
import sys

from openai import AzureOpenAI
from dotenv import load_dotenv

# ---------------------------------------------------------------------------
# 1. Load credentials from .env -- never hardcode keys in source.
#    override=True makes this lesson's .env authoritative even if the machine
#    already has stray AZURE_OPENAI_* environment variables from another project
#    (without override, an OS-level AZURE_OPENAI_ENDPOINT silently shadows the
#    .env and the demo hits the wrong resource).
# ---------------------------------------------------------------------------
load_dotenv(override=True)

ENDPOINT = os.environ.get("AZURE_OPENAI_ENDPOINT")
KEY = os.environ.get("AZURE_OPENAI_KEY")
# The `model` argument below is the DEPLOYMENT name, not the model name. The deploy
# script names the deployment "gpt-4o"; if you renamed it, set this env var to match.
DEPLOYMENT = os.environ.get("AZURE_OPENAI_CHAT_DEPLOYMENT", "gpt-4o")
# 2024-10-21 is the GA api-version that supports Structured Outputs. Older versions
# silently fall back to JSON mode with no schema guarantee -- this string is exam-relevant.
API_VERSION = os.environ.get("AZURE_OPENAI_API_VERSION", "2024-10-21")

if not ENDPOINT or not KEY:
    sys.exit(
        "Missing AZURE_OPENAI_ENDPOINT or AZURE_OPENAI_KEY. Copy .env.example to "
        ".env and paste the values printed by Deploy-Lesson09-Infrastructure.ps1."
    )

# ---------------------------------------------------------------------------
# 2. The system message carries BOTH the persona AND the few-shot examples --
#    the same content pasted into the System message box in the Playground.
#    Few-shot lives inside the system string (one of the two acceptable patterns;
#    the other is alternating user/assistant example turns). The model infers the
#    classification scheme from the two examples -- in-context learning, no
#    fine-tuning, no labeled training set.
#
#    Scenario: Contoso Outdoor support-ticket triage. A triage classifier is a
#    realistic job for Structured Outputs because the JSON it returns is something a
#    downstream router ACTUALLY consumes (which queue, what priority, page a human?).
#    That makes the "json you can parse without a try-except" payoff land on a real
#    workflow instead of a throwaway result.
# ---------------------------------------------------------------------------
SYSTEM_MESSAGE_WITH_FEW_SHOT = """\
You are a support-ticket triage assistant for Contoso Outdoor, a hiking and camping \
equipment retailer. Classify each incoming ticket. Choose the single best category, \
assign a priority, and decide whether the ticket needs a human agent. Safety issues \
and anything mentioning injury always need a human and are high priority.

Examples:

Input: My headlamp stopped charging after two uses and the battery is now bulging.
Output: category=product_defect, priority=high, needs_human=true

Input: Do you ship the AlpineDome tent to Canada, and how long does it take?
Output: category=shipping_question, priority=low, needs_human=false"""

USER_PROMPT = (
    "I followed the setup video but the stove regulator hisses and I can smell gas. "
    "Is this safe to use on my trip this weekend?"
)

# ---------------------------------------------------------------------------
# 3. The Structured Outputs schema -- the triage_result schema used in the
#    Playground. The three exam-tested rules are visible here:
#      1. Every output field is listed in "required".
#      2. "additionalProperties" is false.
#      3. category and priority are enum-constrained -- the model CANNOT invent a
#         queue name or a priority outside the set, which is exactly what a
#         downstream router needs to switch on safely.
#    needs_human is a boolean -- Structured Outputs enforces the TYPE too, so the
#    router gets a real bool, never the string "true".
# ---------------------------------------------------------------------------
TRIAGE_SCHEMA = {
    "type": "object",
    "properties": {
        "category": {
            "type": "string",
            "enum": [
                "product_defect",
                "shipping_question",
                "billing",
                "returns",
                "general",
            ],
        },
        "priority": {"type": "string", "enum": ["low", "medium", "high"]},
        "needs_human": {"type": "boolean"},
    },
    "required": ["category", "priority", "needs_human"],
    "additionalProperties": False,
}


# ---------------------------------------------------------------------------
# 4. The whole Azure OpenAI Structured-Outputs pattern in one function. Client
#    construction, then chat.completions.create with response_format=json_schema.
# ---------------------------------------------------------------------------
def triage(system_message: str, user_prompt: str) -> "ChatCompletion":  # noqa: F821
    """Send one system + user turn and force schema-conformant JSON back."""
    # --- The Azure-flavored client. Three required args; api_version 2024-10-21 is
    #     the GA version that carries the Structured Outputs schema guarantee. ---
    client = AzureOpenAI(
        api_key=KEY,
        api_version=API_VERSION,
        azure_endpoint=ENDPOINT,
    )

    # --- The canonical Structured Outputs call. model = DEPLOYMENT name (not model
    #     name); response_format with type=json_schema + strict:True is the activation. ---
    return client.chat.completions.create(
        model=DEPLOYMENT,
        messages=[
            {"role": "system", "content": system_message},
            {"role": "user", "content": user_prompt},
        ],
        response_format={
            "type": "json_schema",
            "json_schema": {
                "name": "triage_result",
                "strict": True,
                "schema": TRIAGE_SCHEMA,
            },
        },
        # Low temperature for a classification task -- we want the deterministic
        # answer, not creative variety.
        temperature=0,
        max_tokens=100,
    )


# ---------------------------------------------------------------------------
# 5. Run it and prove the guarantee: json.loads with NO try-except, because
#    Structured Outputs guarantees the content parses and matches the schema.
# ---------------------------------------------------------------------------
def main() -> None:
    print(f"Endpoint:   {ENDPOINT}")
    print(f"Deployment: {DEPLOYMENT}   (the `model` argument -- a deployment name)")
    print(f"API ver:    {API_VERSION}   (GA; carries the Structured Outputs guarantee)")
    print(f"Key:        ****{KEY[-4:]}  (last 4 only)\n")
    print("Calling chat.completions.create with response_format=json_schema...\n")

    response = triage(SYSTEM_MESSAGE_WITH_FEW_SHOT, USER_PROMPT)

    raw = response.choices[0].message.content
    usage = response.usage

    print(f"model (resolved): {response.model}")
    print(f"finish_reason:    {response.choices[0].finish_reason}\n")
    print("--- response.choices[0].message.content (raw) -------------------------")
    print(raw)
    print("-----------------------------------------------------------------------\n")

    # The production guarantee: no try-except needed. If Structured Outputs is active,
    # this ALWAYS parses, the enums are always valid, and needs_human is a real bool --
    # exactly what a downstream router switches on.
    parsed = json.loads(raw)
    print("--- json.loads(content) -- guaranteed to parse, no try-except ---------")
    print(f"  category:    {parsed['category']}   (one of the schema enum values)")
    print(f"  priority:    {parsed['priority']}")
    print(f"  needs_human: {parsed['needs_human']}   (a real bool, type {type(parsed['needs_human']).__name__})")
    # Prove the point: this branch is safe because the schema guarantees the shape.
    route = "PAGE A HUMAN NOW" if parsed["needs_human"] else f"queue: {parsed['category']}"
    print(f"  -> router decision: {route}")
    print("-----------------------------------------------------------------------\n")

    print("--- response.usage (the billing meter) --------------------------------")
    print(f"  prompt_tokens:     {usage.prompt_tokens}")
    print(f"  completion_tokens: {usage.completion_tokens}")
    print(f"  total_tokens:      {usage.total_tokens}")
    print("-----------------------------------------------------------------------\n")

    print(EXAM_POCKET_CARD)


# ---------------------------------------------------------------------------
# Exam pocket card -- Azure OpenAI prompt patterns in Python.
# ---------------------------------------------------------------------------
EXAM_POCKET_CARD = """\
=== Azure OpenAI prompt patterns in Python -- exam pocket card ===============
 Import  : from openai import AzureOpenAI       <- NOT OpenAI
 Client  : AzureOpenAI(api_key=..., api_version="2024-10-21", azure_endpoint=...)
                                                  ^ GA; Structured Outputs needs
                                                    >= 2024-08-01-preview
 Messages: [{"role": "system", "content": "persona + few-shot examples"},
            {"role": "user",   "content": "the actual user ask"}]
           System = persona/rules/few-shot (developer-owned, stable).
           User   = the per-turn ask (user-owned, changes every turn).
 Schema  : response_format={"type": "json_schema",
              "json_schema": {"name": "x", "strict": True, "schema": {...}}}
           strict:True is NOT optional. required[] must list every field.
           additionalProperties:false on every object.
 Read    : json.loads(response.choices[0].message.content)  <- always parses
 JSON mode guarantees VALID json. Structured Outputs guarantees SCHEMA json.
 The `model` arg is a deployment name. api_version gates Structured Outputs.
============================================================================="""


if __name__ == "__main__":
    main()
