# Hot-code upgrades (zero downtime)

DocShare uses [Castle](https://hexdocs.pm/castle)/[Forecastle](https://hexdocs.pm/forecastle)
to ship OTP **relups** — new code is loaded into the *running* BEAM node, so
deploys drop no connections and don't restart the LiveView sockets.

## Per-release checklist

1. **Bump the version** in `mix.exs` (`version: "0.2.0"`). Every upgrade needs a
   new, higher version.
2. **Update `appup.ex`** to describe how to go from the running version to the
   new one:
   ```elixir
   {~c"0.2.0",
    [{~c"0.1.0", [{:load_module, DocshareWeb.DocumentLive.Show}]}],   # up
    [{~c"0.1.0", [{:load_module, DocshareWeb.DocumentLive.Show}]}]}   # down
   ```
   - `{:load_module, Mod}` — stateless module, just reload it.
   - `{:update, Mod, {:advanced, []}}` — a **stateful** process (GenServer);
     this calls the module's `code_change/3` so it can migrate its state.
   - `{:add_module, Mod}` / `{:delete_module, Mod}` — new / removed modules.
   - An empty change `[]` reloads nothing (config-only / asset-only releases).
3. **Deploy**: `./deploy.sh`. It detects the running version, generates the
   relup `running -> new`, installs and commits it into the live node.

## What `deploy.sh` does for an upgrade

```
running v0.1.0  ──►  build v0.2.0 tar on VPS
                     mix forecastle.relup --target <new>.rel --fromto <old>.rel
                     mix release --overwrite          # embeds relup in the tar
                     bin/docshare unpack 0.2.0
                     bin/docshare install 0.2.0        # runs the relup, live
                     bin/docshare commit 0.2.0         # permanent across reboots
```

No `systemctl restart`. The node keeps running; modules are swapped in place.

## Caveats (read these)

- **Stateful processes need `code_change/3`.** If you change a GenServer's state
  shape and don't migrate it in `code_change/3`, the live process can crash on
  upgrade. Phoenix's own processes are generally fine to `:load_module`.
- **Dependency version bumps** make relups harder: `systools` needs an appup for
  every changed application. If a dep upgrade breaks relup generation, ship that
  release with `./deploy.sh --full` (extract + restart) instead.
- **Migrations are not hot.** A relup only swaps code. If a release includes a DB
  migration, run it first: `ssh … '/opt/docshare/app/bin/docshare eval "Docshare.Release.migrate()"'`
  and make sure the new code is backward-compatible with the old schema during
  the swap. Pure additive migrations are safe; destructive ones want `--full`.
- **It doesn't survive a wiped release root.** `commit` makes the version
  permanent (survives reboot/crash), but the upgrade history lives in
  `/opt/docshare/app/releases/`. Keep it.

## Escape hatch

Anything goes wrong with a relup? `./deploy.sh --full` does a clean
extract-and-restart of the current version — a brief blip, but always works.
Roll back a bad commit with `bin/docshare install <old> && bin/docshare commit <old>`.
