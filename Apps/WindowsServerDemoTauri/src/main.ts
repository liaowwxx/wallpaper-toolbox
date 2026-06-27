import { convertFileSrc, invoke } from "@tauri-apps/api/core";
import "./styles.css";
import type { PreviewResult, ServerConfig, ProcessState } from "./types";

type PythonCandidate = {
  path: string;
  version: string;
};

type DependencyCheck = {
  ok: boolean;
  missing: string[];
  installCommand: string;
};

const app = document.querySelector<HTMLDivElement>("#app");

let config: ServerConfig = {
  python_path: "",
  library_root: "",
  repkg_path: "RePKG.exe",
  ffmpeg_path: "ffmpeg",
  api_host: "0.0.0.0",
  api_port: 8090,
  api_username: "",
  api_password: "",
  public_api_base_url: "http://localhost:8090",
  public_static_base_url: "",
  miniserve_path: "miniserve.exe",
  miniserve_port: 8080,
  miniserve_auth: "",
};
let preview: PreviewResult | null = null;
let statusText = "Ready";
let busy = false;
let apiStatus: ProcessState = { running: false, label: "not started" };
let miniserveStatus: ProcessState = { running: false, label: "not started" };
let pythonCandidates: PythonCandidate[] = [];
let dependencyCheck: DependencyCheck | null = null;

if (!app) {
  throw new Error("App root was not found.");
}
const appRoot = app;

void bootstrap();

async function bootstrap() {
  config = await invoke<ServerConfig>("load_config");
  if (!config.public_api_base_url) {
    const host = await invoke<string>("recommended_host");
    config.public_api_base_url = `http://${host}:${config.api_port}`;
  }
  await refreshProcesses();
  await refreshPythonCandidates(false);
  render();
  void refreshPreview();
}

function render() {
  appRoot.innerHTML = `
    <main class="shell">
      <section class="topbar">
        <div>
          <p class="eyebrow">Wallpaper Gallery</p>
          <h1>Windows Server</h1>
        </div>
        <div class="status">${escapeHtml(statusText)}</div>
      </section>

      <section class="grid">
        <form class="panel" id="config-form">
          <div class="panel-heading">
            <h2>Configuration</h2>
            <button class="primary" type="submit" ${busy ? "disabled" : ""}>Save</button>
          </div>
          ${renderPythonPicker()}
          ${pathField("Wallpaper library root", "library_root", "D:\\WallpaperLibrary", "folder")}
          ${pathField("RePKG executable", "repkg_path", "RePKG.exe", "exe")}
          ${pathField("miniserve executable", "miniserve_path", "miniserve.exe", "exe")}
          ${pathField("ffmpeg executable", "ffmpeg_path", "ffmpeg.exe", "exe")}
          <div class="columns three">
            ${inputField("API host", "api_host")}
            ${inputField("API port", "api_port", "number")}
            ${inputField("miniserve port", "miniserve_port", "number")}
          </div>
          <div class="columns two">
            ${inputField("API username", "api_username")}
            ${inputField("API password", "api_password", "password")}
          </div>
          ${inputField("Public API base URL for iOS", "public_api_base_url")}
          ${inputField("Public static base URL", "public_static_base_url")}
          ${inputField("miniserve auth user:password", "miniserve_auth")}
        </form>

        <aside class="panel service">
          <h2>Service</h2>
          <div class="actions">
            <button class="primary" data-action="generate" ${busy ? "disabled" : ""}>Generate Manifest</button>
            <button data-action="start-api" ${busy || apiStatus.running ? "disabled" : ""}>Start API</button>
            <button data-action="stop-api" ${busy || !apiStatus.running ? "disabled" : ""}>Stop API</button>
            <button data-action="start-miniserve" ${busy || miniserveStatus.running ? "disabled" : ""}>Start miniserve</button>
            <button data-action="stop-miniserve" ${busy || !miniserveStatus.running ? "disabled" : ""}>Stop miniserve</button>
            <button data-action="rescan" ${busy ? "disabled" : ""}>Rescan API</button>
          </div>
          <dl>
            <div><dt>API process</dt><dd>${escapeHtml(apiStatus.label)}</dd></div>
            <div><dt>miniserve</dt><dd>${escapeHtml(miniserveStatus.label)}</dd></div>
            <div><dt>iOS Settings URL</dt><dd>${escapeHtml(publicApiUrl())}</dd></div>
          </dl>
        </aside>
      </section>

      <section class="panel library">
        <div class="panel-heading">
          <h2>Library Preview</h2>
          <button data-action="refresh-preview" ${busy ? "disabled" : ""}>Refresh</button>
        </div>
        ${renderPreview()}
      </section>
    </main>
  `;

  wireEvents();
}

function renderPythonPicker() {
  const options = [
    `<option value="">Select Python...</option>`,
    ...pythonCandidates.map(
      (candidate) =>
        `<option value="${escapeAttribute(candidate.path)}" ${
          candidate.path === config.python_path ? "selected" : ""
        }>${escapeHtml(candidate.version)} - ${escapeHtml(candidate.path)}</option>`,
    ),
  ].join("");
  const dependencyMessage = dependencyCheck
    ? dependencyCheck.ok
      ? `<p class="hint good">Python dependencies are installed.</p>`
      : `<p class="hint warn">Missing: ${dependencyCheck.missing
          .map(escapeHtml)
          .join(", ")}<br />Run: <code>${escapeHtml(dependencyCheck.installCommand)}</code></p>`
    : `<p class="hint">Choose a Python environment, then check dependencies.</p>`;

  return `
    <div class="python-box">
      <div class="panel-heading compact">
        <h2>Python Runtime</h2>
        <button type="button" data-action="refresh-python" ${busy ? "disabled" : ""}>Search</button>
      </div>
      ${
        pythonCandidates.length
          ? `<label class="field">
              <span>Python environment</span>
              <select name="python_path">${options}</select>
            </label>`
          : `<p class="hint warn">No Python environment found. Install Python, then click Search.</p>`
      }
      <div class="inline-actions">
        <button type="button" data-action="check-python" ${busy ? "disabled" : ""}>Check Dependencies</button>
      </div>
      ${dependencyMessage}
    </div>
  `;
}

function pathField(label: string, key: keyof ServerConfig, placeholder: string, kind: "folder" | "exe") {
  return `
    <label class="field path-field">
      <span>${label}</span>
      <div>
        <input name="${key}" value="${escapeAttribute(String(config[key]))}" placeholder="${placeholder}" />
        <button type="button" data-browse="${key}" data-kind="${kind}">Browse</button>
      </div>
    </label>
  `;
}

function inputField(label: string, key: keyof ServerConfig, type = "text") {
  return `
    <label class="field">
      <span>${label}</span>
      <input name="${key}" type="${type}" value="${escapeAttribute(String(config[key]))}" />
    </label>
  `;
}

function renderPreview() {
  if (!config.library_root) {
    return `<p class="empty">Choose a wallpaper library folder first.</p>`;
  }
  if (!preview) {
    return `<p class="empty">Preview has not been loaded yet.</p>`;
  }
  if (!preview.items.length) {
    return `<p class="empty">No wallpapers found.</p>`;
  }
  return `
    <p class="summary">${preview.count} wallpapers found · ${escapeHtml(preview.manifestPath || "manifest not generated")}</p>
    <div class="cards">
      ${preview.items.map(renderPreviewItem).join("")}
    </div>
  `;
}

function renderPreviewItem(item: PreviewResult["items"][number]) {
  const thumb = item.thumbnailPath
    ? `<img src="${convertFileSrc(item.thumbnailPath)}" alt="" />`
    : `<div class="thumb empty-thumb">No thumbnail</div>`;
  return `
    <article class="card">
      <div class="thumb">${thumb}</div>
      <div>
        <h3>${escapeHtml(item.title)}</h3>
        <p>${escapeHtml(item.id)}</p>
        <div class="chips">
          <span>${escapeHtml(item.type)}</span>
          <span>${item.assetCount} assets</span>
          <span>${item.hasPackage ? "pkg" : "no pkg"}</span>
          <span>${item.isUnpacked ? "unpacked" : "packed"}</span>
        </div>
      </div>
    </article>
  `;
}

function wireEvents() {
  document.querySelector<HTMLFormElement>("#config-form")?.addEventListener("submit", async (event) => {
    event.preventDefault();
    readForm();
    await run("Configuration saved", () => invoke("save_config", { config }));
  });

  document.querySelectorAll<HTMLButtonElement>("[data-browse]").forEach((button) => {
    button.addEventListener("click", async () => {
      const key = button.dataset.browse as keyof ServerConfig;
      const command = button.dataset.kind === "folder" ? "choose_directory" : "choose_executable";
      const selected = await invoke<string>(command, { initialValue: String(config[key] || "") });
      if (selected) {
        config = { ...config, [key]: selected };
        render();
      }
    });
  });

  document.querySelectorAll<HTMLButtonElement>("[data-action]").forEach((button) => {
    button.addEventListener("click", async () => {
      readForm();
      const action = button.dataset.action;
      if (action === "generate") {
        await run("Manifest generated", async () => {
          await invoke("save_config", { config });
          await invoke("generate_manifest");
          await refreshPreview(false);
        });
      }
      if (action === "refresh-python") await refreshPythonCandidates();
      if (action === "check-python") {
        await run("Python dependencies checked", async () => {
          dependencyCheck = await invoke<DependencyCheck>("check_python_dependencies", {
            pythonPath: config.python_path,
          });
        });
      }
      if (action === "start-api") {
        await run("API started", async () => {
          await invoke("save_config", { config });
          await invoke("start_api_server");
        });
      }
      if (action === "stop-api") await run("API stopped", () => invoke("stop_api_server"));
      if (action === "start-miniserve") {
        await run("miniserve started", async () => {
          await invoke("save_config", { config });
          await invoke("start_miniserve");
        });
      }
      if (action === "stop-miniserve") await run("miniserve stopped", () => invoke("stop_miniserve"));
      if (action === "rescan") {
        await run("API rescan requested", async () => {
          await invoke("save_config", { config });
          await invoke("rescan_api");
        });
      }
      if (action === "refresh-preview") {
        await invoke("save_config", { config });
        await refreshPreview();
      }
      await refreshProcesses();
    });
  });
}

function readForm() {
  const form = document.querySelector<HTMLFormElement>("#config-form");
  if (!form) return;
  const data = new FormData(form);
  config = {
    python_path: textValue(data, "python_path"),
    library_root: textValue(data, "library_root"),
    repkg_path: textValue(data, "repkg_path") || "RePKG.exe",
    ffmpeg_path: textValue(data, "ffmpeg_path") || "ffmpeg",
    api_host: textValue(data, "api_host") || "0.0.0.0",
    api_port: numberValue(data, "api_port", 8090),
    api_username: textValue(data, "api_username"),
    api_password: textValue(data, "api_password"),
    public_api_base_url: textValue(data, "public_api_base_url").replace(/\/+$/, ""),
    public_static_base_url: textValue(data, "public_static_base_url").replace(/\/+$/, ""),
    miniserve_path: textValue(data, "miniserve_path") || "miniserve.exe",
    miniserve_port: numberValue(data, "miniserve_port", 8080),
    miniserve_auth: textValue(data, "miniserve_auth"),
  };
}

async function refreshPythonCandidates(showBusy = true) {
  if (showBusy) {
    busy = true;
    statusText = "Searching Python...";
    render();
  }
  try {
    pythonCandidates = await invoke<PythonCandidate[]>("discover_python_environments");
    if (!config.python_path && pythonCandidates.length === 1) {
      config.python_path = pythonCandidates[0].path;
      dependencyCheck = await invoke<DependencyCheck>("check_python_dependencies", {
        pythonPath: config.python_path,
      });
    }
    if (!config.python_path && pythonCandidates.length > 1) {
      statusText = "Choose a Python environment";
    } else if (!pythonCandidates.length) {
      statusText = "Python was not found";
    }
  } catch (error) {
    statusText = error instanceof Error ? error.message : String(error);
  } finally {
    busy = false;
    render();
  }
}

async function run(success: string, work: () => Promise<unknown>) {
  busy = true;
  statusText = "Working...";
  render();
  try {
    await work();
    statusText = success;
  } catch (error) {
    statusText = error instanceof Error ? error.message : String(error);
  } finally {
    busy = false;
    render();
  }
}

async function refreshPreview(showBusy = true) {
  if (!config.library_root) return;
  if (showBusy) {
    busy = true;
    statusText = "Loading preview...";
    render();
  }
  try {
    preview = await invoke<PreviewResult>("scan_preview");
    statusText = "Preview loaded";
  } catch (error) {
    statusText = error instanceof Error ? error.message : String(error);
  } finally {
    busy = false;
    render();
  }
}

async function refreshProcesses() {
  const processes = await invoke<{ api: ProcessState; miniserve: ProcessState }>("process_statuses");
  apiStatus = processes.api;
  miniserveStatus = processes.miniserve;
}

function publicApiUrl() {
  return config.public_api_base_url || `http://localhost:${config.api_port}`;
}

function textValue(data: FormData, key: string) {
  return String(data.get(key) || "").trim();
}

function numberValue(data: FormData, key: string, fallback: number) {
  const value = Number(data.get(key));
  return Number.isFinite(value) ? value : fallback;
}

function escapeHtml(value: string) {
  return value.replace(/[&<>"']/g, (character) => {
    const map: Record<string, string> = { "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#039;" };
    return map[character];
  });
}

function escapeAttribute(value: string) {
  return escapeHtml(value);
}
