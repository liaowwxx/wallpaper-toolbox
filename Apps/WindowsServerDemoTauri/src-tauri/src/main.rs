#![cfg_attr(windows, windows_subsystem = "windows")]

use serde::{Deserialize, Serialize};
use serde_json::Value;
use std::{
    collections::BTreeMap,
    env,
    ffi::OsStr,
    fs,
    net::{SocketAddr, UdpSocket},
    path::{Path, PathBuf},
    process::{Child, Command, Stdio},
    sync::Mutex,
};
#[cfg(windows)]
use std::os::windows::process::CommandExt;
use tauri::{AppHandle, Manager, State, WindowEvent};

#[cfg(windows)]
const CREATE_NO_WINDOW: u32 = 0x08000000;

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(default)]
struct ServerConfig {
    python_path: String,
    library_root: String,
    repkg_path: String,
    ffmpeg_path: String,
    api_host: String,
    api_port: u16,
    api_username: String,
    api_password: String,
    public_api_base_url: String,
}

impl Default for ServerConfig {
    fn default() -> Self {
        Self {
            python_path: String::new(),
            library_root: String::new(),
            repkg_path: "RePKG.exe".into(),
            ffmpeg_path: "ffmpeg".into(),
            api_host: "0.0.0.0".into(),
            api_port: 8090,
            api_username: String::new(),
            api_password: String::new(),
            public_api_base_url: "http://localhost:8090".into(),
        }
    }
}

#[derive(Default)]
struct AppState {
    api_process: Mutex<Option<Child>>,
}

#[derive(Serialize)]
struct ProcessState {
    running: bool,
    label: String,
}

#[derive(Serialize)]
struct ProcessStatuses {
    api: ProcessState,
}

#[derive(Debug, Clone, Serialize)]
struct PythonCandidate {
    path: String,
    version: String,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
struct DependencyCheck {
    ok: bool,
    missing: Vec<String>,
    install_command: String,
}

#[tauri::command]
fn load_config(app: AppHandle) -> Result<ServerConfig, String> {
    let path = config_path(&app)?;
    if !path.exists() {
        return Ok(ServerConfig::default());
    }
    let text = fs::read_to_string(path).map_err(|error| error.to_string())?;
    serde_json::from_str(&text).map_err(|error| error.to_string())
}

#[tauri::command]
fn save_config(app: AppHandle, config: ServerConfig) -> Result<String, String> {
    let path = config_path(&app)?;
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent).map_err(|error| error.to_string())?;
    }
    let text = serde_json::to_string_pretty(&config).map_err(|error| error.to_string())?;
    fs::write(&path, text).map_err(|error| error.to_string())?;
    Ok(path.display().to_string())
}

#[tauri::command]
fn choose_directory(initial_value: String) -> Result<String, String> {
    let mut dialog = rfd::FileDialog::new();
    if Path::new(&initial_value).is_dir() {
        dialog = dialog.set_directory(initial_value);
    }
    Ok(dialog
        .pick_folder()
        .map(|path| path.display().to_string())
        .unwrap_or_default())
}

#[tauri::command]
fn choose_executable(initial_value: String) -> Result<String, String> {
    let mut dialog = rfd::FileDialog::new().add_filter("Executable", &["exe"]);
    let initial_path = Path::new(&initial_value);
    if let Some(parent) = initial_path.parent().filter(|parent| parent.is_dir()) {
        dialog = dialog.set_directory(parent);
    }
    Ok(dialog
        .pick_file()
        .map(|path| path.display().to_string())
        .unwrap_or_default())
}

#[tauri::command]
fn recommended_host() -> String {
    let target: SocketAddr = "8.8.8.8:80".parse().expect("valid socket address");
    UdpSocket::bind("0.0.0.0:0")
        .and_then(|socket| {
            socket.connect(target)?;
            socket.local_addr()
        })
        .map(|address| address.ip().to_string())
        .unwrap_or_else(|_| "localhost".into())
}

#[tauri::command]
fn discover_python_environments(app: AppHandle) -> Result<Vec<PythonCandidate>, String> {
    let mut candidates = BTreeMap::<String, PythonCandidate>::new();
    if let Ok(root) = demo_root(&app) {
        for candidate in [
            root.join(".venv").join("Scripts").join("python.exe"),
            root.join(".venv").join("bin").join("python"),
        ] {
            add_python_candidate(&mut candidates, candidate);
        }
    }

    for candidate in discover_py_launcher_paths() {
        add_python_candidate(&mut candidates, candidate);
    }

    for name in ["python", "python3", "py"] {
        if let Ok(paths) = which::which_all(name) {
            for path in paths {
                add_python_candidate(&mut candidates, path);
            }
        }
    }

    Ok(candidates.into_values().collect())
}

#[tauri::command]
fn check_python_dependencies(app: AppHandle, python_path: String) -> Result<DependencyCheck, String> {
    if python_path.trim().is_empty() {
        return Err("Choose a Python environment first.".into());
    }
    let script = r#"
import importlib.util
import json
deps = {
    "fastapi": "fastapi",
    "uvicorn": "uvicorn",
    "Pillow": "PIL",
}
missing = [name for name, module in deps.items() if importlib.util.find_spec(module) is None]
print(json.dumps({"missing": missing}))
"#;
    let output = hidden_command(&python_path)
        .arg("-c")
        .arg(script)
        .output()
        .map_err(|error| format!("Could not run selected Python: {error}"))?;
    if !output.status.success() {
        return Err(String::from_utf8_lossy(&output.stderr).trim().to_string());
    }
    let payload: Value = serde_json::from_slice(&output.stdout).map_err(|error| error.to_string())?;
    let missing = payload
        .get("missing")
        .and_then(Value::as_array)
        .map(|items| {
            items
                .iter()
                .filter_map(Value::as_str)
                .map(str::to_string)
                .collect::<Vec<_>>()
        })
        .unwrap_or_default();
    let requirements = current_project_root(&app)?.join("requirements-tauri.txt");
    Ok(DependencyCheck {
        ok: missing.is_empty(),
        missing,
        install_command: format!(
            "\"{}\" -m pip install -r \"{}\"",
            python_path,
            requirements.display()
        ),
    })
}

#[tauri::command]
fn generate_manifest(app: AppHandle) -> Result<Value, String> {
    run_bridge(&app, "generate-manifest")
}

#[tauri::command]
fn rescan_api(app: AppHandle) -> Result<Value, String> {
    run_bridge(&app, "rescan-api")
}

#[tauri::command]
fn start_api_server(app: AppHandle, state: State<AppState>) -> Result<(), String> {
    let mut guard = state.api_process.lock().map_err(|error| error.to_string())?;
    if child_is_running(guard.as_mut()) {
        return Ok(());
    }
    let config = load_config(app.clone())?;
    let demo_root = demo_root(&app)?;
    let mut command = python_command(&demo_root, &config)?;
    command
        .arg("-m")
        .arg("uvicorn")
        .arg("wallpaper_server_demo.api:app")
        .arg("--host")
        .arg(config.api_host)
        .arg("--port")
        .arg(config.api_port.to_string())
        .current_dir(demo_root)
        .env("WALLPAPER_SERVER_CONFIG", config_path(&app)?)
        .stdin(Stdio::null());
    *guard = Some(command.spawn().map_err(|error| error.to_string())?);
    Ok(())
}

#[tauri::command]
fn stop_api_server(state: State<AppState>) -> Result<(), String> {
    stop_child(&state.api_process)
}

#[tauri::command]
fn process_statuses(state: State<AppState>) -> Result<ProcessStatuses, String> {
    let mut api = state.api_process.lock().map_err(|error| error.to_string())?;
    Ok(ProcessStatuses {
        api: process_state(&mut api),
    })
}

fn run_bridge(app: &AppHandle, command_name: &str) -> Result<Value, String> {
    let demo_root = demo_root(app)?;
    let config = load_config(app.clone())?;
    let output = python_command(&demo_root, &config)?
        .arg("-m")
        .arg("wallpaper_server_demo.tauri_bridge")
        .arg(command_name)
        .arg(config_path(app)?)
        .current_dir(demo_root)
        .output()
        .map_err(|error| error.to_string())?;

    if !output.status.success() {
        return Err(String::from_utf8_lossy(&output.stderr).trim().to_string());
    }
    serde_json::from_slice(&output.stdout).map_err(|error| error.to_string())
}

fn config_path(app: &AppHandle) -> Result<PathBuf, String> {
    let dir = app
        .path()
        .app_config_dir()
        .map_err(|error| error.to_string())?;
    Ok(dir.join("server-config.json"))
}

fn demo_root(app: &AppHandle) -> Result<PathBuf, String> {
    let current = env::current_dir().map_err(|error| error.to_string())?;
    for candidate in [
        current.join("..").join("WindowsServerDemo"),
        current.join("..").join("..").join("WindowsServerDemo"),
        current.join("WindowsServerDemo"),
    ] {
        let candidate = candidate
            .canonicalize()
            .unwrap_or_else(|_| candidate.to_path_buf());
        if candidate.exists() {
            return Ok(candidate);
        }
    }
    let resource_root = app
        .path()
        .resource_dir()
        .map_err(|error| error.to_string())?
        .join("WindowsServerDemo");
    if resource_root.exists() {
        return Ok(resource_root);
    }
    Err("Could not find Apps/WindowsServerDemo next to the Tauri app.".into())
}

fn current_project_root(app: &AppHandle) -> Result<PathBuf, String> {
    let current = env::current_dir().map_err(|error| error.to_string())?;
    for candidate in [current.clone(), current.join("..")] {
        let candidate = candidate
            .canonicalize()
            .unwrap_or_else(|_| candidate.to_path_buf());
        if candidate.join("requirements-tauri.txt").exists() {
            return Ok(candidate);
        }
    }
    app.path()
        .resource_dir()
        .map_err(|error| error.to_string())
}

fn python_command(_demo_root: &Path, config: &ServerConfig) -> Result<Command, String> {
    if config.python_path.trim().is_empty() {
        return Err("Choose a Python environment first.".into());
    }
    Ok(hidden_command(&config.python_path))
}

fn add_python_candidate(candidates: &mut BTreeMap<String, PythonCandidate>, path: PathBuf) {
    let key = path.display().to_string();
    if candidates.contains_key(&key) {
        return;
    }
    if let Some(version) = python_version(&path) {
        candidates.insert(key.clone(), PythonCandidate { path: key, version });
    }
}

fn python_version(path: &Path) -> Option<String> {
    let output = hidden_command(path).arg("--version").output().ok()?;
    if !output.status.success() {
        return None;
    }
    let text = if output.stdout.is_empty() {
        String::from_utf8_lossy(&output.stderr).trim().to_string()
    } else {
        String::from_utf8_lossy(&output.stdout).trim().to_string()
    };
    if text.to_ascii_lowercase().contains("python") {
        Some(text)
    } else {
        None
    }
}

fn discover_py_launcher_paths() -> Vec<PathBuf> {
    let output = hidden_command("py").arg("-0p").output();
    let Ok(output) = output else {
        return Vec::new();
    };
    if !output.status.success() {
        return Vec::new();
    }
    String::from_utf8_lossy(&output.stdout)
        .lines()
        .filter_map(|line| {
            let trimmed = line.trim();
            let drive_marker = trimmed.find(":\\")?;
            let start = drive_marker.saturating_sub(1);
            Some(PathBuf::from(trimmed[start..].trim()))
        })
        .collect()
}

fn hidden_command<S: AsRef<OsStr>>(program: S) -> Command {
    let mut command = Command::new(program);
    hide_command_window(&mut command);
    command
}

fn hide_command_window(command: &mut Command) {
    #[cfg(windows)]
    {
        command.creation_flags(CREATE_NO_WINDOW);
    }
}

fn child_is_running(child: Option<&mut Child>) -> bool {
    child
        .map(|child| child.try_wait().map(|status| status.is_none()).unwrap_or(false))
        .unwrap_or(false)
}

fn stop_child(lock: &Mutex<Option<Child>>) -> Result<(), String> {
    let mut guard = lock.lock().map_err(|error| error.to_string())?;
    if let Some(child) = guard.as_mut() {
        kill_process_tree(child);
        let _ = child.kill();
        let _ = child.wait();
    }
    *guard = None;
    Ok(())
}

fn stop_all_children(state: &AppState) {
    let _ = stop_child(&state.api_process);
}

fn kill_process_tree(child: &Child) {
    #[cfg(windows)]
    {
        let _ = hidden_command("taskkill")
            .arg("/PID")
            .arg(child.id().to_string())
            .arg("/T")
            .arg("/F")
            .stdout(Stdio::null())
            .stderr(Stdio::null())
            .status();
    }
}

fn process_state(slot: &mut Option<Child>) -> ProcessState {
    let mut clear_slot = false;
    let state = match slot.as_mut() {
        None => ProcessState {
            running: false,
            label: "not started".into(),
        },
        Some(child) => match child.try_wait() {
            Ok(None) => ProcessState {
                running: true,
                label: format!("running (pid {})", child.id()),
            },
            Ok(Some(status)) => ProcessState {
                running: false,
                label: format!("exited ({})", status.code().unwrap_or_default()),
            },
            Err(error) => ProcessState {
                running: false,
                label: error.to_string(),
            },
        },
    };
    if !state.running && slot.is_some() {
        clear_slot = true;
    }
    if clear_slot {
        *slot = None;
    }
    state
}

fn main() {
    tauri::Builder::default()
        .manage(AppState::default())
        .on_window_event(|window, event| {
            if matches!(event, WindowEvent::CloseRequested { .. }) {
                let state = window.app_handle().state::<AppState>();
                stop_all_children(&state);
            }
        })
        .invoke_handler(tauri::generate_handler![
            load_config,
            save_config,
            choose_directory,
            choose_executable,
            recommended_host,
            discover_python_environments,
            check_python_dependencies,
            generate_manifest,
            rescan_api,
            start_api_server,
            stop_api_server,
            process_statuses
        ])
        .run(tauri::generate_context!())
        .expect("error while running Tauri application");
}
