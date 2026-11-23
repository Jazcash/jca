# JCA (Jaz's Clan Arena)

JCA is a custom **gametype for Warfork**, a Quake-style arena FPS built on the qfusion engine. It's a variant of Clan Arena: two teams, rounds, everyone spawns with every weapon and there are no pickups, and the last team standing wins the round. It's written entirely in **AngelScript**, the engine's gametype scripting language. There is no build step, test suite or package manager. The `.as` files are compiled by the game server when it loads the gametype.

`README.md` is the player-facing description of the rules and the rating system. Read it first, and keep it in sync when you change gameplay behaviour.

## How it differs from stock CA

- No armor. Players spawn with health only (`ent.health` in `GT_PlayerRespawn`, [gt-callins.as](../gametypes/jca/gt-callins.as)). The current value is 300 (about 100hp + 150ra).
- Assists: any damage to an enemy who later dies in the same round counts, unless you got the kill ([assists.as](../gametypes/jca/assists.as)).
- Custom scoreboard columns: score, kills, deaths, assists, damage ratio (red below 1, green at 1 or above), MVPs (most damage in a round, [mvp.as](../gametypes/jca/mvp.as)), skill rating and ping (`GT_ScoreboardMessage`). The column layout is declared in `GT_InitGametype`.
- Scoreboard stats survive team changes and rebalance/shuffle. The engine zeroes a client's stats on every team change (and rebalance zeroes everyone it doesn't move), and the script can't write frags/deaths/damage back (only `setScore`). [stats-carry.as](../gametypes/jca/stats-carry.as) notices the drop and keeps a carried-over total that the scoreboard (and score = damage given) adds on top. Assists/MVPs just aren't reset; only the per-round data is (`clearRound`/`newRound`). Engine per-weapon accuracy counters are still wiped.
- The killer's HP isn't shown on death.
- OpenSkill (Weng-Lin Bradley-Terry) per-round ratings, plus `callvote rebalance` ([ratings.as](../gametypes/jca/ratings.as)). Tuning constants and the reasoning behind them are commented at the top of that file.
- Countdown ghosting: `PMFEAT_GHOSTMOVE` during PREROUND, cleared once a player isn't overlapping anyone ([join-rules.as](../gametypes/jca/join-rules.as)). Player-vs-player blocking is decided in pmove, which also runs on clients, so teammate-only phasing isn't possible from the server.
- Join ping limit `g_jca_maxping` (currently disabled: default and jca.cfg are 0; it was 150), checked only when a spectator joins a team ([join-rules.as](../gametypes/jca/join-rules.as)).
- Welcome message on entering the game: chat/console intro plus a centre-print ([welcome.as](../gametypes/jca/welcome.as)). Keep it in sync with gameplay changes.
- Team joining is handled by script ([teams.as](../gametypes/jca/teams.as)): `G_RegisterCommand("join")` overrides the engine's `join`/`enterqueue`/`leavequeue` (an existing command name registered from script is routed to `GT_Command`). Cap per team is the engine cvar `g_teams_maxplayers` (8), extras wait in a FIFO queue filled every frame, placement is by team size then total rating mu. `g_jca_autoteam 1` blocks team choice/switching and evens teams that differ by 2+ at each PREROUND. The engine's challengers queue is unused (it only runs outside PLAYTIME). Callvote `put`/bots still go through the engine directly.
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
    mvp.as          MvpTracker (most damage dealt per round)
    stats-carry.as  StatsCarry: keeps kills/deaths/damage across the engine's stat wipes
    stats.as        StatsLogger: per-round/match stats appended as JSON lines to stats/jca-events.jsonl
                    (consumed by ~/jazcash.com, see server/utils/jca/ingest.ts there)
    utils.as        Warmup/countdown setup, formatFloat
    join-rules.as   SpawnGhosting (countdown ghost move) and PingLimit (g_jca_maxping)
    teams.as        TeamManager: join override, 8v8 cap, join queue, skill-based team placement
    welcome.as      showWelcome: intro text printed to each player on "enterGame" (every map load)
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

- Deployed gametype: `~/warfork/server/basewf/progs/gametypes/{jca.gt,jca.gtd,jca/}`. Only these are copied, not `generic/`/`shared/`/`legacy/`. To compile-check without touching the live server, run a throwaway copy with its own HOME (copy the gametype into `$HOME/.local/share/warfork-2.1/jcatest/progs/gametypes/`) and `+set fs_game jcatest +set sv_port 44490 +set sv_port6 44490 +set sv_http 0 +set sv_public 0 +set masterservers "" +set masterservers_steam "" +set sv_useSteamAuth 0 +map wfca1` under `timeout`; the live server owns 44400 and 44444, and it needs to run outside the sandbox. To deploy, copy them over and restart the service (`sudo systemctl restart warfork`). Back up the deployed copy first; earlier backups look like `~/warfork/jca-deploy-backup-<timestamp>/`.
- The deployed copy can lag behind the repo, so diff before assuming they match: `diff -r gametypes/jca ~/warfork/server/basewf/progs/gametypes/jca`.
- Gametype config: `~/.local/share/warfork-2.1/basewf/configs/server/gametypes/jca.cfg` (write directory, runs each time the gametype loads). Sets `g_inactivity_maxtime 30`, `g_antilag_maxtimedelta 250`, `g_teams_maxplayers 8`, `g_jca_autoteam` and `g_jca_maxping`. `sv_maxclients` (256, the engine maximum) is in server.cfg and only changes on a restart.
- Snapshot rate: `sv_pps` can only be set on the command line, i.e. in the systemd unit's ExecStart (`+set sv_pps ...`). It's currently unset, so the engine default of 20 applies (40 was tried and reverted while checking whether it hurt players' connections).
- Server config: `~/warfork/server/basewf/server.cfg` (sets `g_gametype "jca"`, Steam auth, votable gametypes). Timestamped `.bak` copies sit next to it.
- Server log: `~/.local/share/warfork-2.1/basewf/wfconsole.log`.
- Stats event log: `~/.local/share/warfork-2.1/basewf/stats/jca-events.jsonl`, append-only. jazcash.com tails it into SQLite (`~/jca-data/jca.db`). If you change the line format, bump `STATS_VERSION` and update the ingester. Live player data: never truncate or rewrite it.
- Ratings data: `~/.local/share/warfork-2.1/basewf/ratings/jca.txt` (write directory). Format, one player per line: `<steam_id> <mu> <sigma> <rounds> <name>`. This is live player data, so don't delete or overwrite it without asking.
- Restarting the service or deploying disconnects players on a live public server. Confirm with the user before doing either.

# Useful links

Warfork Gametypes: https://github.com/Warfork/warfork-gametypes
Warfork Engine: https://github.com/Warfork/warfork-qfusion