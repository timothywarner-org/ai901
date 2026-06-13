/*
 * AI-901 Vision Lab -- front-end controller
 * ==========================================
 * Drives the Vision lab: collects the chosen image + operations,
 * POSTs to /analyze, then renders three views of the result:
 *   1. Boxes on image  -- canvas overlay with labeled bounding boxes.
 *   2. Pretty results  -- human-readable summary.
 *   3. Raw JSON        -- the exam teaching surface (shape IS the answer).
 *
 * Accessibility note: bounding boxes are distinguished by SHAPE + a baked-in
 * TEXT LABEL, never by color alone. The legend repeats every label as text.
 */

"use strict";

// Distinct categories get distinct line styles AND distinct labels, so they
// stay readable without relying on hue. Color is a secondary cue only.
const BOX_STYLES = {
  objects:       { stroke: "#0b5fff", dash: [],        label: "OBJ" },
  people:        { stroke: "#9400d3", dash: [8, 4],    label: "PERSON" },
  denseCaptions: { stroke: "#e07b00", dash: [2, 3],    label: "REGION" },
  smartCrops:    { stroke: "#1a1a1a", dash: [12, 6],   label: "CROP" },
  read:          { stroke: "#008060", dash: [4, 2],    label: "TEXT" },
};

// Module state: the loaded image and the analysis result, so a tab switch
// can re-render the canvas at the right scale without re-calling the service.
let loadedImage = null;
let lastResult = null;

/* ---------------------------------------------------------------------- */
/* Element handles                                                         */
/* ---------------------------------------------------------------------- */
const $ = (id) => document.getElementById(id);
const canvas = $("overlay");
const ctx = canvas.getContext("2d");

/* ---------------------------------------------------------------------- */
/* Tab switching                                                          */
/* ---------------------------------------------------------------------- */
document.querySelectorAll(".tab").forEach((tab) => {
  tab.addEventListener("click", () => {
    document.querySelectorAll(".tab").forEach((t) => {
      t.classList.remove("is-active");
      t.setAttribute("aria-selected", "false");
    });
    document.querySelectorAll(".tab-pane").forEach((p) => p.classList.remove("is-active"));
    tab.classList.add("is-active");
    tab.setAttribute("aria-selected", "true");
    $("tab-" + tab.dataset.tab).classList.add("is-active");
    // The canvas needs a redraw when its pane becomes visible, because a
    // hidden canvas has no layout size to scale boxes against.
    if (tab.dataset.tab === "boxes" && lastResult && loadedImage) {
      renderBoxes(lastResult);
    }
  });
});

/* ---------------------------------------------------------------------- */
/* Analyze button                                                         */
/* ---------------------------------------------------------------------- */
$("analyze-btn").addEventListener("click", runAnalysis);

function selectedFeatures() {
  return Array.from(document.querySelectorAll(".feature:checked")).map((c) => c.value);
}

function currentMode() {
  return document.querySelector('input[name="mode"]:checked').value;
}

function setStatus(msg, isError) {
  const el = $("status");
  el.textContent = msg;
  // Error vs. info is signaled by a text prefix + a CSS class, never color
  // alone. Screen readers and colorblind viewers both get the signal.
  el.classList.toggle("status-error", Boolean(isError));
}

async function runAnalysis() {
  const features = selectedFeatures();
  if (features.length === 0) {
    setStatus("Pick at least one operation first.", true);
    return;
  }

  const mode = currentMode();
  setStatus("Analyzing...", false);
  $("analyze-btn").disabled = true;

  try {
    let resp;
    if (mode === "url") {
      const url = $("image-url").value.trim();
      if (!url) {
        setStatus("Enter an image URL or switch to file upload.", true);
        return;
      }
      await loadImageForCanvas(url); // may fail on CORS; handled below
      resp = await fetch("/analyze", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ mode, url, features }),
      });
    } else {
      const file = $("image-file").files[0];
      if (!file) {
        setStatus("Choose a file or switch to URL mode.", true);
        return;
      }
      await loadImageFromFile(file);
      const form = new FormData();
      form.append("file", file);
      form.append("features", features.join(","));
      form.append("mode", "file");
      resp = await fetch("/analyze", { method: "POST", body: form });
    }

    const data = await resp.json();
    if (!resp.ok) {
      // Backend hands us a clean one-line banner (401/429/400/etc.).
      setStatus(data.error || `Request failed (${resp.status}).`, true);
      return;
    }

    lastResult = data;
    renderAll(data);
    setStatus("Done. " + summarize(data), false);
  } catch (err) {
    setStatus("Unexpected error: " + err.message, true);
  } finally {
    $("analyze-btn").disabled = false;
  }
}

/* ---------------------------------------------------------------------- */
/* Image loading for the canvas                                           */
/* ---------------------------------------------------------------------- */
function loadImageForCanvas(url) {
  return new Promise((resolve) => {
    const img = new Image();
    // Load through our own /proxy-image route so the bytes arrive same-origin.
    // Direct cross-origin loads from CORS-silent hosts (aka.ms, doc CDNs)
    // taint the canvas and block drawing; the proxy avoids that entirely.
    img.onload = () => {
      loadedImage = img;
      resolve();
    };
    img.onerror = () => {
      loadedImage = null; // grid fallback if the proxy itself fails
      resolve();
    };
    img.src = "/proxy-image?url=" + encodeURIComponent(url);
  });
}

function loadImageFromFile(file) {
  return new Promise((resolve) => {
    const reader = new FileReader();
    reader.onload = () => {
      const img = new Image();
      img.onload = () => {
        loadedImage = img;
        resolve();
      };
      img.onerror = () => {
        loadedImage = null;
        resolve();
      };
      img.src = reader.result;
    };
    reader.readAsDataURL(file);
  });
}

/* ---------------------------------------------------------------------- */
/* Rendering                                                              */
/* ---------------------------------------------------------------------- */
function renderAll(data) {
  renderBoxes(data);
  renderPretty(data);
  $("json-out").textContent = JSON.stringify(data, null, 2);
}

function renderBoxes(data) {
  // The service reports pixel coordinates against the ORIGINAL image size
  // (data.metadata). We scale the canvas to that aspect ratio, then scale
  // every box by the same factor so overlays line up.
  const meta = data.metadata || { width: 640, height: 480 };
  const maxW = 640;
  const scale = Math.min(1, maxW / meta.width);
  canvas.width = Math.round(meta.width * scale);
  canvas.height = Math.round(meta.height * scale);

  ctx.clearRect(0, 0, canvas.width, canvas.height);

  if (loadedImage) {
    ctx.drawImage(loadedImage, 0, 0, canvas.width, canvas.height);
  } else {
    // No drawable bitmap (CORS-tainted or load failed): neutral backdrop so
    // boxes are still visible and the demo never hard-stops.
    ctx.fillStyle = "#f0f0f0";
    ctx.fillRect(0, 0, canvas.width, canvas.height);
    ctx.fillStyle = "#666";
    ctx.font = "13px sans-serif";
    ctx.fillText("(image not drawable here -- boxes shown on grid)", 12, 20);
  }

  const legend = $("legend");
  legend.innerHTML = "";
  const seen = new Set();

  // Box-shaped features: objects, people, dense captions, smart crops.
  drawBoxList(data.objects, "objects", (o) => labelText(o.name, o.confidence), scale, seen);
  drawBoxList(data.people, "people", () => "person", scale, seen);
  drawBoxList(data.denseCaptions, "denseCaptions", (c) => labelText(c.text, c.confidence), scale, seen);
  drawBoxList(data.smartCrops, "smartCrops", (c) => c.aspectRatio + ":1", scale, seen);

  // OCR draws polygons (lines), not x/y/w/h boxes.
  if (data.read && data.read.blocks) {
    const style = BOX_STYLES.read;
    data.read.blocks.forEach((b) =>
      b.lines.forEach((line) => drawPolygon(line.boundingPolygon, style, scale))
    );
    addLegend(legend, seen, style, "OCR text lines");
  }
}

function drawBoxList(list, kind, labelFn, scale, seen) {
  if (!Array.isArray(list) || list.length === 0) return;
  const style = BOX_STYLES[kind];
  list.forEach((item) => {
    const b = item.boundingBox;
    drawBox(b, style, labelFn(item), scale);
  });
  addLegend($("legend"), seen, style, kind);
}

function drawBox(b, style, text, scale) {
  const x = b.x * scale;
  const y = b.y * scale;
  const w = b.w * scale;
  const h = b.h * scale;

  ctx.lineWidth = 2;
  ctx.setLineDash(style.dash);
  ctx.strokeStyle = style.stroke;
  ctx.strokeRect(x, y, w, h);
  ctx.setLineDash([]);

  // Baked-in text label: a high-contrast chip in the top-left of the box so
  // the box is identifiable without relying on its stroke color.
  const tag = style.label + " " + text;
  ctx.font = "12px sans-serif";
  const padX = 4;
  const tw = ctx.measureText(tag).width + padX * 2;
  ctx.fillStyle = "rgba(0,0,0,0.78)";
  ctx.fillRect(x, Math.max(0, y - 16), tw, 16);
  ctx.fillStyle = "#fff";
  ctx.fillText(tag, x + padX, Math.max(11, y - 4));
}

function drawPolygon(points, style, scale) {
  if (!points || points.length === 0) return;
  ctx.lineWidth = 2;
  ctx.setLineDash(style.dash);
  ctx.strokeStyle = style.stroke;
  ctx.beginPath();
  ctx.moveTo(points[0].x * scale, points[0].y * scale);
  points.slice(1).forEach((p) => ctx.lineTo(p.x * scale, p.y * scale));
  ctx.closePath();
  ctx.stroke();
  ctx.setLineDash([]);
}

function addLegend(legend, seen, style, label) {
  if (seen.has(label)) return;
  seen.add(label);
  const li = document.createElement("li");
  // Swatch shows the dash pattern as a shape cue; the text label is the
  // primary identifier (color is decorative).
  const swatch = document.createElement("span");
  swatch.className = "swatch";
  swatch.style.borderColor = style.stroke;
  swatch.style.borderStyle = style.dash.length ? "dashed" : "solid";
  li.appendChild(swatch);
  li.appendChild(document.createTextNode(" " + style.label + " -- " + label));
  legend.appendChild(li);
}

function labelText(name, confidence) {
  if (typeof confidence === "number") {
    return name + " " + confidence.toFixed(2);
  }
  return name;
}

/* ---------------------------------------------------------------------- */
/* Pretty (human-readable) pane                                           */
/* ---------------------------------------------------------------------- */
function renderPretty(data) {
  const root = $("pretty");
  root.innerHTML = "";

  if (data.caption) {
    addSection(root, "Caption", [
      `"${data.caption.text}" (confidence ${data.caption.confidence.toFixed(2)})`,
    ]);
  }
  if (data.denseCaptions) {
    addSection(
      root,
      "Dense captions",
      data.denseCaptions.map((c) => `${c.text} (${c.confidence.toFixed(2)})`)
    );
  }
  if (data.objects) {
    addSection(
      root,
      "Objects",
      data.objects.map(
        (o) => `${o.name} (${o.confidence.toFixed(2)}) @ ` +
          `x=${o.boundingBox.x}, y=${o.boundingBox.y}, w=${o.boundingBox.w}, h=${o.boundingBox.h}`
      )
    );
  }
  if (data.people) {
    addSection(
      root,
      "People",
      data.people.map((p) => `person (${p.confidence.toFixed(2)})`)
    );
  }
  if (data.read) {
    const lines = [];
    data.read.blocks.forEach((b) => b.lines.forEach((l) => lines.push(l.text)));
    addSection(root, "OCR text", lines.length ? lines : ["(no text found)"]);
  }
  if (data.tags) {
    addSection(
      root,
      "Tags",
      data.tags.map((t) => `${t.name} (${t.confidence.toFixed(2)})`)
    );
  }
  if (data.smartCrops) {
    addSection(
      root,
      "Smart crops",
      data.smartCrops.map((c) => `aspect ${c.aspectRatio}:1`)
    );
  }
}

function addSection(root, title, items) {
  const h = document.createElement("h3");
  h.textContent = title;
  root.appendChild(h);
  const ul = document.createElement("ul");
  items.forEach((text) => {
    const li = document.createElement("li");
    li.textContent = text;
    ul.appendChild(li);
  });
  root.appendChild(ul);
}

function summarize(data) {
  const parts = [];
  if (data.caption) parts.push("1 caption");
  if (data.objects) parts.push(data.objects.length + " objects");
  if (data.people) parts.push(data.people.length + " people");
  if (data.read) {
    let n = 0;
    data.read.blocks.forEach((b) => (n += b.lines.length));
    parts.push(n + " text lines");
  }
  if (data.tags) parts.push(data.tags.length + " tags");
  return parts.join(", ") + ".";
}
