"use strict";

const elements = Object.fromEntries([
  "dump-directory", "version", "compare-version", "use-exceptions", "scan-button",
  "selection-panel", "scan-summary", "select-all", "selected-summary", "pair-list",
  "incomplete-box", "build-button", "result-panel", "result-summary", "directory-grid",
  "result-list", "storage-paths", "activity", "activity-text", "server-status"
  , "preview-version", "preview-character", "preview-search", "preview-load",
  "preview-source-chain", "preview-tabs", "preview-meta", "preview-head", "preview-body"
].map(id => [id, document.getElementById(id)]));

let scanResult = null;
let previewResult = null;
let previewKind = "ac";

async function api(path, options) {
  const response = await fetch(path, options);
  const value = await response.json();
  if (!response.ok) throw new Error(value.error || `HTTP ${response.status}`);
  return value;
}

function post(path, value) {
  return api(path, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(value)
  });
}

function busy(active, text) {
  elements.activity.classList.toggle("hidden", !active);
  elements["activity-text"].textContent = text || "处理中…";
  elements["scan-button"].disabled = active;
  elements["build-button"].disabled = active;
  elements["preview-load"].disabled = active;
}

function formatBytes(bytes) {
  if (bytes < 1024) return `${bytes} B`;
  if (bytes < 1024 ** 2) return `${(bytes / 1024).toFixed(1)} KB`;
  return `${(bytes / 1024 ** 2).toFixed(1)} MB`;
}

function checkedStems() {
  return [...document.querySelectorAll(".pair-check:checked")].map(input => input.value);
}

function updateSelected() {
  const selected = checkedStems().length;
  const total = scanResult ? scanResult.pairs.length : 0;
  elements["selected-summary"].textContent = `已选择 ${selected} / ${total}`;
  elements["select-all"].checked = total > 0 && selected === total;
  elements["select-all"].indeterminate = selected > 0 && selected < total;
}

function renderPairs(result) {
  elements["pair-list"].replaceChildren();
  for (const pair of result.pairs) {
    const row = document.createElement("label");
    row.className = "pair-row";
    const checkbox = document.createElement("input");
    checkbox.type = "checkbox";
    checkbox.className = "pair-check";
    checkbox.value = pair.stem;
    checkbox.checked = true;
    checkbox.addEventListener("change", updateSelected);
    const stem = document.createElement("span"); stem.className = "pair-stem"; stem.textContent = pair.stem;
    const ac = document.createElement("span"); ac.className = "filename"; ac.textContent = pair.ac;
    const bcm = document.createElement("span"); bcm.className = "filename"; bcm.textContent = pair.bcm;
    const bytes = document.createElement("span"); bytes.className = "bytes"; bytes.textContent = formatBytes(pair.total_bytes);
    row.append(checkbox, stem, ac, bcm, bytes);
    elements["pair-list"].append(row);
  }
  elements["incomplete-box"].classList.toggle("hidden", result.incomplete.length === 0);
  elements["incomplete-box"].textContent = result.incomplete.length
    ? `未参与构建的不完整配对：${result.incomplete.map(item => `${item.stem}（缺 ${item.missing.join("+")}）`).join("；")}` : "";
  elements["scan-summary"].textContent = `找到 ${result.pairs.length} 个完整配对，${result.incomplete.length} 个不完整配对。`;
  elements["selection-panel"].classList.remove("hidden");
  updateSelected();
}

function metric(label, value) {
  const span = document.createElement("span");
  span.className = `metric${Number(value) ? " changed" : ""}`;
  span.textContent = `${label} ${value}`;
  return span;
}

function renderResults(result) {
  const mode = result.archive_mode === "merged" ? "已合并/覆盖" : "已新建";
  elements["result-summary"].textContent = `版本 ${result.version} ${mode} ${result.characters.length} 个本次所选角色。`;
  const directories = [
    ["AC+BCM 原始归档", result.raw_archive, "acbcm"],
    ["OFF 官网语义快照", result.official_archive, "off"],
    ["角色简表与报告", result.character_archive, "char"],
    ["v2 运行时（内部）", result.latest, "latest"],
    ["可同步角色例外表", result.latest_exceptions, "latest_exceptions"],
    ["可同步现代显示表", result.latest_modern, "latest_modern"]
  ];
  elements["directory-grid"].replaceChildren();
  for (const [label, directory, kind] of directories) {
    const card = document.createElement("div"); card.className = "directory-card";
    const title = document.createElement("strong"); title.textContent = label;
    const code = document.createElement("code"); code.textContent = directory;
    const button = document.createElement("button"); button.className = "ghost"; button.textContent = "打开目录";
    button.addEventListener("click", () => openFolder(kind));
    card.append(title, code, button);
    elements["directory-grid"].append(card);
  }

  elements["result-list"].replaceChildren();
  const differenceByCharacter = new Map(result.differences.map(item => [item.character, item]));
  for (const entry of result.characters) {
    const difference = differenceByCharacter.get(entry.character);
    const card = document.createElement("article"); card.className = "result-card";
    const head = document.createElement("div"); head.className = "result-head";
    const content = document.createElement("div");
    const name = document.createElement("div"); name.className = "result-name";
    const h3 = document.createElement("h3"); h3.textContent = entry.character;
    const badge = document.createElement("span");
    badge.className = `badge ${entry.status === "valid" ? "valid" : entry.status === "valid-with-warnings" ? "warning" : "invalid"}`;
    badge.textContent = entry.status;
    name.append(h3, badge);
    const metrics = document.createElement("div"); metrics.className = "metrics";
    const s = difference.summary;
    metrics.append(
      metric("AC源", s.ac_source_changed ? 1 : 0), metric("BCM源", s.bcm_source_changed ? 1 : 0),
      metric("指令 +", s.displays_added), metric("指令 -", s.displays_removed), metric("指令改", s.displays_changed),
      metric("别名 +", s.aliases_added), metric("别名 -", s.aliases_removed), metric("别名改", s.aliases_changed),
      metric("TC +", s.target_combos_added), metric("TC -", s.target_combos_removed),
      metric("验证改", s.validation_changed),
      metric("现代 +", s.modern_displays_added || 0),
      metric("现代 -", s.modern_displays_removed || 0),
      metric("现代改", s.modern_displays_changed || 0),
      metric("旧表缺项", entry.compatibility?.missing_action_count || 0),
      metric("兼容兜底", entry.compatibility?.fallback_entry_count || 0),
      metric("现代映射", entry.modern_display_action_count || 0)
    );
    content.append(name, metrics);
    const latest = document.createElement("span");
    latest.className = `badge ${entry.latest_updated ? "valid" : "warning"}`;
    latest.textContent = entry.latest_updated ? "latest 已更新" : "latest 未更新";
    head.append(content, latest);
    const details = document.createElement("details");
    const summary = document.createElement("summary");
    summary.textContent = difference.baseline
      ? "首次归档（无基准版本）"
      : difference.comparison_mode === "same-version-before-overwrite"
        ? `查看相对 ${difference.previous_version} 覆盖前内容的完整差异`
        : `查看相对 ${difference.previous_version} 的完整差异`;
    const pre = document.createElement("pre"); pre.textContent = JSON.stringify(difference, null, 2);
    details.append(summary, pre);
    card.append(head, details);
    elements["result-list"].append(card);
  }
  elements["result-panel"].classList.remove("hidden");
  elements["result-panel"].scrollIntoView({ behavior: "smooth", block: "start" });
}

async function openFolder(kind) {
  try { await post("/api/open-folder", { kind }); }
  catch (error) { alert(error.message); }
}

function renderStorage(state) {
  elements["storage-paths"].replaceChildren();
  for (const [kind, directory] of Object.entries(state.directories)) {
    const row = document.createElement("div"); row.className = "storage-row";
    const label = document.createElement("span"); label.textContent = kind;
    const code = document.createElement("code"); code.textContent = directory;
    const button = document.createElement("button"); button.className = "ghost"; button.textContent = "打开";
    button.addEventListener("click", () => openFolder(kind));
    row.append(label, code, button);
    elements["storage-paths"].append(row);
  }
  const select = elements["compare-version"];
  select.replaceChildren(new Option("自动选择最近归档", ""));
  for (const item of state.versions) {
    select.append(new Option(`${item.version} · ${item.character_count} 角色`, item.version));
  }

  const previewVersion = elements["preview-version"];
  const previousPreviewVersion = previewVersion.value;
  previewVersion.replaceChildren(new Option("请选择版本", ""));
  for (const item of state.versions) {
    previewVersion.append(new Option(`${item.version} · ${item.character_count} 角色`, item.version));
  }
  if (state.versions.some(item => item.version === previousPreviewVersion)) previewVersion.value = previousPreviewVersion;
}

function cellText(value) {
  if (value === null || value === undefined || value === "") return "—";
  if (Array.isArray(value)) return value.join("\n");
  if (typeof value === "object") return JSON.stringify(value);
  return String(value);
}

function profileText(profile) {
  if (!profile || !profile.enabled) return "—";
  const flags = [`cmd=${profile.command_no}`, `idx=${profile.command_index}`, `key=0x${Number(profile.ok_key_flags || 0).toString(16)}`];
  return `${profile.notation || "Normal"}${profile.button && !String(profile.notation || "").includes(profile.button) ? ` + ${profile.button}` : ""}\n${flags.join(" · ")}`;
}

function previewSchema(kind) {
  if (kind === "ac") return [
    ["Action ID", row => row.action_id], ["Scope", row => row.source_scope], ["Style", row => row.style_index],
    ["Frame", row => row.frame], ["Main / Follow / Margin", row => `${cellText(row.main_frame)} / ${cellText(row.follow_frame)} / ${cellText(row.margin_frame)}`],
    ["对象引用", row => row.references], ["详情", row => row.details, true]
  ];
  if (kind === "bcm") return [
    ["Action ID", row => row.action_id], ["Trigger", row => row.trigger_index], ["Classic", row => row.classic_display],
    ["norm", row => profileText(row.norm)], ["easy", row => profileText(row.easy)],
    ["sprt", row => profileText(row.sprt)], ["supr", row => profileText(row.supr)],
    ["条件", row => row.conditions, true]
  ];
  if (kind === "official") return [
    ["官网 ID/行", row => row.official_action_id ?? row.key], ["招式名", row => row.move_name], ["分类", row => row.category],
    ["Classic", row => row.classic_display], ["Modern", row => row.modern_display], ["支持", row => row.control_support], ["备注", row => row.note]
  ];
  return [
    ["Action ID", row => row.action_id], ["Modern 显示", row => row.modern_display], ["归属", row => row.ownership],
    ["来源", row => row.source], ["路线数", row => row.routes.length], ["路线证据", row => row.routes, true]
  ];
}

function previewRows() {
  return previewResult && previewResult[previewKind] && previewResult[previewKind].rows || [];
}

function renderPreviewTable() {
  const schema = previewSchema(previewKind);
  const query = elements["preview-search"].value.trim().toLocaleLowerCase();
  const rows = previewRows().filter(row => !query || JSON.stringify(row).toLocaleLowerCase().includes(query));
  elements["preview-head"].replaceChildren();
  const headerRow = document.createElement("tr");
  for (const [label] of schema) { const th = document.createElement("th"); th.textContent = label; headerRow.append(th); }
  elements["preview-head"].append(headerRow);
  elements["preview-body"].replaceChildren();
  if (!rows.length) {
    const tr = document.createElement("tr"), td = document.createElement("td");
    td.className = "empty-cell"; td.colSpan = schema.length; td.textContent = previewResult ? "没有匹配的数据。" : "请选择归档版本和角色。";
    tr.append(td); elements["preview-body"].append(tr);
  } else {
    for (const row of rows) {
      const tr = document.createElement("tr");
      for (const [, getter, detail] of schema) {
        const td = document.createElement("td"), value = getter(row);
        if (detail) {
          const details = document.createElement("details"), summary = document.createElement("summary"), pre = document.createElement("pre");
          summary.textContent = "展开 JSON"; pre.textContent = JSON.stringify(value, null, 2); details.append(summary, pre); td.append(details);
        } else td.textContent = cellText(value);
        tr.append(td);
      }
      elements["preview-body"].append(tr);
    }
  }
  const total = previewRows().length;
  elements["preview-meta"].textContent = `${previewKind.toUpperCase()}：显示 ${rows.length} / ${total} 行${query ? `，过滤词“${elements["preview-search"].value.trim()}”` : ""}。`;
}

function fileLine(label, file) {
  return file ? `${label}: ${file.name}` : `${label}: 缺失`;
}

function renderPreview(result) {
  previewResult = result;
  elements["preview-source-chain"].replaceChildren();
  const title = document.createElement("strong"); title.textContent = `${result.version} / ${result.character} / Fighter ${result.fighter_id}`;
  const code = document.createElement("code");
  code.textContent = [fileLine("AC", result.files.ac), fileLine("BCM", result.files.bcm), fileLine("OFF原始", result.files.official_raw), fileLine("OFF语义", result.files.official), fileLine("Modern", result.files.modern)].join("  →  ");
  const paths = document.createElement("small");
  paths.textContent = `AC+BCM stem: ${result.stem}；OFF 与输出使用规范角色名 ${result.character}`;
  elements["preview-source-chain"].append(title, code, paths);
  renderPreviewTable();
}

async function loadPreviewIndex() {
  const version = elements["preview-version"].value;
  elements["preview-character"].replaceChildren(new Option(version ? "正在读取…" : "请先选择版本", ""));
  if (!version) return;
  try {
    const index = await post("/api/preview-index", { version });
    elements["preview-character"].replaceChildren(new Option("请选择角色", ""));
    for (const item of index.characters) {
      const status = `${item.ac_file && item.bcm_file ? "AC+BCM" : "源缺失"} / ${item.official_file ? "OFF" : "无OFF"} / ${item.modern_file ? "Modern" : "无输出"}`;
      elements["preview-character"].append(new Option(`${item.character} · ${status}`, item.character));
    }
    elements["preview-source-chain"].textContent = `原始归档：${index.raw_directory}；OFF：${index.official_directory}；输出：${index.character_directory}`;
  } catch (error) { alert(error.message); }
}

elements["select-all"].addEventListener("change", event => {
  document.querySelectorAll(".pair-check").forEach(input => { input.checked = event.target.checked; });
  updateSelected();
});

elements["scan-button"].addEventListener("click", async () => {
  const directory = elements["dump-directory"].value.trim();
  if (!directory) return alert("请填写 dump 目录。");
  localStorage.setItem("sf6cc-acbcm-dump-directory", directory);
  elements["result-panel"].classList.add("hidden");
  busy(true, "正在扫描 AC+BCM 文件…");
  try {
    scanResult = await post("/api/scan", { dump_directory: directory });
    if (!elements.version.value.trim()) {
      const suggestedVersion = directory.replace(/[\\/]+$/, "").split(/[\\/]/).pop();
      if (suggestedVersion) elements.version.value = suggestedVersion;
    }
    renderPairs(scanResult);
  } catch (error) { alert(error.message); }
  finally { busy(false); }
});

elements["build-button"].addEventListener("click", async () => {
  const version = elements.version.value.trim();
  const stems = checkedStems();
  if (!version) return alert("请填写本次版本。");
  if (!stems.length) return alert("至少选择一个完整角色配对。");
  busy(true, `正在编译并归档 ${stems.length} 个角色；大批量 dump 可能需要数分钟…`);
  try {
    const result = await post("/api/build", {
      dump_directory: elements["dump-directory"].value.trim(),
      version,
      compare_version: elements["compare-version"].value || null,
      use_exceptions: elements["use-exceptions"].checked,
      stems
    });
    renderResults(result);
    renderStorage(await api("/api/state"));
  } catch (error) { alert(error.message); }
  finally { busy(false); }
});

elements["preview-version"].addEventListener("change", loadPreviewIndex);
elements["preview-search"].addEventListener("input", renderPreviewTable);
elements["preview-tabs"].addEventListener("click", event => {
  const button = event.target.closest("[data-kind]");
  if (!button) return;
  previewKind = button.dataset.kind;
  document.querySelectorAll(".preview-tab").forEach(tab => tab.classList.toggle("active", tab === button));
  renderPreviewTable();
});
elements["preview-load"].addEventListener("click", async () => {
  const version = elements["preview-version"].value, character = elements["preview-character"].value;
  if (!version || !character) return alert("请选择归档版本和角色。");
  busy(true, `正在解析 ${version} / ${character} 的 AC、BCM 与 OFF…`);
  try { renderPreview(await post("/api/preview", { version, character })); }
  catch (error) { alert(error.message); }
  finally { busy(false); }
});

(async function initialize() {
  elements["dump-directory"].value = localStorage.getItem("sf6cc-acbcm-dump-directory") || "";
  try { renderStorage(await api("/api/state")); }
  catch (error) {
    elements["server-status"].textContent = "本地服务异常";
    elements["server-status"].style.color = "var(--red)";
    alert(error.message);
  }
})();
