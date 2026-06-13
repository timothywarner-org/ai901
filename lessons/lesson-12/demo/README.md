# Lesson 12 Demo -- Build a Lightweight Client Application for an Agent

Demonstrates building a **multi-turn agent client application** using the
`azure-ai-agents` SDK. Lesson 12 is the synthesis of Lessons 10 and 11: a
loop that reads user input, posts it to the same thread, runs the agent,
and prints the reply -- the minimum shape of every production agent front-end
(AI-901 objective 2.4).

This demo folder contains two client programs:

| File | Purpose |
|---|---|
| `lesson-12-agent-client.py` | Multi-turn client that calls the agent built in Lesson 11. Uses `create_and_process` for the clean production pattern. |
| `fabrikam-support-client/client.py` | Extended client with a function tool, thread persistence, and `requires_action` handling. |

The key lesson-12 insight: **conversation memory lives in the thread on the server,
not in client code**. The client stays stateless beyond holding the thread ID.

## Prerequisites

- Python 3.12
- Azure CLI (`az version` to verify) -- run `az login` before the scripts.
- An Azure subscription with Contributor + User Access Administrator rights (Owner works).
- The agent built in Lesson 11 (the `contoso-docs-assistant`). If Lesson 11 resources
  are still running, reuse them with `-ReuseLesson11` below.

## Provision the resources

### Option A -- reuse Lesson 11 (recommended)

If the Lesson 11 resource group is still alive, point Lesson 12 at those resources:

```powershell
.\Deploy-Lesson12-Infrastructure.ps1 -ReuseLesson11
```

The script confirms the resources exist and prints the ready-to-paste `.env` values.

### Option B -- standalone Lesson 12 infrastructure

If Lesson 11 has been cleaned up, provision a fresh set of resources:

```powershell
.\Deploy-Lesson12-Infrastructure.ps1
```

Default names use the `ai901-lesson12-*` prefix. The Foundry resource name must be
**globally unique**. If you see a name-conflict error, add a suffix:

```powershell
.\Deploy-Lesson12-Infrastructure.ps1 -FoundryName ai901-lesson12-abc
```

Then build the `contoso-docs-assistant` agent in the Foundry portal once (same steps
as in Lesson 11) and copy its agent ID.

## Configure

```powershell
Copy-Item .env.example .env
```

Edit `.env` and paste:

```text
FOUNDRY_PROJECT_ENDPOINT=https://<foundry-name>.services.ai.azure.com/api/projects/<project-name>
AGENT_ID=<agent ID from the Foundry Agents tab>
```

For `fabrikam-support-client`, also copy its own `.env.example`:

```powershell
Copy-Item fabrikam-support-client\.env.example fabrikam-support-client\.env
```

Edit that `.env` and paste the same `FOUNDRY_PROJECT_ENDPOINT` (no `AGENT_ID` needed --
the fabrikam client creates its own agent at runtime).

**Never commit `.env`** -- it is listed in `.gitignore`.

## Install

```powershell
python -m venv .venv
.venv\Scripts\Activate.ps1
pip install -r requirements.txt
```

## Run

### lesson-12-agent-client.py

```powershell
python lesson-12-agent-client.py
```

Type questions, then type `exit` to end the session. Try asking a follow-up question
that requires remembering something from an earlier turn -- the agent answers correctly
because the full history lives in the thread.

### fabrikam-support-client

```powershell
python fabrikam-support-client/client.py
```

See `fabrikam-support-client/README.md` for the recommended prompt sequence and
explanations of thread persistence and function tool handling.

## What you should see (lesson-12-agent-client.py)

```
Connected to agent: contoso-docs-assistant (id ending XXXXXX)
Opened conversation thread (id ending XXXXXX).
Type a question, or 'exit' to end the session.

you> What is Microsoft Foundry?
agent> Microsoft Foundry is a unified AI development platform ...

you> How does it relate to what I just asked?
agent> In relation to your question about Microsoft Foundry, ...
Session ended.
```

The second answer demonstrates that the agent has the full conversation history
from the first turn -- without the client resending anything.

If you see `run completed -- see Foundry trace`, check the Foundry portal Agents ->
Traces tab. A `401 Unauthorized` immediately after deploy is RBAC propagation --
wait one minute and retry.

## Practice on your own

1. After a session with `lesson-12-agent-client.py`, note the thread ID that prints
   at startup. Relaunch the script. The thread ID will differ -- a new thread starts.
   Compare this with `fabrikam-support-client`, which persists the thread across
   launches. Think about when each pattern is the right choice.
2. In `lesson-12-agent-client.py`, replace `runs.create_and_process` with the
   manual `runs.create` + polling loop from Lesson 11. Observe that the behavior
   is identical -- `create_and_process` is just a convenience wrapper.
3. Add a `print(f"Thread {thread.id}")` after `threads.create()` in
   `lesson-12-agent-client.py`. Open the Foundry portal Agents -> Traces tab and
   find the matching thread ID to see the full conversation trace in the portal.
4. Break the connection on purpose: change `AGENT_ID` in `.env` to an invalid value
   and rerun. Read the error message carefully -- it shows you the exact validation
   the SDK applies and why IDs that begin with `asst_` are a different runtime.

## Exam connection

AI-901 objectives tested by this demo:

- **2.4** -- Build a client application for an agent:
  - Connect: `AgentsClient(endpoint, credential)` + `get_agent(agent_id)`.
  - Converse: `threads.create()`, `messages.create()`, `runs.create_and_process()`.
  - Multi-turn state: one thread reused across every turn -- memory is server-side.
- **Function tools** (fabrikam client):
  - The run reaches `requires_action` when the agent needs your function.
  - Your client runs the function locally and calls `submit_tool_outputs`.
  - The agent resumes with the function result and generates the final reply.

**SDK method summary:**

```
create_and_process(thread_id, agent_id)    -- convenience: create + poll
runs.create(thread_id, agent_id)           -- granular: returns immediately
runs.get(thread_id, run_id)                -- poll the run lifecycle
runs.submit_tool_outputs(thread_id, run_id, tool_outputs)  -- close a tool call
messages.list(thread_id, order="desc")     -- newest message first
```

## Teardown

```powershell
.\Deploy-Lesson12-Infrastructure.ps1 -Cleanup
```

This deletes the resource group and all resources inside it (async, ~5-10 min).
If you used `-ReuseLesson11`, clean up via the Lesson 11 deploy script instead:

```powershell
..\lesson-11\demo\Deploy-Lesson11-Infrastructure.ps1 -Cleanup
```
