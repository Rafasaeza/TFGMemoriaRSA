#!/usr/bin/env bash
# Build del TFG: xelatex + biber + nomenclatura (makeindex)
#   ./build.sh          compilar
#   ./build.sh clean    borrar auxiliares
# Funciona en WSL (TeX Live) y en Git Bash / PowerShell (MiKTeX).
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT" || exit 1
DOC="main"
LOG="./build.log"

#───────── clean ──────────────────────────────────────────────────────────────
if [ "${1:-}" = "clean" ]; then
  rm -f "$DOC".{aux,toc,lof,lot,bbl,blg,nlo,nls,ilg,out,run.xml,bcf,log,fls,synctex.gz} "$DOC.pdf" "$LOG"
  echo "Limpiados los auxiliares."
  exit 0
fi

#───────── localización de los ejecutables ────────────────────────────────────
MIK='Users/rs97881/AppData/Local/Programs/MiKTeX/miktex/bin/x64'
probe() {  # probe <bin> -> imprime ruta ejecutable o nada
  local b="$1" c
  for c in "$b" "$b.exe" "/mnt/c/$MIK/$b.exe" "C:/$MIK/$b.exe" "/c/$MIK/$b.exe"; do
    if command -v "$c" >/dev/null 2>&1 && { "$c" --version >/dev/null 2>&1 || "$c" >/dev/null 2>&1; }; then
      echo "$c"; return 0
    fi
  done
  return 1
}

XELATEX="$(probe xelatex)"
BIBER="$(probe biber)"
MAKEINDEX="$(probe makeindex)"

if [ -z "$XELATEX" ] || [ -z "$BIBER" ]; then
  echo "FALLO: no encuentro xelatex/biber en el PATH."
  echo "       Añade la carpeta bin de MiKTeX al PATH o ejecútalo desde WSL con TeX Live."
  exit 1
fi

ENGINE="texlive"; case "$XELATEX" in *MiKTeX*|*miktex*) ENGINE="miktex";; esac
echo "Toolchain: $ENGINE  (xelatex: $XELATEX)"

#───────── ejecución ──────────────────────────────────────────────────────────
run_engine() {
  "$XELATEX" -synctex=1 -interaction=nonstopmode -file-line-error "$DOC.tex" >"$LOG" 2>&1
}

abort() {
  echo "FALLO: $1"
  echo "--- primeras lineas de error (formato archivo:linea) ---"
  grep -E "^([^ ]+):[0-9]+: |^! " "$LOG" | head -15
  echo "--- final de $LOG ---"
  tail -25 "$LOG"
  exit 1
}

# Un .aux truncado por dos compilaciones a la vez da "Missing \begin{document}"
check_aux_race() {
  if grep -q "Missing .begin{document}" "$LOG"; then
    echo "  aviso: main.aux ilegible (compilación concurrente) -> limpio y reintento"
    rm -f "$DOC".{aux,toc,lof,lot,fls,out}
    run_engine || abort "xelatex tras limpiar .aux"
  fi
}

step() { printf '  -> %s\n' "$1"; }

step "xelatex (1/3)";            run_engine || abort "xelatex (1/3)"
check_aux_race
step "biber (bibliografía)";     "$BIBER" "$DOC" >"$LOG.biber" 2>&1 \
                                   || { tail -20 "$LOG.biber"; abort "biber (revisa references.bib)"; }
step "makeindex (nomenclatura)"
if [ -n "$MAKEINDEX" ]; then
  "$MAKEINDEX" "$DOC.nlo" -s nomencl.ist -o "$DOC.nls" >"$LOG.makeindex" 2>&1 \
    || abort "makeindex"
else
  echo "  aviso: no hay makeindex, la nomenclatura no se regenerará"
fi
step "xelatex (2/3)";            run_engine || abort "xelatex (2/3)"
check_aux_race
step "xelatex (3/3)";            run_engine || abort "xelatex (3/3)"
check_aux_race

[ -f "$DOC.pdf" ] || abort "no se generó $DOC.pdf"

PAGES="$(grep -o "$DOC.pdf ([0-9]*" "$LOG" | grep -o '[0-9]*$' | head -1)"
UNRESOLVED="$(grep -c "Citation.*undefined\|Reference .*undefined" "$LOG")"
echo "OK -> $DOC.pdf (${PAGES:-?} páginas)"
[ "${UNRESOLVED:-0}" -gt 0 ] && echo "aviso: $UNRESOLVED citas/referencias sin resolver -> repite ./build.sh"
exit 0
