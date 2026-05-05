---
name: ai901-study-planner
description: Generates a personalized AI-901 study plan based on the learner's self-assessed confidence across the two AI-901 domains and their sub-areas, prioritizing weak areas with estimated hours, Microsoft Learn module links, and the matching Microsoft Press video lesson. Use when the learner asks for a study plan, is unsure what to study, or wants exam prep guidance for Microsoft Azure AI Fundamentals.
---

# Skill: ai901.study_planner.personalized

**Description:** Generates a personalized AI-901 (Microsoft Azure AI Fundamentals) study plan based on the learner's self-assessed confidence across exam domains and sub-areas, prioritizing weak areas with estimated hours, Microsoft Learn module links, and the matching lesson from the Microsoft Press video course companion. AI-901 sits at the beginning of your career in AI solution development, so the plan favors plain-language grounding before deep build work.

## Grounding

**Required sources:**

- `docs/ai901-objective-domain.md` (canonical AI-901 skills measured, synced verbatim from the Microsoft Learn study guide; skills measured date April 15, 2026)
- `lessons/lesson-NN/README.md` (the 16-lesson Microsoft Press video course companion; lessons 01-07 cover Domain 1 concepts, lessons 08-16 cover Domain 2 build work)
- Microsoft Learn (access via the **Microsoft Learn MCP server** `ai901buddy-mslearn` using `microsoft_docs_search` for current Learn module URLs)
- Use `microsoft_docs_fetch` to verify Learn module links are current and active

## Workflow

1. **Present domains with weights.** Show the two AI-901 domains and their exam weight percentages:

   | Domain | Exam Weight |
   | --- | --- |
   | Identify AI concepts and capabilities | 40-45% |
   | Implement AI solutions by using Microsoft Foundry | 55-60% |

2. **Offer optional finer-grained confidence ratings.** AI-901 has two domains and eight sub-areas. The Implement domain carries the larger weight and has four sub-areas. If the learner wants a more targeted plan, offer to rate each sub-area separately:

   **Domain 1 sub-areas (Identify AI concepts and capabilities):**
   - 1.1 Describe principles of responsible AI (six considerations: fairness, reliability and safety, privacy and security, inclusiveness, transparency, accountability)
   - 1.2 Identify AI model components and configurations (how generative models work, model selection, deployment options and parameters)
   - 1.3 Identify AI workloads (workload scenarios, text analysis, speech, vision and image generation, information extraction)

   **Domain 2 sub-areas (Implement AI solutions by using Microsoft Foundry):**
   - 2.1 Implement generative AI apps and agents by using Foundry (prompts, deploy a model in the portal, chat client SDK, single-agent in the portal, agent client app)
   - 2.2 Implement AI solutions for text and speech by using Foundry (text analysis app, multimodal speech responses, Azure Speech in Foundry Tools app)
   - 2.3 Implement AI solutions with computer vision and image-generation capabilities by using Foundry (visual input, generative visual outputs, vision app)
   - 2.4 Implement AI solutions for information extraction by using Foundry (documents and forms, images, audio and video, info-extraction app, all by way of Azure Content Understanding)

3. **Ask for confidence ratings.** Ask the learner to rate confidence in each area on a 1-5 scale, or use one of these levels if the learner prefers words:
   - **5 - Strong** -- comfortable with most objectives; needs only light review.
   - **4 - Comfortable** -- knows the territory; needs targeted reinforcement.
   - **3 - Moderate** -- familiar with the concepts but needs targeted practice.
   - **2 - Weak** -- limited experience; needs focused study.
   - **1 - New** -- no prior exposure; needs ground-up study.
   - **Unknown** -- not sure; treat as weak (level 2).

4. **Ask for a target exam window.** Offer three preset time-to-exam options and let the learner pick or supply a custom window:
   - **1 week** (intensive sprint; trims optional reading, doubles down on practice questions and labs)
   - **2 weeks** (balanced; the default recommendation)
   - **4 weeks** (thorough; adds extra Microsoft Learn modules and a second pass of practice questions)

   The total estimated hours range scales with the chosen window; per-day or per-week hour targets are produced from the totals.

5. **Generate a prioritized study plan.** Based on the ratings and the chosen window:
   - Order sub-areas from weakest to strongest.
   - Within equal confidence levels, prioritize sub-areas with higher exam weight (Domain 2 sub-areas first, then Domain 1 sub-areas).
   - For each sub-area, provide:
     - Estimated study hours (level 1-2: 8-12 hours, level 3: 5-7 hours, level 4-5: 2-3 hours; scale by the chosen window).
     - Two to three specific Microsoft Learn module links (grounded by way of the Microsoft Learn MCP server `ai901buddy-mslearn`; do not invent URLs).
     - Key skills to focus on (pulled from `docs/ai901-objective-domain.md`).
     - The matching Microsoft Press video lesson README (relative path such as `lessons/lesson-04/README.md`); lessons 01-07 map to Domain 1 sub-areas, lessons 08-16 map to Domain 2 sub-areas.
     - A pointer to the `ai901-item-creator` skill for a practice question batch on the sub-area, and to the `ai901-lab-creator` skill for a hands-on lab.
   - Include a total estimated hours range at the bottom, broken into per-day or per-week targets that fit the chosen window.

6. **Call out audience-fit context.** AI-901 is a fundamentals exam aimed at the beginning of a career in AI solution development. There is no required prerequisite certification. If the learner mentions weak experience with the Azure portal, prompt deployment, or basic Python or REST calls, recommend a short ramp on those skills before the Domain 2 build sub-areas (2.1 through 2.4).

7. **Offer to start practicing.** After presenting the plan, ask: "Would you like to start with practice questions or a hands-on lab on **[first recommended sub-area]**?"

## Microsoft Learn topic anchors

Use the Microsoft Learn MCP server `ai901buddy-mslearn` to search the AI-901 ecosystem. Anchor searches to current product names and topic clusters:

- **Responsible AI** -- responsible AI principles, responsible generative AI, content safety
- **Generative AI fundamentals** -- generative AI concepts, large language models, tokens, prompts, parameters
- **Microsoft Foundry** -- Microsoft Foundry portal, model catalog, model deployment, agents in Foundry, Foundry Tools, chat playground
- **Azure AI Language** -- text analytics, sentiment analysis, key phrase extraction, language detection, named entity recognition, question answering
- **Azure AI Speech** -- speech-to-text, text-to-speech, speech translation, multimodal speech
- **Azure AI Vision** -- image analysis, optical character recognition, face, image generation
- **Azure Content Understanding** -- document and form extraction, image extraction, audio and video extraction, information extraction app patterns

Always verify links with `microsoft_docs_fetch` before placing them in the final plan.

## Output format

```markdown
## Your Personalized AI-901 Study Plan

**Target exam window:** [1 week / 2 weeks / 4 weeks / custom]
**Skills measured date:** April 15, 2026
**Pass score:** 700

### Priority 1: [Sub-area code and name] (domain weight: XX-XX%)

**Your confidence:** [1-5 or word rating]
**Estimated study time:** X-X hours

**Focus skills:**
- [Skill 1]
- [Skill 2]
- [Skill 3]

**Recommended Microsoft Learn modules:**
- [Module title](URL)
- [Module title](URL)

**Matching course lesson:** `lessons/lesson-NN/README.md`

**Next step:** Run the `ai901-item-creator` skill for a practice question batch on this sub-area, or the `ai901-lab-creator` skill for a hands-on lab.

---

### Priority 2: [Sub-area code and name] (domain weight: XX-XX%)

... (repeat for each sub-area; include all eight, even strong ones, with a light review recommendation)

---

**Total estimated study time:** XX-XX hours
**Suggested cadence:** [per-day or per-week hour targets that fit the chosen window]

**Audience fit:** AI-901 sits at the beginning of your career in AI solution development. There is no required prerequisite certification. Confirmed comfort with the Azure portal and basic prompt deployment? (yes / no / not sure)

Ready to start? I can generate practice questions or a hands-on lab on **[first recommended sub-area]**.
```

## Style

Plan prose follows the **Microsoft Writing Style Guide** (MWSG): warm, scannable, present-tense, sentence-style capitalization, Oxford commas, plain ASCII (no curly quotes, no en or em dashes -- use `--` and `->`). Override one MWSG convention: **no contractions** (the same rule the **Microsoft Worldwide Learning Exam Writing Style Guide** applies to exam items). When a plan mentions a fictional company in an example, draw from the WWL-approved list and use the full company name (a few common picks: A. Datum Corporation, Adventure Works Cycles, Blue Yonder Airlines, Contoso, Ltd., Fabrikam, Inc., Litware, Inc., Northwind Traders, Tailspin Toys, Wide World Importers, Woodgrove Bank). Always use current Microsoft product names; never use retired or legacy names.

## Guardrails

- Do not skip any of the eight sub-areas. Even strong areas appear in the plan with a light review recommendation.
- Do not invent Microsoft Learn module URLs. Use the Microsoft Learn MCP server `ai901buddy-mslearn` (`microsoft_docs_search`) to find real, current module links, and verify with `microsoft_docs_fetch`.
- Treat unknown confidence the same as weak (level 2).
- Always use current Microsoft product names. Use **Microsoft Foundry**, never *Azure AI Foundry* or *Azure AI Studio*. Use **Azure AI Language**, **Azure AI Speech**, **Azure AI Vision**, and **Azure Content Understanding**, never *Cognitive Services* branded names. Never use *Azure AD*, *Power Virtual Agents*, or other legacy names.
- No contractions.
- AI-901 is a fundamentals exam with no required prerequisite certification. Do not invent prerequisites; instead, surface the audience-fit prompt described above so the learner can flag any gap with the Azure portal or basic prompt deployment skills before tackling Domain 2.
- Keep the lesson pointer in sync with the domain split: lessons 01-07 map to Domain 1 sub-areas, lessons 08-16 map to Domain 2 sub-areas.

## Delivery rules

Deliver the full study plan in a single message after the learner provides confidence ratings and a target exam window. Do not split the plan across multiple messages.
