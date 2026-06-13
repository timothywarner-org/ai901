# AI-901 Objective Domain

Verbatim local mirror of the Microsoft Learn study guide for **Exam AI-901: Microsoft Azure AI Fundamentals**. This file is the canonical exam-objective reference for this repo. When the lesson plan or any course content conflicts with this file, this file wins -- or re-sync it from Microsoft Learn and update affected lessons in the same change.

## Currency

| Field | Value |
| --- | --- |
| Source URL | [https://learn.microsoft.com/credentials/certifications/resources/study-guides/ai-901](https://learn.microsoft.com/credentials/certifications/resources/study-guides/ai-901) |
| Microsoft "skills measured as of" date | **April 15, 2026** |
| Local mirror revision date (last MCP sync) | **2026-06-13** |
| Synced by | Tim Warner via Microsoft Learn MCP server (`microsoft_docs_fetch`) |

If Microsoft updates the upstream study guide, re-fetch the page and update the **skills measured as of** date and the **local mirror revision date** above in the same PR. Note any wording deltas in the [Change log](#change-log) at the bottom.

## Purpose of the exam

The exam validates that the candidate can:

- Identify AI concepts and capabilities, including responsible AI principles, generative model components and configuration, and common AI workloads.
- Implement AI solutions by using Microsoft Foundry, including generative apps and agents, text and speech apps, computer vision and image-generation apps, and information extraction with Azure Content Understanding.

A score of **700 or greater** is required to pass. Most questions cover features that are general availability (GA). The exam may contain questions on Preview features if those features are commonly used.

## Audience profile

As a candidate for this Microsoft Certification, you are at the beginning of your career in AI solution development.

For this exam, you should have:

- Conceptual knowledge of AI solutions in Azure and the foundational technical skills to work with them.
- Knowledge of Python coding syntax and programming techniques.
- Familiarity with Azure resources.

## Skills at a glance

| # | Functional group | Weight |
| --- | --- | --- |
| 1 | Identify AI concepts and capabilities | **40 -- 45%** |
| 2 | Implement AI solutions by using Microsoft Foundry | **55 -- 60%** |

The published "skills at a glance" list uses the wording *Identify AI concepts and responsibilities* for group 1, while the detailed heading immediately below it on the same Microsoft page reads *Identify AI concepts and capabilities*. This file uses the detailed heading verbatim.

## Domain 1 -- Identify AI concepts and capabilities (40 -- 45%)

### 1.1 Describe principles of responsible AI

- 1.1.1 Describe considerations for fairness in an AI solution
- 1.1.2 Describe considerations for reliability and safety in an AI solution
- 1.1.3 Describe considerations for privacy and security in an AI solution
- 1.1.4 Describe considerations for inclusiveness in an AI solution
- 1.1.5 Describe considerations for transparency in an AI solution
- 1.1.6 Describe considerations for accountability in an AI solution

### 1.2 Identify AI model components and configurations

- 1.2.1 Describe how generative AI models work
- 1.2.2 Identify an appropriate AI model, based on capabilities
- 1.2.3 Identify appropriate model deployment options and configuration parameters

### 1.3 Identify AI workloads

- 1.3.1 Identify scenarios for common AI workloads, including generative and agentic AI, text analysis, speech, computer vision, and information extraction
- 1.3.2 Describe common text analysis techniques, including keyword extraction, entity detection, sentiment analysis, and summarization
- 1.3.3 Identify features and capabilities of speech recognition and speech synthesis
- 1.3.4 Identify features and capabilities of computer vision and image-generation models
- 1.3.5 Identify techniques to extract information from text, images, audio, and videos

## Domain 2 -- Implement AI solutions by using Microsoft Foundry (55 -- 60%)

### 2.1 Implement generative AI apps and agents by using Foundry

- 2.1.1 Create effective system and user prompts for generative AI models
- 2.1.2 Deploy a model and interact with it in the Foundry portal
- 2.1.3 Create a lightweight chat client application by using the Foundry SDK
- 2.1.4 Create and test a single-agent solution in the Foundry portal
- 2.1.5 Create a lightweight client application for an agent

### 2.2 Implement AI solutions for text and speech by using Foundry

- 2.2.1 Build a lightweight application that includes text analysis
- 2.2.2 Respond to spoken prompts by using a deployed multimodal model
- 2.2.3 Build a lightweight application by using Azure Speech in Foundry Tools

### 2.3 Implement AI solutions with computer vision and image-generation capabilities by using Foundry

- 2.3.1 Interpret visual input in prompts by using a deployed multimodal model
- 2.3.2 Create new visual outputs by using generative models
- 2.3.3 Build a lightweight application that includes vision capabilities

### 2.4 Implement AI solutions for information extraction by using Foundry

- 2.4.1 Extract information from documents and forms by using Azure Content Understanding in Foundry Tools
- 2.4.2 Extract information from images by using Content Understanding
- 2.4.3 Extract information from audio and video by using Content Understanding
- 2.4.4 Build a lightweight application with information extraction capabilities by using Content Understanding

## Course mapping

The 16-lesson Microsoft Press video course in this repo maps to the objective domain as follows. The objective IDs use the local 1.1.1 / 2.1.1 numbering above.

| Lesson | Lesson title | Objective(s) | Domain |
| --- | --- | --- | --- |
| 01 | Identify AI Workloads and Common Scenarios | 1.3.1 | 1 |
| 02 | How Generative AI Models Work and How to Choose Them | 1.2.1 -- 1.2.3 | 1 |
| 03 | Responsible AI: Fairness, Reliability and Safety, Privacy and Security | 1.1.1 -- 1.1.3 | 1 |
| 04 | Responsible AI: Inclusiveness, Transparency, Accountability | 1.1.4 -- 1.1.6 | 1 |
| 05 | Text Analysis and Speech Concepts | 1.3.2, 1.3.3 | 1 |
| 06 | Computer Vision and Image-Generation Concepts | 1.3.4 | 1 |
| 07 | Information Extraction Concepts | 1.3.5 | 1 |
| 08 | Tour Microsoft Foundry and Deploy Your First Model | 2.1.2 | 2 |
| 09 | Craft Effective System and User Prompts | 2.1.1 | 2 |
| 10 | Build a Lightweight Chat Client Application with the Foundry SDK | 2.1.3 | 2 |
| 11 | Create and Test a Single-Agent Solution in the Foundry Portal | 2.1.4 | 2 |
| 12 | Build a Lightweight Client Application for an Agent | 2.1.5 | 2 |
| 13 | Build a Text Analysis Application with Foundry | 2.2.1 | 2 |
| 14 | Build a Speech-Enabled Application with Azure Speech in Foundry Tools | 2.2.2, 2.2.3 | 2 |
| 15 | Build a Computer Vision and Image-Generation Application | 2.3.1 -- 2.3.3 | 2 |
| 16 | Extract Information from Documents, Images, Audio, and Video with Content Understanding | 2.4.1 -- 2.4.4 | 2 |

Coverage check: every objective from 1.1.1 through 2.4.4 maps to at least one lesson; no lesson maps to an objective outside the published study guide.

## Source-of-truth precedence

When facts conflict across files in this repo:

1. The current Microsoft Learn study guide for AI-901 (re-fetch via MCP if uncertain).
2. This file (`docs/ai901-objective-domain.md`) -- treated as the verbatim local mirror of the above.
3. [`outline.pdf`](outline.pdf) -- the locked Microsoft Press deliverable spec for the 16-lesson course (internal, not learner-facing).
4. Per-lesson `lessons/lesson-NN/README.md` files.

If a lesson README drifts from this file, fix the lesson, not this file.

## Change log

| Local mirror date | Microsoft "skills measured as of" date | Notes |
| --- | --- | --- |
| 2026-05-05 | 2026-04-15 | Initial mirror. Two-domain split (40 -- 45% / 55 -- 60%). Captured all 27 measurable skills across four Domain-1 sub-areas and four Domain-2 sub-areas. Heading wording note: study-guide "skills at a glance" uses *responsibilities* in the Domain 1 title, while the detailed section uses *capabilities*; this mirror uses *capabilities* throughout. |
| 2026-06-13 | 2026-04-15 | Re-verified via microsoft_docs_fetch. Upstream study guide unchanged -- skills measured date, domain weights, and all 27 skill bullets are identical to the 2026-05-05 mirror. Local mirror revision date updated only. |
