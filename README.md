<!-- Cover Image -->
<p align="center">
  <img src="images/cover.png" alt="AI-901: Microsoft Azure AI Fundamentals -- Microsoft Press Video Course" width="720"/>
</p>

<p align="center">
  <a href="https://TechTrainerTim.com"><img src="https://img.shields.io/badge/Website-TechTrainerTim.com-1e90ff?logo=google-chrome&logoColor=white" alt="TechTrainerTim.com"></a>
  <a href="https://www.youtube.com/c/TechTrainerTim"><img src="https://img.shields.io/badge/YouTube-Subscribe-ff0000?logo=youtube&logoColor=white" alt="YouTube"></a>
  <a href="https://opensource.org/licenses/MIT"><img src="https://img.shields.io/badge/License-MIT-brightgreen?logo=open-source-initiative&logoColor=white" alt="MIT License"></a>
  <a href="https://www.linkedin.com/in/timothywarner"><img src="https://img.shields.io/badge/LinkedIn-timothywarner-0077b5?logo=linkedin&logoColor=white" alt="LinkedIn"></a>
  <a href="https://mvp.microsoft.com/en-US/mvp/profile/e9a13bca-2798-4247-be56-f116f780869d"><img src="https://img.shields.io/badge/Microsoft%20MVP-2026-blueviolet?logo=microsoft&logoColor=white" alt="Microsoft MVP Profile"></a>
  <a href="https://learn.microsoft.com/credentials/certifications/exams/ai-901/"><img src="https://img.shields.io/badge/Microsoft%20Exam-AI--901-0078d4?logo=microsoft&logoColor=white" alt="Microsoft AI-901 Exam"></a>
</p>

# AI-901: Microsoft Azure AI Fundamentals

**Microsoft Press Video Course** | 16 lessons | 8 hours runtime | 30 minutes per lesson

A focused, exam-aligned video crash course that takes you from "what is generative AI" to "I just shipped a Foundry agent" in a single arc. Every lesson maps to a published AI-901 skill, and the build lessons run on a real Microsoft Foundry project with keyless Microsoft Entra authentication.

This repo is the source of truth for the recorded course:

1. [`outline.pdf`](outline.pdf) -- the locked Microsoft Press deliverable spec (16 lessons with their exam objective IDs).
2. [`lessons/`](lessons/) -- one folder per lesson with a README, on-camera demo code under `demo/`, and supporting media under `assets/`.
3. [`docs/`](docs/) -- cross-lesson reference material, exam objective sync, and study resources.

## Course at a glance

The exam blueprint dated **April 15, 2026** (current at time of writing) defines two domains:

| Domain | Weight | What is measured |
| --- | --- | --- |
| 1 -- Identify AI concepts and capabilities | 40 -- 45% | Responsible AI principles, generative model components and configuration, AI workload identification across text, speech, vision, and information extraction. |
| 2 -- Implement AI solutions by using Microsoft Foundry | 55 -- 60% | Generative apps and agents, text and speech apps, computer vision and image-generation apps, information extraction with Azure Content Understanding. |

Authoritative source: [Microsoft Learn -- AI-901 study guide](https://learn.microsoft.com/credentials/certifications/resources/study-guides/ai-901). The official exam page lives at [learn.microsoft.com/credentials/certifications/exams/ai-901](https://learn.microsoft.com/credentials/certifications/exams/ai-901/). Pass score is **700**.

## Lesson plan

Every lesson is 30 minutes. Lessons 01 -- 07 are concept lessons that map to Domain 1; lessons 08 -- 16 are build lessons that map to Domain 2.

| # | Lesson | Domain | Skills measured |
| --- | --- | --- | --- |
| 01 | [Identify AI Workloads and Common Scenarios](lessons/lesson-01/README.md) | 1 | Identify scenarios for common AI workloads |
| 02 | [How Generative AI Models Work and How to Choose Them](lessons/lesson-02/README.md) | 1 | Generative AI model components and configurations |
| 03 | [Responsible AI: Fairness, Reliability and Safety, Privacy and Security](lessons/lesson-03/README.md) | 1 | Responsible AI principles 1 -- 3 |
| 04 | [Responsible AI: Inclusiveness, Transparency, Accountability](lessons/lesson-04/README.md) | 1 | Responsible AI principles 4 -- 6 |
| 05 | [Text Analysis and Speech Concepts](lessons/lesson-05/README.md) | 1 | Text analysis techniques; speech recognition and synthesis |
| 06 | [Computer Vision and Image-Generation Concepts](lessons/lesson-06/README.md) | 1 | Computer vision and image-generation models |
| 07 | [Information Extraction Concepts](lessons/lesson-07/README.md) | 1 | Techniques to extract information from text, images, audio, video |
| 08 | [Tour Microsoft Foundry and Deploy Your First Model](lessons/lesson-08/README.md) | 2 | Deploy a model and interact with it in the Foundry portal |
| 09 | [Craft Effective System and User Prompts](lessons/lesson-09/README.md) | 2 | Effective system and user prompts for generative AI models |
| 10 | [Build a Lightweight Chat Client Application with the Foundry SDK](lessons/lesson-10/README.md) | 2 | Lightweight chat client using the Foundry SDK |
| 11 | [Create and Test a Single-Agent Solution in the Foundry Portal](lessons/lesson-11/README.md) | 2 | Single-agent solution in the Foundry portal |
| 12 | [Build a Lightweight Client Application for an Agent](lessons/lesson-12/README.md) | 2 | Lightweight client application for an agent |
| 13 | [Build a Text Analysis Application with Foundry](lessons/lesson-13/README.md) | 2 | Lightweight application that includes text analysis |
| 14 | [Build a Speech-Enabled Application with Azure Speech in Foundry Tools](lessons/lesson-14/README.md) | 2 | Spoken prompts via multimodal model; Azure Speech in Foundry Tools |
| 15 | [Build a Computer Vision and Image-Generation Application](lessons/lesson-15/README.md) | 2 | Multimodal vision input; image-generation outputs |
| 16 | [Extract Information from Documents, Images, Audio, and Video with Content Understanding](lessons/lesson-16/README.md) | 2 | Azure Content Understanding across four modalities |

Full per-lesson learning objectives live in each `lessons/lesson-NN/README.md`. The locked spec is [`outline.pdf`](outline.pdf).

## Audience

From the AI-901 audience profile: candidates are at the **beginning of an AI-solutions career**, with conceptual knowledge of AI in Azure, the foundational technical skills to work with it, basic Python coding syntax, and familiarity with Azure resources. This course is built around that profile -- no prior ML background assumed, but you should be comfortable opening a Python file and running a script.

## Prerequisites for the build lessons

Concept lessons (01 -- 07) require no setup. Build lessons (08 -- 16) need:

- An **Azure subscription** with permission to create a Microsoft Foundry project.
- A **Microsoft Foundry project** with one chat-capable model deployed (a small, low-cost model is fine for the entire course).
- **Python 3.12** locally.
- The **Azure CLI** with `az login` completed -- the demos use `DefaultAzureCredential` and Microsoft Entra-based keyless authentication. You will not check in API keys.
- For lesson 14 specifically, an **Azure Speech** resource attached to your Foundry project.
- For lesson 16 specifically, **Azure Content Understanding** enabled in your Foundry project.

A single Foundry project is reused across all build lessons. Sample inputs live in each lesson's `assets/` folder so you do not need to source your own.

## Repository structure

```text
ai901/
├── outline.pdf                  # Locked Microsoft Press deliverable spec
├── README.md                    # This file
├── CLAUDE.md                    # Guidance for Claude Code agents
├── LICENSE                      # MIT
├── .markdownlint.json           # Markdown lint config
├── images/cover.png             # Course cover (800x450, optimized)
├── lessons/                     # 16 lesson folders
│   ├── README.md                # Lessons index + domain map
│   └── lesson-NN/
│       ├── README.md            # Title, runtime, exam objectives, learning objectives, demo, resources
│       ├── demo/                # On-camera code (build lessons) or walkthrough notes (concept lessons)
│       └── assets/              # Slides, screenshots, sample inputs
├── docs/                        # Cross-lesson reference material
├── src/                         # Cross-lesson shared code (only when reused)
├── scripts/                     # Repo-level helpers
└── tests/                       # Cross-lesson tests
```

## Quick start

1. **Clone the repo:**

   ```powershell
   git clone https://github.com/timothywarner-org/ai901.git
   cd ai901
   ```

2. **Read the outline:** [`outline.pdf`](outline.pdf) -- the 16-lesson spec.
3. **Read the lessons index:** [`lessons/README.md`](lessons/README.md).
4. **For build lessons,** open the lesson folder, follow its README, and run the code in `demo/`:

   ```powershell
   cd lessons/lesson-10/demo
   python -m venv .venv
   .venv\Scripts\Activate.ps1
   pip install -r requirements.txt
   az login
   python main.py
   ```

## Companion Microsoft Learn resources

The AI-901 study guide names these as primary references. They are useful as second-pass reading after each video lesson:

- [Microsoft Foundry overview](https://learn.microsoft.com/azure/ai-foundry/)
- [Microsoft Foundry Agent Service](https://learn.microsoft.com/azure/ai-foundry/agents/overview)
- [Azure AI Language](https://learn.microsoft.com/azure/ai-services/language-service/overview)
- [Azure AI Speech](https://learn.microsoft.com/azure/ai-services/speech-service/overview)
- [Azure AI Vision](https://learn.microsoft.com/azure/ai-services/computer-vision/overview)
- [Azure Content Understanding](https://learn.microsoft.com/azure/ai-services/content-understanding/overview)
- [Microsoft Responsible AI](https://www.microsoft.com/ai/responsible-ai)

For broader documentation, ask a question on [Microsoft Q&A](https://learn.microsoft.com/answers/) or visit the [AI and Machine Learning community hub](https://techcommunity.microsoft.com/t5/artificial-intelligence-and/ct-p/AI).

## Authoring conventions

This repo follows the same writing rules as Tim's other Microsoft cert courses:

- Current Microsoft product names only -- *Microsoft Foundry*, not *Azure AI Foundry* or *Azure AI Studio*.
- Plain ASCII -- use `--` for em dashes and `->` for arrows.
- No contractions in instructional content -- write *do not*, not *don't*.
- Markdown lint enforced via `.markdownlint.json`. Validate with `npx markdownlint-cli2 "**/*.md"`.
- Exam objective primacy: when content drifts from the published AI-901 skills measured, the published skills win. See [`CLAUDE.md`](CLAUDE.md) for the full source-of-truth hierarchy.

## Instructor

**Tim Warner** -- Microsoft MVP (Azure AI and Cloud and Datacenter Management), Microsoft Certified Trainer.

- [LinkedIn](https://www.linkedin.com/in/timothywarner/)
- [Website](https://techtrainertim.com/)
- [Microsoft Press author page](https://www.microsoftpressstore.com/authors/bio/2bb8e35a-b8dd-4b65-9a8d-3f0b73af6f10)
- [O'Reilly author page](https://learning.oreilly.com/search/?query=Tim%20Warner)

## Disclaimer

This is an **unofficial** study companion. Always verify exam scope and policy against the [official Microsoft AI-901 exam page](https://learn.microsoft.com/credentials/certifications/exams/ai-901/) and the [AI-901 study guide](https://learn.microsoft.com/credentials/certifications/resources/study-guides/ai-901).

## License

MIT License. See [`LICENSE`](./LICENSE) for details.
