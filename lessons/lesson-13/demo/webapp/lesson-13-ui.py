"""
Lesson 13 -- Azure AI Language UI (Streamlit, optional entry point)
====================================================================
Course:  Exam AI-901 -- Microsoft Azure AI Fundamentals (Video)
Role:    An optional Streamlit UI for the same lab that app.py serves as Flask.
         The Lesson 13 learning objective is "display text-analysis results in a
         client UI", and Streamlit is the lightest way to render entity highlights,
         a sentiment badge, and key-phrase chips over the same TextAnalyticsClient
         the SDK sample uses. Both this file and app.py import ta_client.py and
         share LANGUAGE_ENDPOINT from .env -- configure once, run either surface.

Auth is KEYLESS (DefaultAzureCredential) -- the Lesson 13 pattern. Only
LANGUAGE_ENDPOINT is read from .env; there is no key. The endpoint MUST be a
custom subdomain for Entra auth to work, and the signed-in identity needs the
"Cognitive Services User" role.

Run (local only -- never exposed):
    streamlit run lesson-13-ui.py
    # Streamlit opens http://localhost:8501 in the browser automatically
"""

from __future__ import annotations

import os

import streamlit as st
from azure.ai.textanalytics import TextAnalyticsClient
from azure.identity import DefaultAzureCredential
from dotenv import load_dotenv

load_dotenv(override=True)


@st.cache_resource
def get_client() -> TextAnalyticsClient:
    """Build the keyless client once and reuse it across reruns.

    st.cache_resource keeps a single client (and its credential) alive for the
    session -- Streamlit reruns the whole script on every interaction, so
    without caching we would rebuild the credential chain on each click.
    """
    endpoint = os.environ.get("LANGUAGE_ENDPOINT")
    if not endpoint:
        st.error(
            "Missing LANGUAGE_ENDPOINT. Copy .env.example to .env "
            "and paste the custom-subdomain Language endpoint. No key needed -- "
            "Lesson 13 is keyless (DefaultAzureCredential)."
        )
        st.stop()
    return TextAnalyticsClient(
        endpoint=endpoint,
        credential=DefaultAzureCredential(exclude_managed_identity_credential=True),
    )


def highlight_entities(text: str, entities) -> str:
    """Wrap each recognized entity in a mark span, in place.

    We splice from the END of the string backwards (sorted by offset
    descending) so inserting markup for a later entity does not shift the
    character offsets of the entities we have not spliced yet.
    """
    for ent in sorted(entities, key=lambda e: e.offset, reverse=True):
        span = (
            f"<mark title='{ent.category} ({ent.confidence_score:.2f})' "
            f"style='background:#fff3a0; padding:2px 4px; border-radius:3px'>"
            f"{text[ent.offset:ent.offset + ent.length]}</mark>"
        )
        text = text[: ent.offset] + span + text[ent.offset + ent.length:]
    return text


def sentiment_badge(label: str) -> str:
    """Return an HTML badge for a sentiment label.

    The label TEXT carries the meaning (POSITIVE / NEGATIVE / NEUTRAL / MIXED)
    so the badge is readable without relying on color alone.
    """
    colors = {
        "positive": "#2e7d32",
        "negative": "#c62828",
        "neutral": "#616161",
        "mixed": "#ef6c00",
    }
    color = colors.get(label, "#616161")
    return (
        f"<span style='background:{color}; color:white; padding:6px 12px; "
        f"border-radius:4px; font-weight:600'>{label.upper()}</span>"
    )


st.title("Tailspin Reviews Analyzer")
st.caption("Azure AI Language via keyless auth (DefaultAzureCredential) -- no key in this app.")

review = st.text_area("Paste a review", height=200)

if st.button("Analyze") and review:
    client = get_client()
    docs = [review]

    # Three skills, one client -- the lesson's "one client, many skills" point.
    # Wrapped so a transport / auth / DNS hiccup shows a clean message
    # instead of a Streamlit traceback.
    try:
        with st.spinner("Calling Azure AI Language..."):
            sentiment = client.analyze_sentiment(docs)[0]
            entities = client.recognize_entities(docs)[0].entities
            phrases = client.extract_key_phrases(docs)[0].key_phrases
    except Exception as exc:
        st.error(f"Could not reach Azure AI Language: {exc}")
        st.info(
            "Check LANGUAGE_ENDPOINT in .env, confirm `az login`, or wait a "
            "minute for the Cognitive Services User role to propagate -- then retry."
        )
        st.stop()

    if sentiment.is_error:
        st.error(f"Service returned an error: {sentiment.error}")
        st.stop()

    st.markdown(
        f"### Sentiment: {sentiment_badge(sentiment.sentiment)}",
        unsafe_allow_html=True,
    )
    st.markdown("### Highlighted text")
    st.markdown(highlight_entities(review, entities), unsafe_allow_html=True)
    st.markdown("### Key phrases")
    st.markdown(" ".join(f"`{p}`" for p in phrases[:8]) or "_none detected_")
