# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Commands

```bash
make setup             # first-time setup: deps, DB create + migrate, assets
make dev               # fetch deps then start the dev server at http://localhost:4000
make server            # start dev server (skips dep check)
make test              # run all tests (auto-creates/migrates test DB)
make migrate           # run DB migrations
make reset             # drop + recreate DB from scratch
make deploy            # pull latest main on VPS then run deploy.sh (hot upgrade)
make deploy-full       # pull latest main on VPS then force full extract + restart
```

For running a subset of tests, use mix directly:
```bash
mix test path/to/file_test.exs          # single test file
mix test path/to/file_test.exs:42       # single test by line
mix run priv/repo/demo_seed.exs        # seed demo account (demo@docshare.local / demopassword123)
```

Dev email (Swoosh): `/dev/mailbox`. DB is local Postgres with OS user auth (no password) per `config/dev.exs`.

## Architecture

**Phoenix 1.7 + LiveView 1.0 app.** Two OTP contexts under `lib/docshare/`:

- `Docshare.Accounts` — `phx.gen.auth`-generated email+password auth (User, UserToken, UserNotifier).
- `Docshare.Documents` — all document logic: Documents, Versions, Collaborators, Comments, HTML processing, email notifications, PubSub broadcasts. All real-time events flow through `Phoenix.PubSub` on the `"doc:<id>"` topic.

**Three LiveViews** under `lib/docshare_web/live/document_live/`:
- `Index` — lists documents the user owns or was invited to.
- `New` — create document (paste or upload HTML).
- `Show` — the main view: renders the document, manages versions, comments, sharing, compare, and export. This file is large; all UI (modals, iframe, comment panel) lives in its `render/1`.

**HTML processing pipeline** (`lib/docshare/documents/html.ex`):
1. Floki parses raw user HTML.
2. Dangerous nodes (`script`, `iframe`, `object`, `embed`, `noscript`) are dropped; `on*` attributes and `javascript:` URLs are stripped.
3. Every leaf block element (`p`, `h1`–`h6`, `li`, `blockquote`, `pre`, `td`, `th`, …) gets a stable `data-anchor="b0"`, `b1`, … attribute.
4. `<style>`/`<link rel=stylesheet>` are extracted as `head_html` and re-injected so the document keeps its own styling.
5. The processed HTML is assembled into a full `srcdoc` string for a `sandbox="allow-scripts"` iframe — fully isolated from the app origin.

**iframe ↔ LiveView bridge** (JS hook `DocFrame` in `assets/js/app.js`):
- Clicks inside the iframe `postMessage` `{type: "ds:select", anchor, label}` up to the parent.
- The hook forwards it to the LiveView as a `select_anchor` event.
- The server pushes `ds:counts` (comment badge map) and `ds:select` (highlight) back down via `push_event`, and the hook relays them into the iframe.

**Version diffing**: `Documents.diff_version_blocks/2` runs `List.myers_difference/2` on the sanitized block list from `Html.blocks/1` (no `data-anchor`, so unchanged blocks compare byte-for-byte). The diff is rendered as a second sandboxed iframe (`build_diff_frame/2`) with `+`/`−` CSS markers; the `DiffNav` JS hook sends `ds:goto` messages into it to scroll to a specific step.

**Comment rendering**: stored as plain text, rendered with a minimal markdown subset (bold, italic, inline code, links) in `format_comment/1` — HTML-escaped first so user input can never inject markup.

**Other JS hooks** in `app.js`: `CommentToolbar` (markdown formatting buttons), `DiffNav` (diff step navigation), `CopyButton` (clipboard copy for export).

## Deployment (VPS, hot-code upgrades)

Releases use Castle/Forecastle for OTP relup-based hot upgrades (no restart, no dropped connections). Before deploying a code change:

1. Bump `version:` in `mix.exs`.
2. Update `appup.ex` to list changed modules for the `old -> new` version pair.
3. Run `./deploy.sh` on the VPS (or `make deploy` from local to pull + run it).

Use `./deploy.sh --full` (or `make deploy-full`) to force a full extract + restart — required for DB migrations, dependency version bumps, or relup failures. Run DB migrations manually before a hot upgrade: `bin/docshare eval "Docshare.Release.migrate()"`.

See `deploy/HOT_UPGRADE.md` for the full checklist and caveats.
