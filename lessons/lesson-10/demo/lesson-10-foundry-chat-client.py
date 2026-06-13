"""
Lesson 10 -- Foundry SDK chat client (reference copy)
=======================================================
Course:  Exam AI-901 -- Microsoft Azure AI Fundamentals (Video)
LOs:     2.3.1 (scaffold), 2.3.2 (keyless auth), 2.3.3 (chat completion)
Goal:    Reference copy of the chat client learners build in the lesson.
         The fabrikam-chat/ folder holds a from-scratch version you can
         build step by step; this file is the finished reference.

Pedagogy:
    The show_messages_state() helper prints the running messages list state
    after every append, so you SEE the conversational-memory pattern grow
    turn by turn (system only -> +user -> +assistant -> +user -> +assistant
    ... 1 -> 2 -> 3 -> 4 -> 5 -> 6 -> 7 entries across three turns).
    The roles list IS the lesson -- accumulating it client-side is what gives
    the bot conversational memory because the SDK itself is stateless per call.

Why the openai package is NOT imported directly:
    The Foundry SDK's get_openai_client() returns a pre-wired AzureOpenAI
    instance bound to the project endpoint with an Entra token already in
    place. That keeps the import surface to two packages -- azure-ai-projects
    and azure-identity -- which is the L10 exam pocket card.

Resource backing this script:
    Foundry project provisioned by Deploy-Lesson10-Infrastructure.ps1
    (ai901-lesson10-foundry, project ai901-lesson10-project, East US 2).
    Chat deployment: gpt-4o 2024-11-20, Standard, capacity 10.
    Auth is keyless (DefaultAzureCredential) -- your az login token on a
    laptop, managed identity on Azure compute, federated credential in CI/CD.
    No keys in this file ever.

How to run (after the deploy script + az login):
    python -m venv .venv
    .venv\\Scripts\\Activate.ps1
    pip install -r requirements.txt
    cp .env.example .env   # paste FOUNDRY_PROJECT_ENDPOINT
    python lesson-10-foundry-chat-client.py

    Then type three turns to see the messages list grow from 1 to 7 entries:
      you> Recommend a starter wooden toy for a 4-year-old.
      you> What about something for a 7-year-old who likes the train one you just mentioned?
      you> Which of those two is better for outdoor play?
      you> exit
"""

from __future__ import annotations

import json
import os
import sys

from azure.identity import DefaultAzureCredential
from azure.ai.projects import AIProjectClient
from dotenv import load_dotenv

# ---------------------------------------------------------------------------
# 1. Load configuration -- never hardcode endpoints in source. override=True
#    keeps this lesson's .env authoritative over any stray OS-level vars from
#    earlier lessons.
# ---------------------------------------------------------------------------
load_dotenv(override=True)

ENDPOINT = os.environ.get("FOUNDRY_PROJECT_ENDPOINT")
MODEL = os.environ.get("FOUNDRY_MODEL_NAME", "gpt-4o")

if not ENDPOINT:
    sys.exit(
        "Missing FOUNDRY_PROJECT_ENDPOINT. Copy .env.example to .env and paste "
        "the value from the Foundry project Overview page "
        "(https://ai.azure.com -> ai901-lesson10-project -> Overview)."
    )

# ---------------------------------------------------------------------------
# 2. Client construction. Two packages do all the work:
#    * azure-ai-projects   -- AIProjectClient + project.get_openai_client()
#    * azure-identity      -- DefaultAzureCredential (the keyless credential
#                              chain that picks up your az login token)
#    No keys ever appear in this file -- identity governance IS the access
#    control, not key rotation.
# ---------------------------------------------------------------------------

# These environment variables cause the credential chain to pick the WRONG
# identity on a developer laptop. Clear them so DefaultAzureCredential
# resolves deterministically to the az login identity.
# In PRODUCTION you would NOT clear these -- that is where managed identity
# and service-principal EnvironmentCredential SHOULD win.
for _derailer in ("AZURE_TOKEN_CREDENTIALS", "AZURE_CLIENT_ID",
                  "AZURE_CLIENT_SECRET", "AZURE_TENANT_ID"):
    os.environ.pop(_derailer, None)

# exclude_managed_identity_credential=True skips the localhost managed-identity
# probe (avoids WinError 10061 noise on a laptop -- there is no IMDS endpoint).
project = AIProjectClient(
    endpoint=ENDPOINT,
    credential=DefaultAzureCredential(exclude_managed_identity_credential=True),
)
openai_client = project.get_openai_client()

# ---------------------------------------------------------------------------
# 3. Messages list -- a Python list of role-content dicts. The system message
#    sets persona and constraints; user/assistant messages get appended as
#    the conversation progresses. The model rereads the FULL list every turn,
#    which is why long chats eventually fill the context window.
# ---------------------------------------------------------------------------
messages = [
    {
        "role": "system",
        "content": (
            "You are a friendly product expert for Wingtip Toys. "
            "Keep responses under three sentences."
        ),
    },
]


def show_messages_state(messages: list[dict]) -> None:
    """Print the running messages list as JSON so you SEE the exact
    array shape that gets POSTed to the chat completions endpoint. The
    growing JSON IS the lesson -- the SDK is stateless per call, so the
    client carries the full conversation history in this array on every
    request.

    Long content values are truncated to keep the terminal readable; the
    JSON structure stays intact so the teaching point (the SHAPE of the
    request body) lands cleanly.
    """
    preview = [
        {
            "role": m["role"],
            "content": m["content"] if len(m["content"]) <= 80
                       else m["content"][:77] + "...",
        }
        for m in messages
    ]
    print(f"\n  --- messages array ({len(messages)} entries, sent as JSON over the wire) ---")
    # ensure_ascii=False -- Unicode characters render as themselves instead of
    # \u escapes, which keeps the terminal JSON readable.
    print(json.dumps(preview, indent=2, ensure_ascii=False))
    print("  ---")


# ---------------------------------------------------------------------------
# 4. Read-send-print loop with streaming. Each iteration:
#       a. Read a user turn from stdin
#       b. Append the user turn to messages, show the new state
#       c. Send the FULL messages list to the model (stream=True)
#       d. Stream tokens to stdout as they arrive
#       e. Append the full reply to messages, show the new state
#
#    Streaming improves PERCEIVED latency (tokens appear in milliseconds)
#    without changing TOTAL latency (the model still takes the same time to
#    generate the full response).
# ---------------------------------------------------------------------------
print("Wingtip Toys chat. Type 'q' (or quit/exit) to leave; Ctrl+C also works.\n")
show_messages_state(messages)  # initial state -- system only

# Quit tokens -- accept the common ones (q, quit, exit).
QUIT_TOKENS = {"", "q", "quit", "exit"}

while True:
    # Catch EOFError (Ctrl+Z on Windows, Ctrl+D on Unix) and KeyboardInterrupt
    # (Ctrl+C) so an accidental key combo does NOT dump a traceback.
    try:
        user = input("\nyou> ").strip()
    except (EOFError, KeyboardInterrupt):
        print()  # move to a fresh line after the ^C echo
        break

    if user.lower() in QUIT_TOKENS:
        break

    messages.append({"role": "user", "content": user})
    show_messages_state(messages)  # grew by 1 -- user appended

    try:
        response_stream = openai_client.chat.completions.create(
            model=MODEL,
            messages=messages,
            stream=True,
        )

        print("\nbot> ", end="", flush=True)
        full_reply = ""
        for chunk in response_stream:
            if chunk.choices and chunk.choices[0].delta.content:
                token = chunk.choices[0].delta.content
                print(token, end="", flush=True)
                full_reply += token
        print()  # newline after the streamed reply
    except KeyboardInterrupt:
        # Ctrl+C mid-stream is recoverable -- drop the partial reply, keep the
        # conversation history clean, and prompt for the next turn.
        print("\n(streaming interrupted -- partial reply dropped)")
        # Roll back the user turn we just appended so the messages array stays
        # consistent with what the model actually saw.
        messages.pop()
        show_messages_state(messages)
        continue

    messages.append({"role": "assistant", "content": full_reply})
    show_messages_state(messages)  # grew by 1 -- assistant appended

print("\nGoodbye!")

# ---------------------------------------------------------------------------
# Exam pocket card (L10 LO 2.3.1 + 2.3.2 + 2.3.3)
# ---------------------------------------------------------------------------
"""
import os
from azure.identity import DefaultAzureCredential
from azure.ai.projects import AIProjectClient

project = AIProjectClient(
    endpoint=os.environ["FOUNDRY_PROJECT_ENDPOINT"],
    credential=DefaultAzureCredential(),           # keyless credential chain
)
openai_client = project.get_openai_client()        # pre-wired AzureOpenAI

response = openai_client.chat.completions.create(
    model="<deployment-name>",                     # NOT the underlying model name
    messages=[
        {"role": "system",    "content": "..."},
        {"role": "user",      "content": "..."},
        {"role": "assistant", "content": "..."},   # past turns -- accumulate manually
    ],
    stream=False,                                  # True returns an iterator of chunks
)
# response.choices[0].message.content      -- the generated text
# response.choices[0].finish_reason        -- "stop" | "length" | "content_filter"
# response.usage.total_tokens              -- billing meter
"""
