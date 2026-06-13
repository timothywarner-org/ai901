"""
Lesson 10 -- fabrikam-chat/chat.py (staged build folder)
=========================================================
Course:  Exam AI-901 -- Microsoft Azure AI Fundamentals (Video)
LOs:     2.3.1 (scaffold), 2.3.2 (keyless auth), 2.3.3 (chat completion)

This is the finished working copy of the chat client you build in the lesson.
It lives in demo/fabrikam-chat/ so you can open VS Code once at the demo/
folder and work from here.

To build this from scratch, delete the contents of this file and type it out
following the lesson flow. The finished file is here as a reference and
download for learners.

Run from the demo/ folder (recommended -- reuses the demo/ venv):
    .venv\\Scripts\\Activate.ps1
    python fabrikam-chat/chat.py

Or from inside this folder with its own venv:
    python chat.py

Auth is KEYLESS (DefaultAzureCredential): your az login token locally, a
managed identity on Azure compute, a federated credential in CI/CD. No key in
this file or its .env ever -- the endpoint is the only thing configured.

Try these turns to grow the messages array from 1 to 7 entries:
    you> Recommend a starter wooden toy for a 4-year-old.
    you> What about something for a 7-year-old who likes the train one you mentioned?
    you> Which of those two is better for outdoor play?
    you> exit
"""

from __future__ import annotations

import json
import os
import sys
from pathlib import Path

from azure.identity import DefaultAzureCredential
from azure.ai.projects import AIProjectClient
from dotenv import load_dotenv

# ---------------------------------------------------------------------------
# 1. Load the .env sitting NEXT TO this script (fabrikam-chat/.env), not any
#    parent .env. Path(__file__).with_name(".env") resolves the sibling file
#    regardless of the terminal's current working directory, so
#    `python fabrikam-chat/chat.py` from demo/ still finds the right vars.
#    override=True keeps this lesson's values authoritative over stray OS vars.
# ---------------------------------------------------------------------------
load_dotenv(dotenv_path=Path(__file__).with_name(".env"), override=True)

ENDPOINT = os.environ.get("FOUNDRY_PROJECT_ENDPOINT")
MODEL = os.environ.get("FOUNDRY_MODEL_NAME", "gpt-4o")

if not ENDPOINT:
    sys.exit(
        "Missing FOUNDRY_PROJECT_ENDPOINT. Copy .env.example to .env in this "
        "folder and paste the project endpoint from the Foundry project "
        "Overview (https://ai.azure.com -> ai901-lesson10-project -> Overview)."
    )

# ---------------------------------------------------------------------------
# 2. Keyless credential. DefaultAzureCredential walks a chain of sources; on a
#    laptop you want it to land on your `az login` identity. Two environment
#    settings can derail that:
#      * AZURE_TOKEN_CREDENTIALS=prod  -- restricts the chain to deployed-service
#        credentials (managed identity / workload identity) and SKIPS the Azure
#        CLI credential, so your az login is never even tried.
#      * AZURE_CLIENT_ID / _SECRET / _TENANT -- a service-principal
#        EnvironmentCredential then wins AHEAD of your az login.
#    We clear them here so the credential resolves deterministically to your
#    az-login identity during development. In PRODUCTION you would NOT clear
#    these -- that is exactly where managed identity SHOULD win.
# ---------------------------------------------------------------------------
for _derailer in ("AZURE_TOKEN_CREDENTIALS", "AZURE_CLIENT_ID",
                  "AZURE_CLIENT_SECRET", "AZURE_TENANT_ID"):
    os.environ.pop(_derailer, None)

# exclude_managed_identity_credential=True skips the localhost managed-identity
# probe (avoids WinError 10061 noise -- there is no IMDS endpoint on a laptop).
credential = DefaultAzureCredential(exclude_managed_identity_credential=True)

project = AIProjectClient(endpoint=ENDPOINT, credential=credential)
openai_client = project.get_openai_client()

# ---------------------------------------------------------------------------
# 3. Messages list -- role/content dicts. The system message sets persona; the
#    model rereads the FULL list every turn, which is what gives the bot
#    conversational memory (the SDK is stateless per call).
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
    """Print the running messages list as JSON so you SEE the exact array
    shape POSTed to the chat completions endpoint. The growing JSON IS the
    lesson -- the client carries the full history in this array every request.
    Long content is truncated; the structure stays intact.
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
    print(json.dumps(preview, indent=2, ensure_ascii=False))
    print("  ---")


# ---------------------------------------------------------------------------
# 4. Read-send-print loop with streaming. Each turn: read input, append + show
#    state, send the FULL list (stream=True), print tokens as they arrive,
#    append the reply + show state. Streaming improves PERCEIVED latency, not
#    total latency.
# ---------------------------------------------------------------------------
print("Wingtip Toys chat. Type 'q' (or quit/exit) to leave; Ctrl+C also works.\n")
show_messages_state(messages)  # initial state -- system only

QUIT_TOKENS = {"", "q", "quit", "exit"}

while True:
    try:
        user = input("\nyou> ").strip()
    except (EOFError, KeyboardInterrupt):
        print()
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
        print()
    except KeyboardInterrupt:
        print("\n(streaming interrupted -- partial reply dropped)")
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
    messages=[{"role": "system", "content": "..."}],
    stream=False,                                  # True returns an iterator of chunks
)
# response.choices[0].message.content   -- the generated text
# response.choices[0].finish_reason     -- "stop" | "length" | "content_filter"
"""
