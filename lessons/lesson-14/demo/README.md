# Lesson 14 Demo -- Speech-Enabled Application with Azure Speech in Foundry Tools

Demonstrates a five-hop conversational voice pipeline: microphone ->
**Azure AI Speech** speech-to-text (STT) -> **Azure OpenAI** gpt-4o reasoning ->
**Azure AI Speech** text-to-speech (TTS) -> speaker. Maps to AI-901 objectives
**2.2.2** and **2.2.3**: respond to spoken prompts by using a deployed multimodal
model; configure STT and TTS in a client application and wire it to a Foundry
model for conversational interaction.

---

## Prerequisites

- Python 3.12 or later
- Azure CLI (`az`) 2.60 or later -- [install guide](https://aka.ms/azurecli)
- A working **microphone** and **speaker** -- audio is the user interface; there
  is no browser or text fallback
- An Azure subscription with quota for Azure AI services (S0) and gpt-4o
  GlobalStandard in one of: swedencentral, eastus2, westus2, japaneast, southindia
- The Microsoft.CognitiveServices resource provider registered in your subscription

---

## Provision the resources

Run the PowerShell deploy script once before the first use:

```powershell
.\Deploy-Lesson14-Infrastructure.ps1
```

The script creates:

- A resource group (`rg-ai901-lesson14-demo`)
- An **Azure AI services** resource (kind=AIServices, S0) with a **custom subdomain**
  -- exposes both Speech (STT + TTS) and Azure OpenAI from a single resource
- A **gpt-4o** chat deployment (GlobalStandard, 2024-11-20)
- An RBAC assignment: **Cognitive Services User** on the resource for the
  signed-in identity

**Why "Cognitive Services User" and not "Cognitive Services Speech User"?**
The kiosk makes Speech calls AND an OpenAI chat call, both keyless. The broader
"Cognitive Services User" role covers both. The narrower Speech-only role would
block the chat hop -- this is the most common Lesson 14 RBAC trap.

At the end, the script prints five `.env` values to paste.

To remove all resources when you are done:

```powershell
.\Deploy-Lesson14-Infrastructure.ps1 -Cleanup
```

---

## Configure

Copy the example file and paste the five values printed by the deploy script:

```powershell
copy .env.example .env
```

Open `.env` and fill in:

- `SPEECH_ENDPOINT` -- the custom-subdomain endpoint
  (`https://<name>.cognitiveservices.azure.com/`)
- `SPEECH_REGION` -- short region code (e.g. `swedencentral`)
- `SPEECH_RESOURCE_ID` -- full ARM resource ID for the TTS `aad#` token
- `AOAI_ENDPOINT` -- the Azure OpenAI endpoint
  (`https://<name>.openai.azure.com/`)
- `AOAI_DEPLOYMENT` -- chat deployment name (e.g. `gpt-4o`)

There are **no key lines** -- Lesson 14 is keyless throughout.

**Never commit `.env` to source control.**

---

## Install

```powershell
python -m venv .venv
.venv\Scripts\Activate.ps1          # Windows
# source .venv/bin/activate         # macOS/Linux
pip install -r requirements.txt
```

---

## Run

Sign in to Azure first (needed once per session):

```powershell
az login
```

Run the kiosk:

```powershell
python lesson-14-voice-kiosk.py
```

When the `[mic] Speak now...` prompt appears, say something like:

- "I need a toy for a five-year-old who loves dinosaurs."
- "What would you recommend for a ten-year-old who likes building things?"
- "Do you have anything for a toddler?"

---

## What you should see

The terminal prints each hop as it completes:

```
[mic] Speak now (recognize_once_async waits up to ~15s)...
[stt] Heard: I need a toy for a five year old who loves dinosaurs.
[llm] I recommend the Tailspin Dino Dig Kit -- it includes 12 realistic
      dinosaur fossils to excavate, perfect for curious five-year-olds!
[tts] Speaking with en-US-AvaMultilingualNeural (style='cheerful', degree='1.3')...
[tts] Played 0:00:05.340000 of expressive audio.
[main] Pipeline complete: mic -> STT -> model -> TTS -> speaker.
```

The speaker then plays the model's reply in the `en-US-AvaMultilingualNeural`
voice with a cheerful expressive style.

---

## What you should know about the keyless auth asymmetry

This is the most-tested Lesson 14 nuance on the AI-901 exam:

| Hop | SDK class | Auth method |
|---|---|---|
| STT (SpeechRecognizer) | `SpeechConfig(token_credential=cred, endpoint=...)` | Clean -- SDK refreshes token automatically |
| TTS (SpeechSynthesizer) | `SpeechConfig(auth_token="aad#{resourceId}#{token}", region=...)` | Manual -- you build the `aad#`-prefixed token yourself |
| Chat (AzureOpenAI) | `AzureOpenAI(azure_ad_token_provider=...)` | Bearer token provider via `get_bearer_token_provider` |

All three use the **same `DefaultAzureCredential`** and the **same resource**.
The asymmetry exists because the Speech SDK's synthesizer predates the
`TokenCredential` protocol -- the `aad#` format is the documented workaround.

---

## Practice on your own

1. **Change the voice** -- replace `en-US-AvaMultilingualNeural` with another
   neural voice from the
   [Azure AI Speech voice gallery](https://speech.microsoft.com/portal/voicegallery).
   Try `en-US-GuyNeural` or a different language such as `es-ES-ElviraNeural`.
   Observe how the SSML `<voice name='...'>` element controls which voice speaks.

2. **Adjust the SSML style** -- in `speak_ssml()`, change `style="cheerful"` to
   `style="friendly"` or `style="excited"`. The `mstts:express-as` element is
   what transforms flat TTS into expressive, human-sounding speech.

3. **Swap the system prompt** -- change `SYSTEM_PROMPT` to position the
   assistant as a hotel concierge or a coffee-shop barista. Notice that the
   same five-hop pipeline works for any domain -- the model handles intent,
   Speech handles audio.

4. **Handle a multi-turn loop** -- wrap `main()` in a `while True:` loop and
   add a keyword (e.g. "goodbye") that breaks out. This turns one utterance
   into a continuous kiosk session.

---

## Exam connection

| AI-901 concept | Where it appears in the code |
|---|---|
| **Speech-to-text (STT)** | `SpeechRecognizer.recognize_once_async()` -- returns `RecognizedSpeech`, `NoMatch`, or `Canceled` |
| **Text-to-speech (TTS)** | `SpeechSynthesizer.speak_ssml_async()` -- SSML controls voice, prosody, style |
| **Keyless STT auth** | `SpeechConfig(token_credential=cred, endpoint=...)` -- SDK refreshes automatically |
| **Keyless TTS auth** | `SpeechConfig(auth_token="aad#{resourceId}#{token}", region=...)` -- manual `aad#` format |
| **Custom subdomain requirement** | Deploy script uses `--custom-domain`; a regional endpoint rejects token auth |
| **Cognitive Services User role** | Covers both Speech and OpenAI data-plane access; the narrower Speech-only role blocks the chat hop |
| **SSML** | `<voice>`, `<prosody>`, `<emphasis>`, `<break>`, `<mstts:express-as>` -- the five elements that make TTS sound human |
| **Five-hop pipeline** | Mic -> STT -> Foundry model -> TTS -> Speaker -- each hop is an independent SDK concern |
