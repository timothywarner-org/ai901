"""
Lesson 12 -- Lightweight Agent Client Application
==================================================
Course:  Exam AI-901 -- Microsoft Azure AI Fundamentals (Video)
LOs:     2.4 (build a client application for an agent: connect, converse,
         handle multi-turn state)
Goal:    Turn the single-shot Lesson 11 bookend into a real MULTI-TURN client
         application. One thread is created once and reused across every turn,
         so the agent remembers the conversation -- the whole point of Lesson
         12 is that conversation STATE lives in the thread on the server, not
         in your client code.

Why this is the "client application" the lesson title promises:
    Lesson 10 built a chat client against a raw model. Lesson 11 called an
    agent ONCE from code. Lesson 12 is the synthesis: a loop that reads user
    input, posts it to the SAME thread, runs the agent, and prints the reply
    -- the minimum shape of every production agent front-end. Swap the
    input() loop for a web request handler and you have a chat web app; the
    five SDK calls underneath do not change.

The five-method spine the exam tests (memorize the path, not the prose):
    AgentsClient                             -- the client (runtime)
    agents.get_agent(agent_id)               -- fetch the agent built in Lesson 11
    threads.create()                         -- open ONE conversation, reused below
    messages.create(thread, role, content)   -- post each user turn
    runs.create_and_process(thread, agent)   -- execute + wait for the reply

Resource backing this script:
    The Foundry project provisioned by Deploy-Lesson12-Infrastructure.ps1
    (or reused from Lesson 11). AGENT_ID is the agent built in the portal --
    copy it from the Foundry Agents tab into .env. Auth is keyless
    (DefaultAzureCredential): your az login token locally, a managed identity
    in Azure, a federated credential in CI/CD. No keys in this file ever.

How to run:
    python -m venv .venv
    .venv\\Scripts\\Activate.ps1
    pip install -r requirements.txt
    cp .env.example .env          # paste FOUNDRY_PROJECT_ENDPOINT + AGENT_ID
    az login                      # if not already signed in
    python lesson-12-agent-client.py
    # type questions; type 'exit' (or Ctrl-C) to end the session
"""

from __future__ import annotations

import os
import sys

from azure.ai.agents import AgentsClient
from azure.identity import DefaultAzureCredential
from dotenv import load_dotenv

# ---------------------------------------------------------------------------
# 1. Configuration. override=True keeps THIS lesson's .env authoritative over
#    any stray OS-level vars left by earlier lessons (same rationale as L11).
# ---------------------------------------------------------------------------
load_dotenv(override=True)

ENDPOINT = os.environ.get("FOUNDRY_PROJECT_ENDPOINT")
AGENT_ID = os.environ.get("AGENT_ID")

if not ENDPOINT or not AGENT_ID:
    sys.exit(
        "Missing FOUNDRY_PROJECT_ENDPOINT or AGENT_ID. Copy .env.example to "
        ".env and paste both -- the endpoint from the Foundry project "
        "Overview, the agent ID from the Agents tab built in Lesson 11."
    )

# Terminal run states. Anything outside this set means the run is still
# working (queued / in_progress / requires_action). create_and_process()
# handles the polling for us, so we only check the FINAL status it returns.
TERMINAL_OK = "completed"


def _enum_value(v) -> str:
    """Render a RunStatus / MessageRole enum as its plain string value.

    The SDK returns enums whose default __str__ includes the class name
    (e.g. 'MessageRole.AGENT'). Unwrap to the underlying value for clean
    output; pass strings through untouched.
    """
    return v.value if hasattr(v, "value") else str(v)


def latest_agent_reply(agents: AgentsClient, thread_id: str) -> str:
    """Return the text of the newest agent message on the thread.

    messages.list(order='desc') yields newest-first, so the first message
    whose role is the agent is the reply to the turn we just ran. The
    content field is a list of blocks -- chat replies live in
    content[0].text.value.
    """
    for m in agents.messages.list(thread_id=thread_id, order="desc"):
        if _enum_value(m.role) in ("assistant", "agent"):
            return m.content[0].text.value if m.content else "(no content)"
    return "(no reply found)"


# ---------------------------------------------------------------------------
# 2. Client + agent handle. AgentsClient is the Foundry Agent Service runtime
#    surface (threads / messages / runs). The agent definition -- instructions,
#    tools, knowledge -- lives server-side; get_agent just returns a handle.
#
#    Credential guard: two environment settings derail DefaultAzureCredential
#    on a laptop --
#      * AZURE_TOKEN_CREDENTIALS=prod  -- restricts the chain to deployed-service
#        credentials and SKIPS the Azure CLI credential, so your az login is
#        never tried.
#      * AZURE_CLIENT_ID / _SECRET / _TENANT -- a service-principal
#        EnvironmentCredential wins ahead of your az login.
#    We clear them so the credential resolves to your az-login identity.
#    In PRODUCTION you would NOT clear these.
# ---------------------------------------------------------------------------
for _derailer in ("AZURE_TOKEN_CREDENTIALS", "AZURE_CLIENT_ID",
                  "AZURE_CLIENT_SECRET", "AZURE_TENANT_ID"):
    os.environ.pop(_derailer, None)

credential = DefaultAzureCredential(exclude_managed_identity_credential=True)
agents = AgentsClient(endpoint=ENDPOINT, credential=credential)
agent = agents.get_agent(agent_id=AGENT_ID)
print(f"Connected to agent: {agent.name} (id ending {agent.id[-6:]})")

# ---------------------------------------------------------------------------
# 3. ONE thread for the whole session. This single line is the lesson's
#    headline idea: the thread is the durable conversation handle. We create
#    it once, before the loop, and reuse it for every turn -- so the agent
#    has the full history on every run without the client resending anything.
# ---------------------------------------------------------------------------
thread = agents.threads.create()
print(f"Opened conversation thread (id ending {thread.id[-6:]}).")
print("Type a question, or 'exit' to end the session.\n")

# ---------------------------------------------------------------------------
# 4. The multi-turn loop -- the client application proper. Read, post to the
#    SAME thread, run, print. Conversation memory accumulates server-side; the
#    client stays stateless beyond holding the thread ID.
# ---------------------------------------------------------------------------
while True:
    try:
        user_text = input("you> ").strip()
    except (EOFError, KeyboardInterrupt):
        print("\nSession ended.")
        break

    if not user_text:
        continue
    if user_text.lower() in {"exit", "quit"}:
        print("Session ended.")
        break

    # Post the user's turn onto the thread.
    agents.messages.create(thread_id=thread.id, role="user", content=user_text)

    # Execute the agent against the thread and wait for the run to finish.
    # create_and_process wraps the queued -> in_progress -> completed
    # lifecycle in one call -- the production-friendly counterpart to the
    # manual polling loop we used in Lesson 11 to expose the state machine.
    run = agents.runs.create_and_process(thread_id=thread.id, agent_id=agent.id)

    if _enum_value(run.status) != TERMINAL_OK:
        # One clean line on failure -- no stack trace on screen.
        print(f"agent> (run {_enum_value(run.status)} -- see Foundry trace)\n")
        continue

    print(f"agent> {latest_agent_reply(agents, thread.id)}\n")

# ---------------------------------------------------------------------------
# Exam pocket card
# ---------------------------------------------------------------------------
"""
from azure.identity import DefaultAzureCredential
from azure.ai.agents import AgentsClient

agents = AgentsClient(endpoint=..., credential=DefaultAzureCredential())
agent  = agents.get_agent(agent_id=...)     # built in Lesson 11
thread = agents.threads.create()            # ONCE -- reused for every turn

while True:                                  # the client application loop
    agents.messages.create(thread_id=thread.id, role="user", content=...)
    run = agents.runs.create_and_process(thread_id=thread.id, agent_id=agent.id)
    # newest agent message on the thread is the reply:
    # agents.messages.list(thread_id=thread.id, order="desc")

# Memory lives in the THREAD on the server -- the client never resends history.
"""
