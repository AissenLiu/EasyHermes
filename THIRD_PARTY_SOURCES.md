# Third-party Sources

This repository vendors source snapshots from:

- `hermes-webui`: https://github.com/EKKOLearnAI/hermes-web-ui.git at `5193dbc`
- `hermes-agent`: https://github.com/NousResearch/hermes-agent.git at `cebf95854bf5ee577930a7566a1dc07968821d72`

Each project keeps its original license file in its vendored directory.

GitHub Actions also downloads runtime/package assets while building the Windows
offline Release:

- Windows embeddable Python: https://www.python.org/
- Windows portable Node.js: https://nodejs.org/
- Python wheels: https://pypi.org/
- Node packages: https://www.npmjs.com/

The default offline Release is intentionally slim for intranet Windows usage. It
does not download Docker images, browser automation packages, heavy voice/STT
or premium TTS extras, training extras, or development/test extras. The bundled
Node.js runtime and npm packages are required by the replacement WebUI.
