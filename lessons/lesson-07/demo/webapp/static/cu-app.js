/*
 * AI-901 Content Understanding Lab -- front-end controller
 * =========================================================
 * Responsibilities, kept deliberately small:
 *   1. Tab switching: set the active modality + analyzer label, swap the
 *      input URL to that modality's official Microsoft sample.
 *   2. Analyze: POST /analyze/<modality> with the current URL, render the
 *      highlights block and the raw JSON envelope.
 *   3. Status: report idle / working / ok / error by LABEL TEXT (the CSS
 *      signals state by border weight, never color alone).
 *
 * No framework -- one file, a handful of listeners. The JSON pane is the
 * teaching surface, so the JS does as little as possible to it: pretty-print
 * and show. The structure stays exactly what the service returned.
 */

(function () {
  "use strict";

  // Sample URL map injected by the server (lockstep with cu_client.SAMPLE_URLS).
  const SAMPLES = JSON.parse(
    document.getElementById("samples-data").textContent
  );
  // Per-modality instructional copy injected by the server (lockstep with
  // cu_client.MODALITY_INFO). Keyed by modality -> {title, api, exam}.
  const MODALITY_INFO = JSON.parse(
    document.getElementById("modality-info-data").textContent
  );

  const tabs = Array.from(document.querySelectorAll(".tab"));
  const urlInput = document.getElementById("input-url");
  const analyzeBtn = document.getElementById("analyze-btn");
  const previewBtn = document.getElementById("preview-btn");
  const statusLine = document.getElementById("status-line");
  const jsonPane = document.getElementById("json-pane");
  const highlights = document.getElementById("highlights");
  const resultMeta = document.getElementById("result-meta");
  const modalityTitle = document.getElementById("active-modality-title");
  const analyzerLabel = document.getElementById("active-analyzer");
  const infoApiText = document.getElementById("info-api-text");
  const infoExamText = document.getElementById("info-exam-text");

  // The modality currently selected. Document is first/default.
  let activeModality = tabs[0].dataset.modality;

  function setStatus(kind, message) {
    // kind: idle | working | ok | error. The class drives the border; the
    // text carries the meaning for grayscale/colorblind legibility.
    statusLine.className = "status status-" + kind;
    statusLine.textContent = message;
  }

  function selectTab(tab) {
    tabs.forEach(function (t) {
      const isActive = t === tab;
      t.classList.toggle("is-active", isActive);
      t.setAttribute("aria-selected", isActive ? "true" : "false");
    });
    activeModality = tab.dataset.modality;
    const info = MODALITY_INFO[activeModality] || {};
    // Use the modality's exam-facing title when present (e.g. "Documents and
    // forms"), else fall back to a capitalized modality key.
    modalityTitle.textContent =
      info.title ||
      activeModality.charAt(0).toUpperCase() + activeModality.slice(1);
    analyzerLabel.textContent = tab.dataset.analyzer;
    // Render the instructional copy for this tab (plain text -- the server
    // copy is trusted, but textContent keeps it inert regardless).
    infoApiText.textContent = info.api || "";
    infoExamText.textContent = info.exam || "";
    // Pre-fill the official sample so the lab runs with one click, no typing.
    urlInput.value = SAMPLES[activeModality] || "";
    setStatus("idle", "Ready.");
  }

  function previewAsset() {
    // Open the current input URL in a new tab so the source asset can be
    // inspected before analysis. noopener/noreferrer so the opened tab cannot
    // reach back into this window.
    const url = (urlInput.value || "").trim();
    if (!url) {
      setStatus("error", "Enter a file URL to preview first.");
      return;
    }
    window.open(url, "_blank", "noopener,noreferrer");
  }

  function renderHighlights(h) {
    if (!h || Object.keys(h).length === 0) {
      highlights.hidden = true;
      highlights.innerHTML = "";
      return;
    }
    // Render the modality-aware highlight object as a definition list. Order
    // is insertion order from the server, which puts the headline fields first.
    const rows = Object.keys(h)
      .filter(function (k) {
        return h[k] !== null && h[k] !== undefined && h[k] !== "";
      })
      .map(function (k) {
        return (
          "<dt>" + escapeHtml(k) + "</dt><dd>" + escapeHtml(String(h[k])) + "</dd>"
        );
      })
      .join("");
    highlights.innerHTML = "<dl>" + rows + "</dl>";
    highlights.hidden = false;
  }

  function escapeHtml(s) {
    return s
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;");
  }

  async function analyze() {
    const url = (urlInput.value || "").trim();
    if (!url) {
      setStatus("error", "Enter a file URL first.");
      return;
    }
    analyzeBtn.disabled = true;
    highlights.hidden = true;
    resultMeta.textContent = "";
    // Video can run ~30-45s; say so, so a long spinner does not read as a hang.
    const slow = activeModality === "video" || activeModality === "audio";
    setStatus(
      "working",
      "Analyzing with " +
        (tabForModality(activeModality)?.dataset.analyzer || activeModality) +
        (slow ? " -- this modality can take 30-45 seconds..." : " ...")
    );

    const started = performance.now();
    try {
      const resp = await fetch("/analyze/" + activeModality, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ url: url }),
      });
      const data = await resp.json();
      if (!resp.ok) {
        setStatus("error", data.error || "Analyze failed (HTTP " + resp.status + ").");
        jsonPane.textContent = JSON.stringify(data, null, 2);
        return;
      }
      const seconds = ((performance.now() - started) / 1000).toFixed(1);
      renderHighlights(data.highlights);
      jsonPane.textContent = JSON.stringify(data, null, 2);
      resultMeta.textContent =
        data.analyzerId + " | " + data.contentCount + " content(s) | " + seconds + "s";
      setStatus("ok", "Succeeded in " + seconds + "s.");
    } catch (err) {
      setStatus("error", "Request failed: " + err.message);
    } finally {
      analyzeBtn.disabled = false;
    }
  }

  function tabForModality(modality) {
    return tabs.find(function (t) {
      return t.dataset.modality === modality;
    });
  }

  // Wire up listeners.
  tabs.forEach(function (tab) {
    tab.addEventListener("click", function () {
      selectTab(tab);
    });
  });
  analyzeBtn.addEventListener("click", analyze);
  previewBtn.addEventListener("click", previewAsset);

  // Initialize: select the first tab (pre-fills the document sample +
  // its instructional copy).
  selectTab(tabs[0]);
})();
