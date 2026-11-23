# JCA (Jaz's Clan Arena)

JCA is a custom **gametype for Warfork**, a Quake-style arena FPS built on the qfusion engine. It's a variant of Clan Arena: two teams, rounds, everyone spawns with every weapon and there are no pickups, and the last team standing wins the round. It's written entirely in **AngelScript**, the engine's gametype scripting language. There is no build step, test suite or package manager. The `.as` files are compiled by the game server when it loads the gametype.

`README.md` is the player-facing description of the rules and the rating system. Read it first, and keep it in sync when you change gameplay behaviour.

## How it differs from stock CA

- No armor. Players spawn with health only (`ent.health` in `GT_PlayerRespawn`, [gt-callins.as](../gametypes/jca/gt-callins.as)). The current value is 300 (about 100hp + 150ra).
- Assists: any damage to an enemy who later dies in the same round counts, unless you got the kill ([assists.as](../gametypes/jca/assists.as)).
- Custom scoreboard columns: score, kills, deaths, assists, damage ratio (red below 1, green at 1 or above), skill rating and ping (`GT_ScoreboardMessage`). The column layout is declared in `GT_InitGametype`.
- The killer's HP isn't shown on death.
- OpenSkill (Weng-Lin Bradley-Terry) per-round ratings, plus `callvote rebalance` ([ratings.as](../gametypes/jca/ratings.as)). Tuning constants and the reasoning behind them are commented at the top of that file.
- A `fish` client command prints the caller's steam_id (debug helper).

## Layout

```
gametypes/
  jca.gt          Manifest: the ordered list of script files to compile (paths are relative to progs/gametypes/)
  jca.gtd         Title and description shown in the game UI
  jca/            *** The actual JCA code: this is what you'll edit ***
    main.as         Cvars, round-state constants, the global cCARound
    gt-callins.as   Engine callbacks: GT_InitGametype, GT_ThinkRules, GT_PlayerRespawn, GT_ScoreEvent,
                    GT_ScoreboardMessage, GT_Command, match-state hooks
    ca-round.as     cCARound: the round state machine (PREROUND, ROUND, ROUNDFINISHED, POSTROUND),
                    spawn selection, win detection, 1v1 time limit
    ratings.as      RatingSystem: OpenSkill maths, persistence to ratings/jca.txt, rebalance vote
    assists.as      AssistTracker
    stats.as        StatsLogger: per-round/match stats appended as JSON lines to stats/jca-events.jsonl
                    (consumed by ~/jazcash.com, see server/utils/jca/ingest.ts there)
    utils.as        Warmup/countdown setup, formatFloat
  generic/, shared/, legacy/
                  Stock Warfork scripts, copied here for reference and IDE type resolution.
                  The live server loads its own copies from the game's pk3s, so editing these
                  here does NOT change server behaviour.
  as.predefined   Type stubs for the engine's script API (for the angel-lsp VS Code extension only, never loaded by the game)
```

`as.predefined` is also the best quick reference for which engine API calls exist. The script API is limited: for example there is `pow()` but no `exp()`, and `String`/`Dictionary`/`array<T>`/`Cvar` are engine types. Its header links to the upstream sources: github.com/TeamForbiddenLLC/warfork-qfusion and the warforkwiki "Gametype Scripting" page.

`.vscode/` recommends the `sashi0034.angel-lsp` extension. `implicitMutualInclusion` is on because, like the game, all files share one global namespace with no includes.

## Conventions and gotchas

- All files compile into one module in the order given in `jca.gt`. Globals declared anywhere are visible everywhere. **If you add a new `.as` file, add it to `jca.gt`**, otherwise it isn't loaded.
- Colour codes in strings: `^1` red, `^2` green, and so on (see `shared/constants.as` `S_COLOR_*`).
- Players are identified for ratings by `client.getUserInfoKey("steam_id")`. Bots and players without a Steam ID aren't rated.
- `/test.as` is gitignored (scratch file).
- Without a server there's no compiler to check against. Script compile errors only show up in the server console/log when the gametype loads, so be careful with syntax and API signatures (check `as.predefined`).

## Deployment (this machine)

The repo lives at `~/warfork/jca`. The dedicated server is at `~/warfork/server` and runs as the systemd unit `warfork.service`. Its `ExecStartPre` runs a steamcmd update on every start.

- Deployed gametype: `~/warfork/server/basewf/progs/gametypes/{jca.gt,jca.gtd,jca/}`. Only these are copied, not `generic/`/`shared/`/`legacy/`. To deploy, copy them over and restart the service (`sudo systemctl restart warfork`). Back up the deployed copy first; earlier backups look like `~/warfork/jca-deploy-backup-<timestamp>/`.
- The deployed copy can lag behind the repo, so diff before assuming they match: `diff -r gametypes/jca ~/warfork/server/basewf/progs/gametypes/jca`.
- Server config: `~/warfork/server/basewf/server.cfg` (sets `g_gametype "jca"`, Steam auth, votable gametypes). Timestamped `.bak` copies sit next to it.
- Server log: `~/.local/share/warfork-2.1/basewf/wfconsole.log`.
- Stats event log: `~/.local/share/warfork-2.1/basewf/stats/jca-events.jsonl`, append-only. jazcash.com tails it into SQLite (`~/jca-data/jca.db`). If you change the line format, bump `STATS_VERSION` and update the ingester. Live player data: never truncate or rewrite it.
- Ratings data: `~/.local/share/warfork-2.1/basewf/ratings/jca.txt` (write directory). Format, one player per line: `<steam_id> <mu> <sigma> <rounds> <name>`. This is live player data, so don't delete or overwrite it without asking.
- Restarting the service or deploying disconnects players on a live public server. Confirm with the user before doing either.

# Useful links

Warfork Gametypes: https://github.com/Warfork/warfork-gametypes
Warfork Engine: https://github.com/Warfork/warfork-qfusion