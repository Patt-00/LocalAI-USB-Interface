ANDROID ARM64 / USB OTG / TERMUX
================================

For the complete Redmi/HyperOS walkthrough, open this file at the USB root:

  ANDROID REDMI GUIDE.txt

Requirements
------------
- A 64-bit ARM Android phone or tablet. 32-bit Android is unsupported.
- USB OTG support and enough RAM (8 GB minimum target; 12-16 GB is better).
- Android must be able to read this exFAT USB.
- Termux from its legitimate F-Droid or GitHub release. No root is required.

Android cannot execute ordinary Linux programs directly from USB/shared storage.
The one-time setup copies only the small Android llama.cpp runtime, LocalAI agent
bridge, and official offline web interface into Termux-private storage. The large
GGUF model stays on this USB and is read directly from it.

One-time setup
--------------
1. Open Termux and run:

     termux-setup-storage

   Approve Android's storage prompt.

2. With this USB connected, run setup-termux.sh through the path Android exposes.
   A common example is:

     bash /storage/XXXX-XXXX/LocalAI/android/setup-termux.sh

   If Termux cannot see that script, follow the internal-Download fallback in
   ANDROID REDMI GUIDE.txt. The fallback needs Android runtime, web interface,
   and model-selector support files in addition to LocalAI/android. It never
   requires copying the GGUF model.

3. Setup creates two simple commands in your Termux home:

     ~/localai-start
     ~/localai-stop

Normal offline use
------------------
1. Connect this USB through OTG.
2. Open Termux and run:

     ~/localai-start

3. Wait for "LOCAL AI READY". The Android browser opens the official LocalAI
   llama.cpp interface at 127.0.0.1:8080.
4. Before unplugging the USB, return to Termux and run:

     ~/localai-stop

The private llama-server listens only on 127.0.0.1:8081. A small loopback-only
bridge serves the UI/API on 127.0.0.1:8080 without an API key, supplies the
Android-compatible file and shell tools, and safely owns/stops only the
llama-server it created.

Agent permissions
-----------------
The Tools interface lets you keep approval prompts or choose Always allow for a
tool. Always-allowed tools can be revoked in Tools settings. Read every proposed
command or file change before approving it.

"Full access" means the Termux app's real Android permissions only: its private
home and the shared/USB paths Android grants it. It cannot read other apps'
private data, root-only files, or bypass Android security. Tool output, command
duration, file reads, searches, and concurrent model work are bounded to protect
phone performance.

USB detection and other models
------------------------------
The launcher checks its saved USB path, /mnt/media_rw/*, and /storage/* for a
readable primary GGUF. It ignores mmproj projectors and secondary split-model
shards. It never silently copies a GGUF to the phone. If there is one model, it
is selected automatically. With several models, put the preferred relative
path in LocalAI/models/default-model.txt. A missing/stale preference falls back
to another usable GGUF instead of stopping. You may also pass an exact path:

  ~/localai-start /mnt/media_rw/UUID/LocalAI/models/another-model.gguf

For a vision model, place its matching file beginning with "mmproj" beside the
selected model. The launcher detects that projector without copying either file.

If the model is not readable, the launcher stops with a clear error. Android
versions and vendors expose USB OTG differently, so every phone is not guaranteed.

Capabilities
------------
- Qwen3-8B defaults to a 4096-token context for reliable mobile memory use.
  Settings > General > Context size (tokens) saves a different value for the
  next Termux LocalAI start. 4096 is safest; larger values require more RAM.
- Direct mode is the fast default. Use the interface's Reasoning control when
  you specifically want Qwen3 thinking; it is slower and uses more context.
- The official interface performs chat, reasoning display/control, local chat
  history, context compaction, uploads supported by the loaded model/UI, and
  coding-agent file/shell tools.
- No web-search tool or cloud API is bundled. Normal inference is fully offline.
- Images require a vision-capable GGUF plus its matching mmproj file. The included
  Qwen3-8B GGUF is text-only, so adding an image does not make it a vision model.
- PDF/DOCX text handling is an interface feature; scanned pages require OCR or a
  vision model and are not guaranteed by the text-only model.

Troubleshooting
---------------
- If curl is missing, while online once run: pkg install curl
- Keep Termux exempt from battery optimization for long generations.
- Do not swipe Termux away while the model is running.
- Logs are in ~/.localai-usb/agent-bridge.log and llama-server.log.
- If Android asks to format the USB, cancel. Do not format it; try another OTG
  adapter/file manager or confirm that the device supports exFAT.
