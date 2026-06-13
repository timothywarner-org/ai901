"""
Lesson 8 -- Foundry Chat SDK Bookend
======================================
Course:  Exam AI-901 -- Microsoft Azure AI Fundamentals (Video)
LO:      2.1.1 (deploy + interact with a model), 2.1.2 (portal navigation),
         2.1.3 (model selection -- gpt-4o-mini is the cost/capability default)
Goal:    Show the same chat call you can run in the Foundry Playground --
         against the same deployed gpt-4o-mini endpoint -- as a standalone
         script, so learners see the AzureOpenAI client shape the AI-901
         exam tests on Python code-fill questions.

Why this file exists:
    The portal tour is the lesson: Foundry navigation, the model catalog, the
    deploy wizard, and the Chat Playground. This script is the one runnable
    artifact: it proves the deployed endpoint is real by calling it from code,
    and it drills the two patterns the exam fills in the blanks on:

        1. The client construction:
             from openai import AzureOpenAI
             client = AzureOpenAI(api_key=..., api_version=..., azure_endpoint=...)
           The exam-favorite trap is asking for the Azure-flavored class in a
           code stub -- the answer is AzureOpenAI, NOT OpenAI.

        2. The chat call:
             client.chat.completions.create(model="<deployment-name>", messages=[...])
           The single most-tested Python detail on this exam: the `model`
           argument is the DEPLOYMENT name, not the underlying model name.

Why the openai package and not azure-ai-inference:
    AzureOpenAI from the stable `openai` package is the canonical Azure OpenAI
    client Microsoft Learn shows for chat completions, and azure-ai-inference's
    beta SDK is slated for retirement (Aug 2026). The durable teaching code is
    the openai package against api-version 2024-10-21 (GA).

Resource backing this script:
    The Foundry (AIServices) resource provisioned by
    Deploy-Lesson08-Infrastructure.ps1 -- ai901-lesson08-foundry
    (rg-ai901-lesson08-demo, East US 2), with a gpt-4o-mini Standard deployment.
    Auth is key + endpoint via .env (never hardcode keys in source).

How to run:
    python -m venv .venv
    .venv\\Scripts\\Activate.ps1
    pip install -r requirements.txt
    cp .env.example .env      # paste AZURE_OPENAI_ENDPOINT + _KEY from deploy output
    python lesson-08-foundry-chat.py
"""

from __future__ import annotations

import os
import sys

from openai import AzureOpenAI
from dotenv import load_dotenv

# ---------------------------------------------------------------------------
# 1. Load credentials from .env -- never hardcode keys in source.
#    override=True makes this lesson's .env authoritative even if the machine
#    already has stray AZURE_OPENAI_* environment variables from another project
#    (a real hazard -- without override, an OS-level AZURE_OPENAI_ENDPOINT
#    silently shadows the .env and the demo hits the wrong resource).
# ---------------------------------------------------------------------------
load_dotenv(override=True)

ENDPOINT = os.environ.get("AZURE_OPENAI_ENDPOINT")
KEY = os.environ.get("AZURE_OPENAI_KEY")
# The `model` argument below is the DEPLOYMENT name, not the model name. The
# deploy script names the deployment "gpt-4o-mini" by default; if you renamed
# it in the wizard, set AZURE_OPENAI_CHAT_DEPLOYMENT to match.
DEPLOYMENT = os.environ.get("AZURE_OPENAI_CHAT_DEPLOYMENT", "gpt-4o-mini")
API_VERSION = os.environ.get("AZURE_OPENAI_API_VERSION", "2024-10-21")

if not ENDPOINT or not KEY:
    sys.exit(
        "Missing AZURE_OPENAI_ENDPOINT or AZURE_OPENAI_KEY. Copy .env.example to "
        ".env and paste the values printed by Deploy-Lesson08-Infrastructure.ps1."
    )

# The same Wingtip Toys copywriter system message the Playground uses, so this
# script is the same call -- now expressed in code.
SYSTEM_MESSAGE = (
    "You are a marketing copywriter for Wingtip Toys. Write in a warm, "
    "family-friendly voice. Keep responses under two sentences unless the user "
    "explicitly asks for more."
)
USER_PROMPT = "Write a one-line tagline for a new wooden train set."


# ---------------------------------------------------------------------------
# 2. The whole Azure OpenAI chat pattern in one function. Client construction,
#    then chat.completions.create -- the two shapes the exam tests.
# ---------------------------------------------------------------------------
def chat(system_message: str, user_prompt: str) -> "ChatCompletion":  # noqa: F821
    """Send one system + user turn to the deployed chat model and return the response."""
    # --- The Azure-flavored client. Three required args, every Azure OpenAI app
    #     uses this exact shape. api_version is copied verbatim from the Playground
    #     View code output; azure_endpoint is the Foundry resource endpoint URL. ---
    client = AzureOpenAI(
        api_key=KEY,
        api_version=API_VERSION,
        azure_endpoint=ENDPOINT,
    )

    # --- The canonical chat call. model = DEPLOYMENT name (not model name);
    #     temperature is style/randomness; max_tokens caps response length. ---
    return client.chat.completions.create(
        model=DEPLOYMENT,
        messages=[
            {"role": "system", "content": system_message},
            {"role": "user", "content": user_prompt},
        ],
        temperature=0.7,
        max_tokens=200,
    )


# ---------------------------------------------------------------------------
# 3. Run it and print the same shape the Playground rendered --
#    the generated text plus the usage object (the billing meter).
# ---------------------------------------------------------------------------
def main() -> None:
    print(f"Endpoint:   {ENDPOINT}")
    print(f"Deployment: {DEPLOYMENT}   (the `model` argument -- a deployment name)")
    print(f"API ver:    {API_VERSION}")
    print(f"Key:        ****{KEY[-4:]}  (last 4 only)\n")
    print("Calling chat.completions.create against the deployed gpt-4o-mini...\n")

    response = chat(SYSTEM_MESSAGE, USER_PROMPT)

    # The two fields the Playground showed you, now as typed Python objects.
    text = response.choices[0].message.content
    usage = response.usage

    print(f"model (resolved): {response.model}")  # underlying model + version
    print(f"finish_reason:    {response.choices[0].finish_reason}\n")
    print("--- response.choices[0].message.content -------------------------------")
    print(text)
    print("-----------------------------------------------------------------------\n")
    print("--- response.usage (the billing meter) --------------------------------")
    print(f"  prompt_tokens:     {usage.prompt_tokens}")
    print(f"  completion_tokens: {usage.completion_tokens}")
    print(f"  total_tokens:      {usage.total_tokens}")
    print("-----------------------------------------------------------------------\n")

    print(EXAM_POCKET_CARD)


# ---------------------------------------------------------------------------
# Exam pocket card -- Azure OpenAI chat in Python.
# ---------------------------------------------------------------------------
EXAM_POCKET_CARD = """\
=== Azure OpenAI chat in Python -- exam pocket card ==========================
 Import  : from openai import AzureOpenAI       <- NOT OpenAI
 Client  : AzureOpenAI(api_key=..., api_version=..., azure_endpoint=...)
 Call    : client.chat.completions.create(
               model="<deployment-name>",       <- the DEPLOYMENT, not the model
               messages=[{"role": "system|user|assistant", "content": "..."}],
               temperature=0.0-2.0,             <- style / randomness
               max_tokens=int,                  <- response length cap
           )
 Read    : response.choices[0].message.content  <- the generated text
           response.usage.total_tokens          <- the billing meter
 Style is temperature. Length is max_tokens. The `model` arg is a deployment name.
============================================================================="""


if __name__ == "__main__":
    main()
