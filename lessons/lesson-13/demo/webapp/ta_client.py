"""
ta_client.py -- Azure AI Language wrapper for the Lesson 13 web app
====================================================================
Course: Exam AI-901 -- Microsoft Azure AI Fundamentals (Video)

One thin module that wraps TextAnalyticsClient so app.py stays a
pure Flask routing file. Every function takes raw text and returns a plain
dict the Flask layer can jsonify -- so the browser sees the same JSON shape
the SDK returns, which is the whole teaching point of the web-app surface.

Auth is KEYLESS (DefaultAzureCredential) -- Lesson 13 teaches the keyless
pattern. Only LANGUAGE_ENDPOINT is read from .env; there is no key. The
endpoint MUST be a custom subdomain for Entra auth to work, and the
signed-in identity needs the "Cognitive Services User" role.
"""

from __future__ import annotations

import os

from azure.ai.textanalytics import TextAnalyticsClient
from azure.core.exceptions import HttpResponseError, ClientAuthenticationError
from azure.identity import DefaultAzureCredential
from dotenv import load_dotenv

load_dotenv(override=True)


class TAConfigError(RuntimeError):
    """.env is not populated -- a configuration problem, not a service one."""


class TAServiceError(RuntimeError):
    """The Language service (or auth) rejected the call. Carries an HTTP status."""

    def __init__(self, message: str, status: int = 500):
        super().__init__(message)
        self.status = status


def _build_client() -> TextAnalyticsClient:
    """Construct the keyless client once, lazily, with a clear config error.

    DefaultAzureCredential is constructed here rather than at import time so a
    missing endpoint surfaces as a clean TAConfigError instead of a stack
    trace when the module loads.
    """
    endpoint = os.environ.get("LANGUAGE_ENDPOINT")
    if not endpoint:
        raise TAConfigError(
            "Missing LANGUAGE_ENDPOINT. Copy .env.example to "
            ".env and paste the custom-subdomain Language endpoint. "
            "No key needed -- Lesson 13 is keyless (DefaultAzureCredential)."
        )
    return TextAnalyticsClient(endpoint=endpoint, credential=DefaultAzureCredential())


# Single client reused across requests (thread-safe for read calls).
_client: TextAnalyticsClient | None = None


def _client_or_build() -> TextAnalyticsClient:
    global _client
    if _client is None:
        _client = _build_client()
    return _client


def _guard(fn):
    """Translate SDK exceptions into learner-friendly TAServiceError lines."""

    def wrapped(text: str):
        client = _client_or_build()
        try:
            return fn(client, text)
        except ClientAuthenticationError as err:
            raise TAServiceError(
                f"Keyless auth failed -- check the Cognitive Services User role "
                f"assignment (it can take 5 min to propagate). {err}", 403
            )
        except HttpResponseError as err:
            raise TAServiceError(str(err), getattr(err, "status_code", 500) or 500)

    return wrapped


@_guard
def analyze_entities(client: TextAnalyticsClient, text: str) -> dict:
    """recognize_entities() -> {entities: [{text, category, confidence}]}"""
    result = client.recognize_entities(documents=[text])[0]
    if result.is_error:
        raise TAServiceError(str(result.error), 400)
    return {
        "skill": "entities",
        "method": "recognize_entities()",
        "entities": [
            {"text": e.text, "category": e.category, "confidence": round(e.confidence_score, 2)}
            for e in result.entities
        ],
    }


@_guard
def analyze_key_phrases(client: TextAnalyticsClient, text: str) -> dict:
    """extract_key_phrases() -> {key_phrases: [...]}"""
    result = client.extract_key_phrases(documents=[text])[0]
    if result.is_error:
        raise TAServiceError(str(result.error), 400)
    return {
        "skill": "key_phrases",
        "method": "extract_key_phrases()",
        "key_phrases": list(result.key_phrases),
    }


@_guard
def analyze_sentiment(client: TextAnalyticsClient, text: str) -> dict:
    """analyze_sentiment(show_opinion_mining=True) -> document label + opinion pairs"""
    result = client.analyze_sentiment(documents=[text], show_opinion_mining=True)[0]
    if result.is_error:
        raise TAServiceError(str(result.error), 400)
    opinions = []
    for sentence in result.sentences:
        for op in sentence.mined_opinions:
            for a in op.assessments:
                opinions.append(
                    {
                        "target": op.target.text,
                        "target_sentiment": op.target.sentiment,
                        "assessment": a.text,
                        "assessment_sentiment": a.sentiment,
                    }
                )
    s = result.confidence_scores
    return {
        "skill": "sentiment",
        "method": "analyze_sentiment(show_opinion_mining=True)",
        "document_sentiment": result.sentiment,
        "scores": {"positive": round(s.positive, 2), "neutral": round(s.neutral, 2), "negative": round(s.negative, 2)},
        "opinions": opinions,
    }


@_guard
def summarize(client: TextAnalyticsClient, text: str) -> dict:
    """begin_extract_summary() + begin_abstract_summary() -> both summaries.

    Both are long-running operations: they return a poller, and .result()
    blocks until the service finishes. Extractive pulls verbatim source
    sentences (traceable); abstractive writes new paraphrased text (readable).
    """
    extract = next(iter(client.begin_extract_summary(documents=[text]).result()))
    abstract = next(iter(client.begin_abstract_summary(documents=[text]).result()))
    return {
        "skill": "summarize",
        "method": "begin_extract_summary() / begin_abstract_summary()",
        "extractive": [s.text for s in extract.sentences] if not extract.is_error else [],
        "abstractive": [s.text for s in abstract.summaries] if not abstract.is_error else [],
    }


# Skill name -> function, so the Flask route can dispatch by URL segment.
SKILLS = {
    "entities": analyze_entities,
    "key-phrases": analyze_key_phrases,
    "sentiment": analyze_sentiment,
    "summarize": summarize,
}

# The sample review pre-filled in the textarea so the lab runs with zero typing.
SAMPLE_REVIEW = (
    "I flew Contoso Air from Seattle to Munich on March 12, 2026. The check-in "
    "agent at SEA was wonderful and the Premium Economy meal was the best I have "
    "had on any transatlantic flight this year. Unfortunately the in-flight Wi-Fi "
    "was a disaster -- it dropped three times and the support chat just kept "
    "apologizing. The Munich arrivals lounge was filthy too. I will probably fly "
    "Contoso Air again, but they must fix the Wi-Fi."
)
