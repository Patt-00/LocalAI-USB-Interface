# LocalAI USB

Portable, offline local AI for Windows, macOS, Linux, and ARM64 Android. The
same GGUF model is shared by every platform; each operating system uses its own
llama.cpp runtime.

> The model is not included in this repository. Add your own compatible GGUF
> to `LocalAI/models/` before starting LocalAI.

## What is included

- Offline llama.cpp web interface with local coding-agent tools
- Windows x64 and ARM64 runtimes
- macOS Apple Silicon and Intel runtimes
- Linux x64 and ARM64 CPU/Vulkan runtimes
- Android ARM64 runtime and Termux agent bridge
- Automatic GGUF model selection
- Configurable context size and desktop GPU acceleration
- Desktop and Android start/stop launchers
- llama.cpp build **b10516**

No account or cloud API is required. The local interface listens only on
`127.0.0.1`.

## Contents

- [Add a model](#add-a-model)
- [Windows](#windows)
- [macOS](#macos)
- [Linux](#linux)
- [Redmi and Android with Termux](#redmi-and-android-with-termux)
- [Agent tools and permissions](#agent-tools-and-permissions)
- [Model features](#model-features)
- [Privacy and safety](#privacy-and-safety)

## Add a model

Place one or more llama.cpp-compatible GGUF files in:

```text
LocalAI/models/
```

Do not create separate model copies for Windows, macOS, Linux, or Android.

When there is one primary GGUF, it is selected automatically. When there are
several, write the preferred filename or relative path on the first line of:

```text
LocalAI/models/default-model.txt
```

Example:

```text
qwen3-8b-q4_K_M.gguf
```

If the preference is missing or stale, the launchers select another usable
primary GGUF. Files beginning with `mmproj` and secondary split-model shards
are not selected as the main model.

For a vision model, place its matching `mmproj` file beside the main GGUF.

## Windows

1. Connect the USB.
2. Open the USB in File Explorer.
3. Double-click `START AI.bat`.
4. Wait for `LOCAL AI READY` and the browser to open.
5. Chat at the local page. No API key is required.
6. Before ejecting the USB, double-click `STOP AI.bat`.

The launcher selects Windows x64 or ARM64 automatically. GPU acceleration can
be changed with the included GPU settings launcher. CPU mode remains available
for maximum compatibility.

For terminal chat, run `LocalCLI.bat`.

## macOS

1. Connect the USB.
2. Open `START AI.command`.
3. Wait for `LOCAL AI READY` and the browser to open.
4. Before ejecting, run `STOP AI.command`.

If macOS blocks the launcher, use Finder's **Open** action or allow it through
the normal Privacy & Security prompt. Do not disable or bypass Gatekeeper.

For terminal chat, run `LocalCLI.command`.

## Linux

From a terminal in the USB root, run:

```bash
bash "START AI.sh"
```

Stop it before ejecting:

```bash
bash "STOP AI.sh"
```

For terminal chat:

```bash
bash LocalCLI.sh
```

The launcher handles exFAT executable-bit limitations and reads the model
directly from the USB.

# Redmi and Android with Termux

This section is the complete user guide for Redmi/HyperOS and other compatible
ARM64 Android devices. A plain Android phone cannot execute the Windows, macOS,
or ordinary Linux launchers.

The detailed offline text copy is also available as
[`ANDROID REDMI GUIDE.txt`](ANDROID%20REDMI%20GUIDE.txt).

## Android requirements

- ARM64 Android device; `uname -m` in Termux must show `aarch64` or `arm64`
- USB OTG support and a reliable adapter
- Ability to read the exFAT USB
- At least 8 GB RAM; 12 GB or more is preferred for an 8B Q4 model
- Several hundred MB of free internal storage
- Termux from the official [F-Droid package](https://f-droid.org/packages/com.termux/)
  or [Termux GitHub project](https://github.com/termux/termux-app)
- No root is required

The small Android runtime, agent bridge, and web interface use approximately
123 MB in Termux-private storage. The multi-gigabyte GGUF remains on the USB.

## If Android asks to format the USB

Press **Cancel**. Never format, erase, or adopt the LocalAI USB as internal
storage.

Try these steps:

1. Disconnect and reconnect the OTG adapter while the Redmi is unlocked.
2. Open the Xiaomi/Android Files app and look for the USB.
3. Try another known-good OTG adapter or powered hub.
4. Restart the phone and reconnect the USB.
5. Test the USB on a computer to confirm that its files remain readable.

## One-time Termux preparation

Open Termux and run these commands while online:

```bash
pkg update
pkg install curl
termux-setup-storage
```

Approve the Files/Media permission. On Redmi/HyperOS, settings are commonly
under:

```text
Settings > Apps > Manage apps > Termux > App permissions > Files and media
Settings > Apps > Manage apps > Termux > Battery saver > No restrictions
```

Menu names vary by HyperOS version. After changing permissions, close and
reopen Termux.

Confirm the architecture:

```bash
uname -m
```

Continue only if the result is `aarch64` or `arm64`.

## Find the USB path

Android usually identifies a removable volume with an ID such as `1234-ABCD`,
not the USB label. Do not type `XXXX-XXXX` literally.

Run:

```bash
ls -la /storage
find /storage -maxdepth 4 -type f -iname '*.gguf' 2>/dev/null
```

A working result resembles:

```text
/storage/1234-ABCD/LocalAI/models/qwen3-8b-q4_K_M.gguf
```

The USB root in that example is `/storage/1234-ABCD`.

Some devices also expose `/mnt/media_rw/ID`, but permission denied there is
normal on many non-rooted phones. Prefer a readable `/storage/ID` path.

## Install LocalAI into Termux

Replace `1234-ABCD` with the actual ID shown on the Redmi:

```bash
bash "/storage/1234-ABCD/LocalAI/android/setup-termux.sh"
```

Successful setup reports:

```text
LocalAI Termux runtime and agent bridge installed.
The GGUF model was NOT copied; it remains on the USB.
Start with: ~/localai-start
```

Confirm the commands were installed:

```bash
ls -l ~/localai-start ~/localai-stop
```

### Setup-script fallback

Android external storage is mounted `noexec`, so invoke the installer with
`bash`; do not run `./setup-termux.sh`.

If Termux can read the GGUF but cannot read the setup script directly, use the
Android Files app to create this temporary folder under Internal storage >
Download:

```text
LocalAI-Setup/
  LocalAI/
    android/              from USB LocalAI/android
    android-arm64/        from USB LocalAI/android-arm64
    web/                  from USB LocalAI/web
    runtime/
      model-selection.sh  from USB LocalAI/runtime/model-selection.sh
```

Then run:

```bash
bash ~/storage/downloads/LocalAI-Setup/LocalAI/android/setup-termux.sh
```

This temporary setup copy is approximately 123 MB and does not contain the
model. If Termux cannot read the GGUF itself, this fallback cannot bypass that
Android permission limitation.

## Normal Android use

Every time you use LocalAI:

1. Connect the USB and confirm it appears in the Files app.
2. Open Termux.
3. Run:

   ```bash
   ~/localai-start
   ```

4. Keep Termux running while the model loads.
5. Wait for `LOCAL AI READY`.
6. Use the browser page opened automatically.
7. Before unplugging the USB, run:

   ```bash
   ~/localai-stop
   ```

Wait for `It is safe to disconnect the USB` before removing it.

Use `~/localai-start` so the model and bridge are ready before the browser opens.
It now opens a normal localhost page without an API key or authenticated link.

## Select a specific Android model

Automatic selection normally requires no command-line argument. To select one
model for the current start:

```bash
~/localai-start "/storage/1234-ABCD/LocalAI/models/model-name.gguf"
```

Stop LocalAI before replacing, renaming, or removing a model file.

## Android context size

- 4096 tokens is the safest default for an 8B Q4 model.
- 8192 may work on a 12 GB Redmi, but consumes more RAM and may be slower.
- Close memory-heavy apps before loading the model.

Change context under **Settings > General > Context size** in the web
interface, then restart LocalAI. It can also be set in Termux:

```bash
printf '%s\n' 4096 > ~/.localai-usb-context-size
```

## Android performance

- The Android launcher uses the ARM64 CPU runtime for compatibility.
- Set Termux battery usage to **No restrictions** in HyperOS.
- Do not swipe Termux away while generating.
- Lock Termux in Recent apps if HyperOS offers that option.
- Long generations can heat the phone and cause thermal throttling.
- A powered OTG hub may help if the USB connection is unstable.
- Shorter prompts, responses, and 4096 context use less RAM.

## Android troubleshooting

### `No such file or directory`

Find the real volume ID again:

```bash
find /storage -maxdepth 4 -type f -iname '*.gguf' 2>/dev/null
```

Quote the complete path and do not type the example ID literally.

### `Permission denied`

Run `termux-setup-storage`, grant Files/Media permission in HyperOS, fully close
and reopen Termux, then retry. Invoke external scripts with `bash`.

### `Termux cannot find a readable primary GGUF`

Confirm the Files app sees the USB and the model is in `LocalAI/models/`. If
the `find` command returns nothing, Android is not granting Termux direct USB
access. The launcher will not silently copy the model. Some Android builds make
USB files available only through the Storage Access Framework used by file
managers; ordinary Termux commands cannot bypass that restriction.

### White screen, HTTP 403, 404, or Access Denied

Close stale LocalAI tabs and run:

```bash
~/localai-start
```

If LocalAI is already running, this reopens the local page.

Check the local bridge:

```bash
curl -s http://127.0.0.1:8080/api/status
```

Port 8080 is the loopback-only interface. Port 8081 is the private llama-server
behind it and is not the chat website. Neither requires an API key.

### Model fails to load or Android closes Termux

Use 4096 context, close other apps, enable **No restrictions** for Termux, and
verify that the selected model fits available RAM.

Check the logs:

```bash
tail -n 60 ~/.localai-usb/agent-bridge.log
tail -n 80 ~/.localai-usb/llama-server.log
```

Then safely retry:

```bash
~/localai-stop
~/localai-start
```

### Model writes JSON instead of using a tool

Enable the required tools in the chat and use an instruct model with reliable
tool/function-call behavior. Small, base, or incompatible models may ignore
tools even when the interface offers them. Start a new chat after changing the
model.

## Update the Android runtime

After updating the USB files:

1. Run `~/localai-stop`.
2. Reconnect the updated USB.
3. Run the setup script again from its current `/storage/ID` path.

This refreshes the runtime, bridge, model selector, web UI, and launchers. It
does not copy or modify the GGUF.

## Android command reference

| Action | Command |
|---|---|
| Grant storage access | `termux-setup-storage` |
| Find models on USB | `find /storage -maxdepth 4 -type f -iname '*.gguf' 2>/dev/null` |
| Install | `bash "/storage/ID/LocalAI/android/setup-termux.sh"` |
| Start | `~/localai-start` |
| Start a specific model | `~/localai-start "/storage/ID/LocalAI/models/model.gguf"` |
| Stop safely | `~/localai-stop` |
| Check status | `curl -s http://127.0.0.1:8080/api/status` |
| Bridge log | `tail -n 60 ~/.localai-usb/agent-bridge.log` |
| llama.cpp log | `tail -n 80 ~/.localai-usb/llama-server.log` |

# Agent tools and permissions

The interface can expose file reading, searching, writing, editing, and shell
commands. Enable the desired tools in the current chat.

- **Approval mode** shows each operation before it runs.
- **Always allow** permits enabled tools to operate without asking every time.

Approval mode is recommended for unfamiliar models. Always allow does not grant
root or bypass the operating system. Tools run with the permissions of the
signed-in desktop user or, on Android, the Termux app.

# Model features

Features depend on the loaded model:

- Tool calling requires a model that can reliably follow function/tool schemas.
- Images require a vision-capable GGUF and matching `mmproj` file.
- A text-only model cannot understand images just because an upload button is
  visible.
- PDF/DOCX text extraction is an interface feature. Scanned pages need OCR or a
  vision model.
- Reasoning, coding quality, context length, and multilingual ability depend on
  the model and available device memory.
- No web-search or cloud tool is bundled by default.

# Privacy and safety

- The model server binds only to `127.0.0.1`, never the LAN.
- Normal inference is local and offline.
- The API/session key protects the local browser/agent session; it is generated
  locally and should not be published or reused.
- Agent commands can modify files accessible to the current user. Keep backups
  and use approval mode when appropriate.
- Always stop LocalAI before ejecting the USB.

## Repository notes

AI model files, credentials, logs, caches, and operating-system-generated USB
metadata are intentionally excluded. Large runtime files use Git LFS, so a
full development clone requires Git LFS:

```bash
git lfs install
git clone https://github.com/Patt-00/LocalAI-USB-Interface.git
```

The USB stores the model. The connected device's CPU/GPU and RAM perform the AI
calculations.
