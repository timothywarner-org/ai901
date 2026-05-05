---
name: ai901-plan
description: "Create a personalized AI-901 study plan from your confidence ratings."
argument-hint: "identify='Weak' implement='Moderate'"
agent: ai901-cert-buddy-agent
tools:
  - ai901buddy-mslearn/*
---

# AI-901 Plan

Generate a personalized AI-901 study plan, prioritized weakest first, with Microsoft Learn module links.

Use the **ai901-study-planner** skill for workflow, output format, and delivery rules (full plan in a single message).

## Inputs

- Identify confidence: ${input:identify:Strong | Moderate | Weak | Unknown}
- Implement confidence: ${input:implement:Strong | Moderate | Weak | Unknown}
- Optional exam date: ${input:examDate:YYYY-MM-DD (blank if none)}
- Optional weekly hours: ${input:weeklyHours:e.g., 5}

## Reminders

- Treat Unknown as Weak. Cover both domains.
- Within equal confidence levels, sort by weight (Implement 55-60% first).
- If exam date and weekly hours are both provided, include a feasibility check.
- Surface the AI-901 audience profile reminder (beginning of career, conceptual Azure AI knowledge, Python syntax).
- Do not invent Learn URLs.
