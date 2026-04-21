/**
 * app.js — AI-Powered QA Automation System
 * Front-end: scenario cards, editable RF script, SSE execution log,
 *            credential sync, reports, Jira panel.
 */

"use strict";

// ─── Global state ────────────────────────────────────────────
const state = {
  scenarios:    [],          // flat scenario list (type-tagged)
  scenariosRaw: {},          // original { positive_scenarios, negative_scenarios }
  selectedIds:  new Set(),   // IDs selected for script generation
  scriptId:     null,        // ID returned by /generate-script
  scriptContent: "",         // current editor content (may differ from disk)
  runId:        null,        // active execution run_id
  eventSource:  null,        // SSE EventSource handle
  results:      null,        // last parsed results dict
  saveTimer:    null,        // debounce timer for auto-save
};

// ─── DOM helpers ─────────────────────────────────────────────
const $  = id  => document.getElementById(id);
const qs = sel => document.querySelector(sel);

// ─── Overlay ─────────────────────────────────────────────────
function showOverlay(msg = "Processing…") {
  $("overlay").classList.remove("hidden");
  $("overlayMsg").textContent = msg;
}
function hideOverlay() { $("overlay").classList.add("hidden"); }

// ─── Toast ───────────────────────────────────────────────────
let _toastTimer = null;
function toast(msg, type = "info", duration = 3500) {
  const el = $("toast");
  el.textContent = msg;
  el.className = `toast toast-${type} show`;
  clearTimeout(_toastTimer);
  _toastTimer = setTimeout(() => el.classList.remove("show"), duration);
}

// ─── Status bar ──────────────────────────────────────────────
function setStatus(text, s = "idle") {
  $("statusDot").className = `status-dot ${s}`;
  $("statusText").textContent = text;
}

// ═══════════════════════════════════════════════════════════
// CREDENTIAL INDICATOR (sidebar badges + sync)
// ═══════════════════════════════════════════════════════════

function onCredentialChange() {
  const user = $("username").value.trim();
  const pass = $("password").value.trim();

  const ind = $("credIndicator");
  const ub  = $("credUserBadge");
  const pb  = $("credPassBadge");

  ind.classList.remove("hidden");

  ub.textContent = user ? `👤 ${user}` : "👤 No username";
  ub.className   = "cred-badge " + (user ? "set" : "unset");

  pb.textContent = pass ? `🔑 ${"•".repeat(Math.min(pass.length, 8))}` : "🔑 No password";
  pb.className   = "cred-badge " + (pass ? "set" : "unset");

  // If a script is loaded, auto-inject immediately
  if (state.scriptId) syncCredentials(true);
}

/**
 * Replace ${USERNAME} and ${PASSWORD} in the Variables section
 * of the current editor content with the sidebar field values.
 *
 * @param {boolean} silent — if true, suppress the toast notification
 */
function syncCredentials(silent = false) {
  const user = $("username").value.trim();
  const pass = $("password").value.trim();

  const ta = $("scriptCode");
  if (!ta || !ta.value) return;

  const updated = injectCredentials(ta.value, user, pass);
  if (updated !== ta.value) {
    ta.value = updated;
    state.scriptContent = updated;
    updateLineCount(updated);
    scheduleSave();
    if (!silent) toast("Credentials synced into script.", "success");
  } else {
    if (!silent) toast("Nothing to sync — credentials already match.", "info");
  }
}

/**
 * Inject username and password into the *** Variables *** section.
 * Matches lines like:
 *   ${USERNAME}      ${EMPTY}
 *   ${PASSWORD}      ${EMPTY}
 * and replaces the trailing value with the provided credentials.
 */
function injectCredentials(script, username, password) {
  let result = script;

  if (username) {
    // Match: line starting with ${USERNAME} (no leading spaces = Variables section)
    result = result.replace(
      /^(\$\{USERNAME\}[ \t]+)(.*)$/m,
      (_, prefix) => `${prefix}${username}`
    );
  }

  if (password) {
    result = result.replace(
      /^(\$\{PASSWORD\}[ \t]+)(.*)$/m,
      (_, prefix) => `${prefix}${password}`
    );
  }

  return result;
}

// ═══════════════════════════════════════════════════════════
// TAB MANAGEMENT
// ═══════════════════════════════════════════════════════════
function switchTab(name, btn) {
  document.querySelectorAll(".tab-content").forEach(el => el.classList.remove("active"));
  document.querySelectorAll(".tab-btn").forEach(el => el.classList.remove("active"));
  $(`tab-${name}`).classList.add("active");
  btn.classList.add("active");
}

// ═══════════════════════════════════════════════════════════
// JIRA PANEL COLLAPSIBLE
// ═══════════════════════════════════════════════════════════
function toggleJira() {
  const panel = $("jiraPanel");
  panel.classList.toggle("collapsed");
  $("jiraToggleIcon").textContent = panel.classList.contains("collapsed") ? "▼" : "▲";
}

document.addEventListener("DOMContentLoaded", () => {
  $("jiraPanel").classList.add("collapsed");

  // Tab key inserts spaces (not focuses next element) in the editor
  $("scriptCode").addEventListener("keydown", e => {
    if (e.key === "Tab") {
      e.preventDefault();
      const ta    = e.target;
      const start = ta.selectionStart;
      const end   = ta.selectionEnd;
      ta.value = ta.value.slice(0, start) + "    " + ta.value.slice(end);
      ta.selectionStart = ta.selectionEnd = start + 4;
      state.scriptContent = ta.value;
    }
  });

  // Ctrl+S saves script
  document.addEventListener("keydown", e => {
    if ((e.ctrlKey || e.metaKey) && e.key === "s" && state.scriptId) {
      e.preventDefault();
      saveScript();
    }
  });

  // Ctrl+Enter on description → generate
  $("description").addEventListener("keydown", e => {
    if (e.key === "Enter" && (e.ctrlKey || e.metaKey)) generateScenarios();
  });
});

// ═══════════════════════════════════════════════════════════
// 1. GENERATE SCENARIOS
// ═══════════════════════════════════════════════════════════
async function generateScenarios() {
  const appUrl      = $("appUrl").value.trim();
  const description = $("description").value.trim();
  const username    = $("username").value.trim();
  const password    = $("password").value.trim();
  const apiKey      = $("apiKey").value.trim();

  if (!description) {
    toast("Please enter a description / scenario title.", "error");
    $("description").focus();
    return;
  }

  showOverlay("Generating scenarios with Claude AI…");
  setStatus("Generating scenarios…", "working");

  try {
    const res  = await fetch("/api/generate-scenarios", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body:   JSON.stringify({ app_url: appUrl, description, username, password, api_key: apiKey }),
    });
    const data = await res.json();
    if (!data.success) throw new Error(data.error || "Unknown error");

    const sc  = data.scenarios;
    const all = [
      ...(sc.positive_scenarios || []).map(s => ({ ...s, type: "positive" })),
      ...(sc.negative_scenarios || []).map(s => ({ ...s, type: "negative" })),
    ];

    state.scenarios    = all;
    state.scenariosRaw = sc;
    state.selectedIds  = new Set(all.map(s => s.id));

    renderScenarios(all, sc.enhanced_description);
    switchTab("scenarios", qs('[data-tab="scenarios"]'));
    $("btnGenScript").disabled = false;
    setStatus("Scenarios ready", "success");
    toast(
      `Generated ${all.length} scenarios ` +
      `(${(sc.positive_scenarios||[]).length}✅ positive, ` +
      `${(sc.negative_scenarios||[]).length}❌ negative).`,
      "success"
    );

  } catch (err) {
    setStatus("Error", "error");
    toast(`Scenario generation failed: ${err.message}`, "error", 5000);
  } finally {
    hideOverlay();
  }
}

function renderScenarios(scenarios, enhanced = "") {
  const container = $("scenariosContainer");
  const empty     = $("scenariosEmpty");

  if (!scenarios.length) {
    container.classList.add("hidden");
    empty.classList.remove("hidden");
    return;
  }

  empty.classList.add("hidden");
  container.classList.remove("hidden");

  const banner = enhanced
    ? `<div class="enhanced-desc"><strong>AI Summary:</strong> ${escHtml(enhanced)}</div>`
    : "";

  container.innerHTML = banner + scenarios.map((s, idx) => `
    <div class="scenario-card ${state.selectedIds.has(s.id) ? "selected" : ""}"
         id="sc-${s.id}">
      <div class="sc-header" onclick="toggleScenario('${s.id}')">
        <span class="sc-id">${s.id}</span>
        <span class="sc-badge ${s.type}">${s.type}</span>
        <span class="sc-badge" style="background:rgba(210,153,34,.12);color:#d29922">
          ${s.priority || "Medium"}
        </span>
        <button class="sc-edit-btn" onclick="event.stopPropagation(); toggleEditScenario('${s.id}', ${idx})" title="Edit scenario">✏️</button>
      </div>
      <div class="sc-view" id="sc-view-${s.id}">
        <div class="sc-title">${escHtml(s.title || "")}</div>
        <ul class="sc-steps">
          ${(s.steps || []).map(step => `<li>${escHtml(step)}</li>`).join("")}
        </ul>
        <div class="sc-expected">✓ ${escHtml(s.expected_result || "")}</div>
      </div>
      <div class="sc-edit hidden" id="sc-edit-${s.id}">
        <label>Title:</label>
        <input type="text" class="sc-edit-input" id="sc-title-${s.id}" value="${escAttr(s.title || '')}" />
        <label>Steps (one per line):</label>
        <textarea class="sc-edit-textarea" id="sc-steps-${s.id}" rows="5">${(s.steps || []).join('\n')}</textarea>
        <label>Expected Result:</label>
        <input type="text" class="sc-edit-input" id="sc-expected-${s.id}" value="${escAttr(s.expected_result || '')}" />
        <label>Priority:</label>
        <select class="sc-edit-select" id="sc-priority-${s.id}">
          <option value="High" ${s.priority === 'High' ? 'selected' : ''}>High</option>
          <option value="Medium" ${s.priority === 'Medium' ? 'selected' : ''}>Medium</option>
          <option value="Low" ${s.priority === 'Low' ? 'selected' : ''}>Low</option>
        </select>
        <div class="sc-edit-actions">
          <button class="sc-save-btn" onclick="event.stopPropagation(); saveScenarioEdit('${s.id}', ${idx})">💾 Save</button>
          <button class="sc-cancel-btn" onclick="event.stopPropagation(); cancelScenarioEdit('${s.id}')">✖ Cancel</button>
          <button class="sc-delete-btn" onclick="event.stopPropagation(); deleteScenario('${s.id}', ${idx})">🗑 Delete</button>
        </div>
      </div>
    </div>
  `).join("");
}

function toggleEditScenario(id, idx) {
  const viewEl = $(`sc-view-${id}`);
  const editEl = $(`sc-edit-${id}`);
  viewEl.classList.toggle("hidden");
  editEl.classList.toggle("hidden");
}

function saveScenarioEdit(id, idx) {
  const title    = $(`sc-title-${id}`).value.trim();
  const stepsRaw = $(`sc-steps-${id}`).value.trim();
  const expected = $(`sc-expected-${id}`).value.trim();
  const priority = $(`sc-priority-${id}`).value;
  const steps    = stepsRaw.split('\n').map(s => s.trim()).filter(s => s);

  state.scenarios[idx].title           = title;
  state.scenarios[idx].steps           = steps;
  state.scenarios[idx].expected_result = expected;
  state.scenarios[idx].priority        = priority;

  // Also update scenariosRaw
  const type = state.scenarios[idx].type;
  const rawKey = type === 'positive' ? 'positive_scenarios' : 'negative_scenarios';
  const rawList = state.scenariosRaw[rawKey] || [];
  const rawIdx = rawList.findIndex(s => s.id === id);
  if (rawIdx >= 0) {
    rawList[rawIdx].title           = title;
    rawList[rawIdx].steps           = steps;
    rawList[rawIdx].expected_result = expected;
    rawList[rawIdx].priority        = priority;
  }

  renderScenarios(state.scenarios, '');
  toast(`Scenario ${id} updated.`, 'success');
}

function cancelScenarioEdit(id) {
  $(`sc-view-${id}`).classList.remove('hidden');
  $(`sc-edit-${id}`).classList.add('hidden');
}

function deleteScenario(id, idx) {
  if (!confirm(`Delete scenario ${id}?`)) return;
  state.scenarios.splice(idx, 1);
  state.selectedIds.delete(id);

  // Remove from scenariosRaw
  ['positive_scenarios', 'negative_scenarios'].forEach(key => {
    const list = state.scenariosRaw[key] || [];
    const i = list.findIndex(s => s.id === id);
    if (i >= 0) list.splice(i, 1);
  });

  renderScenarios(state.scenarios, '');
  $("btnGenScript").disabled = state.selectedIds.size === 0;
  toast(`Scenario ${id} deleted.`, 'info');
}

function addNewScenario() {
  const type = prompt('Scenario type? (positive / negative)', 'positive');
  if (!type || !['positive', 'negative'].includes(type)) return;

  const prefix = type === 'positive' ? 'TC_POS' : 'TC_NEG';
  const count  = state.scenarios.filter(s => s.type === type).length + 1;
  const id     = `${prefix}_${String(count).padStart(3, '0')}`;

  const newSc = {
    id, type,
    title: 'New scenario — click ✏️ to edit',
    priority: 'Medium',
    steps: ['Step 1: Navigate to the application', 'Step 2: Perform action', 'Step 3: Verify result'],
    expected_result: 'Expected outcome',
  };

  state.scenarios.push(newSc);
  state.selectedIds.add(id);

  const rawKey = type === 'positive' ? 'positive_scenarios' : 'negative_scenarios';
  if (!state.scenariosRaw[rawKey]) state.scenariosRaw[rawKey] = [];
  state.scenariosRaw[rawKey].push(newSc);

  renderScenarios(state.scenarios, '');
  $("btnGenScript").disabled = false;
  toast(`Added new ${type} scenario ${id}. Click ✏️ to edit it.`, 'success');
}

function toggleScenario(id) {
  const card = $(`sc-${id}`);
  if (state.selectedIds.has(id)) {
    state.selectedIds.delete(id);
    card.classList.remove("selected");
  } else {
    state.selectedIds.add(id);
    card.classList.add("selected");
  }
  $("btnGenScript").disabled = state.selectedIds.size === 0;
}

function selectAllScenarios(select) {
  state.scenarios.forEach(s => {
    const card = $(`sc-${s.id}`);
    if (select) { state.selectedIds.add(s.id);    card && card.classList.add("selected"); }
    else        { state.selectedIds.delete(s.id); card && card.classList.remove("selected"); }
  });
  $("btnGenScript").disabled = !select || state.selectedIds.size === 0;
}

// ═══════════════════════════════════════════════════════════
// 2. GENERATE ROBOT FRAMEWORK SCRIPT
// ═══════════════════════════════════════════════════════════
async function generateScript() {
  const selected = state.scenarios.filter(s => state.selectedIds.has(s.id));
  if (!selected.length) { toast("Select at least one scenario.", "error"); return; }

  const appUrl    = $("appUrl").value.trim();
  const username  = $("username").value.trim();
  const password  = $("password").value.trim();
  const apiKey    = $("apiKey").value.trim();
  const suiteName = $("description").value.trim() || "AI QA Suite";

  const positive = selected.filter(s => s.type === "positive");
  const negative = selected.filter(s => s.type === "negative");
  const payload  = { positive_scenarios: positive, negative_scenarios: negative };

  showOverlay("Generating Robot Framework script…");
  setStatus("Generating RF script…", "working");

  try {
    const res  = await fetch("/api/generate-script", {
      method:  "POST",
      headers: { "Content-Type": "application/json" },
      body:    JSON.stringify({
        scenarios: payload, app_url: appUrl, username, password,
        api_key: apiKey, suite_name: suiteName,
      }),
    });
    const data = await res.json();
    if (!data.success) throw new Error(data.error || "Unknown error");

    state.scriptId      = data.script_id;
    state.scriptContent = data.script;

    // Inject the sidebar credentials into the Variables section
    const finalScript = injectCredentials(data.script, username, password);
    state.scriptContent = finalScript;

    renderScript(finalScript);
    enableScriptButtons(true);

    switchTab("script", qs('[data-tab="script"]'));
    setStatus("Script ready", "success");
    toast("Robot Framework script generated — credentials injected!", "success");

  } catch (err) {
    setStatus("Error", "error");
    toast(`Script generation failed: ${err.message}`, "error", 5000);
  } finally {
    hideOverlay();
  }
}

function renderScript(content) {
  $("scriptEmpty").classList.add("hidden");
  const wrap = $("scriptContainer");
  wrap.classList.remove("hidden");

  const ta = $("scriptCode");
  ta.value = content;
  updateLineCount(content);
}

function updateLineCount(content) {
  const lines = (content.match(/\n/g) || []).length + 1;
  const el = $("editorLineCount");
  if (el) el.textContent = `${lines} lines`;
}

function enableScriptButtons(on) {
  ["btnSyncCreds", "btnSaveScript", "btnDownloadScript", "btnRunScript", "btnRunFromExec"]
    .forEach(id => { if ($(id)) $(id).disabled = !on; });
}

// ─── Editor change handler ────────────────────────────────
function onScriptEdit() {
  const content = $("scriptCode").value;
  state.scriptContent = content;
  updateLineCount(content);
  scheduleSave();
}

// ─── Debounced auto-save (1.5 s after last keystroke) ─────
function scheduleSave() {
  clearTimeout(state.saveTimer);
  state.saveTimer = setTimeout(saveScript, 1500);
}

// ═══════════════════════════════════════════════════════════
// 3. SAVE SCRIPT
// ═══════════════════════════════════════════════════════════
async function saveScript() {
  if (!state.scriptId) return;
  const content = $("scriptCode").value;
  if (!content.trim()) return;

  state.scriptContent = content;

  try {
    const res  = await fetch(`/api/save-script/${state.scriptId}`, {
      method:  "POST",
      headers: { "Content-Type": "application/json" },
      body:    JSON.stringify({ content }),
    });
    const data = await res.json();
    if (data.success) {
      const el = $("saveStatus");
      el.textContent = "✓ Saved";
      el.classList.add("show");
      setTimeout(() => el.classList.remove("show"), 2000);
    }
  } catch { /* silent — auto-save is best effort */ }
}

// ═══════════════════════════════════════════════════════════
// 4. DOWNLOAD SCRIPT
// ═══════════════════════════════════════════════════════════
function downloadScript() {
  if (!state.scriptId) { toast("No script generated yet.", "error"); return; }
  // Save latest edits first, then download
  saveScript().then(() => {
    window.open(`/api/download-script/${state.scriptId}`, "_blank");
  });
}

// ═══════════════════════════════════════════════════════════
// 5. RUN EXECUTION
// ═══════════════════════════════════════════════════════════
async function runExecution() {
  if (!state.scriptId && !state.scriptContent) {
    toast("Generate a script first.", "error");
    return;
  }

  // Save latest edits before running
  await saveScript();

  const appUrl   = $("appUrl").value.trim();
  const username = $("username").value.trim();
  const password = $("password").value.trim();

  switchTab("execution", qs('[data-tab="execution"]'));
  clearConsole();
  $("testResultsContainer").classList.add("hidden");
  $("testResultsList").innerHTML = "";
  $("testStats").classList.add("hidden");
  $("btnAllureReport").disabled = true;
  $("btnPowerBI").disabled      = true;

  setStatus("Running tests…", "working");
  appendLog({ message: "▶ Sending execution request…", level: "INFO" });

  try {
    const res  = await fetch("/api/run-execution", {
      method:  "POST",
      headers: { "Content-Type": "application/json" },
      body:    JSON.stringify({ script_id: state.scriptId, app_url: appUrl, username, password }),
    });
    const data = await res.json();
    if (!data.success) throw new Error(data.error || "Unknown error");

    state.runId = data.run_id;
    appendLog({ message: `Run ID: ${state.runId}`, level: "DEBUG" });
    openLogStream(state.runId);

  } catch (err) {
    setStatus("Error", "error");
    appendLog({ message: `FATAL: ${err.message}`, level: "ERROR" });
    toast(`Execution failed: ${err.message}`, "error", 5000);
  }
}

// ═══════════════════════════════════════════════════════════
// 6. SSE LOG STREAM
// ═══════════════════════════════════════════════════════════
function openLogStream(runId) {
  if (state.eventSource) { state.eventSource.close(); state.eventSource = null; }

  const es = new EventSource(`/api/stream/${runId}`);
  state.eventSource = es;

  es.onmessage = event => {
    let msg;
    try { msg = JSON.parse(event.data); }
    catch { msg = { message: event.data, level: "INFO" }; }

    appendLog(msg);

    if (msg.level === "DONE") {
      es.close();
      state.eventSource = null;
      onExecutionDone();
    }
  };

  es.onerror = () => {
    es.close();
    state.eventSource = null;
    appendLog({ message: "Log stream disconnected.", level: "WARN" });
  };
}

async function onExecutionDone() {
  setStatus("Execution complete", "success");
  let retries = 12;
  while (retries-- > 0) {
    await sleep(1000);
    try {
      const res  = await fetch(`/api/run-status/${state.runId}`);
      const data = await res.json();
      if (data.results) {
        state.results = data.results;
        renderTestResults(data.results);
        updateReportsTab(data.results);
        $("btnAllureReport").disabled = false;
        $("btnPowerBI").disabled      = false;
        toast(
          data.results.status === "pass"
            ? `✅ All ${data.results.passed} tests passed!`
            : `❌ ${data.results.failed || 0} test(s) failed out of ${data.results.total}.`,
          data.results.status === "pass" ? "success" : "error",
          6000,
        );
        break;
      }
    } catch { /* retry */ }
  }
}

// ─── Console helpers ──────────────────────────────────────
function appendLog(msg) {
  const con = $("console");
  const ph  = con.querySelector(".console-placeholder");
  if (ph) ph.remove();

  const div = document.createElement("div");
  div.className = `log-line ${msg.level || "INFO"}`;
  div.innerHTML = `
    <span class="log-ts">${msg.timestamp || now()}</span>
    <span class="log-msg">${escHtml(msg.message || "")}</span>
  `;
  con.appendChild(div);
  con.scrollTop = con.scrollHeight;
}

function clearConsole() {
  $("console").innerHTML = '<div class="console-placeholder">Execution logs will appear here…</div>';
}

// ─── Test result rows ────────────────────────────────────
function renderTestResults(results) {
  const container = $("testResultsContainer");
  const list      = $("testResultsList");
  const stats     = $("testStats");

  $("statPassed").textContent = `✅ ${results.passed || 0}`;
  $("statFailed").textContent = `❌ ${results.failed || 0}`;
  $("statTotal").textContent  = `📊 ${results.total || 0}`;
  stats.classList.remove("hidden");

  if (!results.tests || !results.tests.length) {
    container.classList.add("hidden");
    return;
  }

  list.innerHTML = results.tests.map(t => `
    <div class="result-row">
      <span class="r-status-badge ${t.status}">${t.status}</span>
      <span class="r-name">${escHtml(t.name)}</span>
      ${t.message ? `<span class="r-message">${escHtml(t.message)}</span>` : ""}
    </div>
  `).join("");

  container.classList.remove("hidden");
}

// ─── Reports tab ─────────────────────────────────────────
function updateReportsTab(results) {
  const rfLinks = $("rfReportLinks");
  rfLinks.innerHTML = "";
  if (results.report_url)
    rfLinks.innerHTML += `<a href="${results.report_url}" target="_blank">📄 Report</a>`;
  if (results.log_url)
    rfLinks.innerHTML += `<a href="${results.log_url}" target="_blank">📝 Log</a>`;

  $("summaryContent").innerHTML = `
    <div class="summary-row"><span>Total</span>  <span class="summary-val">${results.total||0}</span></div>
    <div class="summary-row"><span>Passed</span> <span class="summary-val pass">${results.passed||0}</span></div>
    <div class="summary-row"><span>Failed</span> <span class="summary-val fail">${results.failed||0}</span></div>
    <div class="summary-row"><span>Status</span>
      <span class="summary-val ${results.status==="pass"?"pass":"fail"}">
        ${results.status==="pass"?"✅ PASS":"❌ FAIL"}
      </span>
    </div>`;
}

// ═══════════════════════════════════════════════════════════
// 7. ALLURE REPORT
// ═══════════════════════════════════════════════════════════
async function generateAllureReport() {
  showOverlay("Generating Allure report…");
  try {
    const res  = await fetch("/api/generate-report", { method: "POST" });
    const data = await res.json();
    const links = $("allureReportLinks");
    if (data.success) {
      links.innerHTML = `<a href="${data.report_url}/" target="_blank">🔮 Open Allure Report</a>`;
      toast("Allure report generated!", "success");
    } else {
      links.innerHTML = `<span class="muted">${escHtml(data.message)}</span>`;
      toast(data.message, "error", 6000);
    }
  } catch (err) {
    toast(`Failed: ${err.message}`, "error");
  } finally {
    hideOverlay();
  }
}

// ═══════════════════════════════════════════════════════════
// 8. POWERBI EXPORT
// ═══════════════════════════════════════════════════════════
function exportPowerBI() {
  // Open the beautiful PowerBI-style dashboard in a new tab
  window.open('/api/powerbi-dashboard', '_blank');
  toast('PowerBI Dashboard opened in new tab.', 'success');

  // Also trigger CSV download in background if a run exists
  if (state.runId) {
    fetch(`/api/export-powerbi/${state.runId}`)
      .then(res => {
        if (res.ok) {
          return res.blob().then(blob => {
            const a = document.createElement('a');
            a.href = URL.createObjectURL(blob);
            a.download = `qa_results_${state.runId.substring(0,8)}.csv`;
            document.body.appendChild(a);
            a.click();
            document.body.removeChild(a);
            toast('CSV also downloaded for PowerBI import.', 'info');
          });
        }
      })
      .catch(() => {});
  }
}

// ═══════════════════════════════════════════════════════════
// 9. JIRA
// ═══════════════════════════════════════════════════════════
async function testJiraConnection() {
  const jiraUrl  = $("jiraUrl").value.trim();
  const username = $("jiraUsername").value.trim();
  const token    = $("jiraToken").value.trim();
  if (!jiraUrl || !username || !token) {
    toast("Fill Jira URL, username, and API token.", "error");
    return;
  }
  showOverlay("Testing Jira connection…");
  try {
    const res  = await fetch("/api/jira/test-connection", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body:   JSON.stringify({ jira_url: jiraUrl, username, api_token: token }),
    });
    const data = await res.json();
    const el   = $("jiraStatus");
    el.classList.remove("hidden", "ok", "fail");
    el.classList.add(data.success ? "ok" : "fail");
    el.textContent = data.message || (data.success ? "Connected" : "Failed");
    toast(data.success ? "Jira connected!" : "Connection failed.", data.success ? "success" : "error");
  } catch (err) { toast(`Error: ${err.message}`, "error"); }
  finally { hideOverlay(); }
}

async function fetchJiraTickets() {
  const jiraUrl    = $("jiraUrl").value.trim();
  const username   = $("jiraUsername").value.trim();
  const token      = $("jiraToken").value.trim();
  const projectKey = $("jiraProject").value.trim();
  const apiKey     = $("apiKey").value.trim();
  if (!jiraUrl || !username || !token) {
    toast("Fill Jira credentials first.", "error");
    return;
  }
  showOverlay("Fetching Jira sprint tickets…");
  try {
    const res  = await fetch("/api/jira/fetch-tickets", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body:   JSON.stringify({ jira_url: jiraUrl, username, api_token: token,
                                project_key: projectKey, api_key: apiKey }),
    });
    const data = await res.json();
    if (!data.success) throw new Error(data.error || "Fetch failed");
    renderJiraTickets(data.issues || []);
    toast(`Fetched ${data.count} Done tickets.`, "success");
  } catch (err) { toast(`Jira fetch failed: ${err.message}`, "error", 5000); }
  finally { hideOverlay(); }
}

function renderJiraTickets(tickets) {
  const el = $("jiraTickets");
  if (!tickets.length) {
    el.innerHTML = '<p class="muted">No Done tickets found in current sprint.</p>';
    return;
  }
  el.innerHTML = tickets.map(t => `
    <div class="jira-ticket"
         onclick="useJiraTicket('${escAttr(t.id)}','${escAttr(t.summary)}')">
      <div class="jt-key">${t.id} · ${t.type || "Issue"}</div>
      <div class="jt-summ">${escHtml(t.summary)}</div>
      <div class="jt-meta">${t.priority||""} · ${t.assignee||""}</div>
    </div>
  `).join("");
}

function useJiraTicket(id, summary) {
  $("description").value = `${id}: ${summary}`;
  toast(`Loaded ticket ${id}. Click Generate Scenarios.`, "info");
}

// ═══════════════════════════════════════════════════════════
// UTILITIES
// ═══════════════════════════════════════════════════════════
function sleep(ms) { return new Promise(r => setTimeout(r, ms)); }

function now() {
  return [new Date().getHours(), new Date().getMinutes(), new Date().getSeconds()]
    .map(n => String(n).padStart(2, "0")).join(":");
}

function escHtml(str) {
  return String(str)
    .replace(/&/g, "&amp;").replace(/</g, "&lt;")
    .replace(/>/g, "&gt;").replace(/"/g, "&quot;");
}

function escAttr(str) {
  return String(str).replace(/'/g, "\\'").replace(/"/g, "&quot;");
}
