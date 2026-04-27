#!/usr/bin/env bash
set -euo pipefail

mkdir -p "${HERMES_HOME}" "${HERMES_WEBUI_STATE_DIR}" "${HERMES_WEBUI_DEFAULT_WORKSPACE}"

if [[ ! -f "${HERMES_HOME}/.env" && -f /opt/hermes-agent/.env.example ]]; then
  cp /opt/hermes-agent/.env.example "${HERMES_HOME}/.env"
fi

if [[ ! -f "${HERMES_HOME}/config.yaml" && -f /opt/hermes-agent/cli-config.yaml.example ]]; then
  cp /opt/hermes-agent/cli-config.yaml.example "${HERMES_HOME}/config.yaml"
fi

if [[ "${EAZYHERMES_START_GATEWAY:-0}" =~ ^(1|true|yes)$ ]]; then
  echo "[EazyHermes] starting Hermes gateway in background"
  (cd /opt/hermes-agent && hermes gateway run >>"${HERMES_WEBUI_STATE_DIR}/gateway.log" 2>&1) &
fi

echo "[EazyHermes] starting WebUI on ${HERMES_WEBUI_HOST}:${HERMES_WEBUI_PORT}"
cd /opt/hermes-webui
exec python /opt/hermes-webui/server.py

