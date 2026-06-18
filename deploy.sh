#!/usr/bin/env bash
#
# Deploy DocShare to a VPS with OTP hot-code upgrades (Castle/Forecastle).
#
#   - First deploy (or `--full`): build a release tar on the VPS, extract it to
#     the release root, (re)start the systemd service.
#   - Subsequent deploys: build the new versioned tar, generate a relup against
#     the running version, install it into the LIVE node — no restart, no dropped
#     connections.
#
# Layout on the server:
#   current repo  <- source checkout where `mix release` runs (keeps _build)
#   $BASE/app     <- extracted release root; systemd runs $BASE/app/bin/docshare
#   $BASE/.env    <- runtime env (EnvironmentFile); also read by runtime.exs
#
# Hot upgrades require an appup describing the change: bump `version:` in mix.exs
# AND update appup.ex for the new version BEFORE deploying. See deploy/HOT_UPGRADE.md.
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
ENV_FILE="$BASE/.env"

FORCE_FULL=0
[[ "${1:-}" == "--full" ]] && FORCE_FULL=1

green() { printf '\033[0;32m%s\033[0m\n' "$1"; }
red()   { printf '\033[0;31m%s\033[0m\n' "$1" >&2; }
step()  { printf '\n\033[1;36m==> %s\033[0m\n' "$1"; }

VSN="$(grep -m1 -E '^\s*version:' mix.exs | sed -E 's/.*"([^"]+)".*/\1/')"
[[ -n "$VSN" ]] || { red "Could not read version from mix.exs."; exit 1; }

green "Deploying $APP_NAME v$VSN locally on this VPS ($BASE)"

step "Checking local prerequisites"
mkdir -p "$APP_DIR"
for bin in mix elixir; do
  command -v "$bin" >/dev/null || { red "Missing $bin on server (install Erlang/Elixir)."; exit 1; }
done
[[ -f "$ENV_FILE" ]] || {
  red "Missing $ENV_FILE. Copy deploy/env.prod.example there and fill it in."
  exit 1
}

step "Building release v$VSN locally"
export MIX_ENV=prod
mix local.hex --force >/dev/null
mix local.rebar --force >/dev/null
mix deps.get --only prod
mix compile
mix assets.setup
mix assets.deploy
mix release --overwrite

CUR_VSN="$(test -x "$APP_DIR/bin/docshare" && "$APP_DIR/bin/docshare" releases 2>/dev/null | awk 'tolower($0) ~ /permanent/ {print $2}' || true)"
CUR_VSN="$(echo "$CUR_VSN" | tr -d '[:space:]')"

if [[ "$FORCE_FULL" == "1" || -z "$CUR_VSN" ]]; then
  # ---------------------- FULL DEPLOY (first install / forced) ------------------
  step "Full deploy: extracting release into $APP_DIR"
  tar="$BUILD_DIR/_build/prod/${APP_NAME}-${VSN}.tar.gz"
  [[ -f "$tar" ]] || { red "Release tar not found: $tar"; exit 1; }
  tar xzf "$tar" -C "$APP_DIR"
  $RESTART restart "$SERVICE"
  sleep 2
  $RESTART --no-pager --full status "$SERVICE" | head -n 10 || true
  green "Full deploy of v$VSN complete."

elif [[ "$CUR_VSN" == "$VSN" ]]; then
  red "Running version is already $VSN. Bump version: in mix.exs (and update appup.ex) to upgrade."
  red "Or run ./deploy.sh --full to re-extract and restart this same version."
  exit 1

else
  # ---------------------- HOT UPGRADE (relup, no restart) ----------------------
  step "Hot upgrade: $CUR_VSN -> $VSN (no restart)"
  target="$BUILD_DIR/_build/prod/rel/${APP_NAME}/releases/${VSN}/${APP_NAME}"
  fromto="$APP_DIR/releases/${CUR_VSN}/${APP_NAME}"
  [[ -f "${target}.rel" ]] || { red "Missing new .rel: ${target}.rel"; exit 1; }
  [[ -f "${fromto}.rel" ]] || { red "Missing old .rel: ${fromto}.rel (is $CUR_VSN still installed?)"; exit 1; }

  echo "-> generating relup ${CUR_VSN} -> ${VSN}"
  mix forecastle.relup --target "$target" --fromto "$fromto" --outdir "$BUILD_DIR"
  [[ -f "$BUILD_DIR/relup" ]] || { red "relup was not generated (check appup.ex)."; exit 1; }

  echo "-> rebuilding release to embed relup"
  mix release --overwrite >/dev/null

  echo "-> installing into the running node"
  tar="$BUILD_DIR/_build/prod/${APP_NAME}-${VSN}.tar.gz"
  cp "$tar" "$APP_DIR/releases/${APP_NAME}-${VSN}.tar.gz"
  "$APP_DIR/bin/${APP_NAME}" unpack "$VSN"
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
#   4. cp deploy/env.prod.example /opt/docshare/.env   (edit; chmod 600;
#      generate SECRET_KEY_BASE with `mix phx.gen.secret`)
#   5. sudo cp deploy/docshare.service /etc/systemd/system/docshare.service
#      sudo systemctl daemon-reload && sudo systemctl enable docshare
#   6. echo 'docshare ALL=(root) NOPASSWD: /bin/systemctl restart docshare, /bin/systemctl status docshare' \
#        | sudo tee /etc/sudoers.d/docshare
#   7. Reverse proxy (nginx/Caddy) TLS for docshare.gatetroy.com -> 127.0.0.1:4000
#   8. ./deploy.sh        (first run does the full deploy + starts the service)
# Thereafter: bump version: in mix.exs, update appup.ex, ./deploy.sh  (hot upgrade)
# ------------------------------------------------------------------------------
