"""
Lesson 14 -- Tailspin Toys Voice Kiosk
=======================================
Course:  Exam AI-901 -- Microsoft Azure AI Fundamentals (Video)
LOs:     2.2.2, 2.2.3 (build a speech-enabled application; configure
         speech-to-text and text-to-speech in a client application and
         wire it to a Foundry model for conversational interaction)

THE FIVE HOPS
    1. Microphone capture        (AudioConfig, default mic)
    2. Speech-to-text            (SpeechRecognizer.recognize_once_async)
    3. Foundry model reasoning   (AzureOpenAI chat completion, gpt-4o)
    4. Text-to-speech            (SpeechSynthesizer.speak_ssml_async)
    5. Speaker playback          (AudioOutputConfig, default speaker)

THE KEYLESS-AUTH ASYMMETRY (the most-tested Lesson 14 nuance -- grounded on MS Learn
"Configure Microsoft Entra authentication for the Speech service"):
    * STT  -> SpeechConfig(token_credential=cred, endpoint=...)   <- clean
    * TTS  -> SpeechConfig(auth_token="aad#{resourceId}#{token}", region=...)
             The SpeechSynthesizer does NOT take a TokenCredential directly;
             it needs the aad#-prefixed authorization token built by hand.
    * Chat -> AzureOpenAI(azure_ad_token_provider=...)            <- bearer token

All three call the SAME resource with the SAME DefaultAzureCredential identity.
The signed-in user holds "Cognitive Services User" (covers Speech AND OpenAI).

How to run (microphone and speaker are required -- audio is the UI):
    python -m venv .venv
    .venv\\Scripts\\Activate.ps1           # Windows
    # source .venv/bin/activate           # macOS/Linux
    pip install -r requirements.txt
    cp .env.example .env                  # paste the five values from the deploy script
    az login
    python lesson-14-voice-kiosk.py
"""

from __future__ import annotations

import os

import azure.cognitiveservices.speech as speechsdk
from azure.identity import DefaultAzureCredential, get_bearer_token_provider
from dotenv import load_dotenv
from openai import AzureOpenAI

load_dotenv(override=True)

# Cognitive Services data-plane scope -- the audience for every keyless token here.
COGNITIVE_SCOPE = "https://cognitiveservices.azure.com/.default"

# Warm, friendly multilingual neural voice that matches the in-store brand tone.
VOICE = "en-US-AvaMultilingualNeural"

SYSTEM_PROMPT = (
    "You are a friendly Tailspin Toys in-store assistant. "
    "Recommend ONE specific toy that fits the customer's request. "
    "Keep responses under 40 words -- this is a spoken kiosk reply."
)


def build_credential() -> DefaultAzureCredential:
    """Return a DefaultAzureCredential pinned to the az-login identity.

    Credential guard (same pattern as the L10-L13 clients): on a dev laptop,
    stray environment variables make DefaultAzureCredential try a service
    principal or managed identity FIRST and fail with a confusing 401. We clear
    those derailers and exclude managed identity so the chain lands on the
    Azure CLI credential -- i.e. whoever ran `az login`.
    Remove this block in production, where managed identity SHOULD win.
    """
    for derailer in (
        "AZURE_TOKEN_CREDENTIALS",
        "AZURE_CLIENT_ID",
        "AZURE_CLIENT_SECRET",
        "AZURE_TENANT_ID",
    ):
        os.environ.pop(derailer, None)
    return DefaultAzureCredential(exclude_managed_identity_credential=True)


def require(name: str) -> str:
    """Fetch a required .env value or fail with an actionable message."""
    value = os.environ.get(name)
    if not value:
        raise SystemExit(
            f"Missing {name}. Run Deploy-Lesson14-Infrastructure.ps1 and paste "
            f"its output into .env (no keys -- L14 is keyless)."
        )
    return value


# ----------------------------------------------------------------------------
# Configuration objects (built once at import; reused by every hop)
# ----------------------------------------------------------------------------
CREDENTIAL = build_credential()
SPEECH_ENDPOINT = require("SPEECH_ENDPOINT").rstrip("/")
SPEECH_REGION = require("SPEECH_REGION")
SPEECH_RESOURCE_ID = require("SPEECH_RESOURCE_ID")

# --- Hop 2 config: STT keyless = token_credential + custom-domain endpoint ---
# This is the CLEAN pattern. SpeechConfig exchanges the credential for an
# Entra token under the hood and refreshes it automatically.
stt_config = speechsdk.SpeechConfig(
    token_credential=CREDENTIAL,
    endpoint=SPEECH_ENDPOINT,
)
stt_config.speech_recognition_language = "en-US"

# --- Hop 3 config: AzureOpenAI keyless = bearer token provider ---
client = AzureOpenAI(  # chat endpoint is client.chat.completions.create (not .completions)
    azure_endpoint=require("AOAI_ENDPOINT"),
    api_version=os.environ.get("AOAI_API_VERSION", "2024-10-21"),
    azure_ad_token_provider=get_bearer_token_provider(CREDENTIAL, COGNITIVE_SCOPE),
)
CHAT_DEPLOYMENT = require("AOAI_DEPLOYMENT")


def build_tts_config() -> speechsdk.SpeechConfig:
    """Build a SpeechConfig for the synthesizer using the aad# token pattern.

    THE ASYMMETRY: the SpeechSynthesizer cannot take a TokenCredential the way
    the recognizer can. It needs an authorization token of the exact shape
    'aad#{resourceId}#{entraToken}', plus the region. We rebuild this each run
    so the underlying Entra token is fresh (in production, refresh on a timer).
    """
    entra_token = CREDENTIAL.get_token(COGNITIVE_SCOPE).token
    authorization_token = f"aad#{SPEECH_RESOURCE_ID}#{entra_token}"
    cfg = speechsdk.SpeechConfig(auth_token=authorization_token, region=SPEECH_REGION)
    cfg.speech_synthesis_voice_name = VOICE
    return cfg


# ----------------------------------------------------------------------------
# Hop 1 + 2: microphone capture and speech-to-text
# ----------------------------------------------------------------------------
def listen_once() -> str | None:
    """Capture one utterance from the default microphone and return the text.

    Branches on ALL THREE result reasons every production STT handler must
    cover: RecognizedSpeech (got text), NoMatch (audio but no speech), and
    Canceled (auth, network, or quota error -- details tell you which).
    """
    audio_config = speechsdk.audio.AudioConfig(use_default_microphone=True)
    recognizer = speechsdk.SpeechRecognizer(
        speech_config=stt_config,
        audio_config=audio_config,
    )

    print("[mic] Speak now (recognize_once_async waits up to ~15s)...")
    result = recognizer.recognize_once_async().get()

    if result.reason == speechsdk.ResultReason.RecognizedSpeech:
        print(f"[stt] Heard: {result.text}")
        return result.text
    if result.reason == speechsdk.ResultReason.NoMatch:
        print("[stt] NoMatch -- audio captured but no speech recognized.")
        return None
    if result.reason == speechsdk.ResultReason.Canceled:
        details = result.cancellation_details
        print(f"[stt] Canceled: {details.reason} / {details.error_details}")
        return None
    return None


# ----------------------------------------------------------------------------
# Hop 3: route the transcript to the Foundry model
# ----------------------------------------------------------------------------
def reason(transcript: str) -> str:
    """Send the transcript to gpt-4o and return a short, spoken-kiosk reply.

    The model does NOT care that the input came from a microphone -- the Speech
    SDK owns audio, the AzureOpenAI client owns reasoning, and they compose
    cleanly because they own different concerns.
    """
    response = client.chat.completions.create(
        model=CHAT_DEPLOYMENT,
        messages=[
            {"role": "system", "content": SYSTEM_PROMPT},
            {"role": "user", "content": transcript},
        ],
        max_tokens=120,
        temperature=0.7,
    )
    reply = response.choices[0].message.content.strip()
    print(f"[llm] {reply}")
    return reply


# ----------------------------------------------------------------------------
# Hop 4 + 5: text-to-speech with SSML, played through the speaker
# ----------------------------------------------------------------------------
def speak_ssml(text: str, style: str = "cheerful", style_degree: str = "1.3") -> None:
    """Synthesize the reply wrapped in SSML for expressive playback.

    Four SSML elements cover most production needs: voice (pick the neural
    voice), prosody (pitch/rate/volume), emphasis (word-level stress), break
    (accessibility pauses) -- plus mstts:express-as for emotional styles. Flat
    TTS sounds robotic; SSML makes the kiosk sound human.
    """
    ssml = f"""<speak version='1.0'
       xmlns='http://www.w3.org/2001/10/synthesis'
       xmlns:mstts='http://www.w3.org/2001/mstts'
       xml:lang='en-US'>
  <voice name='{VOICE}'>
    <mstts:express-as style='{style}' styledegree='{style_degree}'>
      <prosody rate='-5%'>{text}</prosody>
      <break time='400ms'/>
      <emphasis level='moderate'>Thanks for visiting Tailspin Toys!</emphasis>
    </mstts:express-as>
  </voice>
</speak>"""

    audio_output = speechsdk.audio.AudioOutputConfig(use_default_speaker=True)
    synthesizer = speechsdk.SpeechSynthesizer(
        speech_config=build_tts_config(),
        audio_config=audio_output,
    )
    print(f"[tts] Speaking with {VOICE} (style={style!r}, degree={style_degree!r})...")
    result = synthesizer.speak_ssml_async(ssml).get()

    if result.reason == speechsdk.ResultReason.SynthesizingAudioCompleted:
        print(f"[tts] Played {result.audio_duration} of expressive audio.")
    elif result.reason == speechsdk.ResultReason.Canceled:
        details = result.cancellation_details
        print(f"[tts] Canceled: {details.reason} / {details.error_details}")


# ----------------------------------------------------------------------------
# The full five-hop pipeline
# ----------------------------------------------------------------------------
def main() -> None:
    """Run one turn of the kiosk: listen, reason, speak."""
    transcript = listen_once()
    if not transcript:
        print("[main] No transcript -- nothing to do. Run again and speak clearly.")
        return
    reply = reason(transcript)
    speak_ssml(reply)
    print("[main] Pipeline complete: mic -> STT -> model -> TTS -> speaker.")


if __name__ == "__main__":
    main()
