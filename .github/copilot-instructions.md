# Copilot instructions

## Repository purpose

- This repo is the companion material for Tim Warner's Microsoft Press video course **Microsoft Azure AI Fundamentals (AI-901)**. The cert-buddy agent and the course scaffolding (16 lessons, 30 minutes each, 8 hours total) share this workspace.
- The repo also defines GitHub Copilot agent behavior and AI-901 skills used during course recording and learner self-study.

## Key locations

- Agent definition: `.github/agents/ai901-cert-buddy-agent.agent.md`
- Skills: `.github/skills/*/SKILL.md`
- Prompts: `.github/prompts/ai901-quiz.prompt.md`, `.github/prompts/ai901-lab.prompt.md`, `.github/prompts/ai901-plan.prompt.md`
- MCP servers (workspace only): `.vscode/mcp.json`
- AI-901 objectives (canonical, verbatim Microsoft Learn sync): `docs/ai901-objective-domain.md`
- Course outline (locked deliverable spec, internal, not learner-facing): `docs/outline.pdf`
- Lesson plans: `lessons/lesson-NN/README.md`
- Style and naming rules: embedded directly in the agent and skill files (Microsoft Worldwide Learning Exam Writing Style Guide for items, Microsoft Writing Style Guide for prose).

## Skill and agent conventions

- Each skill file is a single YAML frontmatter block followed by Markdown.
- The skill name used by agents must match the YAML frontmatter name in the skill file, not the folder name.
- Skills are auto-discovered from `.github/skills/` folders. The agent references them by name in its Markdown body; there is no `skills:` field in agent YAML frontmatter.
- Agent files use YAML frontmatter with tools lists. Keep tool IDs scoped to MCP servers defined in `.vscode/mcp.json`.
- Prompt files (in `.github/prompts/`) reference agents by the `name` field in the agent's YAML frontmatter via the `agent:` key. The current value is `ai901-cert-buddy-agent`. If the agent is renamed, update all prompt files that reference it.
- Current skills:
  - `ai901-item-creator` (exam item generation)
  - `ai901-lab-creator` (Foundry, Azure AI services, and responsible-AI lab generation)
  - `ai901-study-planner` (personalized study plan generation)

## MCP server IDs

- `ai901buddy-mslearn` -- Microsoft Learn MCP (free, no API key; provides `microsoft_docs_search`, `microsoft_docs_fetch`, `microsoft_code_sample_search`)

### How users set up the MCP server

The Microsoft Learn MCP server requires no API keys, logins, or sign-ups. It is configured in `.vscode/mcp.json` as an HTTP server pointing to `https://learn.microsoft.com/api/mcp`. Users can also search for "@mcp learn" in the VS Code Extensions marketplace for one-click install.

## AI-901 exam facts (canonical)

- **Exam:** AI-901 -- Microsoft Azure AI Fundamentals
- **Skills measured date:** April 15, 2026
- **Pass score:** 700
- **Domain split:**
  - Domain 1: Identify AI concepts and capabilities (40-45%)
  - Domain 2: Implement AI solutions by using Microsoft Foundry (55-60%)
- **Audience profile:** beginning of career in AI solution development; conceptual knowledge of AI in Azure; Python coding syntax; familiar with Azure resources.

## Grounding and validation rules

- Questions must be grounded in Microsoft Learn content first. Use the Microsoft Learn MCP server to retrieve current Learn documentation and code samples.
- Foundry, Azure AI services, and responsible-AI labs must be grounded in Microsoft Learn for correct configuration and any CLI, PowerShell, Python, or Bicep syntax.
- If a request mixes questions and labs, split the output and apply the correct skill to each section.
- Grounding chain: Microsoft Learn MCP (`microsoft_docs_search` for discovery, `microsoft_docs_fetch` for full detail, `microsoft_code_sample_search` for code accuracy).

## Authentication default (non-negotiable)

The default authentication pattern for Foundry SDK and Azure SDK code is **keyless via Microsoft Entra ID** using `DefaultAzureCredential`. Do not use API keys in samples or labs unless an objective explicitly requires demonstrating key-based auth.

## Answer choice randomization (non-negotiable)

When generating practice questions, the correct answer MUST be randomized across A, B, C, and D. Never default to any single letter position.

## Fictional company randomization (non-negotiable)

Use only WWL-approved fictional company names (the full list with approved URLs is embedded in `.github/agents/ai901-cert-buddy-agent.agent.md` and in the `ai901-item-creator` and `ai901-lab-creator` skills). Always use the entire company name on every mention (write *Litware, Inc.*, not *Litware*). Randomize across the full list. Do not default to Contoso, Ltd. for every scenario.

## Terminology (non-negotiable)

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
| Azure AI Foundry | Microsoft Foundry (official rebrand) |
| Azure AI Foundry Tools | Microsoft Foundry Tools |
| Azure Cognitive Services | Azure AI services |
| Cognitive Services | Azure AI services |
| Azure Cognitive Search | Azure AI Search |
| Form Recognizer | Azure AI Document Intelligence |
| LUIS (Language Understanding) | Conversational language understanding in Azure AI Language |

If Microsoft Learn shows a different current name than what appears above, prefer the Learn name. Always check the [AI-901 study guide](https://learn.microsoft.com/credentials/certifications/resources/study-guides/ai-901) and active product pages first.

## Interactive question delivery

When the user asks for a practice question (one or more items):

1. Present **only** the metadata, scenario stem, and answer choices.
2. Do **NOT** include the correct answer, rationale, or references in the same message.
3. Wait for the user to reply with their answer.
4. After the user replies, reveal the correct answer, full rationale (2 sentences per choice), and references.

This rule applies to all question-generation skills and prompts in this workspace.

## Authoring guidance

- Keep instructions and outputs in plain ASCII (avoid curly quotes and en dashes). Use `--` instead.
- Follow the **Microsoft Worldwide Learning Exam Writing Style Guide** (WWL) for exam items: scenario-first stems beginning with *What* or *Which* + **should**; no banned auxiliaries (*can, must, might, do, would, may*) in the question sentence; no contractions; no negatives unless **CAP**+**bold**; no specific determiners (*all, none, only, always, never*); no indefinite qualifiers (*few, many, multiple, several, some, usually*); parallel and mutually exclusive choices.
- Follow the **Microsoft Writing Style Guide** (MWSG) for lab prose, study plans, and other prose where WWL is silent.
- Where the two guides conflict in exam items, WWL wins. Two MWSG conventions overridden by WWL: no contractions; key names in all uppercase (TAB, ENTER, CTRL+ALT+DELETE).
- Full WWL rule sets, approved fictional company list, approved city list, and resource-naming patterns (Server1, Computer1, App1, Subnet1, Site1, *the user*, User1/User2) live inside `.github/agents/ai901-cert-buddy-agent.agent.md` and the per-skill `SKILL.md` files. Read those for authoritative guidance.
