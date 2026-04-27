# Third-party Sources

This repository vendors source snapshots from:

- `hermes-webui`: https://github.com/nesquena/hermes-webui.git at `69bf2878bcd727a951e64677499ab4381f169c3f`
- `hermes-agent`: https://github.com/NousResearch/hermes-agent.git at `cebf95854bf5ee577930a7566a1dc07968821d72`

Each project keeps its original license file in its vendored directory.

GitHub Actions also downloads runtime/package assets while building the Windows
offline Release:

- Windows embeddable Python: https://www.python.org/
- Python wheels: https://pypi.org/
- WebUI browser assets: KaTeX, Prism.js, Mermaid, and streaming-markdown

The default offline Release is intentionally slim for intranet Windows usage. It
does not download Docker images, Node.js runtimes, npm packages, browser
automation packages, platform bot integrations, voice packages, training extras,
or development/test extras.
