# LocalAI USB Interface

This private repository contains the portable LocalAI USB interface and its
launcher/configuration scripts. It is an interface-only snapshot of the USB;
large AI models and compiled llama.cpp platform runtimes are intentionally not
included.

## Included

- Offline llama.cpp web interface with local coding-agent tools
- Windows, macOS, and Linux start/stop and terminal-chat launchers
- Automatic GGUF model selection helpers
- GPU and context-size preference helpers
- Android/Termux setup, start, stop, and documentation scripts
- Chat templates and USB documentation

## Not included

- GGUF model files
- Windows, macOS, Linux, or Android llama.cpp binaries/libraries
- Android agent bridge binary
- API keys, credentials, logs, caches, or temporary runtime state

The full USB uses official llama.cpp build **b10516** and keeps its GGUF under
`LocalAI/models/`. To select a preferred model when several are present, put
its path relative to that directory on the first line of
`LocalAI/models/default-model.txt`. If the entry is missing or stale, the
launchers automatically select another primary GGUF.

The launchers in this repository are not runnable until the matching llama.cpp
runtime directories and at least one compatible GGUF are added. See
`README.txt` for the complete platform layout and operating instructions.

## Privacy

The interface binds the desktop server to `127.0.0.1` and uses a private,
per-launch local API key. Normal inference is local and offline. Agent commands
run only with the permissions of the signed-in operating-system user.
