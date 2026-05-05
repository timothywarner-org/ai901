# Lessons

Microsoft Press video course **Exam AI-901: Microsoft Azure AI Fundamentals** -- 16 lessons, 8 hours runtime, 30 minutes per lesson.

Verbatim Microsoft Learn skills measured live in [`../docs/ai901-objective-domain.md`](../docs/ai901-objective-domain.md).

## Domain map

The course follows the published AI-901 study guide. Domain 1 is concept-focused; Domain 2 is build-focused on Microsoft Foundry.

| # | Lesson | Exam objective(s) |
| --- | --- | --- |
| 01 | Identify AI Workloads and Common Scenarios | 1.3.1 |
| 02 | How Generative AI Models Work and How to Choose Them | 1.2.1 -- 1.2.3 |
| 03 | Responsible AI: Fairness, Reliability and Safety, Privacy and Security | 1.1.1 -- 1.1.3 |
| 04 | Responsible AI: Inclusiveness, Transparency, Accountability | 1.1.4 -- 1.1.6 |
| 05 | Text Analysis and Speech Concepts | 1.3.2, 1.3.3 |
| 06 | Computer Vision and Image-Generation Concepts | 1.3.4 |
| 07 | Information Extraction Concepts | 1.3.5 |
| 08 | Tour Microsoft Foundry and Deploy Your First Model | 2.1.2 |
| 09 | Craft Effective System and User Prompts | 2.1.1 |
| 10 | Build a Lightweight Chat Client Application with the Foundry SDK | 2.1.3 |
| 11 | Create and Test a Single-Agent Solution in the Foundry Portal | 2.1.4 |
| 12 | Build a Lightweight Client Application for an Agent | 2.1.5 |
| 13 | Build a Text Analysis Application with Foundry | 2.2.1 |
| 14 | Build a Speech-Enabled Application with Azure Speech in Foundry Tools | 2.2.2, 2.2.3 |
| 15 | Build a Computer Vision and Image-Generation Application | 2.3.1 -- 2.3.3 |
| 16 | Extract Information from Documents, Images, Audio, and Video with Content Understanding | 2.4.1 -- 2.4.4 |

## Lesson folder layout

Every `lesson-NN/` folder follows the same shape:

```text
lesson-NN/
├── README.md      # Title, runtime, exam objectives, learning objectives, demo plan, resources
├── demo/          # Code demonstrated on camera (Python, Bicep, scripts)
└── assets/        # Slides, screenshots, sample data referenced in the lesson
```

Concept-only lessons (01 -- 07) keep `demo/` for in-portal walkthrough notes. Build lessons (08 -- 16) keep working code in `demo/` -- prefer minimal, runnable, keyless-auth Python.
