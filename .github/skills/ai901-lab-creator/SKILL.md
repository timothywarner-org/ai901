---
name: ai901-lab-creator
description: Create short AI-901 practice labs (15-25 minutes) that are executable and self-validating. Every lab includes prerequisites, exact tasks, validation steps, expected outputs, and cleanup. Scope covers Microsoft Foundry portal builds, Foundry Python SDK client apps with keyless authentication, Azure AI Services via Foundry Tools, and Azure Content Understanding analyzers. Use when the user asks for a hands-on lab, practice exercise, or guided walkthrough.
---

# Skill: ai901.practice_labs.micro.validated

**Description:** Create short AI-901 practice labs (15-25 minutes) that are executable and self-validating. Every lab includes prerequisites, exact tasks, validation steps, expected outputs, and cleanup.

## Course context

This skill backs Tim Warner's Microsoft Press AI-901 video course companion repo at `C:\github\ai901`. The course is a 16-lesson Microsoft Press video course. Lessons 01-07 are concept lessons aligned to AI-901 Domain 1. Lessons 08-16 are build lessons aligned to AI-901 Domain 2. Each lesson lives at `lessons/lesson-NN/README.md`. When a lab is built to support a specific lesson, save the lab artifact under `lessons/lesson-NN/labs/` so that learners find it next to the lesson plan.

## Audience profile

The AI-901 audience is at the beginning of a career in AI solution development. Learners have conceptual knowledge of AI in Azure, can read Python coding syntax, and are familiar with Azure resources. Lab prose stays warm and direct. Avoid jargon that the lesson has not yet introduced.

## Style precedence

Follow the **Microsoft Worldwide Learning Exam Writing Style Guide** (WWL) for any text that mirrors exam phrasing (titles, goal statements, named resources, company references). Follow the **Microsoft Writing Style Guide** (MWSG) for the lab prose itself: warm, scannable, present-tense, sentence-style capitalization. Two MWSG conventions overridden by WWL for our labs: **no contractions** and **all uppercase for key names** (TAB, ENTER, CTRL+ALT+DELETE).

## Lab categories

AI-901 labs span four practical categories that map to the AI-901 build domain:

- **foundry-portal** -- Microsoft Foundry portal hands-on. Model deployment from the model catalog, playground experiments, single-agent builds, prompt flow inspection, and grounded chat configuration entirely inside the portal.
- **foundry-sdk** -- Python 3.12 client apps that call Microsoft Foundry endpoints with the **azure-ai-projects** and **azure-ai-agents** packages. Authentication is keyless via **DefaultAzureCredential**. Patterns include chat completion, multi-turn conversations, single-agent invocation, and tool-augmented agents.
- **ai-services** -- Azure AI Language, Azure AI Speech, and Azure AI Vision exercised through Microsoft Foundry Tools. Examples include text analytics, sentiment, key phrases, entity recognition, speech-to-text, text-to-speech, image analysis, optical character recognition, and image generation.
- **content-understanding** -- Azure Content Understanding analyzers across the four supported modalities: documents, images, audio, and video. Includes analyzer creation, schema definition, sample input runs, and output validation.

Default authoring tools by category:

- For **foundry-portal** labs, the primary path is the Microsoft Foundry portal at `ai.azure.com`.
- For **foundry-sdk** labs, the primary path is **Python 3.12** with the Foundry SDK and **DefaultAzureCredential**. Never default to API keys.
- For **ai-services** labs, the primary path is the Microsoft Foundry portal. When automation is required, use **Azure CLI** for tenant-side resource operations.
- For **content-understanding** labs, the primary path is the Microsoft Foundry portal. When code is required, use Python 3.12 with keyless authentication.

## Grounding

**Required sources:**

- Microsoft Learn (truth source for service capabilities, configuration, and architecture). Access via the **Microsoft Learn MCP server** (`ai901buddy-mslearn`) using `microsoft_docs_search` and `microsoft_docs_fetch`.
- Microsoft Learn code samples (for Python SDK, Azure CLI, and Bicep accuracy). Access via `microsoft_code_sample_search`.
- Canonical AI-901 objective domain file: `docs/ai901-objective-domain.md`.

Always ground first. Do not invent service capabilities, model names, or SKU options.

## AI-901 domains (canonical)

Skills measured date: **April 15, 2026**.

| Domain | Weight |
| --- | --- |
| Identify AI concepts and capabilities | 40-45% |
| Implement AI solutions by using Microsoft Foundry | 55-60% |

Domain 1 covers concept lessons 01-07 (no hands-on labs required, although optional reflective walkthroughs are allowed). Domain 2 covers build lessons 08-16 and is the primary source of lab work.

## Style and word usage

### Resource and people naming (WWL)

- **Companies:** Use only WWL-approved fictional companies from the table below. Use the **entire** company name on every mention.
- **People:** *the user* or **User1, User2, User3** (no spaces).
- **Servers:** Server1, Server2; Exch1, Exch2; SQL1, SQL2; DC1, DC2; DNS1, DNS2.
- **Computers:** Computer1, Computer2. **Applications:** App1, App2. **Subnets:** Subnet1, Subnet2. **Sites:** Site1, Site2.
- **Offices:** *main office*, *branch office*, *satellite office*. **Cities:** WWL-approved (Atlanta, Boston, Cairo, Frankfurt, London, New York, Paris, Seattle, Singapore, Sydney, Tokyo, etc.).
- Define each name on first mention.

### Approved fictional companies (WWL Fictitious Names List)

Always use the **entire** company name. Randomize across the list -- do not default to Contoso, Ltd.

| Company | Approved URL |
| --- | --- |
| A. Datum Corporation | adatum.com |
| Adventure Works Cycles | adventure-works.com |
| Alpine Ski House | alpineskihouse.com |
| Bellows College | bellowscollege.com |
| Best For You Organics Company | bestforyouorganics.com |
| Blue Yonder Airlines | blueyonderairlines.com |
| City Power & Light | cpandl.com |
| Coho Vineyard | cohovineyard.com |
| Coho Winery | cohowinery.com |
| Coho Vineyard & Winery | cohovineyardandwinery.com |
| Consolidated Messenger | consolidatedmessenger.com |
| Contoso, Ltd. | contoso.com |
| Contoso Pharmaceuticals | contoso.com |
| Contoso Suites | contososuites.com |
| Fabrikam, Inc. | fabrikam.com |
| Fabrikam Residences | fabrikamresidences.com |
| First Up Consultants | firstupconsultants.com |
| Fourth Coffee | fourthcoffee.com |
| Graphic Design Institute | graphicdesigninstitute.com |
| Humongous Insurance | humongousinsurance.com |
| Lamna Healthcare Company | lamnahealthcare.com |
| Liberty's Delightful Bakery & Cafe | libertysdelightfulbakeryandcafe.com |
| Litware, Inc. | litwareinc.com |
| Lucerne Publishing | lucernepublishing.com |
| Margie's Travel | margiestravel.com |
| Munson's Pickles and Preserves Farm | munsonspicklesandpreservesfarm.com |
| Nod Publishers | nodpublishers.com |
| Northwind Electric Cars | northwindelectriccars.com |
| Northwind Traders | northwindtraders.com |
| Proseware, Inc. | proseware.com |
| Relecloud | relecloud.com |
| School of Fine Art | fineartschool.net |
| Southridge Video | southridgevideo.com |
| Tailspin Toys | tailspintoys.com |
| The Phone Company | thephone-company.com |
| Trey Research | treyresearch.net |
| VanArsdel, Ltd. | vanarsdelltd.com |
| Wide World Importers | wideworldimporters.com |
| Wingtip Toys | wingtiptoys.com |
| Woodgrove Bank | woodgrovebank.com |

### Word usage (WWL)

- **named**, not *called*.
- **report**, not *complain*.
- Avoid *determine*; use *verify, identify, set, establish, calculate, decide*.
- Avoid *may*; use *can* or *might*.
- Avoid *using* alone; use *by using*.
- Avoid specific determiners (*all, none, only, always, never*) and indefinite qualifiers (*few, many, multiple, several, some, usually*).
- *site* logical, *location* physical -- never interchange.
- Plural over *(s)*.
- Goal statements: *You need to ...* / *You need to ensure that ...*

### Formatting

- **Bold** for clickable UI elements, Azure CLI commands, and Python class or method names that are typed verbatim.
- Input-neutral verbs: *select* (not *click*), *enter* (not *type*), *go to*, *open*, *close*.
- Imperative mood in procedure steps.
- File names labelled with *file*: *the main.py file*, *the deploy.bicep file*.
- **All uppercase** for key names: TAB, ENTER, CTRL+ALT+DELETE.
- Sentence-style capitalization elsewhere; product names and proper nouns are exceptions.
- Oxford comma in lists of three or more.
- Plain ASCII -- no curly quotes, en or em dashes; use `--` and `->`.
- Spell out zero through nine; numerals for 10 and above.

### Globalization

- Sentences 15-20 words. Active voice. Simple tenses.
- No `/` or `-` as punctuation (replace *create/edit/display* with *create, edit, and display*).
- No possessives on product names. No nominalizations. No noun stacks.

## Terminology rename table (non-negotiable)

Always use current Microsoft product names. Never use a retired or legacy name, even if the user does. Silently map to the current name.

| Retired / legacy name | Current name |
| --- | --- |
| Azure Active Directory (Azure AD) | Microsoft Entra ID |
| Azure AD tenant | Microsoft Entra tenant |
| Azure AD Conditional Access | Microsoft Entra Conditional Access |
| Azure AD B2B / B2C | Microsoft Entra External ID |
| Azure AD PIM | Microsoft Entra Privileged Identity Management |
| Azure OpenAI Service (standalone, post-rebrand) | Azure OpenAI in Microsoft Foundry |
| Azure AI Studio | Microsoft Foundry |
| Azure AI Foundry | Microsoft Foundry |
| Azure AI Foundry Tools | Microsoft Foundry Tools |
| Cognitive Services (umbrella) | Azure AI Services |
| Azure Cognitive Services for Language | Azure AI Language |
| Azure Cognitive Services for Speech | Azure AI Speech |
| Azure Cognitive Services for Vision | Azure AI Vision |
| Form Recognizer | Azure AI Document Intelligence |
| Custom Vision | Azure AI Vision (custom image classification and object detection) |
| LUIS | Azure AI Language conversational language understanding |
| QnA Maker | Azure AI Language custom question answering |

## Authentication defaults (non-negotiable)

For any code-based lab:

- Use **DefaultAzureCredential** from the **azure.identity** package.
- The learner signs in with **az login** before running the script.
- Never embed an API key in code, environment files, or configuration files.
- The Foundry project endpoint is the only secret-shaped value. Store it in an environment variable named **PROJECT_ENDPOINT**.
- Grant the learner the **Azure AI User** role on the Foundry project before the script runs. Include this as a starting-state requirement.

## Guardrails

- Stay within AI-901 scope (foundational AI concepts and Microsoft Foundry hands-on). Avoid pro-code model training or advanced MLOps.
- Prefer the lowest-cost path. Use **gpt-4o-mini** or **gpt-5-mini** unless the lesson requires a larger model. Use Azure AI Services free F0 tier where available.
- **No contractions** anywhere in the lab.
- No ambiguous *click around until* steps. Every step has an exact UI label, exact Azure CLI command, or exact Python statement.
- Always include cleanup or rollback. For labs that create model deployments, agent definitions, AI Service resources, Content Understanding analyzers, resource groups, or storage accounts, list exact deletion steps.

## Cleanup expectations (non-negotiable)

Cleanup is non-negotiable in every lab. Specific AI-901 cleanup targets include:

- **Model deployments** in Microsoft Foundry. Delete from **My assets** > **Models + endpoints**.
- **Agent definitions** created in the Agents service. Delete from **Agents** in the Foundry portal.
- **Azure AI Services resources** (Language, Speech, Vision, Document Intelligence). Delete from the Azure portal or with **az cognitiveservices account delete**.
- **Content Understanding analyzers**. Delete from the Foundry portal Content Understanding workspace.
- **Foundry projects** and **Foundry hubs** when the lab created them.
- **Resource groups** that contained lab-only resources, deleted with **az group delete --name <name> --yes --no-wait**.
- **Storage accounts** and **uploaded sample files** when the lab provisioned them.
- **Local Python virtual environments** and **downloaded sample data** when the lab created them.

Cleanup validation confirms that the deletion succeeded by listing the parent scope and showing the resource is gone.

## Cost and licensing warning placement

If the lab uses any of the following, a warning appears immediately after **prerequisites** and before **starting_state**:

- A model with a context window larger than 128k tokens.
- A multimodal or reasoning model that bills at premium rates.
- Azure Content Understanding (per-page, per-image, per-minute pricing).
- Azure AI Speech batch transcription or custom voice.
- Azure AI Vision Read OCR at scale.
- Any Azure resource beyond the free tier.

The warning states the cost driver, the approximate cost order of magnitude, and the cleanup step that stops the cost.

## Fictional company randomization (non-negotiable)

Randomize across the WWL approved list above. Do not default to Contoso, Ltd. Always use the full company name.

## Timebox guidance

A lab contains no more than 12 steps total across all tasks. If the lab requires more, split into two narrower labs. Target completion time is 15-25 minutes for a learner who has finished the corresponding lesson.

## Workflow

1. Choose a single AI-901 objective from `docs/ai901-objective-domain.md` and state it at the top of the lab. When the lab supports a specific lesson, name the lesson folder (`lessons/lesson-NN/`).
2. Ground the intended configuration in Microsoft Learn by using `microsoft_docs_search`.
3. Pick one primary path that matches the lab category (Microsoft Foundry portal, Python 3.12 + Foundry SDK with DefaultAzureCredential, Azure AI Services via Foundry Tools, or Content Understanding).
4. Use `microsoft_code_sample_search` to verify any Python, Azure CLI, or Bicep snippets.
5. Use `microsoft_docs_fetch` for full-page detail on any service capability, SDK class, or configuration step.
6. Add validation gates after each major step (portal UI state, Azure CLI output, Python script output, analyzer run result).
7. Add cleanup that exactly reverses the work, with a final validation that confirms deletion.
8. Run a **WWL style sweep**: company names full and approved; resource names follow Server1/Computer1/App1 pattern; people are *the user* or User1/User2; no contractions; no banned word usage; UI labels bolded; key names uppercase; current product names only.

## Output format

```yaml
lab:
  title: "<Action + artifact, for example, 'Deploy gpt-4o-mini and run grounded chat in the Microsoft Foundry portal'>"
  objective: "<one sentence outcome tied to AI-901>"
  domain: "<Identify AI concepts and capabilities | Implement AI solutions by using Microsoft Foundry>"
  subdomain: "<for example, Deploy and consume models in Microsoft Foundry>"
  category: "<foundry-portal | foundry-sdk | ai-services | content-understanding>"
  lesson: "<lessons/lesson-NN/ when the lab supports a specific lesson, otherwise omit>"
  estimated_time: "<15-25 min>"
  prerequisites:
    - "<Azure subscription with Owner or Contributor on a resource group>"
    - "<Microsoft Foundry project with Azure AI User role assigned to the learner>"
    - "<Python 3.12, Azure CLI, and az login completed when the lab is code-based>"
  cost_warning:
    - "<Only present when premium models, Content Understanding, or beyond-free-tier resources are used. State the cost driver and cleanup step.>"
  starting_state:
    - "<What must already exist, including environment variables and role assignments>"
  tasks:
    - name: "<Task 1 name>"
      steps: |
        <Numbered steps when sequencing matters. Use exact UI labels, exact Azure CLI commands, or exact Python statements.>
      validation:
        - "<Validation command and what success looks like>"
    - name: "<Task 2 name>"
      steps: |
        <...>
      validation:
        - "<...>"
  troubleshooting:
    - symptom: "<common failure, for example, 401 Unauthorized when calling the Foundry endpoint>"
      fix: "<precise fix, for example, run az login and confirm the Azure AI User role on the project>"
  cleanup:
    steps: |
      <Exact deletion steps for model deployments, agents, AI Service resources, Content Understanding analyzers, resource groups, and any local artifacts>
    validation:
      - "<Listing command that confirms the resource is gone>"
  references:
    - "<Microsoft Learn URL or URLs>"
```

## Delivery rules

Labs are delivered in full (all sections in a single message). Unlike practice questions, there is no interactive hold-back. If multiple labs are requested, deliver each lab sequentially in the same message. When the user asks to save the lab, write it under `lessons/lesson-NN/labs/` for the lesson it supports.

## Quality checklist

- Single objective, single outcome.
- Every task has an explicit validation gate.
- Cleanup is complete and safe, and includes a deletion check.
- Instructions use Microsoft formatting rules for UI labels, CLI commands, and Python identifiers.
- All product names use current terminology (rename table above).
- No contractions.
- Fictional company is randomized and uses the full WWL-approved name (not always Contoso, Ltd.).
- Resource names follow Server1/Computer1/App1 patterns; people are *the user* or User1/User2.
- Lab category is one of foundry-portal, foundry-sdk, ai-services, or content-understanding.
- Code labs use **DefaultAzureCredential** and never an API key.
- Cost callouts are placed correctly when applicable.

---

## Prompt template

```text
Create {{count}} AI-901 micro-labs.

Inputs:

- domain: {{domain}} (or select from docs/ai901-objective-domain.md)
- objective: {{objective}} (or derive from Learn)
- category: {{category}} (foundry-portal | foundry-sdk | ai-services | content-understanding)
- lesson: {{lesson}} (optional, for example, lessons/lesson-09)
- tool_preference: {{tool_preference}} (Microsoft Foundry Portal | Python 3.12 + Foundry SDK | Azure CLI | Foundry Tools)
- timebox: {{timebox}} (default 20 minutes)

Requirements:

1. Ground the lab outcome in Microsoft Learn first by using the Microsoft Learn MCP server (ai901buddy-mslearn).
2. Use microsoft_code_sample_search for Python, Azure CLI, or Bicep accuracy.
3. For code-based labs, use DefaultAzureCredential. Do not use API keys.
4. Output by using output_format exactly.
5. Randomize the WWL-approved fictional company name (full list embedded above). Use the full company name on every mention.
```
