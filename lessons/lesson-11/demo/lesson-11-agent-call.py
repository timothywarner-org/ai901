"""
Lesson 11 -- Foundry Agents SDK Bookend
========================================
Course:  Exam AI-901 -- Microsoft Azure AI Fundamentals (Video)
LOs:     2.4.1 (build and test), 2.4.2 (agent components), 2.4.3 (test and trace)
Goal:    Call the agent you created in the Foundry portal earlier in this
         lesson (the `contoso-docs-assistant`) from ~30 lines of Python,
         so you see the three-noun Agent Service model -- agent / thread /
         message -- plus the run lifecycle that drives every Foundry agent call.

Why TWO Azure SDK packages are imported:
    Foundry's Agent Service got split across two SDK packages in 2026:

      * azure-ai-projects (AIProjectClient)
            -- the entry point for all Foundry surfaces
            -- exposes connections, deployments, datasets, indexes, the new
               version-based agent surface (project.agents.create_version,
               list, get, etc.) and an OpenAI client (get_openai_client)

      * azure-ai-agents (AgentsClient)
            -- the runtime Agent Service surface AI-901 LO 2.4 tests:
               threads, messages, runs, plus the older create_agent /
               list_agents / delete_agent shape

    The threads-messages-runs pattern -- the one the Foundry portal Agents
    tab builds visually in the portal steps earlier in this lesson --
    lives in AgentsClient. This script constructs AgentsClient directly
    against the project endpoint.

The visibility upgrade -- show_thread_state():
    AgentsClient.runs.create_and_process() is the convenience method that
    wraps the entire run lifecycle in one call. That convenience hides the
    most exam-relevant detail of the Agent Service: the run state machine.
    This demo uses the granular runs.create + manual runs.get polling
    loop so you SEE the run transition queued -> in_progress ->
    completed in real time, and SEE the message count grow from 1 (user
    only) to 2 (user + assistant) after the run completes. The hidden state
    becomes visible state.

Resource backing this script:
    The Foundry project provisioned by Deploy-Lesson11-Infrastructure.ps1
    (ai901-lesson11-<suffix>, East US 2). The AGENT_ID comes from the agent
    built in Beats 1-3 -- copy it from the Foundry portal Agents tab into
    .env after the portal build completes.
    Auth is keyless (DefaultAzureCredential) -- the developer az login token
    on your laptop, the managed identity on Azure compute, the federated
    credential in CI/CD. No keys in this file ever.

How to run:
    python -m venv .venv
    .venv\\Scripts\\Activate.ps1
    pip install -r requirements.txt
    cp .env.example .env          # paste FOUNDRY_PROJECT_ENDPOINT + AGENT_ID
    az login                      # if not already signed in
    python lesson-11-agent-call.py
"""

from __future__ import annotations

import os
import sys
import time

from azure.identity import DefaultAzureCredential
from azure.ai.agents import AgentsClient
from dotenv import load_dotenv

# ---------------------------------------------------------------------------
# 1. Load configuration from .env -- never hardcode endpoints or IDs.
#    override=True keeps this lesson's .env authoritative over any stray
#    OS-level vars from earlier lessons (see Lesson 8 for the rationale).
# ---------------------------------------------------------------------------
load_dotenv(override=True)

ENDPOINT = os.environ.get("FOUNDRY_PROJECT_ENDPOINT")
AGENT_ID = os.environ.get("AGENT_ID")

if not ENDPOINT or not AGENT_ID:
    sys.exit(
        "Missing FOUNDRY_PROJECT_ENDPOINT or AGENT_ID. Copy .env.example to .env "
        "and paste both. The endpoint is on the Foundry project Overview. In the "
        "new Foundry the agent's ID IS its name -- so AGENT_ID is just the name "
        "you gave the agent (for example: contoso-azure-dev-agent). Make sure "
        "FOUNDRY_PROJECT_ENDPOINT points at the SAME project the agent lives in."
    )

# Demo prompt -- single-shot to keep the SDK bookend under three minutes.
USER_PROMPT = "In two sentences: what is the keyless way to authenticate the Microsoft Foundry SDK from Python, and why prefer it over API keys?"

# ---------------------------------------------------------------------------
# 2. Visibility helper -- print the running thread + run state so you SEE
#    the Agent Service runtime state machine. The convenience method hides
#    the state machine; we expose it so you can watch the run transition
#    queued -> in_progress -> completed and the message count grow.
# ---------------------------------------------------------------------------
def _enum_value(v):
    """Render an enum (or string) as its plain string value.

    The Agent Service SDK returns RunStatus and MessageRole as enums whose
    default __str__ includes the class name (e.g. 'RunStatus.QUEUED'). We
    want clean output, so unwrap to the underlying string value when the
    type is an enum and pass through otherwise.
    """
    return v.value if hasattr(v, "value") else str(v)


def show_thread_state(label: str, thread, agents_client, run=None) -> None:
    """Print thread id, run status (if any), and current message count.

    The bracketed marker helps you correlate each SDK call to a visible
    state change. The thread.id is truncated to the last six chars for
    screen real estate -- the full id is a UUID with hyphens that wraps
    at typical terminal widths.
    """
    thread_short = thread.id[-6:]
    msg_count = sum(1 for _ in agents_client.messages.list(thread_id=thread.id))
    if run is not None:
        print(
            f"  [{label} | thread {thread_short} | "
            f"run status: {_enum_value(run.status)} | messages: {msg_count}]"
        )
    else:
        print(f"  [{label} | thread {thread_short} | messages: {msg_count}]")


# ---------------------------------------------------------------------------
# 3. Client construction. AgentsClient is the Foundry Agent Service runtime
#    surface -- the same project endpoint used for the portal build earlier
#    in this lesson, plus the keyless credential chain (DefaultAzureCredential).
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

# Retrieve the agent you built in the Foundry portal earlier in this lesson.
# The agent definition (instructions, tools, knowledge) lives server-side;
# this call just gets a handle to it by ID.
agent = agents.get_agent(agent_id=AGENT_ID)
print(f"Retrieved agent: {agent.name} (id ending {agent.id[-6:]})\n")

# ---------------------------------------------------------------------------
# 4. Thread + message + run -- the three-noun pattern the exam tests.
#    Each step is followed by show_thread_state so you correlate the SDK
#    call to the visible state change in the bracketed marker.
# ---------------------------------------------------------------------------
thread = agents.threads.create()
show_thread_state("after threads.create", thread, agents)
# Expected: [after threads.create | thread XXXXXX | messages: 0]

agents.messages.create(
    thread_id=thread.id,
    role="user",
    content=USER_PROMPT,
)
show_thread_state("after messages.create", thread, agents)
# Expected: [after messages.create | thread XXXXXX | messages: 1]

print(f"\nyou> {USER_PROMPT}\n")

# Start the run. `create` (not `create_and_process`) returns immediately with
# status "queued" -- we poll manually so the lifecycle is visible. In a
# production app you would usually call `create_and_process` and let the SDK
# handle the polling, but for this demo we trade convenience for visibility.
run = agents.runs.create(thread_id=thread.id, agent_id=agent.id)
show_thread_state("after runs.create", thread, agents, run)
# Expected: [after runs.create | thread XXXXXX | run status: queued | messages: 1]

# Poll until the run reaches a terminal state. The terminal statuses on the
# Agent Service are: completed, failed, cancelled, expired. Anything else
# (queued, in_progress, requires_action) means the run is still working and
# we should poll again. One-second cadence is plenty for a demo; production
# code would back off exponentially.
TERMINAL_STATUSES = {"completed", "failed", "cancelled", "expired"}
poll_count = 0
while run.status not in TERMINAL_STATUSES:
    poll_count += 1
    time.sleep(1)
    run = agents.runs.get(thread_id=thread.id, run_id=run.id)
    show_thread_state(f"polling (#{poll_count})", thread, agents, run)
    # Expected progression: queued -> in_progress -> ... -> completed

if run.status != "completed":
    sys.exit(f"\nRun ended in non-success state: {run.status}")

# ---------------------------------------------------------------------------
# 5. Read the thread back. order="asc" reads oldest-first so the print order
#    matches the conversation order (user turn first, assistant turn second).
#    The content field is a list -- messages can carry multiple content
#    blocks (text, file citations, image references) -- but for chat
#    responses you mostly see content[0].text.value.
# ---------------------------------------------------------------------------
print("\n--- Final thread contents ---")
messages = agents.messages.list(thread_id=thread.id, order="asc")
for m in messages:
    text = m.content[0].text.value if m.content else "(no content)"
    print(f"{_enum_value(m.role)}> {text}\n")

# Final visibility marker so the closing state is visible.
show_thread_state("final state", thread, agents, run)

# ---------------------------------------------------------------------------
# Exam pocket card
# ---------------------------------------------------------------------------
"""
from azure.identity import DefaultAzureCredential
from azure.ai.agents import AgentsClient

agents = AgentsClient(endpoint=..., credential=DefaultAzureCredential())

agent  = agents.get_agent(agent_id=...)          # by ID from the portal
thread = agents.threads.create()                  # one per user session

agents.messages.create(thread_id=..., role="user", content="...")
run = agents.runs.create(thread_id=..., agent_id=...)             # returns queued
while run.status not in {"completed","failed","cancelled","expired"}:
    run = agents.runs.get(thread_id=..., run_id=run.id)           # poll lifecycle
# (or: run = agents.runs.create_and_process(thread_id=..., agent_id=...))

for m in agents.messages.list(thread_id=..., order="asc"):
    print(m.role, m.content[0].text.value)
"""
