# DocShare

A Phoenix + LiveView app to **host an HTML document online, share it by email,
and collect comments on each part of the page in real time.**

> The OTP app is named `docshare` because an Elixir app cannot be named
> `phoenix` (it collides with the framework dependency).

## Features

- **Accounts** — email + password auth (`phx.gen.auth`).
- **Documents** — create a doc by pasting HTML or uploading an `.html` file.
  Each doc gets an unguessable share URL (`/docs/:token`).
- **Versions** — a document holds multiple versions (v1, v2, …). The owner adds a
  new version (paste or upload) from the doc page; a version selector switches the
  rendered HTML. **Comments are scoped to a version**, so each version keeps its
  own per-part discussion and the selector shows each version's open-comment count.
  The document's own `<style>`/`<link>` are preserved, so it renders as designed.
- **Safe rendering** — user HTML is parsed with Floki: `<script>`/`<iframe>`/etc.
  and `on*` / `javascript:` handlers are stripped, then rendered inside a
  `sandbox="allow-scripts"` iframe (isolated origin — no access to app cookies/DOM).
- **Per-part commenting** — every block element (`p`, `h1`–`h6`, `li`,
  `blockquote`, `pre`, `td`, …) is tagged with a stable anchor. Click any part
  to open its comment thread; a badge shows the open-comment count.
- **Sharing by email** — the owner invites collaborators by email; an invitation
  email is sent (Swoosh — lands in `/dev/mailbox` in development). Invited users
  get access once they sign in with that address.
- **Real-time** — comments and collaborator changes broadcast over Phoenix
  PubSub, so everyone viewing a doc sees updates live.
- **Compare versions** — when a document has 2+ versions, "⇄ Compare" shows a
  *rendered redline* (git-diff style) between any two versions: unchanged blocks
  render normally, removed blocks red/struck-through, added blocks green — all
  with the document's own styling, in a sandboxed iframe (no raw source shown).
  A step sidebar lists every change; clicking one scrolls the diff to that block.
- **Fullscreen** — the document render pane has a fullscreen toggle (Esc to exit)
  that doesn't reload the iframe.
- **Export comments for an LLM** — "Export comments" produces a plain-text bundle
  pairing each commented section's content with its comment(s), plus an
  instruction header, ready to copy into a prompt to have an LLM revise the doc.
- **Mermaid diagrams** — if a document contains a `mermaid` block (e.g.
  `<pre class="mermaid">graph TD; A--&gt;B;</pre>`), Mermaid is loaded into the
  render frame and the diagram is drawn automatically.

## Running

```bash
mix setup            # deps, db create + migrate, assets
mix phx.server       # http://localhost:4000
```

The DB is configured for a local Postgres superuser (the OS user, no password)
via `config/dev.exs`. Register at `/users/register`, then view sent emails at
`/dev/mailbox`. A sample document you can paste/upload lives in `priv/samples/`.

## Demo

Seed the bundled example report (creates a `demo@docshare.local` account that
owns the `k_sync_go` analysis report as v1, with sample comments):

```bash
mix run priv/repo/demo_seed.exs
# Login: demo@docshare.local / demopassword123
```

## Tests

```bash
mix test
```

## How per-part commenting works

1. `Docshare.Documents.Html.process/1` parses the raw HTML, strips dangerous
   nodes, and adds `data-anchor="b0"`, `b1`, … to block elements in document
   order, returning the processed HTML.
2. `DocumentLive.Show` builds a sandboxed iframe `srcdoc` containing the
   processed HTML plus a small injected script.
3. Clicking a part in the iframe `postMessage`s the anchor id up to the parent;
   the `DocFrame` JS hook forwards it to the LiveView (`select_anchor`).
4. The LiveView shows that anchor's thread; new comments broadcast via PubSub
   and comment counts are pushed back down into the iframe as badges.
