#!/usr/bin/env bash
#
# Deploy DocShare to a VPS with OTP hot-code upgrades (Castle/Forecastle).
#
#   - First deploy (or `--full`): build a release tar on the VPS, extract it to
#     the release root, run DB migrations, (re)start the systemd service.
#   - Subsequent deploys: build the new versioned tar, generate a relup against
#     the running version, run DB migrations, install it into the LIVE node —
#     no restart, no dropped connections.
#   - If the old release .rel file is missing (e.g. after a manual rollback or
#     first run after switching to Castle), falls back to a full deploy.
#
# Version is read from mix.exs; bump it (and update appup.ex) before deploying.
# The easiest way is `make hooks` once — the pre-commit hook auto-bumps on main.
#
# Layout on the server:
#   current repo  <- source checkout where `mix release` runs (keeps _build)
#   $BASE/app     <- extracted release root; systemd runs $BASE/app/bin/docshare
#   .env          <- optional runtime env loaded by config/runtime.exs
#
# Optional overrides:
#   BASE     (default /opt/docshare)
#   SERVICE  (default docshare)
#   RESTART  (default "sudo systemctl")
#
# Usage: ./deploy.sh [--full]
#
set -euo pipefail
cd "$(dirname "$0")"

BASE="${BASE:-/opt/docshare}"
SERVICE="${SERVICE:-docshare}"
RESTART="${RESTART:-sudo systemctl}"
APP_NAME="docshare"

BUILD_DIR="$PWD"
APP_DIR="$BASE/app"

FORCE_FULL=0
[[ "${1:-}" == "--full" ]] && FORCE_FULL=1

green() { printf '\033[0;32m%s\033[0m\n' "$1"; }
red()   { printf '\033[0;31m%s\033[0m\n' "$1" >&2; }
step()  { printf '\n\033[1;36m==> %s\033[0m\n' "$1"; }

VSN="$(grep -m1 -E '^\s*version:' mix.exs | sed -E 's/.*"([^"]+)".*/\1/')"
[[ -n "$VSN" ]] || { red "Could not read version from mix.exs."; exit 1; }

green "Deploying $APP_NAME v$VSN to $BASE"

step "Checking local prerequisites"
mkdir -p "$APP_DIR"
for bin in mix elixir; do
  command -v "$bin" >/dev/null || { red "Missing $bin on server (install Erlang/Elixir)."; exit 1; }
done

step "Building release v$VSN"
export MIX_ENV=prod
mix local.hex --force >/dev/null
mix local.rebar --force >/dev/null
mix deps.get --only prod
mix compile
mix assets.setup
mix assets.deploy
mix release --overwrite

# Determine the currently running version (empty if not running / not yet installed).
CUR_VSN="$(test -x "$APP_DIR/bin/docshare" && \
  "$APP_DIR/bin/docshare" releases 2>/dev/null | \
  awk '{ for (i=1;i<=NF;i++) if (tolower($i)=="permanent" && i>1) { print $(i-1); exit } }' \
  || true)"
CUR_VSN="$(echo "$CUR_VSN" | tr -d '[:space:]')"

# Decide deploy mode. Fall back to full when old .rel is missing so a hot
# upgrade is never attempted against a release that isn't properly installed.
DEPLOY_MODE="hot"
if [[ "$FORCE_FULL" == "1" || -z "$CUR_VSN" || "$CUR_VSN" == "$VSN" ]]; then
  DEPLOY_MODE="full"
fi
if [[ "$DEPLOY_MODE" == "hot" ]]; then
  OLD_REL="$APP_DIR/releases/${CUR_VSN}/${APP_NAME}.rel"
  if [[ ! -f "$OLD_REL" ]]; then
    red "Old .rel not found for $CUR_VSN ($OLD_REL) — falling back to full deploy."
    DEPLOY_MODE="full"
  fi
fi

TAR="$BUILD_DIR/_build/prod/${APP_NAME}-${VSN}.tar.gz"
[[ -f "$TAR" ]] || { red "Release tar not found: $TAR"; exit 1; }

if [[ "$DEPLOY_MODE" == "full" ]]; then
  # ---------------------- FULL DEPLOY ----------------------------------------
  if [[ "$CUR_VSN" == "$VSN" ]]; then
    step "Full redeploy: refreshing v$VSN in $APP_DIR"
  else
    step "Full deploy: extracting v$VSN into $APP_DIR"
  fi

  tar xzf "$TAR" -C "$APP_DIR"

  $RESTART restart "$SERVICE"
  sleep 2
  $RESTART --no-pager --full status "$SERVICE" | head -n 10 || true
  green "Full deploy of v$VSN complete."

else
  # ---------------------- HOT UPGRADE (relup, no restart) --------------------
  step "Hot upgrade: $CUR_VSN -> $VSN (no restart)"
  TARGET="$BUILD_DIR/_build/prod/rel/${APP_NAME}/releases/${VSN}/${APP_NAME}"
  FROMTO="$APP_DIR/releases/${CUR_VSN}/${APP_NAME}"

  echo "-> generating relup ${CUR_VSN} -> ${VSN}"
  mix forecastle.relup --target "$TARGET" --fromto "$FROMTO" --outdir "$BUILD_DIR"
  [[ -f "$BUILD_DIR/relup" ]] || { red "relup was not generated (check appup.ex)."; exit 1; }

  echo "-> rebuilding release to embed relup"
  mix release --overwrite >/dev/null

  echo "-> unpacking new release"
  cp "$TAR" "$APP_DIR/releases/${APP_NAME}-${VSN}.tar.gz"
  "$APP_DIR/bin/${APP_NAME}" unpack "$VSN"

  echo "-> running database migrations"
  MIX_ENV=prod mix ecto.migrate

  echo "-> installing into the running node"
  "$APP_DIR/bin/${APP_NAME}" install "$VSN"
  "$APP_DIR/bin/${APP_NAME}" commit "$VSN"

  echo "-> current releases:"
  "$APP_DIR/bin/${APP_NAME}" releases
  rm -f "$BUILD_DIR/relup"
  green "Hot upgrade to v$VSN complete (no downtime)."
fi

green "
App:  https://${PHX_HOST:-docshare.gatetroy.com}
Logs: journalctl -u $SERVICE -f
"

# ------------------------------------------------------------------------------
# FIRST-TIME SERVER SETUP (run once, by hand)
#   1. Install Erlang/Elixir (match local OTP 27) and Node 18+.
#   2. sudo useradd -m -d /opt/docshare -s /bin/bash docshare
#      sudo mkdir -p /opt/docshare/{build,app} && sudo chown -R docshare:docshare /opt/docshare
#   3. sudo -u postgres createuser docshare --pwprompt
#      sudo -u postgres createdb docshare_prod -O docshare
#   4. cp deploy/env.prod.example .env   (edit; chmod 600;
#      generate SECRET_KEY_BASE with `mix phx.gen.secret`)
#   5. sudo cp deploy/docshare.service /etc/systemd/system/docshare.service
#      sudo systemctl daemon-reload && sudo systemctl enable docshare
#   6. echo 'docshare ALL=(root) NOPASSWD: /bin/systemctl restart docshare, /bin/systemctl status docshare' \
#        | sudo tee /etc/sudoers.d/docshare
#   7. Reverse proxy (nginx/Caddy) TLS for docshare.gatetroy.com -> 127.0.0.1:4000
#   8. Run once: make hooks   (installs the pre-commit version-bump hook)
#   9. ./deploy.sh            (first run does the full deploy + starts the service)
# Thereafter: commit your changes on main (hook bumps version) then ./deploy.sh
# ------------------------------------------------------------------------------
