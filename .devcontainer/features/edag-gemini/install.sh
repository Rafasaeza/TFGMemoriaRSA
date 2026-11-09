#!/usr/bin/env bash
set -euo pipefail

VERSION="${VERSION:-latest}"
PACKAGE="@google/gemini-cli@${VERSION}"

TARGET_USER="${_REMOTE_USER:-}"
case "${TARGET_USER}" in ''|automatic) TARGET_USER="$(getent passwd 1000 | cut -d: -f1)"; TARGET_USER="${TARGET_USER:-root}" ;; esac

as_user() {
  if [ "${TARGET_USER}" = root ]; then
    bash -c "$1"
  else
    su "${TARGET_USER}" -s /bin/bash -c "umask 0002 && export PATH='${PATH}' && $1"
  fi
}

# The node feature installs Node via nvm into /usr/local/share/nvm (npm lives in
# .../current/bin); su resets PATH, so forward it explicitly. npm globals must be
# installed as the remote user (no sudo) so they land in the shared nvm prefix.
as_user "npm install -g ${PACKAGE}" </dev/null

NPM_BIN="$(as_user 'npm prefix -g' | tr -d '[:space:]')/bin"
if [ ! -x "${NPM_BIN}/gemini" ]; then
  echo "edag-gemini: npm global install did not create ${NPM_BIN}/gemini." >&2
  exit 1
fi

ln -sfn "${NPM_BIN}/gemini" /usr/local/bin/gemini
echo "edag-gemini: installed $(gemini --version 2>/dev/null || echo 'unknown version')"

# Store the Gemini CLI settings JSON in the image; setup-clis.sh copies it to
# ~/.gemini/settings.json at container create.
FEATURE_DIR="$(cd "$(dirname "$0")" && pwd)"
if jq empty "${FEATURE_DIR}/settings.json" > /dev/null 2>&1; then
  install -d -m 755 /opt/edag
  install -m 644 "${FEATURE_DIR}/settings.json" /opt/edag/gemini-config.reference.json
  echo "edag-gemini: settings stored at /opt/edag/gemini-config.reference.json"
else
  echo "WARNING: edag-gemini: settings.json is not valid JSON - skipped (no Gemini settings stored)." >&2
fi
