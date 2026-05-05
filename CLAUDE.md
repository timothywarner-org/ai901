# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository purpose

This is Tim Warner's source repo for the **Microsoft Press video course** *Exam AI-901: Microsoft Azure AI Fundamentals* -- 16 recorded lessons, 30 minutes each, 8 hours total runtime. The repo is structured for a **recorded video product**, not a live training, and not a Cert Buddy.

The authoritative course outline is [`outline.pdf`](outline.pdf) -- 16 lesson titles with their AI-901 exam objective mappings. Treat the outline as the locked deliverable spec; do not invent new lessons or restructure the 16-lesson plan without explicit instruction.

The repository personality (governance, style, MS Learn grounding, exam-objective primacy) is borrowed from Tim's AB-100 teaching repo. The lesson-by-lesson scaffold under [`lessons/`](lessons/) is what makes this repo a video course rather than a live training.

## Course structure

Per [`outline.pdf`](outline.pdf):

| Lessons | Theme | AI-901 domain |
| --- | --- | --- |
| 01 -- 07 | AI workloads, Responsible AI, text/speech/vision/extraction concepts | Domain 1 -- AI and Responsible AI concepts |
| 08 -- 16 | Foundry portal, prompts, SDK, agents, text/speech/vision/extraction apps | Domain 2 -- Build solutions on Microsoft Foundry |

Lessons 01 -- 07 are **concept** lessons -- portal walkthroughs, no shipping code. Lessons 08 -- 16 are **build** lessons -- each has a runnable Python sample under `lessons/lesson-NN/demo/`. Do not blur the line: do not add code demos to concept lessons or strip them from build lessons.

The exam objective mapping in each lesson README is canonical. Re-sync from the outline if Microsoft updates the AI-901 study guide.

## Layout

```text
ai901/
├── outline.pdf                  # Authoritative 16-lesson outline (do not edit)
├── README.md                    # Public-facing course overview
├── CLAUDE.md                    # This file
├── LICENSE                      # MIT
├── .markdownlint.json           # Markdown lint config (line length 120, 2-space lists)
├── .gitignore                   # Python-flavored
├── images/cover.png             # Course cover image
│
├── lessons/                     # 16 lesson folders (the heart of the repo)
│   ├── README.md                # Lessons index + domain map
│   └── lesson-NN/
│       ├── README.md            # Title, runtime, exam objectives, learning objectives, demo, resources
│       ├── demo/                # Code shown on camera (concept lessons: walkthrough notes only)
│       └── assets/              # Slides, screenshots, sample inputs
│
├── docs/                        # Cross-lesson reference: exam objectives sync, study resources, slide deck
├── src/                         # Cross-lesson shared code (only if multiple lessons reuse the same module)
├── scripts/                     # Repo-level helpers (deck build, validation, lesson scaffolding)
├── tests/                       # Cross-lesson tests (most testing happens inside lesson demos)
└── .github/, .vscode/           # CI, MS Learn MCP config (added when needed)
```

### Lesson folder contract

Every `lessons/lesson-NN/README.md` has the same five sections in this order:

1. **Title line** -- `# Lesson N: <title>` matching the outline verbatim.
2. **Runtime + exam objectives** -- one bold line: `**Runtime:** 30 min | **Exam objectives:** X.Y.Z`.
3. **Learning objectives** -- bullet list lifted verbatim from `outline.pdf`. Do not paraphrase; the outline is the deliverable spec.
4. **Demo** -- one short paragraph describing what is shown on camera. Concept lessons (01 -- 07) describe a portal tour; build lessons (08 -- 16) point to `demo/` for runnable code.
5. **Resources** -- bullets to Microsoft Learn primary sources plus a back-link to `outline.pdf`.

Keep these five headings stable across all 16 lessons so a learner can scan any folder identically.

## Authoring conventions

These come straight from Tim's AB-100 repo and apply here too:

- **Microsoft product names** -- exact casing: *Microsoft Foundry*, *Microsoft Foundry Tools*, *Microsoft Copilot Studio*, *Microsoft Entra ID*, *Azure AI Language*, *Azure AI Speech*, *Azure AI Vision*, *Azure Content Understanding*. **Microsoft Foundry** is the current name -- not "Azure AI Foundry," not "Azure AI Studio."
- **Plain ASCII only** -- no curly quotes, no en/em dashes. Use `--` for em dashes and `->` for arrows.
- **No contractions** -- write "do not", not "don't"; "cannot", not "can't".
- **Exam objective primacy** -- when course content conflicts with the published AI-901 skills measured, the skills measured win. Re-sync the outline rather than fix the lesson around stale objectives.
- **Markdown lint** -- `.markdownlint.json` enforces line length 120, 2-space list indent, siblings-only MD024. Validate with `npx markdownlint-cli2 "**/*.md"`.
- **Filenames** -- lessons are `lesson-NN/` with zero-padded two-digit numbers (`lesson-01` through `lesson-16`). Do not renumber; do not drop the padding.

## Build-lesson code conventions

Lessons 08 -- 16 ship working samples. Keep them classroom-friendly:

- **Python only** for client samples unless a lesson explicitly needs another language. Target Python 3.12.
- **Keyless auth** -- use `DefaultAzureCredential` from `azure.identity` and Microsoft Foundry Entra-based auth. Never check in API keys; use `.env.example` for documented settings, never `.env`.
- **Minimal dependencies** -- pin only what the lesson actually imports in a per-lesson `requirements.txt` under `lessons/lesson-NN/demo/`. Do not introduce a monorepo lockfile or shared virtualenv across lessons.
- **One concept per demo** -- a lesson demo should illustrate exactly the learning objective it maps to. Resist adding "while we are here" features; they hurt on-camera pacing.
- **Cleanup** -- if a demo provisions Azure resources, include teardown steps in the lesson README. The course assumes a learner has a single Foundry project they reuse, not 16 disposable subscriptions.

## Common operations

This repo has no build pipeline yet, no test suite, and no deploy stack -- it is a content scaffold. The commands below are the ones that matter today:

```powershell
# Validate Markdown across the whole repo
npx markdownlint-cli2 "**/*.md"

# Self-check for non-ASCII punctuation before committing
rg -n "[‘’“”–—]" .

# Self-check for contractions (excluding contributing.md if added later)
rg -ni "\b(don't|doesn't|won't|can't|it's|that's|we're|you're|I'm|I've|I'll)\b" .
```

When a lesson demo lands in `lessons/lesson-NN/demo/`, run it from inside that folder with its own venv:

```powershell
cd lessons/lesson-NN/demo
python -m venv .venv
.venv\Scripts\Activate.ps1
pip install -r requirements.txt
python main.py
```

## Grounding via MS Learn MCP

This repo's `.vscode/mcp.json` (when added) wires the free Microsoft Learn MCP server (`https://learn.microsoft.com/api/mcp`). Use it to ground AI-901 facts before editing any lesson README, exam-objective doc, or demo narrative:

1. `microsoft_docs_search` for breadth.
2. `microsoft_docs_fetch` for the full page when a lesson needs precise wording.
3. `microsoft_code_sample_search` for SDK accuracy in lessons 10 -- 16.

Never invent a Microsoft Learn URL. If a URL cannot be verified, omit it.

## Source-of-truth hierarchy

When facts conflict across files:

1. `outline.pdf` -- the locked Microsoft Press deliverable spec (16 lessons, titles, exam objective mappings).
2. The current published AI-901 skills measured on Microsoft Learn (re-fetch via MCP when in doubt).
3. `lessons/lesson-NN/README.md` -- per-lesson learning objectives and demo plan.
4. Any future `docs/ai901-exam-objectives.md` -- treat as a verbatim local mirror that must match Microsoft Learn.

Do not let a lesson README drift from the outline. If the outline changes, propagate to every affected lesson in the same change.
