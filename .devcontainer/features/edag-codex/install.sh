#!/usr/bin/env bash
set -euo pipefail

VERSION="${VERSION:-latest}"
CONFIG_URL="${CONFIGURL-}"
INSTALLER_URL="https://chatgpt.com/codex/install.sh"
HOOK_SCRIPT="/opt/edag/selfheal/codex.sh"

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

# The image ships jq but no TOML parser, so the config template is validated by
# structure: a model provider table plus the two keys the runtime rewrite depends on.
is_codex_config() {
  [ -s "${1}" ] \
    && grep -q '^\[model_providers\.' "${1}" \
    && grep -q '^base_url' "${1}" \
    && grep -q '^wire_api' "${1}"
}

# The native installer takes a pinned release via --release.
release_arg=""
if [ -n "${VERSION}" ] && [ "${VERSION}" != "latest" ]; then
  release_arg="--release ${VERSION}"
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
# Generated at image build time by .devcontainer/features/edag-codex/install.sh and run as this
# feature's postCreateCommand. It heals a CLI that failed to bake, repairs the /usr/local/bin
# symlink, and writes ~/.codex/config.toml plus ~/.codex/auth.json using the Kelpie base that
# setup-clis.sh detected in onCreateCommand. Removing the edag-codex feature removes this hook.
BAKED_VERSION='${VERSION}'
INSTALLER_URL='${INSTALLER_URL}'
RELEASE_ARG='${release_arg}'
CONFIG_REF='/opt/edag/codex-config.reference.toml'
AUTH_REF='/opt/edag/codex-auth.reference.json'
HOST_KELPIE_BASE='http://host.docker.internal:18080'

export PATH="\$HOME/.local/bin:\$PATH"
grep -q 'HOME/.local/bin' ~/.bashrc 2>/dev/null || echo 'export PATH="\$HOME/.local/bin:\$PATH"' >> ~/.bashrc

KELPIE_BASE="\$HOST_KELPIE_BASE"
if [ -f "\$HOME/.config/edag/kelpie.env" ]; then
  . "\$HOME/.config/edag/kelpie.env"
else
  echo "edag-codex: no kelpie.env from setup-clis.sh - assuming the host Kelpie base \$KELPIE_BASE."
fi

# Self-heal: the build-time bake is best-effort, so install now when it did not land.
if ! command -v codex > /dev/null 2>&1 && [ ! -x "\$HOME/.local/bin/codex" ]; then
  echo "edag-codex: codex missing - attempting runtime install (feature version: \${BAKED_VERSION})..."
  if curl -fsSL --retry 3 --retry-delay 2 --retry-all-errors "\$INSTALLER_URL" -o /tmp/codex_install.sh; then
    for attempt in 1 2 3; do
      if CODEX_NON_INTERACTIVE=1 bash /tmp/codex_install.sh \${RELEASE_ARG} </dev/null; then break; fi
      echo "WARNING: edag-codex: runtime install attempt \${attempt}/3 failed."
      [ "\${attempt}" = 3 ] || sleep 5
    done
    command -v codex > /dev/null 2>&1 || [ -x "\$HOME/.local/bin/codex" ] || echo "WARNING: edag-codex: runtime install failed after 3 attempts - install manually later." >&2
  else
    echo "WARNING: edag-codex: installer unreachable - install manually later." >&2
  fi
  rm -f /tmp/codex_install.sh
fi

# The build-time install symlinks the baked binary into /usr/local/bin. A runtime install
# (or a bake that failed after downloading) leaves no link, and non-shell processes such as
# the VS Code server do not read ~/.bashrc - repair the link so the Codex extension finds the CLI.
if [ -x "\$HOME/.local/bin/codex" ] && [ ! -x /usr/local/bin/codex ]; then
  sudo ln -sfn "\$HOME/.local/bin/codex" /usr/local/bin/codex \\
    && echo "edag-codex: linked /usr/local/bin/codex -> \$HOME/.local/bin/codex for non-shell processes." \\
    || echo "WARNING: edag-codex: could not link /usr/local/bin/codex - the Codex VS Code extension may not find the CLI." >&2
fi

# Config: rewrite the placeholder base URL to the Kelpie base detected at container create.
mkdir -p ~/.codex
if [ -f "\$CONFIG_REF" ] && grep -q '^base_url' "\$CONFIG_REF"; then
  sed -E "s#https?://(localhost|127\.0\.0\.1):18080#\${KELPIE_BASE}#g" "\$CONFIG_REF" > ~/.codex/config.toml
  if [ -s ~/.codex/config.toml ] && grep -q '^base_url' ~/.codex/config.toml; then
    chmod 600 ~/.codex/config.toml
    echo "edag-codex: config written from \$CONFIG_REF (kelpie base: \$KELPIE_BASE)."
  else
    rm -f ~/.codex/config.toml
    echo "WARNING: edag-codex: reference template rewrite produced no usable config - no Codex config written (configure ~/.codex/config.toml manually)." >&2
  fi
else
  echo "edag-codex: reference template \$CONFIG_REF missing - no Codex config written (configure ~/.codex/config.toml manually)."
fi

# Codex refuses to start without a non-empty API key; the placeholder lets the proxy inject
# the real auth.
if [ -f "\$AUTH_REF" ] && jq empty "\$AUTH_REF" > /dev/null 2>&1; then
  cp "\$AUTH_REF" ~/.codex/auth.json
  chmod 600 ~/.codex/auth.json
  echo "edag-codex: auth placeholder copied from \$AUTH_REF."
else
  echo "edag-codex: auth placeholder \$AUTH_REF missing - put {\\"OPENAI_API_KEY\\": \\"kelpie\\"} into ~/.codex/auth.json manually."
fi

exit 0
EOF
chmod 0755 "${HOOK_SCRIPT}"
echo "edag-codex: runtime hook written at ${HOOK_SCRIPT}"

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT
chmod 755 "${TMP_DIR}"
# Best-effort bake: retry both the installer download AND the installer run; on
# failure warn - this feature's own hook retries at container create.
if curl -fsSL --retry 3 --retry-delay 2 --retry-all-errors "${INSTALLER_URL}" -o "${TMP_DIR}/codex-install.sh"; then
  # The native installer is $HOME-driven and installs into <home>/.local/bin.
  # Run it as the remote user so the binary does not land in /root.
  install_ok=0
  for attempt in 1 2 3; do
    if as_user "CODEX_NON_INTERACTIVE=1 bash '${TMP_DIR}/codex-install.sh' ${release_arg}" </dev/null; then
      install_ok=1
      break
    fi
    echo "WARNING: edag-codex: installer run attempt ${attempt}/3 failed." >&2
    [ "${attempt}" = 3 ] || sleep 5
  done
  [ "${install_ok}" = 1 ] || echo "WARNING: edag-codex: installer failed after 3 attempts - the feature hook retries at container create." >&2
else
  echo "WARNING: edag-codex: installer download failed after retries." >&2
fi

BIN="${TARGET_HOME}/.local/bin/codex"
if [ -x "${BIN}" ]; then
  ln -sfn "${BIN}" /usr/local/bin/codex
  echo "edag-codex: installed $(codex --version 2>/dev/null || echo 'unknown version')"
else
  echo "WARNING: edag-codex: codex not baked - the feature hook installs it at container create." >&2
fi

# Store the EDAG Codex config in the image. The hook above rewrites the placeholder base URL
# http://127.0.0.1:18080 to the detected Kelpie base into ~/.codex/config.toml at every
# container create. With the default empty configUrl the bundled EDAG config.toml (next to this
# script) is stored; a configured URL is fetched instead.
FEATURE_DIR="$(cd "$(dirname "$0")" && pwd)"
REF_TMP="${TMP_DIR}/codex-config.toml"
if [ -z "${CONFIG_URL}" ]; then
  echo "edag-codex: configUrl is empty - storing the bundled EDAG config.toml."
  cp "${FEATURE_DIR}/config.toml" "${REF_TMP}"
elif curl -fsSL "${CONFIG_URL}" -o "${REF_TMP}" && is_codex_config "${REF_TMP}"; then
  echo "edag-codex: config fetched from ${CONFIG_URL}"
else
  echo "WARNING: edag-codex: could not fetch/validate ${CONFIG_URL} - using the bundled config.toml." >&2
  cp "${FEATURE_DIR}/config.toml" "${REF_TMP}"
fi
if is_codex_config "${REF_TMP}"; then
  install -d -m 755 /opt/edag
  install -m 644 "${REF_TMP}" /opt/edag/codex-config.reference.toml
  echo "edag-codex: config stored at /opt/edag/codex-config.reference.toml"
else
  echo "WARNING: edag-codex: config template is not a valid Codex config - skipped (no Codex config is stored)." >&2
fi

# Store the Kelpie auth placeholder next to it; the hook copies it to ~/.codex/auth.json.
# Codex refuses to start without a non-empty API key; the proxy replaces it anyway.
if jq empty "${FEATURE_DIR}/auth.json" > /dev/null 2>&1; then
  install -d -m 755 /opt/edag
  install -m 644 "${FEATURE_DIR}/auth.json" /opt/edag/codex-auth.reference.json
  echo "edag-codex: auth placeholder stored at /opt/edag/codex-auth.reference.json"
else
  echo "WARNING: edag-codex: auth.json is not valid JSON - skipped (Codex needs ~/.codex/auth.json manually)." >&2
fi
