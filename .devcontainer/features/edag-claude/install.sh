#!/usr/bin/env bash
set -euo pipefail

VERSION="${VERSION:-latest}"
CONFIG_URL="${CONFIGURL-}"
INSTALLER_URL="https://claude.ai/install.sh"
HOOK_SCRIPT="/opt/edag/selfheal/claude.sh"

TARGET_USER="${_REMOTE_USER:-}"
case "${TARGET_USER}" in ''|automatic) TARGET_USER="$(getent passwd 1000 | cut -d: -f1)"; TARGET_USER="${TARGET_USER:-root}" ;; esac
TARGET_HOME="$(getent passwd "${TARGET_USER}" | cut -d: -f6)"

as_user() {
  if [ "${TARGET_USER}" = root ]; then
    bash -c "$1"
  else
    su "${TARGET_USER}" -s /bin/bash -c "$1"
  fi
}

# The native installer takes the channel or pinned version as a trailing positional argument.
channel_arg=""
if [ -n "${VERSION}" ] && [ "${VERSION}" != "latest" ]; then
  channel_arg="${VERSION}"
fi

# --- Runtime hook (this feature's postCreateCommand) -------------------------
# Written FIRST, before anything below can abort this script: devcontainer-feature.json points
# the lifecycle hook at this path, so it has to exist in the image even when the bake fails.
# Option values are baked in because they are no longer in the environment at hook time.
# Warn-only by design (deliberately no set -e, explicit exit 0): feature lifecycle commands run
# blocking and an error here would surface as a container-creation failure.
install -d -m 755 /opt/edag/selfheal
cat > "${HOOK_SCRIPT}" <<EOF
#!/usr/bin/env bash
# Generated at image build time by .devcontainer/features/edag-claude/install.sh and run as this
# feature's postCreateCommand. It heals a CLI that failed to bake and writes ~/.claude/settings.json
# using the Kelpie base that setup-clis.sh detected in onCreateCommand. Removing the edag-claude
# feature removes this hook with it, so nothing here runs for projects that do not want Claude.
BAKED_VERSION='${VERSION}'
INSTALLER_URL='${INSTALLER_URL}'
CHANNEL_ARG='${channel_arg}'
CONFIG_REF='/opt/edag/claude-config.reference.json'
HOST_KELPIE_BASE='http://host.docker.internal:18080'

export PATH="\$HOME/.local/bin:\$PATH"
grep -q 'HOME/.local/bin' ~/.bashrc 2>/dev/null || echo 'export PATH="\$HOME/.local/bin:\$PATH"' >> ~/.bashrc

KELPIE_BASE="\$HOST_KELPIE_BASE"
if [ -f "\$HOME/.config/edag/kelpie.env" ]; then
  . "\$HOME/.config/edag/kelpie.env"
else
  echo "edag-claude: no kelpie.env from setup-clis.sh - assuming the host Kelpie base \$KELPIE_BASE."
fi

# Self-heal: the build-time bake is best-effort, so install now when it did not land.
if ! command -v claude > /dev/null 2>&1 && [ ! -x "\$HOME/.local/bin/claude" ]; then
  echo "edag-claude: claude missing - attempting runtime install (feature version: \${BAKED_VERSION})..."
  if curl -fsSL --retry 3 --retry-delay 2 --retry-all-errors "\$INSTALLER_URL" -o /tmp/claude_install.sh; then
    for attempt in 1 2 3; do
      if bash /tmp/claude_install.sh \${CHANNEL_ARG} </dev/null; then break; fi
      echo "WARNING: edag-claude: runtime install attempt \${attempt}/3 failed."
      [ "\${attempt}" = 3 ] || sleep 5
    done
    command -v claude > /dev/null 2>&1 || [ -x "\$HOME/.local/bin/claude" ] || echo "WARNING: edag-claude: runtime install failed after 3 attempts - install manually later." >&2
  else
    echo "WARNING: edag-claude: installer unreachable - install manually later." >&2
  fi
  rm -f /tmp/claude_install.sh
fi

# Config: rewrite the placeholder base URL to the Kelpie base detected at container create.
mkdir -p ~/.claude
if [ -f "\$CONFIG_REF" ] && jq empty "\$CONFIG_REF" > /dev/null 2>&1; then
  sed -E "s#https?://(localhost|127\.0\.0\.1):18080#\${KELPIE_BASE}#g" "\$CONFIG_REF" > ~/.claude/settings.json
  if jq empty ~/.claude/settings.json > /dev/null 2>&1; then
    chmod 600 ~/.claude/settings.json
    echo "edag-claude: settings written from \$CONFIG_REF (kelpie base: \$KELPIE_BASE)."
  else
    rm -f ~/.claude/settings.json
    echo "WARNING: edag-claude: reference template produced invalid JSON - no Claude settings written (configure ~/.claude/settings.json manually)." >&2
  fi
else
  echo "edag-claude: reference template \$CONFIG_REF missing - no Claude settings written (configure ~/.claude/settings.json manually)."
fi

exit 0
EOF
chmod 0755 "${HOOK_SCRIPT}"
echo "edag-claude: runtime hook written at ${HOOK_SCRIPT}"

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT
chmod 755 "${TMP_DIR}"
# Best-effort bake: retry both the installer download AND the installer run; on
# failure warn - this feature's own hook retries at container create.
if curl -fsSL --retry 3 --retry-delay 2 --retry-all-errors "${INSTALLER_URL}" -o "${TMP_DIR}/claude-install.sh"; then
  # The native installer is $HOME-driven and installs into <home>/.local/bin.
  # Run it as the remote user so the binary does not land in /root.
  install_ok=0
  for attempt in 1 2 3; do
    if as_user "bash '${TMP_DIR}/claude-install.sh' ${channel_arg}" </dev/null; then
      install_ok=1
      break
    fi
    echo "WARNING: edag-claude: installer run attempt ${attempt}/3 failed." >&2
    [ "${attempt}" = 3 ] || sleep 5
  done
  [ "${install_ok}" = 1 ] || echo "WARNING: edag-claude: installer failed after 3 attempts - the feature hook retries at container create." >&2
else
  echo "WARNING: edag-claude: installer download failed after retries." >&2
fi

BIN="${TARGET_HOME}/.local/bin/claude"
if [ -x "${BIN}" ]; then
  ln -sfn "${BIN}" /usr/local/bin/claude
  echo "edag-claude: installed $(claude --version 2>/dev/null || echo 'unknown version')"
else
  echo "WARNING: edag-claude: claude not baked - the feature hook installs it at container create." >&2
fi

# Store the EDAG Claude settings JSON in the image. The hook above rewrites the placeholder
# base URL http://127.0.0.1:18080 to the detected Kelpie base into ~/.claude/settings.json at
# every container create. With the default empty configUrl the bundled on-prem settings.json
# (next to this script) is stored; a configured URL is fetched instead.
FEATURE_DIR="$(cd "$(dirname "$0")" && pwd)"
REF_TMP="${TMP_DIR}/claude-config.json"
if [ -z "${CONFIG_URL}" ]; then
  echo "edag-claude: configUrl is empty - storing the bundled on-prem settings.json."
  cp "${FEATURE_DIR}/settings.json" "${REF_TMP}"
elif curl -fsSL "${CONFIG_URL}" -o "${REF_TMP}" && jq empty "${REF_TMP}" > /dev/null 2>&1; then
  echo "edag-claude: config fetched from ${CONFIG_URL}"
else
  echo "WARNING: edag-claude: could not fetch/validate ${CONFIG_URL} - using the bundled settings.json." >&2
  cp "${FEATURE_DIR}/settings.json" "${REF_TMP}"
fi
if jq empty "${REF_TMP}" > /dev/null 2>&1; then
  install -d -m 755 /opt/edag
  install -m 644 "${REF_TMP}" /opt/edag/claude-config.reference.json
  echo "edag-claude: settings stored at /opt/edag/claude-config.reference.json"
else
  echo "WARNING: edag-claude: settings template is not valid JSON - skipped (no Claude settings are stored)." >&2
fi
