# Bundled CLI tools

Place offline binaries here before building a distributable `.dmg`:

```
tools/
├── poppler/pdftoppm, pdftotext
├── qpdf/qpdf
├── ghostscript/gs
├── libreoffice/soffice (+ frameworks)
└── tesseract/tesseract (+ tessdata/)
```

Run from repo root:

```bash
./Scripts/bundle-tools.sh
```

Development: if this folder is empty, the app falls back to tools on your `PATH` (e.g. Homebrew).
