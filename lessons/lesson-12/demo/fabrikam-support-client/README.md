# fabrikam-support-client

A self-contained client application for a Foundry agent, demonstrating multi-turn
conversation state, function tool calls, and thread persistence across launches
(AI-901 objective 2.4 / 2.5).

## Run

From the `demo/` folder:

```powershell
az login
python fabrikam-support-client/client.py
```

`client.py` loads the `.env` in **this** folder, so it works from `demo/` or from
inside this folder.

## Try these (in order)

```
Hi, I have a question about order F-7781.
Remind me -- which order was I asking about?      # proves thread memory
What is the current status of order F-7781?        # fires the get_order_status tool
exit
```

Start by introducing the order number without explicitly asking for status. Then ask a
follow-up question that requires remembering the order number -- this proves the thread
holds the conversation history. Then ask for the status to trigger the function tool call
and watch the `[tool]` line appear in your terminal.

## Why this client CREATES the agent

The classic `AgentsClient` (threads/runs/messages) only accepts `asst_...` agent
IDs. Agents built in the new Foundry portal use their **name** as the ID and a
different runtime -- `agents.get_agent("fabrikam-support-agent")` rejects them
with the message: *"Expected an ID that begins with 'asst'."*

So a client that wants the threads/runs/tool-call lifecycle creates its **own**
classic assistant. That is a clean "build a client application for an agent"
story: the client owns the agent from code, creates it at startup, and deletes
it on exit so reruns stay tidy. The **thread** (the conversation memory) is kept
across launches via the `.thread` file next to this script.

## Thread persistence

The `.thread` file stores the thread ID so you can resume the conversation when
you relaunch `client.py`. Delete `.thread` to start a fresh conversation. In
production you would store the thread ID in your database, keyed by the user.

## Auth

Keyless (`DefaultAzureCredential`). Your `az login` identity needs the
**Cognitive Services OpenAI User** role on the Foundry resource. The deploy
scripts assign this automatically. A `401` right after deploy is RBAC
propagation -- wait one minute and retry.

The client clears `AZURE_TOKEN_CREDENTIALS` and service-principal environment
variables so `DefaultAzureCredential` resolves to your az login, not a hidden
service principal that may not have the correct role.

## Practice on your own

1. Add a second function tool, for example `get_return_policy(product_id)`, with
   a stub implementation. Observe how the agent decides when to call each tool.
2. Remove the `THREAD_FILE` persistence and restart the client. Verify the agent
   does not remember the prior conversation -- this concretely demonstrates that
   memory lives in the thread, not in the client.
3. Change `INSTRUCTIONS` to instruct the agent to respond only in Spanish. Rerun
   and observe that the agent behavior changes without any code changes to the
   tool or loop logic.
4. After a session, open the `.thread` file, copy the thread ID, and use the
   Azure CLI or Foundry portal to inspect the thread contents directly.
