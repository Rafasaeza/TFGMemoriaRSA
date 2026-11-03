#!/usr/bin/env bash
# Build script for TFG: xelatex + biber + nomenclature (makeindex)
#   ./build.sh          compile
#   ./build.sh clean    clean auxiliary files
# Works on Linux, macOS, WSL, and Git Bash / MSYS2 without machine-specific paths.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT" || exit 1
DOC="main"
LOG="./build.log"

#───────── clean ──────────────────────────────────────────────────────────────
if [ "${1:-}" = "clean" ]; then
  rm -f "$DOC".{aux,toc,lof,lot,bbl,blg,nlo,nls,ilg,out,run.xml,bcf,log,fls,synctex.gz} "$DOC.pdf" "$LOG" "$LOG.biber" "$LOG.makeindex"
  echo "Auxiliary files cleaned."
  exit 0
fi

#───────── localización dinámica de ejecutables ──────────────────────────────
probe_tool() {
  local tool="$1"
  local p

  # 1. Comprobar en el PATH del sistema (Linux, macOS, WSL o Git Bash)
  for name in "$tool" "$tool.exe"; do
    if command -v "$name" >/dev/null 2>&1; then
      p="$(command -v "$name")"
      if [ -x "$p" ] || { "$p" --version >/dev/null 2>&1; }; then
        echo "$p"
        return 0
      fi
    fi
  done

  # 2. Si estamos en WSL o Git Bash con utilidades de Windows disponibles
  if command -v where.exe >/dev/null 2>&1; then
    local w
    w="$(where.exe "$tool" 2>/dev/null | tr -d '\r' | head -n 1 || true)"
    if [ -n "$w" ]; then
      if command -v wslpath >/dev/null 2>&1; then
        w="$(wslpath -u "$w" 2>/dev/null || echo "$w")"
      fi
      if [ -e "$w" ]; then
        echo "$w"
        return 0
      fi
    fi
  elif command -v cmd.exe >/dev/null 2>&1; then
    local w
    w="$(cmd.exe /c "where $tool" 2>/dev/null | tr -d '\r' | head -n 1 || true)"
    if [ -n "$w" ]; then
      if command -v wslpath >/dev/null 2>&1; then
        w="$(wslpath -u "$w" 2>/dev/null || echo "$w")"
      fi
      if [ -e "$w" ]; then
        echo "$w"
        return 0
      fi
    fi
  fi

  # 3. macOS: rutas estándar de MacTeX y Homebrew
  local mac_paths=(
    "/Library/TeX/texbin/$tool"
    "/Library/TeX/Distributions/.DefaultTeX/Contents/Programs/texbin/$tool"
    "/usr/texbin/$tool"
    "/opt/homebrew/bin/$tool"
    "/usr/local/bin/$tool"
  )
  for c in "${mac_paths[@]}"; do
    if [ -f "$c" ] && [ -x "$c" ]; then
      echo "$c"
      return 0
    fi
  done

  # 4. Linux: rutas estándar de TeX Live fuera de PATH
  shopt -s nullglob
  local linux_globs=(
    /usr/local/texlive/*/bin/*/"$tool"
    /opt/texlive/*/bin/*/"$tool"
    "$HOME/.local/bin/$tool"
  )
  for c in "${linux_globs[@]}"; do
    if [ -f "$c" ] && [ -x "$c" ]; then
      shopt -u nullglob
      echo "$c"
      return 0
    fi
  done

  # 5. Git Bash / MSYS2 usando variables de entorno de Windows
  if [ -n "${LOCALAPPDATA:-}" ]; then
    for c in "$LOCALAPPDATA/Programs/MiKTeX/miktex/bin/x64/$tool.exe" \
             "$LOCALAPPDATA/Programs/MiKTeX/miktex/bin/$tool.exe"; do
      if [ -f "$c" ]; then
        shopt -u nullglob
        echo "$c"
        return 0
      fi
    done
  fi

  # 6. Búsqueda dinámica en carpetas de Windows (Git Bash: /c/..., WSL: /mnt/c/...)
  local win_globs=(
    # Git Bash / MSYS2
    /c/Users/*/AppData/Local/Programs/MiKTeX/miktex/bin/x64/"$tool.exe"
    /c/Users/*/AppData/Local/Programs/MiKTeX/miktex/bin/"$tool.exe"
    "/c/Program Files/MiKTeX/miktex/bin/x64/$tool.exe"
    "/c/Program Files/MiKTeX 2.9/miktex/bin/x64/$tool.exe"
    "/c/Program Files (x86)/MiKTeX/miktex/bin/$tool.exe"
    /c/texlive/*/bin/windows/"$tool.exe"
    /c/texlive/*/bin/win32/"$tool.exe"

    # WSL (/mnt/[c-z]/...)
    /mnt/[c-z]/Users/*/AppData/Local/Programs/MiKTeX/miktex/bin/x64/"$tool.exe"
    /mnt/[c-z]/Users/*/AppData/Local/Programs/MiKTeX/miktex/bin/"$tool.exe"
    "/mnt/[c-z]/Program Files/MiKTeX/miktex/bin/x64/$tool.exe"
    "/mnt/[c-z]/Program Files/MiKTeX 2.9/miktex/bin/x64/$tool.exe"
    "/mnt/[c-z]/Program Files (x86)/MiKTeX/miktex/bin/$tool.exe"
    /mnt/[c-z]/texlive/*/bin/windows/"$tool.exe"
    /mnt/[c-z]/texlive/*/bin/win32/"$tool.exe"
  )
  for c in "${win_globs[@]}"; do
    if [ -f "$c" ]; then
      shopt -u nullglob
      echo "$c"
      return 0
    fi
  done
  shopt -u nullglob

  return 1
}

XELATEX="$(probe_tool xelatex)"
BIBER="$(probe_tool biber)"
MAKEINDEX="$(probe_tool makeindex)"

if [ -z "$XELATEX" ] || [ -z "$BIBER" ]; then
  echo "========================================================================"
  echo "ERROR: Required LaTeX tools not found."
  [ -z "$XELATEX" ] && echo "  - Missing: xelatex"
  [ -z "$BIBER" ]   && echo "  - Missing: biber"
  echo "------------------------------------------------------------------------"
  echo "Recommended installation by operating system:"
  echo ""
  echo "  * Ubuntu / Debian / WSL (Linux):"
  echo "      sudo apt update"
  echo "      sudo apt install -y texlive-xetex texlive-bibtex-extra biber texlive-science texlive-fonts-extra texlive-lang-spanish"
  echo ""
  echo "  * Fedora / RHEL:"
  echo "      sudo dnf install -y texlive-xetex texlive-biber texlive-nomencl"
  echo ""
  echo "  * Arch Linux:"
  echo "      sudo pacman -S texlive-bin texlive-bibtexextra biber"
  echo ""
  echo "  * macOS (with Homebrew):"
  echo "      brew install --cask mactex"
  echo "      (or: brew install basictex && eval \"\$(/usr/libexec/path_helper)\")"
  echo ""
  echo "  * Windows (PowerShell / Git Bash):"
  echo "      Install MiKTeX (https://miktex.org) or run in CMD/PowerShell:"
  echo "      winget install MiKTeX.MiKTeX"
  echo "      (ensure 'Install missing packages on the fly' is enabled)"
  echo "========================================================================"
  exit 1
fi

ENGINE="texlive"
case "$XELATEX" in
  *[Mm][Ii][Kk][Tt][Ee][Xx]*) ENGINE="miktex" ;;
esac
echo "Toolchain: $ENGINE  (xelatex: $XELATEX)"

ENGINE_ARGS=("-synctex=1" "-interaction=nonstopmode" "-file-line-error")
if [ "$ENGINE" = "miktex" ]; then
  # Allows MiKTeX to download missing packages without blocking the console
  ENGINE_ARGS=("-enable-installer" "${ENGINE_ARGS[@]}")
fi

#───────── execution ──────────────────────────────────────────────────────────
run_engine() {
  "$XELATEX" "${ENGINE_ARGS[@]}" "$DOC.tex" >"$LOG" 2>&1
}

abort() {
  echo "FAILED: $1"
  echo "--- First error lines (file:line format) ---"
  grep -E "^([^ ]+):[0-9]+: |^! " "$LOG" | head -15
  echo "--- End of $LOG ---"
  tail -25 "$LOG"
  exit 1
}

step() { printf '  -> %s\n' "$1"; }

# A truncated .aux file from concurrent or aborted builds causes
# "Missing \begin{document}" / "Extra }" errors: clean and retry.
aux_error() { grep -qE "main\.aux.*: (Missing .begin\{document\}|Extra \}, or forgotten|File ended while scanning)|\\\\@firstoffive" "$LOG"; }

engine_step() {
  run_engine && return 0
  if aux_error; then
    echo "  warning: corrupt main.aux (concurrent/aborted build) -> cleaning and retrying"
    rm -f "$DOC".{aux,toc,lof,lot,fls,out}
    run_engine || abort "$1 (after cleaning .aux)"
  else
    abort "$1"
  fi
}

step() { printf '  -> %s\n' "$1"; }

step "xelatex (1/3)";            engine_step "xelatex (1/3)"
step "biber (bibliography)";     "$BIBER" "$DOC" >"$LOG.biber" 2>&1 \
                                   || { tail -20 "$LOG.biber"; abort "biber (check references.bib)"; }
step "makeindex (nomenclature)"
if [ -n "$MAKEINDEX" ]; then
  "$MAKEINDEX" "$DOC.nlo" -s nomencl.ist -o "$DOC.nls" >"$LOG.makeindex" 2>&1 \
    || abort "makeindex"
else
  echo "  warning: makeindex not found, nomenclature will not be regenerated"
fi
step "xelatex (2/3)";            engine_step "xelatex (2/3)"
step "xelatex (3/3)";            engine_step "xelatex (3/3)"

[ -f "$DOC.pdf" ] || abort "main.pdf was not generated"

PAGES="$(grep -o "$DOC.pdf ([0-9]*" "$LOG" | grep -o '[0-9]*$' | head -1)"
UNRESOLVED="$(grep -c "Citation.*undefined\|Reference .*undefined" "$LOG")"
echo "OK -> $DOC.pdf (${PAGES:-?} pages)"
[ "${UNRESOLVED:-0}" -gt 0 ] && echo "warning: $UNRESOLVED unresolved citations/references -> rerun ./build.sh"
exit 0
