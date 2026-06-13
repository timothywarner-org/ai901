# Lesson 10: Build a Lightweight Chat Client with the Foundry SDK

Demonstrates keyless authentication with `DefaultAzureCredential` and a
streaming read-send-print loop using the `AIProjectClient` from the
`azure-ai-projects` SDK against a gpt-4o deployment in Microsoft Foundry.

**AI-901 objectives:** 2.3.1 (scaffold a chat client), 2.3.2 (keyless auth),
2.3.3 (chat completion with streaming and conversational memory)

## Prerequisites

- Python 3.12
- Azure CLI (`az`) -- install from <https://aka.ms/azurecli>
- An Azure subscription with Microsoft.CognitiveServices registered
- `az login` completed

## Provision the resources

Run the deploy script from this folder (PowerShell):

```powershell
.\Deploy-Lesson10-Infrastructure.ps1
```

The script provisions a Foundry (AIServices) resource, a Foundry project, a
gpt-4o chat deployment, and assigns you the **Cognitive Services OpenAI User**
role so the keyless credential chain can call the model.

**The resource name must be globally unique.** If the default is taken, pass
`-FoundryName` with a name of your choosing.

Pass `-TeammateUpn` with a second identity UPN to document the teammate for the
RBAC failure-to-success demo in the final lesson beat.

To tear down when you are done:

```powershell
.\Deploy-Lesson10-Infrastructure.ps1 -Cleanup
```

## Configure

Copy `.env.example` to `.env` and paste the project endpoint from the deploy
script output:

```powershell
cp .env.example .env
# Edit .env -- paste FOUNDRY_PROJECT_ENDPOINT
```

The same `.env.example` pattern applies inside `fabrikam-chat/` -- copy it there
as well when building from scratch.

**Never commit `.env` to source control.**

## Install

```powershell
python -m venv .venv
.venv\Scripts\Activate.ps1
pip install -r requirements.txt
```

## Run

To run the reference copy:

```powershell
python lesson-10-foundry-chat-client.py
```

To build from scratch (as in the lesson):

```powershell
# Open VS Code at this demo/ folder
# Clear fabrikam-chat/chat.py and build it from scratch
# Run it:
python fabrikam-chat/chat.py
```

Type three turns and watch the messages array grow from 1 to 7 entries:

```
you> Recommend a starter wooden toy for a 4-year-old.
you> What about something for a 7-year-old who likes the train one you just mentioned?
you> Which of those two is better for outdoor play?
you> exit
```

## What you should see

Each turn prints the **messages array** before and after the call -- the array is
the lesson. The SDK sends the FULL list to the model on every call, which is how
the bot has conversational memory. After three turns the array has 7 entries:

```
  --- messages array (7 entries, sent as JSON over the wire) ---
  [
    {"role": "system",    "content": "You are a friendly product expert..."},
    {"role": "user",      "content": "Recommend a starter wooden toy..."},
    {"role": "assistant", "content": "..."},
    {"role": "user",      "content": "What about something for a 7-year-old..."},
    {"role": "assistant", "content": "..."},
    {"role": "user",      "content": "Which of those two is better..."},
    {"role": "assistant", "content": "..."}
  ]
  ---
```

## Practice on your own

1. After three turns, send a fourth message that refers back to the first answer
   (for example: "Tell me more about that 4-year-old toy you mentioned first").
   The model answers correctly because the full history is in the array.
2. Change `stream=True` to `stream=False` in the chat call. Observe that the
   response now arrives all at once instead of streaming token by token.
3. Deliberately revoke your **Cognitive Services OpenAI User** role in the Azure
   portal IAM blade, wait 5 minutes, and rerun. Observe the 403 error. Then
   re-assign the role and confirm that waiting 5 minutes lets the next call succeed.
4. Set `AZURE_CLIENT_ID` to a dummy value in your shell, then run the script.
   Observe that the credential chain picks up `EnvironmentCredential` and fails
   (no service principal exists), instead of falling through to your az login.
   Then clear the variable and rerun to confirm az login takes over.

## Exam connection

| Topic | Key fact |
| --- | --- |
| Keyless auth packages | `azure-ai-projects` + `azure-identity` |
| How to get a chat client | `project.get_openai_client()` -- returns a pre-wired `AzureOpenAI` |
| Conversational memory | Accumulate messages manually -- the SDK is stateless per call |
| Streaming vs. non-streaming | `stream=True` improves perceived latency; total latency is unchanged |
| RBAC role for chat | **Cognitive Services OpenAI User** on the Foundry resource |
| Role propagation delay | Up to 5 minutes -- a favorite exam-gotcha question |
| Credential chain derailment | `AZURE_CLIENT_ID`/`_SECRET`/`_TENANT` make EnvironmentCredential win before az login |
