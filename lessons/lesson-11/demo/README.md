# Lesson 11 Demo -- Create and Test a Single-Agent Solution in the Foundry Portal

Demonstrates the **Foundry Agent Service** end to end: build an agent in the portal
(instructions, File Search knowledge, MCP tool), test it in the Agents playground,
review the trace, then call the same agent from ~30 lines of Python using the
`azure-ai-agents` SDK (AI-901 objectives 2.4.1 -- 2.4.3).

The Python bookend (`lesson-11-agent-call.py`) exposes the run state machine --
`queued -> in_progress -> completed` -- with bracketed visibility markers so you
can watch the agent lifecycle in your terminal.

## Prerequisites

- Python 3.12
- Azure CLI (`az version` to verify) -- run `az login` before the script.
- An Azure subscription with Contributor + User Access Administrator rights
  (Owner role works). Owner is needed to assign the RBAC role the script creates.
- The `azure-ai-agents`, `azure-identity`, and `python-dotenv` packages
  (installed via `requirements.txt` below).

## Provision the resources

Run the deploy script from this folder. The script is idempotent -- safe to rerun.

```powershell
.\Deploy-Lesson11-Infrastructure.ps1
```

Default names use the `ai901-lesson11-*` prefix. The Foundry resource name must be
**globally unique**. If you see a name-conflict error, pass a custom suffix:

```powershell
.\Deploy-Lesson11-Infrastructure.ps1 -FoundryName ai901-lesson11-abc
```

The script provisions:

- A Foundry AIServices resource (S0) with project management enabled.
- A Foundry project (`ai901-lesson11-project` by default).
- A `gpt-4o` model deployment (2024-11-20, GlobalStandard) -- the tool-capable
  base model. **Non-tool-capable models silently ignore attached tools.** This is
  the most common Lesson 11 troubleshooting trap.
- A Log Analytics workspace + Application Insights resource for trace export.
- The Cognitive Services OpenAI User RBAC role on the Foundry resource for the
  signed-in identity (required for keyless auth).

After the script finishes, go to the Foundry portal (https://ai.azure.com),
open your project, navigate to **Agents -> Traces -> Connect**, and connect the
Application Insights resource. This enables OpenTelemetry trace export.

Then build the agent in the **Agents** tab (earlier in this lesson). When the agent
is created, copy its **agent ID** from the portal into your `.env` file.

## Configure

```powershell
Copy-Item .env.example .env
```

Edit `.env` and paste:

```text
FOUNDRY_PROJECT_ENDPOINT=https://<foundry-name>.services.ai.azure.com/api/projects/<project-name>
AGENT_ID=<agent ID from the Foundry Agents tab>
```

The deploy script prints the ready-to-paste `FOUNDRY_PROJECT_ENDPOINT` at the end
of its output. **Never commit `.env`** -- it is listed in `.gitignore`.

## Install

```powershell
python -m venv .venv
.venv\Scripts\Activate.ps1
pip install -r requirements.txt
```

## Run

```powershell
python lesson-11-agent-call.py
```

The script:

1. Retrieves the agent you built in the portal.
2. Creates a thread (one per session).
3. Posts a single user message.
4. Starts a run with `runs.create` (not `create_and_process`) and polls manually
   so you can watch `queued -> in_progress -> completed` in your terminal.
5. Prints the full thread -- user turn, then agent reply.

## What you should see

```
Retrieved agent: contoso-docs-assistant (id ending XXXXXX)

  [after threads.create | thread XXXXXX | messages: 0]
  [after messages.create | thread XXXXXX | messages: 1]

you> In two sentences: what is the keyless way to authenticate the Microsoft Foundry SDK from Python, and why prefer it over API keys?

  [after runs.create | thread XXXXXX | run status: queued | messages: 1]
  [polling (#1) | thread XXXXXX | run status: in_progress | messages: 1]
  [polling (#2) | thread XXXXXX | run status: completed | messages: 2]

--- Final thread contents ---
user> In two sentences: ...

assistant> Use DefaultAzureCredential from azure-identity ...

  [final state | thread XXXXXX | run status: completed | messages: 2]
```

If you see `run status: failed`, check the Foundry portal Agents -> Traces tab
for the error detail. A `401 Unauthorized` immediately after deploy means the
RBAC role assignment is still propagating -- wait one minute and retry.

## Practice on your own

1. Change `USER_PROMPT` in the script to a different Azure AI question and rerun.
   Watch the message count grow from 1 to 2 each time.
2. Switch from the manual polling loop to `runs.create_and_process` (one-liner).
   Observe how it hides the state machine -- and why the manual loop is more
   educational for learning the lifecycle.
3. In the Foundry portal, navigate to the **Traces** tab and expand the trace for
   your run. Identify the `gen_ai.request.model` span and the tool-call spans.
4. Open the `kql-queries.kql` file in this folder and run query 0 in the Log
   Analytics workspace to see the raw OpenTelemetry spans Foundry exported.
   Then run query 2 to chart token usage over time.

## Exam connection

AI-901 objectives tested by this demo:

- **2.4.1** -- Build and test a single-agent solution (portal build + SDK call).
- **2.4.2** -- Describe agent components: role, instructions, tools, knowledge.
  - The agent JSON (`lesson-11-agent.json`) shows the `tools` array and the
    `instructions` field that map to these components.
  - **Key term:** **File Search** (knowledge source) vs **Code Interpreter**
    (computation tool) vs **MCP** (external tool connection).
- **2.4.3** -- Test an agent and review the conversation trace.
  - The `kql-queries.kql` file has four ready-to-run queries for the
    Log Analytics workspace the deploy script provisions.

**SDK class map (memorize the path):**

```
AgentsClient(endpoint, credential)
  .get_agent(agent_id)            -- fetch agent definition by ID
  .threads.create()               -- open a conversation (one per session)
  .messages.create(thread_id, role, content)   -- post a user turn
  .runs.create(thread_id, agent_id)            -- start a run (returns queued)
  .runs.get(thread_id, run_id)                 -- poll the run lifecycle
  .runs.create_and_process(...)                -- convenience: create + poll
  .messages.list(thread_id, order="asc")       -- read all messages
```

## Teardown

```powershell
.\Deploy-Lesson11-Infrastructure.ps1 -Cleanup
```

This deletes the resource group and all resources inside it (async, ~5-10 min).
