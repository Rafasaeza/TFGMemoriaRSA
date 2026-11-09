#!/usr/bin/env bash
set -euo pipefail

AT_BUILD="${ATBUILD:-never}"
INSTALLER_URL="${INSTALLERURL:-https://gitlab-pages.edag.de/dare/kelpie/install.sh}"

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

if [ "${AT_BUILD}" = "never" ]; then
  echo "edag-kelpie: atBuild=never - skipping build-time install (setup-clis.sh installs it at container create)."
  exit 0
fi

# The Kelpie bootstrap downloads the real binary from SharePoint behind a device-code
# login. That login cannot be completed unattended, so this build-time attempt is
# time-boxed and non-fatal; setup-clis.sh keeps a runtime fallback install.
echo "edag-kelpie: attempting build-time install. If a SharePoint device-code login appears below,"
echo "edag-kelpie: open the printed URL in a browser within a few minutes to bake Kelpie into the image."

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT
chmod 755 "${TMP_DIR}"
curl -fsSL --retry 3 --retry-delay 2 --retry-all-errors "${INSTALLER_URL}" -o "${TMP_DIR}/kelpie-install.sh"

if as_user "timeout 240 bash '${TMP_DIR}/kelpie-install.sh' -y" </dev/null; then
  echo "edag-kelpie: build-time install finished."
else
  echo "WARNING: edag-kelpie: build-time install did not complete (login pending or offline)."
  echo "WARNING: edag-kelpie: setup-clis.sh will install Kelpie at container create instead."
fi

if [ -x "${TARGET_HOME}/.local/bin/kelpie" ]; then
  ln -sfn "${TARGET_HOME}/.local/bin/kelpie" /usr/local/bin/kelpie
  echo "edag-kelpie: Kelpie baked into the image: $(command -v kelpie)"
fi
