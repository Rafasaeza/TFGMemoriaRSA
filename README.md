# Bachelor's Thesis (TFG) - ETSI Informática, Universidad de Málaga

This repository contains the LaTeX source code and build automation for the Bachelor's Thesis (*Trabajo Fin de Grado*).

The document is compiled using **XeLaTeX**, **Biber** (for BibLaTeX bibliographies), and **MakeIndex** (for nomenclature and symbols).

---

## Quick Start

The build scripts automatically locate your LaTeX distribution across all operating systems without requiring hardcoded paths.

### Windows

You can build using either Command Prompt (CMD) or PowerShell:

- **Command Prompt (CMD) or Double-Click:**
  ```cmd
  build.bat
  ```
  To clean auxiliary files:
  ```cmd
  build.bat -Clean
  ```

- **PowerShell:**
  ```powershell
  .\build.ps1
  ```
  To clean auxiliary files:
  ```powershell
  .\build.ps1 -Clean
  ```

### Linux / macOS / WSL

Run the Bash build script or use `make`:

- **Using Bash:**
  ```bash
  ./build.sh
  ```
  To clean auxiliary files:
  ```bash
  ./build.sh clean
  ```

- **Using Make:**
  ```bash
  make
  make clean
  ```

### Visual Studio Code

If you use the **LaTeX Workshop** extension in VS Code:
- Open the project in VS Code.
- Recipes are configured in `.vscode/settings.json`:
  - `Linux / macOS / WSL (build.sh)`
  - `Windows (build.ps1)`
- Press `Ctrl+Alt+B` (or `Cmd+Alt+B` on macOS) to build, or save any `.tex` file to trigger an auto-build.

### Overleaf

If uploading the project to Overleaf:
1. Open **Menu** (top left).
2. Set **Compiler** to **XeLaTeX**.
3. Set **TeX Live version** to the latest available (e.g., 2024 or newer).

---

## Prerequisites & Installation

The project requires three command-line tools: `xelatex`, `biber`, and `makeindex`.

### Ubuntu / Debian / WSL (Linux)
Install the required packages using `apt`:
```bash
sudo apt update
sudo apt install -y texlive-xetex texlive-bibtex-extra biber texlive-science texlive-fonts-extra texlive-lang-spanish
```

### Fedora / RHEL
Install the required packages using `dnf`:
```bash
sudo dnf install -y texlive-xetex texlive-biber texlive-nomencl
```

### Arch Linux
Install the required packages using `pacman`:
```bash
sudo pacman -S texlive-bin texlive-bibtexextra biber
```

### macOS
Install MacTeX using Homebrew:
```bash
brew install --cask mactex
```
*(Or install BasicTeX: `brew install basictex && eval "$(/usr/libexec/path_helper)"`)*

### Windows
1. Download and install **MiKTeX** from [miktex.org](https://miktex.org), or install via `winget`:
   ```cmd
   winget install MiKTeX.MiKTeX
   ```
2. During installation, select **"Install missing packages on the fly: Yes"**.
   *(The build scripts also automatically pass `-enable-installer` so missing CTAN packages will be downloaded silently in the background on first run).*
3. Alternatively, install [TeX Live for Windows](https://www.tug.org/texlive/).

---

## Project Structure

```text
├── main.tex                 # Root LaTeX document
├── references.bib           # BibLaTeX bibliography database
├── build.sh                 # Unix/Linux/macOS/WSL build script
├── build.ps1                # Windows PowerShell build script
├── build.bat                # Windows CMD wrapper
├── Makefile                 # Make wrapper
├── abstract/                # Spanish & English abstracts
├── introduction/            # Chapter 1: Introduction
├── technologies/            # Chapter 2: Technologies
├── stateOfTheArt/           # Chapter 3: State of the Art
├── requirementsAnalysis/    # Chapter 4: Requirements
├── systemArchitecture/      # Chapter 5: Architecture design
├── systemImplementation/    # Chapter 6: Implementation details
├── testingEvaluation/       # Chapter 7: Testing and evaluation
├── conclusions/             # Chapter 8: Conclusions and future work
├── appendices/              # Appendices
├── nomenclature/            # Nomenclature and glossary entries
├── figures/                 # Diagrams, plots, and architecture images
└── template/                # University cover pages, styles, and fonts
```
