# Quill

A single-page reading dashboard for KOReader.

One screen:

- **Top dashbar** — icon buttons (library, search, history, settings)
- **Reading heatmap** — GitHub/Anki style; darker square = more pages read that day
- **Continue reading** — the three most recently opened books, most recent first

Quill owns the home screen only. It deliberately does not patch the reader
view, so [Zen UI](https://github.com/gaudeti/zen-ui)'s in-book chrome keeps
working alongside it.

## Install

Copy `quill.koplugin/` into your KOReader `plugins/` directory and restart.

## Data sources

- Heatmap: KOReader's `statistics.sqlite3` (`page_stat` view), aggregated per day
- Recent books: `ReadHistory`, enriched via `BookInfoManager` and `.sdr` sidecars

Both are read-only; Quill never writes to them.
