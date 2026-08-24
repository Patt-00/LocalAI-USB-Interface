# LocalAI USB Interface

This private repository contains the portable LocalAI USB system: its offline
web interface, launcher/configuration scripts, and compiled llama.cpp platform
runtimes. AI model files are intentionally not included.

## Included

- Offline llama.cpp web interface with local coding-agent tools
- Windows, macOS, and Linux start/stop and terminal-chat launchers
- Automatic GGUF model selection helpers
- GPU and context-size preference helpers
- Android/Termux setup, start, stop, and documentation scripts
- Compiled llama.cpp runtimes for Windows, macOS, Linux, and Android
- Android local agent bridge
- Chat templates and USB documentation

## Not included

- GGUF model files
- API keys, credentials, logs, caches, or temporary runtime state
- Operating-system-generated removable-drive metadata

The full USB uses official llama.cpp build **b10516** and keeps its GGUF under
`LocalAI/models/`. To select a preferred model when several are present, put
its path relative to that directory on the first line of
`LocalAI/models/default-model.txt`. If the entry is missing or stale, the
launchers automatically select another primary GGUF.

The platform runtimes are included, but inference requires the user to place at
least one compatible GGUF in `LocalAI/models/`. See `README.txt` for the
complete platform layout and operating instructions.

## Privacy

The interface binds the desktop server to `127.0.0.1` and uses a private,
per-launch local API key. Normal inference is local and offline. Agent commands
run only with the permissions of the signed-in operating-system user.
