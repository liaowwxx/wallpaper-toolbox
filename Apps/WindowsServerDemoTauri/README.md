# Wallpaper Server Tauri

Tauri desktop shell for `Apps/WindowsServerDemo`.

This first pass replaces the Streamlit control panel with a Windows desktop app while keeping the existing Python scanning, thumbnail, RePKG, and FastAPI logic. That keeps the iOS/macOS remote-library protocol unchanged.

The app does not bundle a Python runtime. On launch, use the Python Runtime section to search local Python installs, choose one, and check whether the required packages are installed. If packages are missing, the app shows the exact install command to run.

## Development

Install prerequisites:

- Node.js
- Rust and Cargo (`cargo` must be available in `PATH`)
- Microsoft C++ Build Tools for the Rust MSVC linker
- Python installed on the Windows PC

On a fresh Windows install, the fastest setup path is:

```powershell
winget install --id Rustlang.Rustup -e
winget install --id Microsoft.VisualStudio.2022.BuildTools -e --override "--wait --passive --add Microsoft.VisualStudio.Workload.VCTools --includeRecommended"
```

After installing Rust, close and reopen PowerShell so the updated `PATH` is loaded, then verify:

```powershell
cargo --version
rustc --version
```

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
npm run tauri:release
```

The Windows installer artifacts are copied to the repository root under `release\windows-tauri`.

## Troubleshooting

If `npm run tauri build` fails with this error:

```text
failed to run 'cargo metadata' command ... program not found
```

Rust/Cargo is not installed or the current terminal has not picked up the Rust `PATH`. Install Rust with `winget install --id Rustlang.Rustup -e`, reopen PowerShell, and confirm `cargo --version` works before running the Tauri build again.

## Packaging Note

This version intentionally does not bundle Python. It bundles the existing demo source files and expects the Windows PC to have Python installed. The app guides the user through choosing a Python executable and installing missing packages.
