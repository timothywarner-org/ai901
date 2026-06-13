# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository purpose

This is Tim Warner's source repo for the **Microsoft Press video course** *Exam AI-901: Microsoft Azure AI
Fundamentals* -- 16 recorded lessons, 30 minutes each, 8 hours total runtime. The course is a recorded video
product, not a live training, and not a standalone Cert Buddy product.

The repo also hosts a workspace-scoped **AI-901 Cert Buddy** GitHub Copilot agent under `.github/`. The Cert
Buddy is a *companion* to the video course -- it runs inside VS Code via Copilot Chat and lets the same
learners drill exam items, generate hands-on Microsoft Foundry labs, and build personalized study plans
between lessons. The Cert Buddy is not the deliverable; the videos are.

The authoritative course outline is [`docs/outline.pdf`](docs/outline.pdf) -- 16 lesson titles with their AI-901 exam
objective mappings. Treat the outline as the locked Microsoft Press deliverable spec; do not invent new
lessons or restructure the 16-lesson plan without explicit instruction.

## Two distinct work areas

The repo serves two different audiences. Keep changes scoped to the right area; do not bleed Cert Buddy
agent rules into lesson READMEs or vice versa.

| Area | Lives in | Audience | Deliverable |
| --- | --- | --- | --- |
| Recorded video course | `lessons/`, `docs/` (incl. internal `outline.pdf`), `images/`, `README.md` | Learners watching the 16 videos | Microsoft Press video product |
| AI-901 Cert Buddy agent | `.github/agents/`, `.github/skills/`, `.github/prompts/`, `.github/copilot-instructions.md`, `.vscode/mcp.json`, `.vscode/extensions.json` | Same learners using Copilot Chat between videos | Workspace-scoped Copilot agent |

CI lives in `.github/workflows/` and applies to both areas.

## Course structure

Per [`docs/outline.pdf`](docs/outline.pdf):

| Lessons | Theme | AI-901 domain |
| --- | --- | --- |
| 01 -- 07 | AI workloads, Responsible AI, text/speech/vision/extraction concepts | Domain 1 -- Identify AI concepts and capabilities (40 -- 45%) |
| 08 -- 16 | Foundry portal, prompts, SDK, agents, text/speech/vision/extraction apps | Domain 2 -- Implement AI solutions by using Microsoft Foundry (55 -- 60%) |

Lessons 01 -- 03 are pure **concept** lessons -- portal walkthroughs with no shipping code. Lessons 04 -- 07
are concept lessons that also ship a small **SDK bookend** sample and a one-command deploy script under
`lessons/lesson-NN/demo/`, so a learner can reproduce the portal walkthrough in code (lesson 04 ships only the
Responsible AI provisioning script). Lessons 08 -- 16 are **build** lessons -- each has a runnable Python
sample under `lessons/lesson-NN/demo/`. Keep the spirit: do not add gratuitous code to a concept lesson, and
do not strip the headline build from a build lesson.

Per-lesson learning objectives are lifted verbatim from `docs/outline.pdf`. The exam objective IDs and weights
are mirrored from `docs/ai901-objective-domain.md`.

## Layout

```text
ai901/
├── README.md                                    # Public-facing course overview
├── CLAUDE.md                                    # This file
├── LICENSE                                      # MIT
├── .markdownlint.json                           # Markdown lint config (line length 120, 2-space lists)
├── .gitignore                                   # Python-flavored
├── images/cover.png                             # Course cover, 800x450, 58 KB
│
├── lessons/                                     # 16 lesson folders
│   ├── README.md                                # Lessons index + domain map
│   └── lesson-NN/                               # lesson-01 through lesson-16
│       ├── README.md                            # Five-section lesson contract (see below)
│       ├── demo/                                # Runnable scripts, requirements.txt, .env.example, deploy script, optional webapp/ and samples/
│       └── assets/                              # Slides, screenshots, sample inputs
│
├── docs/
│   ├── ai901-objective-domain.md                # Verbatim local mirror of AI-901 skills measured
│   └── outline.pdf                              # Locked Microsoft Press 16-lesson deliverable spec (internal)
│
├── .github/
│   ├── copilot-instructions.md                  # Cert Buddy agent-wide rules + retired-terminology table
│   ├── agents/
│   │   └── ai901-cert-buddy-agent.agent.md      # Cert Buddy orchestrator
│   ├── skills/
│   │   ├── ai901-item-creator/SKILL.md          # Exam-realistic practice questions (WWL style)
│   │   ├── ai901-lab-creator/SKILL.md           # 15 -- 25 min hands-on labs, four categories
│   │   └── ai901-study-planner/SKILL.md         # Confidence-based personalized study plans
│   ├── prompts/
│   │   ├── ai901-quiz.prompt.md                 # /ai901-quiz slash command
│   │   ├── ai901-lab.prompt.md                  # /ai901-lab slash command
│   │   └── ai901-plan.prompt.md                 # /ai901-plan slash command
│   └── workflows/
│       ├── validate.yml                         # Non-blocking content checks on PRs to main
│       └── mlc-config.json                      # Markdown link check config
│
└── .vscode/
    ├── mcp.json                                 # Declares ai901buddy-mslearn MCP server (HTTP)
    └── extensions.json                          # Recommended extensions
```

### Lesson folder contract

Every `lessons/lesson-NN/README.md` has the same five sections in this order:

1. **Title line** -- `# Lesson N: <title>` matching the outline verbatim.
2. **Runtime + exam objectives** -- one bold line: `**Runtime:** 30 min | **Exam objectives:** X.Y.Z`.
3. **Learning objectives** -- bullet list lifted verbatim from `docs/outline.pdf`. Do not paraphrase; the
   outline is the deliverable spec.
4. **Demo** -- one short paragraph describing what the lesson demonstrates. Concept lessons 01 -- 03 describe
   a portal tour; lessons 04 -- 16 also point to `demo/` for runnable code (a provisioning script for 04, an
   SDK bookend for 05 -- 07, a full build for 08 -- 16).
5. **Resources** -- bullets to Microsoft Learn primary sources.

Keep these five headings stable across all 16 lessons so a learner can scan any folder identically. When a
lab is generated for a specific lesson, save it under `lessons/lesson-NN/labs/` so it sits next to the
lesson plan.

## AI-901 Cert Buddy architecture

The Cert Buddy is a workspace-scoped GitHub Copilot agent. Components and their wiring:

| Piece | File | Role |
| --- | --- | --- |
| Orchestrator agent | `.github/agents/ai901-cert-buddy-agent.agent.md` | Routes requests, enforces grounding, applies WWL/MWSG style precedence |
| Item-creator skill | `.github/skills/ai901-item-creator/SKILL.md` | Exam-realistic practice questions, two-phase delivery, Microsoft WWL Exam Writing Style Guide |
| Lab-creator skill | `.github/skills/ai901-lab-creator/SKILL.md` | 15 -- 25 min hands-on labs with prerequisites, validation, and mandatory cleanup |
| Study-planner skill | `.github/skills/ai901-study-planner/SKILL.md` | Confidence-based personalized study plans |
| Quiz prompt | `.github/prompts/ai901-quiz.prompt.md` | `/ai901-quiz` slash command |
| Lab prompt | `.github/prompts/ai901-lab.prompt.md` | `/ai901-lab` slash command |
| Plan prompt | `.github/prompts/ai901-plan.prompt.md` | `/ai901-plan` slash command |
| Workspace rules | `.github/copilot-instructions.md` | Repo-wide Copilot rules, retired-terminology rename table |
| MCP server | `.vscode/mcp.json` | Declares `ai901buddy-mslearn` HTTP server pointing at `https://learn.microsoft.com/api/mcp` |

### Documented Copilot gotcha

Skills are auto-discovered from `.github/skills/*/SKILL.md` based on YAML frontmatter `name:` and
`description:`. **Do not add a `skills:` field to the agent frontmatter** -- Copilot ignores it, and adding
one creates the false impression that wiring is explicit when it is not. The agent body references skills
by name in prose; Copilot resolves the reference via auto-discovery.

### Cross-component dependencies

When you change one of these, audit the others in the same change:

- **Agent name** (frontmatter `name:` of `ai901-cert-buddy-agent.agent.md`) -- referenced by every prompt
  file via the `agent:` key. Renaming the agent breaks all three prompts.
- **Skill name** (frontmatter `name:` of each `SKILL.md`) -- referenced in the agent body. Renaming a skill
  breaks the agent's routing prose.
- **MCP server id** (`ai901buddy-mslearn` in `.vscode/mcp.json`) -- referenced in the agent's `tools` list
  and in skill grounding rules. Renaming the server breaks tool resolution.
- **Lab category enum** (`foundry-portal`, `foundry-sdk`, `ai-services`, `content-understanding`) -- the
  `category` input in `ai901-lab.prompt.md` must stay in sync with the categories defined in
  `ai901-lab-creator/SKILL.md`. They drift easily; keep them locked.

## Authoring conventions

These rules apply to every Markdown file in the repo, including lesson READMEs, skills, prompts, and the
agent.

- **Microsoft product names** -- exact casing, current names only. The full retired-name rename table lives
  in `.github/copilot-instructions.md`. The most common mappings:
  - *Microsoft Foundry* (not *Azure AI Foundry*, not *Azure AI Studio*)
  - *Microsoft Foundry Tools* (not *Azure AI Foundry Tools*)
  - *Microsoft Entra ID* (not *Azure Active Directory*, not *Azure AD*)
  - *Azure AI services* (not *Azure Cognitive Services*, not *Cognitive Services*)
  - *Azure AI Search* (not *Azure Cognitive Search*)
  - *Azure AI Document Intelligence* (not *Form Recognizer*)
  - *Azure AI Language conversational language understanding* (not *LUIS*)
- **Plain ASCII only** -- no curly quotes, no en/em dashes. Use `--` for em dashes and `->` for arrows.
- **No contractions** in instructional content -- write *do not*, not *don't*; *cannot*, not *can't*. WWL
  rule; overrides MWSG for this repo.
- **Exam objective primacy** -- when course content conflicts with the published AI-901 skills measured,
  the skills measured win. Re-sync `docs/ai901-objective-domain.md` rather than fix the lesson around stale
  objectives.
- **Markdown lint** -- `.markdownlint.json` enforces line length 120, 2-space list indent, siblings-only
  MD024. Validate with `npx markdownlint-cli2 "**/*.md"`.
- **Filenames** -- lessons are `lesson-NN/` with zero-padded two-digit numbers (`lesson-01` through
  `lesson-16`). Do not renumber; do not drop the padding.

## Build-lesson code conventions

Lessons 05 -- 16 ship runnable samples -- lessons 05 -- 07 add a small SDK bookend to the concept
walkthrough, and lessons 08 -- 16 are full builds (lesson 04 ships only a Responsible AI provisioning
script). Keep them classroom-friendly:

- **Python 3.12** for client samples unless a lesson explicitly needs another language.
- **Auth** -- lessons 10 -- 16 use keyless `DefaultAzureCredential` (Microsoft Entra) wherever the objective
  allows; the early concept bookends (lessons 05 -- 09) read a key from `.env` for Fundamentals simplicity.
  Never check in API keys or `.env`; ship `.env.example` only.
- **Per-lesson `requirements.txt`** -- pin only what the lesson actually imports under
  `lessons/lesson-NN/demo/`. Do not introduce a monorepo lockfile or shared virtualenv across lessons.
- **One concept per demo** -- a lesson demo illustrates exactly the learning objective it maps to. Resist
  adding "while we are here" features; they dilute the lesson and the matching exam objective.
- **Cleanup mandatory** -- if a demo provisions Azure resources, include teardown steps in the lesson
  README. The course assumes a learner has a single Foundry project they reuse across all build lessons,
  not 16 disposable subscriptions.

## Common operations

```powershell
# Validate Markdown across the whole repo (matches what CI runs locally)
npx markdownlint-cli2 "**/*.md"

# Self-check for non-ASCII punctuation before committing (CI also runs this)
rg -n "[‘’“”–—]" .

# Self-check for contractions in instructional content
rg -ni "\b(don't|doesn't|won't|can't|it's|that's|we're|you're|I'm|I've|I'll)\b" .
```

When a build-lesson demo lands in `lessons/lesson-NN/demo/`, run it from inside that folder with its own
venv:

```powershell
cd lessons/lesson-NN/demo
python -m venv .venv
.venv\Scripts\Activate.ps1
pip install -r requirements.txt
az login
python main.py
```

### Smoke-testing the Cert Buddy

To confirm the Copilot agent wiring is intact:

1. Open the repo root in VS Code with the GitHub Copilot Chat extension loaded.
2. Confirm `.vscode/mcp.json` is recognized; the `ai901buddy-mslearn` server should appear in Copilot
   Chat's MCP server list.
3. In Copilot Chat, invoke the agent directly with `@ai901-cert-buddy-agent` followed by a request, or use
   one of the slash commands: `/ai901-quiz`, `/ai901-lab`, `/ai901-plan`.
4. The agent should ground its response via `microsoft_docs_search` / `microsoft_docs_fetch` /
   `microsoft_code_sample_search` from the `ai901buddy-mslearn` server and surface Microsoft Learn URLs in
   references.

## CI validation (`.github/workflows/validate.yml`)

PRs to `main` that touch any `**.md` or `.github/**` file run four checks. Every check is **non-blocking**
(`continue-on-error: true`) -- they post warnings, not failures.

| Check | What it grep-greps for | Exempt files |
| --- | --- | --- |
| Retired / legacy terminology | *Azure AD*, *Azure Active Directory*, *Azure AI Studio*, *Azure Cognitive Services*, *Form Recognizer*, *LUIS*, etc. | `copilot-instructions.md` (defines the rename table), `CLAUDE.md` (references the table), `CONTRIBUTING.md` |
| Non-ASCII characters | Curly quotes, en dashes, em dashes (Unicode 2018, 2019, 201C, 201D, 2013, 2014) | None |
| Contractions | *don't*, *can't*, *won't*, *it's*, *we're*, etc. | `CONTRIBUTING.md` |
| Markdown link check | Broken links in Markdown files | Configured via `mlc-config.json` |

Before pushing, run the same checks locally with the `rg` commands in the section above to avoid CI noise.

## Grounding via MS Learn MCP

The `ai901buddy-mslearn` server in `.vscode/mcp.json` is the canonical grounding tool. It is a free,
no-API-key HTTP MCP server pointing at `https://learn.microsoft.com/api/mcp`. Use it before editing any
lesson README, exam-objective doc, demo narrative, skill, or prompt:

| Tool | When to use |
| --- | --- |
| `microsoft_docs_search` | First pass; up to 10 chunks for breadth and discovery. |
| `microsoft_docs_fetch` | Full-page content when a lesson needs precise wording or a complete code sample. |
| `microsoft_code_sample_search` | SDK accuracy for the build lessons (08 -- 16). |

Never invent a Microsoft Learn URL. If a URL cannot be verified through the MCP server, omit it.

## Source-of-truth hierarchy

When facts conflict across files, resolve in this order:

1. **Live AI-901 study guide on Microsoft Learn**:
   `https://learn.microsoft.com/credentials/certifications/resources/study-guides/ai-901`. Re-fetch via the
   MCP server when in doubt.
2. **`docs/ai901-objective-domain.md`** -- verbatim local mirror of the study guide. When re-syncing,
   update both the *skills measured as of* date and the *local mirror revision date* in the same PR, and
   note any wording deltas in that file's change log.
3. **`docs/outline.pdf`** -- locked Microsoft Press deliverable spec (16 lessons, titles, exam objective
   mappings). Internal reference, not learner-facing. Do not edit; treat as immutable for the duration of
   course recording.
4. **`lessons/lesson-NN/README.md`** -- per-lesson learning objectives and demo plan, lifted verbatim from
   the outline.

If the upstream study guide changes, propagate the delta through items 2 -> 4 in the same change set. Do
not let a lesson README drift from the outline.

## What NOT to do

Repo-specific gotchas earned the hard way:

- **Do not add a `skills:` field to the agent frontmatter.** Copilot does not read it; skills are
  auto-discovered from `.github/skills/*/SKILL.md` via frontmatter `name:` and `description:`. Adding the
  field invites future drift.
- **Do not break the lab prompt's `category` enum out of sync with the lab-creator skill.** The four
  values (`foundry-portal`, `foundry-sdk`, `ai-services`, `content-understanding`) are the contract
  between `.github/prompts/ai901-lab.prompt.md` and `.github/skills/ai901-lab-creator/SKILL.md`.
- **Do not let lesson READMEs drift from `docs/outline.pdf`.** The outline is the locked Microsoft Press
  deliverable; the lesson READMEs mirror it.
- **Do not push AB-100 content into AI-901.** The Cert Buddy was retargeted from AB-100, and every AB-100
  reference inside `.github/` and `.vscode/` was scrubbed. Do not reintroduce AB-100 names, prompts, or
  workflows here.
- **Do not delete or modify the AB-100 source repo at `C:\github\ab100`.** It is a separate live training
  repo. Changes to AI-901 must not touch it.
