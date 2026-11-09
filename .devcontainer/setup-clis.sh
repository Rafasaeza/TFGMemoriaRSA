#!/usr/bin/env bash
set -euo pipefail

# Committed, secret-free runtime script (runs as onCreateCommand in the container).
#
# It deliberately runs one lifecycle phase BEFORE the feature-contributed postCreateCommand
# hooks: this script detects the Kelpie mode and publishes the result in
# ~/.config/edag/kelpie.env, and each edag-<tool> feature hook sources that file before it
# rewrites its own CLI configuration. Feature lifecycle commands always run BEFORE the
# devcontainer.json lifecycle commands, so Kelpie detection can never live in a
# postCreateCommand here - onCreateCommand is the earliest phase that runs in the container.
#
# The tool CLIs are installed at image build time by the local devcontainer features in
# .devcontainer/features/ (edag-kelpie, edag-opencode, edag-claude, edag-gemini and
# edag-codex plus the public node feature). A CLI that failed to bake is healed by that same
# feature's own hook, never here - that way removing a feature from devcontainer.json also
# removes its install. This script only does the Kelpie runtime wiring: mode detection, the
# local proxy startup and the kelpie devcontainer shim.
#
# Two auth modes, auto-detected at container create:
#   HOST mode:      Kelpie proxy runs on the host machine (Windows/Rancher or Linux host)
#                   and is reached via http://host.docker.internal:18080
#   CONTAINER mode: no host proxy found -> Kelpie is installed inside the container
#                   and served locally on http://127.0.0.1:18080
#                   (tokens persist in the /home/vscode/.config/kelpie volume)
#
# All API keys below are non-secret placeholders; Kelpie strips and replaces
# auth headers before forwarding to the Ephyne gateway.

HOST_KELPIE_BASE="http://host.docker.internal:18080"
LOCAL_KELPIE_BASE="http://127.0.0.1:18080"

# PATH for tools that live in the container user's home (kelpie runtime fallback install)
export PATH="$HOME/.local/bin:$PATH"
grep -q 'HOME/.local/bin' ~/.bashrc 2>/dev/null || echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc

# --- Kelpie mode detection ---
wait_for_kelpie() {
  base="$1"
  tries="$2"
  count=0
  while [ "$count" -lt "$tries" ]; do
    if curl -fsS -m 3 "$base/kelpie/health" > /dev/null 2>&1; then
      return 0
    fi
    sleep 1
    count=$((count+1))
  done
  return 1
}

KELPIE_MODE=""
KELPIE_BASE="$HOST_KELPIE_BASE"

if wait_for_kelpie "$HOST_KELPIE_BASE" 3; then
  KELPIE_MODE="HOST"
  echo "HOST mode: using Kelpie proxy on the host at $HOST_KELPIE_BASE."
else
  echo "Host Kelpie not reachable at $HOST_KELPIE_BASE - falling back to CONTAINER mode."
  # First-run login helper: the device-code login needs a visible terminal, so it is
  # never run unattended here. The helper is idempotent and TTY-aware; a guarded line
  # in ~/.bashrc completes the sign-in (and any pending install) automatically in the
  # next interactive terminal.
  mkdir -p "$HOME/.local/bin"
  cat > "$HOME/.local/bin/edag-kelpie-login" <<'KELPIELOGIN'
#!/usr/bin/env bash
# EDAG Kelpie first-run login helper (written by setup-clis.sh; safe to run manually).
HOST_KELPIE_BASE="http://host.docker.internal:18080"
LOCAL_KELPIE_BASE="http://127.0.0.1:18080"
export PATH="$HOME/.local/bin:$PATH"
# HOST mode wins whenever the host proxy answers.
if curl -fsS -m 1 "$HOST_KELPIE_BASE/kelpie/health" > /dev/null 2>&1; then
  exit 0
fi
# Install Kelpie if the runtime fallback never completed (only in visible terminals).
if ! command -v kelpie > /dev/null 2>&1; then
  [ -t 1 ] || exit 0
  echo "Installing Kelpie..."
  curl -fsSL --retry 3 --retry-delay 2 --retry-all-errors https://gitlab-pages.edag.de/dare/kelpie/install.sh -o /tmp/kelpie_install.sh \
    && bash /tmp/kelpie_install.sh -y </dev/null || { echo "WARNING: kelpie install failed; retry later." >&2; exit 1; }
  rm -f /tmp/kelpie_install.sh
fi
# Complete the one-time Microsoft device-code login in this terminal when needed.
if ! kelpie auth print-access-token > /dev/null 2>&1; then
  [ -t 1 ] || exit 0
  kelpie auth login || exit 1
fi
# Make sure the local proxy runs (containers have no systemd for 'serve start').
if ! curl -fsS -m 1 "$LOCAL_KELPIE_BASE/kelpie/health" > /dev/null 2>&1; then
  pkill -f 'kelpie serve run' > /dev/null 2>&1 || true
  sleep 1
  nohup kelpie serve run > /tmp/kelpie-serve.log 2>&1 &
fi
exit 0
KELPIELOGIN
  chmod +x "$HOME/.local/bin/edag-kelpie-login"
  grep -q 'edag-kelpie-login' ~/.bashrc 2>/dev/null || echo '[ -t 1 ] && [ -x "$HOME/.local/bin/edag-kelpie-login" ] && "$HOME/.local/bin/edag-kelpie-login" --auto' >> ~/.bashrc
  if ! command -v kelpie > /dev/null 2>&1 && [ ! -x "$HOME/.local/bin/kelpie" ]; then
    # Runtime fallback: the edag-kelpie feature defaults to atBuild=never, so Kelpie is
    # normally installed here. -y installs without the menu; the login token is cached
    # in the kelpie config volume. Transient upstream errors get two more attempts.
    for attempt in 1 2 3; do
      if curl -fsSL --retry 3 --retry-delay 2 --retry-all-errors https://gitlab-pages.edag.de/dare/kelpie/install.sh -o /tmp/kelpie_install.sh \
         && bash /tmp/kelpie_install.sh -y </dev/null; then
        break
      fi
      echo "WARNING: kelpie runtime install attempt $attempt failed."
      if [ "$attempt" = 3 ]; then
        echo "WARNING: kelpie not installed - the edag-kelpie-login helper will retry in your next terminal."
      fi
      sleep 5
    done
    rm -f /tmp/kelpie_install.sh
  fi
  # Kelpie >= 1.5.6: 'serve start' requires a systemd user service -> not available in
  # containers, the proxy must run in the foreground. Clear stale instances first so the
  # port is free (a leftover 'serve run' causes "bind: address already in use").
  pkill -f 'kelpie serve run' > /dev/null 2>&1 || true
  sleep 1
  if command -v kelpie > /dev/null 2>&1 && ! curl -fsS -m 3 "$LOCAL_KELPIE_BASE/kelpie/health" > /dev/null 2>&1; then
    nohup kelpie serve run > /tmp/kelpie-serve.log 2>&1 &
  fi
  if wait_for_kelpie "$LOCAL_KELPIE_BASE" 15; then
    KELPIE_MODE="CONTAINER"
    KELPIE_BASE="$LOCAL_KELPIE_BASE"
    echo "CONTAINER mode: local Kelpie proxy running at $LOCAL_KELPIE_BASE."
    # 'auth status' was removed in kelpie 1.5.6 (returns rc 0 with help text now) -
    # print-access-token fails reliably when there is no valid session.
    if kelpie auth print-access-token > /dev/null 2>&1; then
      echo "Kelpie already authenticated (token from volume)."
    else
      echo "CONTAINER mode: open a new terminal (or run 'edag-kelpie-login') to complete the"
      echo "one-time Microsoft sign-in - the code appears right in the terminal."
      echo "Alternative: open http://127.0.0.1:18080/kelpie/status and click 'Log in'."
    fi
    # Platform minimum-version gate: too-old kelpie builds get HTTP 403 from the gateway.
    gate_code="$(curl -s -o /tmp/kelpie-gate.out -w '%{http_code}' -m 5 "$LOCAL_KELPIE_BASE/openai/v1/models" -H 'Authorization: Bearer kelpie' || echo 000)"
    if [ "$gate_code" = "403" ] && grep -qi 'no longer supported' /tmp/kelpie-gate.out 2>/dev/null; then
      echo "WARNING: this Kelpie build is blocked by the platform (minimum version enforced)."
      echo "Run 'kelpie update' in a container terminal (one-time SharePoint device-code login),"
      echo "then restart the proxy: pkill -f 'kelpie serve run' && nohup kelpie serve run > /tmp/kelpie-serve.log 2>&1 &"
    fi
    rm -f /tmp/kelpie-gate.out
  else
    echo "WARNING: no Kelpie proxy reachable (host unreachable, local proxy did not start)."
    echo "See /tmp/kelpie-serve.log. The CLI configs are written for the host base URL."
  fi
fi

# Hand the detected mode to the per-feature postCreateCommand hooks. They run one lifecycle
# phase later and in their own processes, so this file is the only handoff channel.
install -d -m 700 "$HOME/.config/edag"
cat > "$HOME/.config/edag/kelpie.env" <<KELPENV
# Written by setup-clis.sh (onCreateCommand). Sourced by the edag-* feature hooks.
KELPIE_MODE="${KELPIE_MODE:-NONE}"
KELPIE_BASE="${KELPIE_BASE}"
KELPENV
chmod 600 "$HOME/.config/edag/kelpie.env"
echo "Published the Kelpie mode for the feature hooks (mode: ${KELPIE_MODE:-NONE}, base: ${KELPIE_BASE})."

# kelpie devcontainer shim: systemd-daemon subcommands cannot work without systemd.
if command -v kelpie > /dev/null 2>&1 && ! grep -q 'EDAG devcontainer kelpie shim' ~/.bashrc 2>/dev/null; then
  cat >> ~/.bashrc <<'SHIM'

# EDAG devcontainer kelpie shim (usage web / systemd daemon commands unavailable)
kelpie() {
  if [ "$1" = "usage" ] && [ "$2" = "web" ]; then
    echo "kelpie usage web is not available in the devcontainer (needs a systemd-registered daemon)." >&2
    echo "Use 'kelpie usage' for terminal output, or open http://127.0.0.1:18080/kelpie/status" >&2
    return 1
  fi
  if [ "$1" = "serve" ] && [ "$2" != "run" ]; then
    echo "Note: 'kelpie serve $2' manages the systemd daemon, which does not exist in the devcontainer." >&2
    case "$2" in
      status) health="$(curl -fsS -m 3 http://127.0.0.1:18080/kelpie/health 2>/dev/null || true)"
            if [ -n "$health" ]; then
              echo "Background proxy IS running: $health"
            else
              echo "Background proxy is not running." >&2
              echo "To (re)start manually: 'nohup kelpie serve run > /tmp/kelpie-serve.log 2>&1 &'" >&2
            fi
            return 0 ;;
      stop) echo "The proxy runs via 'kelpie serve run'." >&2
            pkill -f 'kelpie serve run' && echo "Stopped background proxy." || echo "No background proxy running."
            return 0 ;;
      start) echo "The proxy runs via 'kelpie serve run'. To check the proxy status run: 'kelpie serve status'" >&2
            echo "To (re)start manually: 'nohup kelpie serve run > /tmp/kelpie-serve.log 2>&1 &'" >&2
            return 1 ;;
    esac
  fi
  command kelpie "$@"
}
SHIM
fi

# Gemini CLI configuration. The edag-gemini feature stores the settings JSON at
# /opt/edag/gemini-config.reference.json during the image build; copy it into place at
# container create. The Kelpie base URL arrives via /etc/profile.d/edag-ai.sh below.
mkdir -p ~/.gemini
GEMINI_REF="/opt/edag/gemini-config.reference.json"
if [ -f "$GEMINI_REF" ] && jq empty "$GEMINI_REF" > /dev/null 2>&1; then
  cp "$GEMINI_REF" ~/.gemini/settings.json
  chmod 600 ~/.gemini/settings.json
  echo "Gemini CLI config copied from $GEMINI_REF."
else
  echo "edag-gemini reference config missing - no Gemini settings written (configure ~/.gemini/settings.json manually)."
fi
sudo tee /etc/profile.d/edag-ai.sh > /dev/null <<EOF
export GOOGLE_GEMINI_BASE_URL="${KELPIE_BASE}/gemini"
export GEMINI_API_KEY="kelpie"
EOF

echo "setup-clis completed (mode: ${KELPIE_MODE:-NONE}, kelpie base: ${KELPIE_BASE})."
selfheal_tools=""
for hook in /opt/edag/selfheal/*.sh; do
  [ -e "$hook" ] && selfheal_tools="${selfheal_tools} $(basename "$hook" .sh)"
done
echo "The per-feature hooks configure their own CLIs:${selfheal_tools:- none}."
echo "Only the Gemini config is still written by this script."
