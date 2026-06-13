"""
Lesson 12 -- fabrikam-support-client/client.py
===============================================
Course:  Exam AI-901 -- Microsoft Azure AI Fundamentals (Video)
LOs:     2.5 (build a client application for an agent: connect, converse,
         handle multi-turn state, and handle a tool call from code)

WHY THIS CREATES THE AGENT INSTEAD OF FETCHING ONE
---------------------------------------------------
The `azure-ai-agents` SDK (AgentsClient -> threads / runs / messages) is the
classic Assistants runtime. It only accepts agent IDs that begin with `asst_`.
The agents you build in the new Foundry portal (or via the management API) are
a DIFFERENT, newer kind whose ID is just their name -- and AgentsClient cannot
drive those. So a client that wants the threads/runs/tool-call lifecycle must
create its OWN classic assistant. That is exactly what a "client application
for an agent" does: it owns the agent's lifecycle from code.

If you try `agents.get_agent("contoso-docs-assistant")` you will see:
  "Expected an ID that begins with 'asst'."
This is expected behavior, not a bug -- the two runtimes are separate.

THE FIVE-METHOD SPINE (the exam-tested shape)
    AgentsClient(endpoint, credential)
    agents.create_agent(model, name, instructions, tools)   # returns asst_...
    agents.threads.create()                                 # one per conversation
    agents.messages.create(thread_id, role, content)        # post a user turn
    agents.runs.create(thread_id, agent_id)                 # then poll runs.get
plus the tool-call closer: on `requires_action`, run your function and call
    agents.runs.submit_tool_outputs(thread_id, run_id, tool_outputs=[...])

AUTH: keyless (DefaultAzureCredential -> your az login). No keys anywhere.

How to run (from the demo/ folder):
    az login
    python fabrikam-support-client/client.py

Try these (in order):
    you> Hi, I have a question about order F-7781.
    you> Remind me -- which order was I asking about?      (proves thread memory)
    you> What is the current status of order F-7781?        (fires the tool)
    you> exit
"""

from __future__ import annotations

import json
import os
import sys
import time
from pathlib import Path

from azure.ai.agents import AgentsClient
from azure.ai.agents.models import ToolOutput
from azure.identity import DefaultAzureCredential
from dotenv import load_dotenv

# ---------------------------------------------------------------------------
# 1. Config. Load the .env sitting next to this file so it works whether your
#    terminal is in demo/ or demo/fabrikam-support-client/.
# ---------------------------------------------------------------------------
load_dotenv(dotenv_path=Path(__file__).with_name(".env"), override=True)

# Credential guard (same as the other lessons): clear the env settings that
# derail DefaultAzureCredential on a laptop so it resolves to your az login.
for _derailer in ("AZURE_TOKEN_CREDENTIALS", "AZURE_CLIENT_ID",
                  "AZURE_CLIENT_SECRET", "AZURE_TENANT_ID"):
    os.environ.pop(_derailer, None)

ENDPOINT = os.environ.get("FOUNDRY_PROJECT_ENDPOINT")
MODEL    = os.environ.get("FOUNDRY_MODEL_NAME", "gpt-4o")

if not ENDPOINT:
    sys.exit(
        "Missing FOUNDRY_PROJECT_ENDPOINT. Copy .env.example to .env in this "
        "folder and paste the Lesson 11 or 12 project endpoint."
    )

# ---------------------------------------------------------------------------
# 2. The function tool. This is the classic Assistants tool shape: type
#    'function' with a nested 'function' object. The agent will pause at
#    `requires_action` and ask the client to run this when a customer asks
#    about an order.
# ---------------------------------------------------------------------------
ORDER_TOOL = {
    "type": "function",
    "function": {
        "name": "get_order_status",
        "description": "Look up the current shipping status and estimated "
                       "delivery date of a Fabrikam customer order by its order ID.",
        "parameters": {
            "type": "object",
            "properties": {
                "order_id": {
                    "type": "string",
                    "description": "The Fabrikam order ID, for example 'F-7781'.",
                }
            },
            "required": ["order_id"],
            # Strict-mode runtimes require this to be present and false.
            "additionalProperties": False,
        },
    },
}

INSTRUCTIONS = (
    "You are the Fabrikam Support Assistant, a friendly customer-service agent. "
    "When a customer asks about the status, shipping, or delivery of an order, "
    "you MUST call get_order_status with the order ID -- never guess a status. "
    "Keep replies concise and warm."
)


def get_order_status(order_id: str) -> dict:
    """Simulated backend lookup. In production this calls your real order API.

    The whole point of the function-tool pattern: the AGENT decides to call this,
    YOUR client executes it, and submit_tool_outputs hands the result back.
    """
    return {
        "order_id": order_id,
        "status": "Shipped",
        "carrier": "Fabrikam Express",
        "estimated_delivery": "2026-06-15",
    }


def _val(v) -> str:
    """Unwrap a RunStatus / MessageRole enum to its plain string value."""
    return v.value if hasattr(v, "value") else str(v)


# ---------------------------------------------------------------------------
# 3. Client + agent. AgentsClient is the classic Agent Service runtime. We
#    create the agent here, so its ID is a proper asst_... that threads/runs use.
# ---------------------------------------------------------------------------
agents = AgentsClient(
    endpoint=ENDPOINT,
    credential=DefaultAzureCredential(exclude_managed_identity_credential=True),
)

agent = agents.create_agent(
    model=MODEL,
    name="fabrikam-support-agent",
    instructions=INSTRUCTIONS,
    tools=[ORDER_TOOL],
)
print(f"Created agent: {agent.name}  (id {agent.id})")

# The thread carries the conversation memory -- server-side, durable until deleted.
# To "pick up where we left off" across launches, we PERSIST the thread ID to a small
# file next to this script and reuse it. In production you would store this ID in your
# database, keyed by the user. Delete the .thread file to start a fresh conversation.
THREAD_FILE = Path(__file__).with_name(".thread")

thread = None
if THREAD_FILE.exists():
    saved_id = THREAD_FILE.read_text().strip()
    try:
        thread = agents.threads.get(saved_id)        # resume the prior conversation
        print(f"Resumed thread {thread.id} -- conversation history preserved.")
    except Exception:
        print("Saved thread was gone; starting a new one.")

if thread is None:
    thread = agents.threads.create()
    THREAD_FILE.write_text(thread.id)                 # persist for next launch
    print(f"Opened new thread {thread.id} (saved for next time).")

print("Ask a question. Try the order prompts in the module header. Type 'exit' to quit.\n")

TERMINAL = {"completed", "failed", "cancelled", "expired"}

# ---------------------------------------------------------------------------
# 4. The client loop: read -> post -> run -> (handle tool call) -> print.
# ---------------------------------------------------------------------------
try:
    while True:
        try:
            user = input("you> ").strip()
        except (EOFError, KeyboardInterrupt):
            print()
            break
        if user.lower() in {"", "exit", "quit"}:
            break

        agents.messages.create(thread_id=thread.id, role="user", content=user)

        # create (not create_and_process) so we can intercept requires_action
        run = agents.runs.create(thread_id=thread.id, agent_id=agent.id)
        while _val(run.status) not in TERMINAL:
            time.sleep(1)
            run = agents.runs.get(thread_id=thread.id, run_id=run.id)

            if _val(run.status) == "requires_action":
                outputs = []
                for call in run.required_action.submit_tool_outputs.tool_calls:
                    if call.function.name == "get_order_status":
                        args   = json.loads(call.function.arguments)
                        result = get_order_status(args.get("order_id", "unknown"))
                        print(f"  [tool] get_order_status({args.get('order_id')}) -> {result['status']}")
                        outputs.append(ToolOutput(tool_call_id=call.id, output=json.dumps(result)))
                run = agents.runs.submit_tool_outputs(
                    thread_id=thread.id, run_id=run.id, tool_outputs=outputs
                )

        if _val(run.status) != "completed":
            print(f"agent> (run ended: {_val(run.status)})\n")
            continue

        # Newest agent message on the thread is the reply to this turn.
        reply = "(no reply found)"
        for m in agents.messages.list(thread_id=thread.id, order="desc"):
            if _val(m.role) in ("assistant", "agent"):
                reply = m.content[0].text.value if m.content else "(no content)"
                break
        print(f"agent> {reply}\n")

finally:
    # Clean up the AGENT (its config) but KEEP the thread (the memory), so the next
    # launch can resume from the saved .thread file. Delete that file to start over.
    agents.delete_agent(agent.id)
    print(f"Cleaned up agent {agent.id}. Conversation saved -- relaunch to resume.")
