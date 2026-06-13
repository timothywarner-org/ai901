# Lesson 04 Demo -- Responsible AI: Inclusiveness, Transparency, and Accountability

This demo provisions the Azure portal resources that support the Lesson 04
**Responsible AI** walkthrough. The lesson has no Python code -- all learning
objectives are demonstrated through the Microsoft Foundry portal (content filters,
RAI policy configuration, and the Application Insights audit trail).

**AI-901 objective:** 1.2 -- Identify guiding principles for responsible AI
(fairness, reliability, privacy, inclusiveness, transparency, accountability).

---

## Prerequisites

- **PowerShell 7.4 or later** --
  verify with `$PSVersionTable.PSVersion`
- **Azure CLI 2.51 or later** --
  install from <https://aka.ms/install-azure-cli>
- **An Azure subscription** where you can create resource groups and
  Cognitive Services resources
- **Signed in** to the correct subscription:
  ```powershell
  az login
  az account set --subscription "<your subscription name or id>"
  ```
- **Contributor + User Access Administrator** on the subscription (needed
  for RBAC grants in Step 8)

---

## Provision the resources

Run the deploy script from the `demo/` folder:

```powershell
cd lessons\lesson-04\demo
.\Deploy-Lesson04-Infrastructure.ps1
```

The script is **idempotent** -- re-running it after a partial failure is safe.
It prints `[OK]` / `[SKIP]` / `[WAIT]` status lines so you can track progress.

**What it creates:**

| Resource | Purpose |
| --- | --- |
| Resource group `rg-ai901-lesson04-demo` | Logical container for all lesson resources |
| Foundry resource `ai901-lesson04-foundry` (AIServices, S0) | Multi-service umbrella for Speech, Language, Translator |
| Model deployment `gpt-4o-mini` (GlobalStandard, 10K TPM) | Chat playground for content-filter policy walkthrough |
| Log Analytics workspace `log-ai901-lesson04` | Backend for Application Insights |
| Application Insights `appi-ai901-lesson04` | Long-term audit store for Foundry tracing |
| Azure AI Search `srch-ai901-lesson04` (Basic) | Required by the "Add your data" RAG flow |
| Storage account `stai901lesson04` + `data` container | PDF upload target for "Add your data" |
| RBAC grants (Storage Blob Data Reader, Search roles) | Foundry managed identity access to Search and Storage |

After the script completes, follow the **TWO MANUAL STEPS** it prints to:

1. Create the Foundry project `ai901-lesson04-project` in the portal.
2. Connect `appi-ai901-lesson04` to the project for tracing.

**Cleanup when you are done:**

```powershell
.\Deploy-Lesson04-Infrastructure.ps1  # already ran -- just delete the group
az group delete --name rg-ai901-lesson04-demo --yes --no-wait
```

Or pass the resource group name you used if you added a `-NameSuffix`.

---

## Configure

This is a concept lesson (Lessons 01-07) -- there is no Python script to
configure. All demo steps run in the browser:

| Portal | URL |
| --- | --- |
| Microsoft Foundry portal | <https://ai.azure.com> |
| Azure portal (resource group) | <https://portal.azure.com> |

After provisioning, open the Foundry portal, select the project, and follow the
walkthrough in the demo runbook:

- **Responsible AI policy** -- Foundry left nav -> Safety + security -> Content
  filters. Walk through the default Microsoft policy categories
  (hate, violence, self-harm, sexual) and show how each slider maps to
  the AI-901 exam concepts of transparency and accountability.
- **"Add your data" RAG flow** -- shows the Search + Storage resources working
  as a retrieval layer, connecting to the inclusiveness discussion
  (grounding AI responses in your own authoritative content).
- **Application Insights traces** -- Foundry left nav -> Agents -> Traces.
  Shows the long-term audit log that makes AI decisions auditable --
  the accountability pillar in action.

---

## Practice on your own

1. **Adjust a content-filter threshold.** In the Foundry portal, open
   Safety + security -> Content filters, clone the default policy, and
   raise the "Violence" threshold one level. Send a borderline test prompt.
   Does the output change? What does the filter results block in the API
   response tell you?

2. **Upload a different PDF.** Replace the default PDF in the `data` container
   with a short document of your own. Re-run the "Add your data" configuration
   and ask the chat playground a question whose answer is in your document.
   Observe how grounding changes the response.

3. **Read the Application Insights log.** After running a few chat turns,
   open Application Insights in the Azure portal and navigate to
   Logs -> traces. Filter on `customDimensions`. What fields does Foundry
   populate automatically? Which ones relate to accountability?

---

## Exam connection

- **Transparency** -- content-filter policy configuration surfaces which
  categories are active and at what thresholds. The AI-901 exam tests your
  ability to match the six Responsible AI principles to real Azure controls.
- **Accountability** -- Application Insights tracing gives auditors a
  record of every model call and its filter result. "Who made this decision,
  and when?" is the accountability question.
- **Inclusiveness** -- RAG grounding on your own documents lets you supply
  content that reflects the needs of diverse user groups rather than relying
  on a model's general training data.
