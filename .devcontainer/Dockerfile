# syntax=docker/dockerfile:1
FROM ubuntu:22.04

ARG DEBIAN_FRONTEND=noninteractive
SHELL ["/bin/bash", "-lc"]

# Basis-Pakete (SSL, Curl, Git)
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates curl gnupg git build-essential ripgrep vim sudo jq unzip locales \
 && rm -rf /var/lib/apt/lists/*

# LaTeX-Toolchain fuer build.sh / Makefile (xelatex + biber + makeindex + latexmk).
# Ohne diesen Block bricht build.sh mit "ERROR: Required LaTeX tools not found" ab,
# sobald der Container neu gebaut wird - von Hand installiertes TeX ueberlebt das nicht.
# Die Malacitana-Fonts liegen im Repo unter template/fonts/ (fontspec Path), deshalb
# ist texlive-fonts-extra nicht noetig. texlive-lang-spanish deckt die spanischen
# Umbrueche ab; en_US.UTF-8 wird generiert, weil biber ein Perl-Tool ist und sonst
# bei jedem Aufruf vor einer nicht installierten Locale warnnt.
RUN apt-get update && apt-get install -y --no-install-recommends \
    texlive-xetex texlive-latex-recommended texlive-latex-extra \
    texlive-fonts-recommended texlive-bibtex-extra texlive-science \
    texlive-lang-spanish biber latexmk \
 && locale-gen en_US.UTF-8 \
 && rm -rf /var/lib/apt/lists/*

# vscode-User
RUN useradd -m -s /bin/bash vscode

# Kelpie-Config-Verzeichnis (Volume-Mount; Owner aus Image uebernehmen)
RUN mkdir -p /home/vscode/.config/kelpie \
 && touch /home/vscode/.config/kelpie/.keep \
 && chown -R vscode:vscode /home/vscode/.config

# Passwortloses sudo für vscode
RUN echo "vscode ALL=(root) NOPASSWD:ALL" > /etc/sudoers.d/90-vscode \
 && chmod 0440 /etc/sudoers.d/90-vscode

# Setup-Script (committed, keine Secrets; Tool-Configs werden zur Laufzeit geschrieben)
COPY .devcontainer/setup-clis.sh /usr/local/bin/setup-clis.sh
RUN chmod +x /usr/local/bin/setup-clis.sh

USER vscode
WORKDIR /workspaces
