---
name: ai901-lab
description: "Build one short AI-901 lab with validation and cleanup."
argument-hint: "domain='implement' category='foundry-sdk' toolPreference='Foundry SDK for Python' timebox='20'"
agent: ai901-cert-buddy-agent
tools:
  - ai901buddy-mslearn/*
---

# AI-901 Lab

Generate **ONE** short AI-901 lab (15-25 minutes), self-validating, with cleanup.

Use the **ai901-lab-creator** skill for structure, WWL style, output format, and delivery rules (full lab in a single message).

## Inputs

- Domain: ${input:domain:Identify | Implement (blank = agent picks)}
- Objective: ${input:objective:specific objective (optional)}
- Category: ${input:category:foundry-portal | foundry-sdk | ai-services | content-understanding}
- Tool: ${input:toolPreference:Microsoft Foundry portal | Foundry SDK for Python | Azure CLI | Azure portal}
- Timebox: ${input:timebox:minutes (default 20)}

## Reminders

- Default tools when blank: Microsoft Foundry portal for visual workflows, Foundry SDK for Python for code labs, Azure CLI for resource provisioning.
- Default authentication: DefaultAzureCredential (keyless, Microsoft Entra). No API keys unless objective requires.
- Randomize the WWL-approved fictional company; use the full name on every mention.
- Cleanup is mandatory.
