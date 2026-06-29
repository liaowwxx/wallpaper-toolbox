import { invoke } from "@tauri-apps/api/core";
import "./styles.css";
import type { ServerConfig, ProcessState } from "./types";

type AppLanguage = "en" | "zh-CN";

type PythonCandidate = {
  path: string;
  version: string;
};

type DependencyCheck = {
  ok: boolean;
  missing: string[];
  installCommand: string;
};

const translations = {
  en: {
    appTitle: "Windows Server",
    statusReady: "Ready",
    configuration: "Configuration",
    save: "Save",
    wallpaperRoot: "Wallpaper library root",
    repkgExecutable: "RePKG executable",
    ffmpegExecutable: "ffmpeg executable",
    apiHost: "API host",
    apiPort: "API port",
    apiUsername: "API username",
    apiPassword: "API password",
    publicApiBaseUrl: "Public API base URL for iOS",
    service: "Service",
    generateManifest: "Generate Manifest",
    startApi: "Start API",
    stopApi: "Stop API",
    rescanApi: "Rescan API",
    apiProcess: "API process",
    iosSettingsUrl: "iOS Settings URL",
    pythonRuntime: "Python Runtime",
    search: "Search",
    selectPython: "Select Python...",
    pythonEnvironment: "Python environment",
    checkDependencies: "Check Dependencies",
    dependenciesInstalled: "Python dependencies are installed.",
    missingDependencies: "Missing",
    runCommand: "Run",
    choosePythonHint: "Choose a Python environment, then check dependencies.",
    noPython: "No Python environment found. Install Python, then click Search.",
    browse: "Browse",
    configurationSaved: "Configuration saved",
    manifestGenerated: "Manifest generated",
    dependenciesChecked: "Python dependencies checked",
    apiStarted: "API started",
    apiStopped: "API stopped",
    apiRescanRequested: "API rescan requested",
    searchingPython: "Searching Python...",
    choosePythonEnvironment: "Choose a Python environment",
    pythonNotFound: "Python was not found",
    working: "Working...",
    notStarted: "not started",
    running: "running",
    exited: "exited",
    language: "Language",
    english: "English",
    simplifiedChinese: "简体中文",
  },
  "zh-CN": {
    appTitle: "Windows 服务器",
    statusReady: "就绪",
    configuration: "配置",
    save: "保存",
    wallpaperRoot: "壁纸库根目录",
    repkgExecutable: "RePKG 可执行文件",
    ffmpegExecutable: "ffmpeg 可执行文件",
    apiHost: "API 主机",
    apiPort: "API 端口",
    apiUsername: "API 用户名",
    apiPassword: "API 密码",
    publicApiBaseUrl: "iOS 使用的公开 API 地址",
    service: "服务",
    generateManifest: "生成清单",
    startApi: "启动 API",
    stopApi: "停止 API",
    rescanApi: "重新扫描 API",
    apiProcess: "API 进程",
    iosSettingsUrl: "iOS 设置地址",
    pythonRuntime: "Python 运行时",
    search: "搜索",
    selectPython: "选择 Python...",
    pythonEnvironment: "Python 环境",
    checkDependencies: "检查依赖",
    dependenciesInstalled: "Python 依赖已安装。",
    missingDependencies: "缺少",
    runCommand: "运行",
    choosePythonHint: "选择 Python 环境后检查依赖。",
    noPython: "未找到 Python 环境。请安装 Python，然后点击搜索。",
    browse: "浏览",
    configurationSaved: "配置已保存",
    manifestGenerated: "清单已生成",
    dependenciesChecked: "Python 依赖检查完成",
    apiStarted: "API 已启动",
    apiStopped: "API 已停止",
    apiRescanRequested: "已请求 API 重新扫描",
    searchingPython: "正在搜索 Python...",
    choosePythonEnvironment: "请选择 Python 环境",
    pythonNotFound: "未找到 Python",
    working: "正在处理...",
    notStarted: "未启动",
    running: "运行中",
    exited: "已退出",
    language: "语言",
    english: "English",
    simplifiedChinese: "简体中文",
  },
} as const;

type TranslationKey = keyof (typeof translations)["en"];

const app = document.querySelector<HTMLDivElement>("#app");
let appLanguage = loadLanguage();

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
};
let statusText: string = t("statusReady");
let busy = false;
let apiStatus: ProcessState = { running: false, label: "not started" };
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
}

function render() {
  appRoot.innerHTML = `
    <main class="shell">
      <section class="topbar">
        <div>
          <p class="eyebrow">Wallpaper Gallery</p>
          <h1>${t("appTitle")}</h1>
        </div>
        <div class="top-actions">
          <label class="language-field">
            <span>${t("language")}</span>
            <select data-language>
              <option value="en" ${appLanguage === "en" ? "selected" : ""}>${t("english")}</option>
              <option value="zh-CN" ${appLanguage === "zh-CN" ? "selected" : ""}>${t("simplifiedChinese")}</option>
            </select>
          </label>
          <div class="status">${escapeHtml(statusText)}</div>
        </div>
      </section>

      <section class="grid">
        <form class="panel" id="config-form">
          <div class="panel-heading">
            <h2>${t("configuration")}</h2>
            <button class="primary" type="submit" ${busy ? "disabled" : ""}>${t("save")}</button>
          </div>
          ${renderPythonPicker()}
          ${pathField(t("wallpaperRoot"), "library_root", "D:\\WallpaperLibrary", "folder")}
          ${pathField(t("repkgExecutable"), "repkg_path", "RePKG.exe", "exe")}
          ${pathField(t("ffmpegExecutable"), "ffmpeg_path", "ffmpeg.exe", "exe")}
          <div class="columns two">
            ${inputField(t("apiHost"), "api_host")}
            ${inputField(t("apiPort"), "api_port", "number")}
          </div>
          <div class="columns two">
            ${inputField(t("apiUsername"), "api_username")}
            ${inputField(t("apiPassword"), "api_password", "password")}
          </div>
          ${inputField(t("publicApiBaseUrl"), "public_api_base_url")}
        </form>

        <aside class="panel service">
          <h2>${t("service")}</h2>
          <div class="actions">
            <button class="primary" data-action="generate" ${busy ? "disabled" : ""}>${t("generateManifest")}</button>
            <button data-action="start-api" ${busy || apiStatus.running ? "disabled" : ""}>${t("startApi")}</button>
            <button data-action="stop-api" ${busy || !apiStatus.running ? "disabled" : ""}>${t("stopApi")}</button>
            <button data-action="rescan" ${busy ? "disabled" : ""}>${t("rescanApi")}</button>
          </div>
          <dl>
            <div><dt>${t("apiProcess")}</dt><dd>${escapeHtml(processLabel(apiStatus))}</dd></div>
            <div><dt>${t("iosSettingsUrl")}</dt><dd>${escapeHtml(publicApiUrl())}</dd></div>
          </dl>
        </aside>
      </section>
    </main>
  `;

  wireEvents();
}

function renderPythonPicker() {
  const options = [
    `<option value="">${t("selectPython")}</option>`,
    ...pythonCandidates.map(
      (candidate) =>
        `<option value="${escapeAttribute(candidate.path)}" ${
          candidate.path === config.python_path ? "selected" : ""
        }>${escapeHtml(candidate.version)} - ${escapeHtml(candidate.path)}</option>`,
    ),
  ].join("");
  const dependencyMessage = dependencyCheck
    ? dependencyCheck.ok
      ? `<p class="hint good">${t("dependenciesInstalled")}</p>`
      : `<p class="hint warn">${t("missingDependencies")}: ${dependencyCheck.missing
          .map(escapeHtml)
          .join(", ")}<br />${t("runCommand")}: <code>${escapeHtml(dependencyCheck.installCommand)}</code></p>`
    : `<p class="hint">${t("choosePythonHint")}</p>`;

  return `
    <div class="python-box">
      <div class="panel-heading compact">
        <h2>${t("pythonRuntime")}</h2>
        <button type="button" data-action="refresh-python" ${busy ? "disabled" : ""}>${t("search")}</button>
      </div>
      ${
        pythonCandidates.length
          ? `<label class="field">
              <span>${t("pythonEnvironment")}</span>
              <select name="python_path">${options}</select>
            </label>`
          : `<p class="hint warn">${t("noPython")}</p>`
      }
      <div class="inline-actions">
        <button type="button" data-action="check-python" ${busy ? "disabled" : ""}>${t("checkDependencies")}</button>
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
        <button type="button" data-browse="${key}" data-kind="${kind}">${t("browse")}</button>
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

function wireEvents() {
  document.querySelector<HTMLSelectElement>("[data-language]")?.addEventListener("change", (event) => {
    const selected = (event.currentTarget as HTMLSelectElement).value;
    if (selected === "en" || selected === "zh-CN") {
      appLanguage = selected;
      localStorage.setItem("wallpaper-server-language", selected);
      statusText = t("statusReady");
      render();
    }
  });

  document.querySelector<HTMLFormElement>("#config-form")?.addEventListener("submit", async (event) => {
    event.preventDefault();
    readForm();
    await run(t("configurationSaved"), () => invoke("save_config", { config }));
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
        await run(t("manifestGenerated"), async () => {
          await invoke("save_config", { config });
          await invoke("generate_manifest");
        });
      }
      if (action === "refresh-python") await refreshPythonCandidates();
      if (action === "check-python") {
        await run(t("dependenciesChecked"), async () => {
          dependencyCheck = await invoke<DependencyCheck>("check_python_dependencies", {
            pythonPath: config.python_path,
          });
        });
      }
      if (action === "start-api") {
        await run(t("apiStarted"), async () => {
          await invoke("save_config", { config });
          await invoke("start_api_server");
        });
      }
      if (action === "stop-api") await run(t("apiStopped"), () => invoke("stop_api_server"));
      if (action === "rescan") {
        await run(t("apiRescanRequested"), async () => {
          await invoke("save_config", { config });
          await invoke("rescan_api");
        });
      }
      await refreshProcesses();
      render();
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
  };
}

async function refreshPythonCandidates(showBusy = true) {
  if (showBusy) {
    busy = true;
    statusText = t("searchingPython");
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
      statusText = t("choosePythonEnvironment");
    } else if (!pythonCandidates.length) {
      statusText = t("pythonNotFound");
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
  statusText = t("working");
  render();
  try {
    await work();
    statusText = success;
  } catch (error) {
    statusText = error instanceof Error ? error.message : String(error);
  } finally {
    busy = false;
    await refreshProcesses();
    render();
  }
}

async function refreshProcesses() {
  const processes = await invoke<{ api: ProcessState }>("process_statuses");
  apiStatus = processes.api;
}

function publicApiUrl() {
  return config.public_api_base_url || `http://localhost:${config.api_port}`;
}

function processLabel(state: ProcessState) {
  if (state.label === "not started") return t("notStarted");
  if (state.label.startsWith("running")) return `${t("running")} ${state.label.replace("running", "").trim()}`;
  if (state.label.startsWith("exited")) return `${t("exited")} ${state.label.replace("exited", "").trim()}`;
  return state.label;
}

function loadLanguage(): AppLanguage {
  const saved = localStorage.getItem("wallpaper-server-language");
  if (saved === "en" || saved === "zh-CN") return saved;
  return navigator.language.toLowerCase().startsWith("zh") ? "zh-CN" : "en";
}

function t(key: TranslationKey): string {
  return translations[appLanguage][key];
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
