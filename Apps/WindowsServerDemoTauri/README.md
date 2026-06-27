# Wallpaper Server Tauri

Tauri desktop shell for `Apps/WindowsServerDemo`.

This first pass replaces the Streamlit control panel with a Windows desktop app while keeping the existing Python scanning, thumbnail, RePKG, and FastAPI logic. That keeps the iOS/macOS remote-library protocol unchanged.

The app does not bundle a Python runtime. On launch, use the Python Runtime section to search local Python installs, choose one, and check whether the required packages are installed. If packages are missing, the app shows the exact install command to run.

## Development

Install prerequisites:

- Node.js
- Rust and Cargo
- Python installed on the Windows PC

```powershell
cd Apps\WindowsServerDemoTauri
npm install
npm run tauri dev
```

After the desktop app opens, choose a Python environment and click `Check Dependencies`. If dependencies are missing, run the command shown in the app, then check again.

## Build exe

```powershell
cd Apps\WindowsServerDemoTauri
npm install
npm run tauri build
```

The Windows installer/exe artifacts are written under `src-tauri\target\release\bundle`.

## Packaging Note

This version intentionally does not bundle Python. It bundles the existing demo source files and expects the Windows PC to have Python installed. The app guides the user through choosing a Python executable and installing missing packages.
