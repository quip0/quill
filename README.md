# Quill

A single-page reading dashboard for KOReader.

Quill replaces the home screen with one screen and nothing else:

- **Reading heatmap** — GitHub/Anki style. One column per week, Sunday to
  Saturday, most recent week on the right. The more pages read that day, the
  darker the square. Today's square is outlined.
- **Selected book** — cover, title, author and progress for one book, with a
  **Continue reading** button that opens it. The most recently read book is
  selected when the page opens.
- **Recent books** — a strip of the six most recently opened books' covers,
  most recent first, each with a thin progress bar. Tap a cover to select it.

Quill owns the **home screen only**. It deliberately does not touch the reader,
so a reader-side UI plugin such as Zen UI keeps working alongside it: Quill
while you are choosing what to read, Zen once you are inside a book.

## Install

Copy `quill.koplugin/` into your KOReader `plugins/` directory and restart.

```sh
cp -R quill.koplugin /path/to/koreader/plugins/
```

## Usage

By default Quill appears whenever the file browser opens — at startup and each
time you close a book. Dismiss it (swipe down, or Back) to drop into your
normal library view.

Under **Tools → Quill**:

- **Open Quill home** — show the page on demand
- **Use as home screen** — toggle the takeover, on by default

A `Quill home` action is also registered with the Dispatcher, so it can be
bound to a gesture or profile.

## How it works

| Feature | Source |
| --- | --- |
| Heatmap | `statistics.sqlite3`, via the `page_stat` view, aggregated per day |
| Recent books | `ReadHistory`, ordered most-recent-first |
| Cover, title, author | `BookInfoManager` (CoverBrowser's cache) |
| Progress | the book's `.sdr` sidecar |

All of these are read-only. Quill never writes to your statistics, history or
sidecar files.

Two details worth knowing:

- The statistics plugin buffers the current session in memory, so Quill forces
  a flush before querying. Without it, today's reading would be missing.
- Heatmap shading is **relative**: the darkest shade means "your busiest day in
  the window shown", so the scale adapts as your habits change. GitHub uses
  fixed thresholds instead — see `LEVEL_COLORS` and `Heatmap:levelFor` if you
  prefer that.

### Metadata sanitizing

Embedded book metadata is often wrong, so Quill corrects two recurring cases
before display:

- Scanned PDFs frequently carry the scanner's output filename as their title
  (`img-Z03140005.pdf`); Quill falls back to the filename.
- Some EPUBs store the title twice (`Shadow Divers Shadow Divers`); Quill
  collapses an exactly-doubled title. Only when both halves are multi-word, so
  genuine reduplications (`Boom Boom`, `Sing Sing`) survive.

Placeholder authors (`Administrator`, `calibre`, `Unknown`) are dropped rather
than shown, since they read as a real credit.

These are heuristics: they fix bad data rather than read correct data. See
`cleanTitle` in `common/recent.lua` to adjust or remove them.

## Layout

```
quill.koplugin/
  main.lua                plugin entry, menu, home-screen takeover
  common/stats.lua        per-day page counts
  common/recent.lua       recent books + metadata sanitizing
  widgets/home_page.lua   assembles the page
  widgets/heatmap.lua     the activity grid
  widgets/book_detail.lua the selected book and its button
  widgets/cover_cell.lua  one cover in the recent-books strip
  widgets/tap_text.lua    a line of text with a generous tap target
  widgets/topbar.lua      icon dashbar (built, not currently shown)
```

## Development

Pure Lua, so there is no build step — edit and restart. Test against the
KOReader emulator:

```sh
# from a KOReader build directory
QUILL_AUTOSHOW=1 ./luajit reader.lua -d /path/to/books
```

Two environment hooks help when the UI cannot be driven by hand:

| Variable | Effect |
| --- | --- |
| `QUILL_AUTOSHOW=1` | open the home page on startup |
| `QUILL_SHOT=<path>` | dump the screen to a PNG |
| `QUILL_SHOT_DELAY=<seconds>` | when to capture (default 3) |

They are independent, so `QUILL_SHOT` alone captures whatever KOReader is
showing.

## Status

Early. Developed against KOReader v2025.10, targeting a Kindle Paperwhite 5.
Layout has been verified in the emulator at the device's aspect ratio, but not
yet on physical hardware at full resolution.
