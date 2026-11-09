#!/usr/bin/env bash
set -euo pipefail

VERSION="${VERSION:-latest}"
INSTALLER_URL="https://opencode.ai/v2/install"
HOOK_SCRIPT="/opt/edag/selfheal/opencode.sh"

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

# The upstream installer pins a release via --version.
version_arg=""
if [ -n "${VERSION}" ] && [ "${VERSION}" != "latest" ]; then
  version_arg="--version ${VERSION}"
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
# Generated at image build time by .devcontainer/features/edag-opencode/install.sh and run as this
# feature's postCreateCommand. It heals a CLI that failed to bake, keeps ~/.opencode/bin on PATH and
# writes ~/.config/opencode/opencode.json using the Kelpie base that setup-clis.sh detected in
# onCreateCommand. Removing the edag-opencode feature removes this hook with it.
BAKED_VERSION='${VERSION}'
INSTALLER_URL='${INSTALLER_URL}'
VERSION_ARG='${version_arg}'
CONFIG_REF='/opt/edag/opencode-config.reference.json'
HOST_KELPIE_BASE='http://host.docker.internal:18080'

export PATH="\$HOME/.local/bin:\$PATH"
grep -q 'HOME/.local/bin' ~/.bashrc 2>/dev/null || echo 'export PATH="\$HOME/.local/bin:\$PATH"' >> ~/.bashrc

KELPIE_BASE="\$HOST_KELPIE_BASE"
if [ -f "\$HOME/.config/edag/kelpie.env" ]; then
  . "\$HOME/.config/edag/kelpie.env"
else
  echo "edag-opencode: no kelpie.env from setup-clis.sh - assuming the host Kelpie base \$KELPIE_BASE."
fi

# Self-heal: the build-time bake is best-effort, so install now when it did not land. The
# upstream v2 installer fetches version info and can blip, hence the repeated run.
if ! command -v opencode > /dev/null 2>&1 && [ ! -x "\$HOME/.opencode/bin/opencode" ]; then
  echo "edag-opencode: opencode missing - attempting runtime install (feature version: \${BAKED_VERSION})..."
  if curl -fsSL --retry 3 --retry-delay 2 --retry-all-errors "\$INSTALLER_URL" -o /tmp/opencode_install.sh; then
    for attempt in 1 2 3; do
      if bash /tmp/opencode_install.sh \${VERSION_ARG} </dev/null; then break; fi
      echo "WARNING: edag-opencode: runtime installer attempt \${attempt}/3 failed (e.g. upstream version-endpoint blip)."
      [ "\${attempt}" = 3 ] || sleep 5
    done
    command -v opencode > /dev/null 2>&1 || [ -x "\$HOME/.opencode/bin/opencode" ] || echo "WARNING: edag-opencode: runtime install failed after 3 attempts - install manually later." >&2
  else
    echo "WARNING: edag-opencode: installer unreachable - install manually later." >&2
  fi
  rm -f /tmp/opencode_install.sh
fi

if [ -x "\$HOME/.opencode/bin/opencode" ]; then
  export PATH="\$HOME/.opencode/bin:\$PATH"
  grep -q 'HOME/.opencode/bin' ~/.bashrc 2>/dev/null || echo 'export PATH="\$HOME/.opencode/bin:\$PATH"' >> ~/.bashrc
fi

# Config: rewrite the placeholder baseURLs to the Kelpie base detected at container create.
mkdir -p ~/.config/opencode
if [ -f "\$CONFIG_REF" ] && jq empty "\$CONFIG_REF" > /dev/null 2>&1; then
  sed -E "s#https?://(localhost|127\.0\.0\.1):18080#\${KELPIE_BASE}#g" "\$CONFIG_REF" > ~/.config/opencode/opencode.json
  if jq empty ~/.config/opencode/opencode.json > /dev/null 2>&1; then
    chmod 600 ~/.config/opencode/opencode.json
    echo "edag-opencode: config written from \$CONFIG_REF (kelpie base: \$KELPIE_BASE)."
  else
    rm -f ~/.config/opencode/opencode.json
    echo "WARNING: edag-opencode: reference config rewrite produced invalid JSON - skipped." >&2
  fi
else
  echo "WARNING: edag-opencode: reference config \$CONFIG_REF missing - opencode needs manual setup."
fi

exit 0
EOF
chmod 0755 "${HOOK_SCRIPT}"
echo "edag-opencode: runtime hook written at ${HOOK_SCRIPT}"

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT
chmod 755 "${TMP_DIR}"
# Best-effort bake: retry both the installer download AND the installer run
# (the upstream v2 installer fetches version info and can blip); on failure warn -
# this feature's own hook retries at container create.
if curl -fsSL --retry 3 --retry-delay 2 --retry-all-errors "${INSTALLER_URL}" -o "${TMP_DIR}/opencode-install.sh"; then
  fetch_ok=1
else
  echo "WARNING: edag-opencode: installer download failed from ${INSTALLER_URL} after retries." >&2
  fetch_ok=0
fi

# The upstream installer is $HOME-driven and installs into <home>/.opencode/bin.
# Feature scripts run as root, so run it as the remote user, otherwise the binary
# lands in /root and is unusable.
if [ "${fetch_ok}" = 1 ]; then
  install_ok=0
  for attempt in 1 2 3; do
    if as_user "bash '${TMP_DIR}/opencode-install.sh' ${version_arg}" </dev/null; then
      install_ok=1
      break
    fi
    echo "WARNING: edag-opencode: installer run attempt ${attempt}/3 failed (e.g. upstream version-endpoint blip)." >&2
    [ "${attempt}" = 3 ] || sleep 5
  done
  [ "${install_ok}" = 1 ] || echo "WARNING: edag-opencode: installer failed after 3 attempts - the feature hook retries at container create." >&2
fi

BIN="${TARGET_HOME}/.opencode/bin/opencode"
if [ -x "${BIN}" ]; then
  # /usr/local/bin is on PATH for shells and exec'ed processes regardless of shell init.
  ln -sfn "${BIN}" /usr/local/bin/opencode
  echo "edag-opencode: installed $(opencode --version 2>/dev/null || echo 'unknown version')"
else
  echo "WARNING: edag-opencode: opencode not baked - the feature hook installs it at container create." >&2
fi

# Store the DARE reference config in the image; the hook above rewrites the mode-dependent
# Kelpie baseURLs into ~/.config/opencode/opencode.json at every container create.
CONFIG_URL="${CONFIGURL-https://gitlab-pages.edag.de/dare/codebuddy-config-guide/reference/opencode-config.json}"
if [ -n "${CONFIG_URL}" ]; then
  if curl -fsSL "${CONFIG_URL}" -o "${TMP_DIR}/opencode-config.json" && jq empty "${TMP_DIR}/opencode-config.json" > /dev/null 2>&1; then
    install -d -m 755 /opt/edag
    install -m 644 "${TMP_DIR}/opencode-config.json" /opt/edag/opencode-config.reference.json
    echo "edag-opencode: reference config stored at /opt/edag/opencode-config.reference.json"
  else
    echo "WARNING: edag-opencode: could not fetch/validate the reference config - no reference config stored." >&2
  fi
else
  echo "edag-opencode: configUrl is empty, skipping reference config."
fi
