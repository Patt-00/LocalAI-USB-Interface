LOCALAI PORTABLE OFFLINE AGENT USB
=================================

The same GGUF model is shared by Windows, macOS, Linux, and Android/Termux.
Each operating system uses its own llama.cpp runtime. The USB stores the model;
the connected device's CPU/GPU and RAM perform the calculations.

Normal chat and agent work are fully local. Every server listens only on
127.0.0.1:8080. No account, API key, cloud API, or Internet connection is
required. Never remove the USB while LocalAI is running; use the matching STOP
launcher first.

QUICK START
-----------
Windows 10/11 x86-64 or ARM64
  1. Double-click START AI.bat.
  2. Wait for LOCAL AI READY and the browser.
  3. Chat or ask the agent to work with files/commands.
  4. Double-click STOP AI.bat before ejecting.
  On x86-64, the launcher probes the included CUDA and Vulkan backends. It
  prefers CUDA for an NVIDIA GPU, uses Vulkan for a compatible AMD/Intel GPU,
  and otherwise falls back to CPU automatically. Windows ARM64 probes the
  included Qualcomm Adreno OpenCL backend and falls back to CPU.
  To force CPU mode, open Command Prompt on the USB and run:
  set LOCALAI_FORCE_CPU=1
  "START AI.bat"

macOS Apple Silicon or Intel
  1. Double-click START AI.command.
  2. Wait for LOCAL AI READY and the browser.
  3. Run STOP AI.command before ejecting.
  If Gatekeeper blocks it, Control-click the launcher, choose Open, then Open.
  If macOS separately blocks the unsigned llama.cpp binary, use System Settings
  > Privacy & Security > Open Anyway. The USB never bypasses Gatekeeper.
  Terminal fallback: bash "/Volumes/LOCALAI/START AI.command"
  Apple Silicon automatically uses Metal GPU offload. To force CPU mode:
  LOCALAI_FORCE_CPU=1 bash "/Volumes/LOCALAI/START AI.command"

Linux x86-64 or ARM64
  Start: bash "START AI.sh"
  Stop:  bash "STOP AI.sh"
  On Linux x86-64, the launcher automatically uses the included Vulkan runtime
  when it detects a supported discrete NVIDIA, AMD Radeon RX, or Intel Arc GPU.
  Linux ARM64 also probes its included Vulkan runtime for a hardware GPU.
  Model layers that fit are placed in VRAM and the remainder stays on CPU/RAM.
  To force the compatibility CPU runtime, start with:
  LOCALAI_FORCE_CPU=1 bash "START AI.sh"
  If exFAT is mounted noexec, the launcher copies only the small runtime to a
  private temporary directory. The 5.2 GB model remains on the USB.

TERMINAL CLI MODE
-----------------
CLI mode is available on every supported desktop and uses the same GGUF:
  Windows x86-64/ARM64: double-click LocalCLI.bat, or run LocalCLI.bat.
  macOS Apple Silicon/Intel: double-click LocalCLI.command.
  Linux x86-64/ARM64: run bash "LocalCLI.sh".

The launcher safely stops only this USB's tracked website server before loading
the model, because running both would waste RAM/VRAM. It reuses that computer's
saved context-size and GPU-acceleration choices. Press Ctrl+C (Control-C on Mac)
to exit. To select another compatible model from a terminal, provide its path:
  Windows: LocalCLI.bat "C:\path\model.gguf"
  macOS: bash "/Volumes/LOCALAI/LocalCLI.command" "/path/model.gguf"
  Linux: bash "LocalCLI.sh" "/path/model.gguf"

This raw llama.cpp CLI provides terminal chat and reasoning. It is not the
website coding agent: file tools, command execution, approvals, documents, and
the visible-terminal tool remain website features.

Android ARM64 / USB OTG
  There is no APK. Open ANDROID/README.txt or
  LocalAI/android/README-ANDROID.txt and use the included Termux setup. Android
  cannot execute desktop/ordinary Linux binaries directly from USB storage.

GPU ACCELERATION TOGGLE
-----------------------
On a desktop, open Settings > General and switch GPU acceleration on or off,
then choose Save. Saving unloads and reloads the active model, so the page may
take a minute or more to become ready again. On uses the best compatible GPU
backend detected by the launcher; off keeps model computation on CPU/system
RAM. The choice is remembered separately on each computer, outside the USB, and
is reused on the next launch. If a GPU backend fails, the launcher still falls
back to CPU. Android/Termux remains CPU-only, so this control is unavailable
there.

CONTEXT SIZE
------------
Open Settings > General > Context size (tokens), enter a whole number from 512
to 131072, then choose Save. Desktop LocalAI unloads and reloads the active
model with the new context. Android/Termux remembers the value for its next
LocalAI start. The value is remembered separately on each device.

4096 is recommended for 8 GB RAM. Try 8192 on a 12 GB device and 8192 or 16384
on a 16 GB device. Larger context retains more of the conversation but consumes
more RAM/VRAM, can reduce speed, and can fail if the device or selected model
cannot support it. A model cannot gain a larger native context than it was
trained to support.

AGENT ACCESS AND APPROVALS
--------------------------
Desktop tools can read/search files, search text, run shell commands, and write
or edit files. They run as the signed-in user and start in that user's home
folder. Absolute paths are supported, so access covers every file that the
current user can legitimately access. The agent cannot bypass root, sudo, UAC,
macOS security, Android app isolation, permissions, encryption, or policy.

The website asks before each tool call. Choose:
  - Allow once: approve only that action.
  - Always allow this tool: stop asking for that tool.
  - Always allow all Server Tools: maximum autonomy in that browser profile.
  - Deny: do not run it.

When asked to open a visible terminal, a compatible tool-calling model can use
the included desktop helper. It opens Command Prompt on Windows, Terminal on
macOS, or an installed graphical terminal on Linux. The new window has exactly
the same signed-in-user permissions; it does not add root or administrator
access. On Android, LocalAI is already running inside the Termux terminal.

Always-allow choices are stored in that device's browser and can be revoked in
Tools settings. Read commands and file changes before approving them. The model
is instructed to ask again for destructive, irreversible, credential, or
privacy-sensitive actions, but model instructions are not a security boundary.
Agent mutations accept requests only from the exact same loopback browser origin.
A local process already running as the same user has equivalent OS access. Never
change the launchers to bind LocalAI to a LAN address such as 0.0.0.0.

FILES AND DOCUMENTS
-------------------
The website can attach text, source code, PDF text, and DOCX text entirely in the
browser. Scanned/image-only PDFs need OCR or a compatible vision model and are
not guaranteed. Treat document contents as untrusted data, not instructions.

The included Qwen3-8B model is TEXT-ONLY. It cannot understand uploaded images.
Image controls become useful only after selecting a llama.cpp-compatible vision
GGUF with its matching mmproj GGUF. Put a multimodal pair in one subfolder:

  LocalAI-Models/MyVisionModel/model.gguf
  LocalAI-Models/MyVisionModel/mmproj-model.gguf

The desktop router detects that bundle on restart. A similar subfolder may be
added under LocalAI/models, but the finished USB intentionally contains exactly
one GGUF: the required Qwen3 model.

MODELS
------
Launchers no longer depend on a fixed GGUF filename. If LocalAI/models contains
one readable primary GGUF, it is selected automatically. Projector files named
mmproj* and secondary split-model shards are never mistaken for the main model.
You can replace the current GGUF with another compatible model without editing
any launcher.

If LocalAI/models contains several models, put the preferred path on the first
line of LocalAI/models/default-model.txt, relative to the models folder, for
example:

  MyModel/model.gguf

If that file is missing or points to a model that was removed, launchers fall
back to another primary GGUF instead of failing. The website lists all detected
models; existing conversations may retain their prior model until you select a
new one from the Model menu.

The desktop Model menu discovers compatible GGUF files in:
  - LocalAI/models on this USB (including model bundles in subfolders)
  - LocalAI-Models in the current user's home folder
  - the current user's Desktop
  - the current user's Downloads folder

Only one model is kept in RAM. External models stay where they are and are not
copied to the USB. Restart LocalAI after adding an external model. Model features
such as vision, tool calling, reasoning quality, and document understanding
depend on the selected model and its compatibility with llama.cpp b10516.

All seven desktop server tools are offered to every selected model. Models with
a tool-aware GGUF chat template use their native function-call format. The USB
also supplies llama.cpp's official Qwen2.5 Instruct tool template and can recover
an exact enabled-tool call when a capable model returns it as fenced JSON instead
of structured tool_calls. Normal tool approval rules still apply. A model that
does not understand tools or cannot produce a valid call remains chat-only; the
launcher cannot add capabilities that are absent from the model itself.

CONTEXT, REASONING, AND PERFORMANCE
-----------------------------------
Launchers default to a 4096-token context for reliable operation with the larger
8B model. Settings > General > Context size (tokens) can change it per device.
Older agent turns are summarized locally before the active context fills; exact
old messages remain in browser chat history, but summaries can lose small details.
Only one model and one generation slot run at a time. Secondary prompt-cache RAM
is capped at 256 MiB and idle-slot caching is disabled.

Direct/no-thinking mode is the fast default. Use the Reasoning control when you
specifically want Qwen3 thinking. Reasoning is slower and consumes more context.
Apple Silicon automatically uses Metal. Windows x86-64 automatically prefers
CUDA on NVIDIA, then Vulkan on a compatible AMD/Intel GPU, and otherwise uses
CPU. Linux x86-64 automatically uses Vulkan on supported discrete GPUs and
otherwise uses CPU. GPU layers that fit are placed in VRAM; remaining model
data and normal application memory stay in system RAM. Windows ARM64 tries its
Qualcomm Adreno OpenCL backend, and Linux ARM64 tries Vulkan; both fall back to
CPU. macOS Intel and Android use compatible CPU settings. No dedicated GPU,
background indexer, or extra always-on service is required.

GPU acceleration is optional. Change it at Settings > General > GPU
acceleration. A discrete GPU can be faster, but a very small/old GPU or a slow
shared-memory path can be slower than CPU; in that case turn the option off.

WEB ACCESS AND PRIVACY
----------------------
No web-search tool is bundled because a dependable cross-platform offline-first
search backend would add setup and background overhead. The agent can run an
installed command such as curl only when you explicitly approve it and Internet
is available; that may transmit the command's data to the named site. Prompts,
documents, chats, and model data are not otherwise sent outside the device.

RUNTIME NOTES
-------------
Model: Ollama Library qwen3:8b / qwen3-8b-q4_K_M.gguf / Q4_K_M
llama.cpp: official build b10516, commit b95502ba9
Linux x64 Vulkan runtime: official build b10516, commit b95502ba9.
Windows x64 CUDA 13.3 and Vulkan backends: official build b10516.
Windows ARM64 Qualcomm Adreno OpenCL backend: official build b10516.
Linux ARM64 Vulkan runtime: official build b10516.
Linux x64 runtime needs glibc 2.34 or newer.
Linux ARM64 runtime needs glibc 2.38 or newer.
Official macOS runtimes declare macOS 13.3 or newer.
8 GB RAM is the minimum target; 12-16 GB is substantially better.
