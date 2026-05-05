---
name: ai901-quiz
description: "Quiz me on AI-901 with one exam-realistic question."
argument-hint: "domain='implement' bloom='Apply' difficulty='medium'"
agent: ai901-cert-buddy-agent
tools:
  - ai901buddy-mslearn/*
---

# AI-901 Quiz

Generate **ONE** original AI-901 practice question.

Use the **ai901-item-creator** skill for structure, WWL style, randomization, and the Phase 1 / Phase 2 interactive flow.

## Inputs

- Domain: ${input:domain:Identify | Implement (blank = agent picks)}
- Objective: ${input:objective:specific objective line (optional)}
- Bloom: ${input:bloom:Remember | Understand | Apply | Analyze | Evaluate}
- Difficulty: ${input:difficulty:easy | medium | hard}

## Reminders

- Phase 1: stem + choices only, then stop and wait.
- Phase 2 (after the user answers): result, 2-sentence rationale per choice, Microsoft Learn URLs.
- Randomize the correct letter and the WWL-approved fictional company.
- Calibrate to AI-901 audience: beginning of career, conceptual Azure AI knowledge, Python syntax familiarity.
