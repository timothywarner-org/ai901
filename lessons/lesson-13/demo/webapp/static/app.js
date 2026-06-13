// Lesson 13 -- Azure AI Language lab front-end logic
// Course: Exam AI-901 -- Microsoft Azure AI Fundamentals (Video)
//
// Wires the four skill buttons to POST /analyze/<skill> and renders the raw
// JSON response into the <pre> panel via JSON.stringify(result, null, 2).
// The point is for learners to SEE the SDK's JSON shape, not a styled UI.

(function () {
  "use strict";

  const output = document.getElementById("output");
  const status = document.getElementById("status");
  const textarea = document.getElementById("text");
  const buttons = document.querySelectorAll("button[data-skill]");

  function setBusy(busy, label) {
    buttons.forEach((b) => (b.disabled = busy));
    status.textContent = busy ? `Calling Azure AI Language: ${label}...` : status.textContent;
  }

  async function runSkill(skill) {
    const text = (textarea.value || "").trim();
    if (!text) {
      status.textContent = "Enter some text first.";
      return;
    }
    setBusy(true, skill);
    try {
      const resp = await fetch(`/analyze/${skill}`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ text }),
      });
      const data = await resp.json();
      // Render the raw JSON exactly as returned -- success OR error envelope.
      output.textContent = JSON.stringify(data, null, 2);
      status.textContent = resp.ok
        ? `Done: ${skill} (HTTP ${resp.status}).`
        : `Service returned HTTP ${resp.status}.`;
    } catch (err) {
      output.textContent = JSON.stringify({ error: String(err) }, null, 2);
      status.textContent = "Network error -- is the Flask app running?";
    } finally {
      setBusy(false, skill);
    }
  }

  buttons.forEach((btn) =>
    btn.addEventListener("click", () => runSkill(btn.dataset.skill))
  );
})();
