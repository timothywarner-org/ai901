# Lesson 10 -- fabrikam-chat (staged build folder)

The working folder for the Lesson 10 demo. Open VS Code at `demo/` and work
from here. The `demo/` virtual environment already has the two packages this
needs (`azure-ai-projects`, `azure-identity`), so there is no separate venv to
create if you installed from `demo/requirements.txt`.

## How to run

```powershell
az login                                   # keyless auth uses your az token
cd demo
.venv\Scripts\Activate.ps1
python fabrikam-chat/chat.py
```

`chat.py` loads the `.env` in **this** folder (not any parent `.env`), so it
works whether your terminal is in `demo/` or `demo/fabrikam-chat/`.

## What is here

- **`chat.py`** -- the finished read-send-print + streaming client. To practice
  building from scratch, clear this file and type it out following the lesson.
  The finished file is here as a reference download.
- **`.env.example`** -- the template to copy. Keyless: endpoint + deployment
  name only, no API key.

## Auth note

Lesson 10 is **keyless**. `chat.py` uses `DefaultAzureCredential`, which picks
up your `az login` token on a developer laptop, a managed identity on Azure
compute, or a federated credential in CI/CD. Your signed-in identity needs the
**Cognitive Services OpenAI User** role on the Foundry resource -- the deploy
script assigns this to you automatically.

**Role assignment takes up to 5 minutes to propagate.** If you get a 403
immediately after the deploy script finishes, wait 5 minutes and try again.
This propagation delay is a favorite exam gotcha question.

## Got a 401 PermissionDenied on chat completions?

`DefaultAzureCredential` tries credentials in order, and **EnvironmentCredential
(a service principal from `AZURE_CLIENT_ID` / `AZURE_CLIENT_SECRET` /
`AZURE_TENANT_ID`) wins ahead of your Azure CLI login**. If those env vars are
set, your call authenticates as the service principal, not as you -- and that
principal may not hold the role. The 401 error names the exact principal making
the call.

**Fix A (recommended for a clean keyless demo) -- use your az-login identity:**

```powershell
Remove-Item Env:AZURE_CLIENT_ID, Env:AZURE_CLIENT_SECRET, Env:AZURE_TENANT_ID -ErrorAction SilentlyContinue
az login
```

**Fix B (fast unblock) -- grant the role to whatever principal is calling.**
Copy the principal GUID from the 401 message, then:

```powershell
$scope = "/subscriptions/<your-subscription-id>" +
         "/resourceGroups/rg-ai901-lesson10-demo" +
         "/providers/Microsoft.CognitiveServices/accounts/<your-foundry-name>"
az role assignment create `
  --assignee <principal-guid-from-the-401> `
  --role "Cognitive Services OpenAI User" `
  --scope $scope
```

Replace `<your-subscription-id>` and `<your-foundry-name>` with your actual
values from the deploy script output.

Confirm which identity you actually are:

```powershell
az ad signed-in-user show --query userPrincipalName -o tsv
```
