// Per-round player stats, appended to STATS_FILE as one JSON object per line.
// jazcash.com tails this file into a database (see README.md), so the file is
// append-only and is the source of truth for everything except live ratings.
//
// Lines (all have "v" = format version, "type", "match", "t" = unix seconds):
//   match_start: map, server
//   round:       num, map, winner (TEAM_ALPHA = 2, TEAM_BETA = 3, -1 draw), durationMs,
//                winChance (alpha's predicted chance, -1 if unknown), rated, baseline,
//                players[]: id, name, team, alive, clutch, k, d, a, dg, dr,
//                           mu0, sig0, mu1, sig1 (omitted for unrated players),
//                           w {weapon: [shots, hits, damage, kills]}, kills {victim id: count}
//   match_end:   map, completed, scoreAlpha, scoreBeta, rounds,
//                players[]: id, name, team (everyone on alpha/beta at the end)

const String STATS_FILE = "stats/jca-events.jsonl";
const int STATS_VERSION = 1;
const int STATS_WEAPONS = 9; // gb mg rg gl rl pg lg eb ig, in ammo tag order

// Test only: log bots too (as "bot-<name>") so stats can be checked without humans.
Cvar g_jca_stats_bots("g_jca_stats_bots", "0", 0);

String statsWeaponKey(int w) {
    switch (w) {
    case 0: return "gb";
    case 1: return "mg";
    case 2: return "rg";
    case 3: return "gl";
    case 4: return "rl";
    case 5: return "pg";
    case 6: return "lg";
    case 7: return "eb";
    case 8: return "ig";
    }
    return "";
}

// Weapon index for a means of death, or -1 for non-weapon damage (falling, lava, ...).
int statsWeaponOfMod(int mod) {
    switch (mod) {
    case MOD_GUNBLADE_W: case MOD_GUNBLADE_S: return 0;
    case MOD_MACHINEGUN_W: case MOD_MACHINEGUN_S: return 1;
    case MOD_RIOTGUN_W: case MOD_RIOTGUN_S: return 2;
    case MOD_GRENADE_W: case MOD_GRENADE_S: case MOD_GRENADE_SPLASH_W: case MOD_GRENADE_SPLASH_S: return 3;
    case MOD_ROCKET_W: case MOD_ROCKET_S: case MOD_ROCKET_SPLASH_W: case MOD_ROCKET_SPLASH_S: return 4;
    case MOD_PLASMA_W: case MOD_PLASMA_S: case MOD_PLASMA_SPLASH_W: case MOD_PLASMA_SPLASH_S: return 5;
    case MOD_LASERGUN_W: case MOD_LASERGUN_S: return 6;
    case MOD_ELECTROBOLT_W: case MOD_ELECTROBOLT_S: return 7;
    case MOD_INSTAGUN_W: case MOD_INSTAGUN_S: return 8;
    }
    return -1;
}

String jsonString(const String &in s) {
    String r = s.replace("\\", "\\\\");
    r = r.replace("\"", "\\\"");
    r = r.replace("\n", " ");
    r = r.replace("\r", " ");
    r = r.replace("\t", " ");
    return "\"" + r + "\"";
}

String jsonNumber(double v) {
    return StringUtils::FormatFloat(v, "", 0, 6);
}

String jsonBool(bool b) {
    return b ? "true" : "false";
}

// the global AssistTracker, which RoundPlayerStats.assists would otherwise shadow
int statsAssistsOf(int playerNum) {
    return assists.get(playerNum);
}

int statsNow() {
    return int(localTime);
}

class RoundPlayerStats {
    String steamId;
    String name;
    int team;
    int playerNum;
    Client@ client; // null once they disconnect
    bool dead;
    bool alive;     // at round end
    bool finalized; // accuracy/assists captured (at round end or on disconnect)

    int kills;
    int deaths;
    int assists;
    int assistsAtStart;
    double damageGiven;
    double damageReceived;

    array<int> shotsAtStart(STATS_WEAPONS);
    array<int> hitsAtStart(STATS_WEAPONS);
    array<int> damageAtStart(STATS_WEAPONS);
    array<int> shots(STATS_WEAPONS);
    array<int> hits(STATS_WEAPONS);
    array<int> weaponDamage(STATS_WEAPONS);
    array<int> weaponKills(STATS_WEAPONS);
    Dictionary victims; // victim steamId -> int64 kills

    bool rated;
    double mu0, sigma0, mu1, sigma1;

    RoundPlayerStats() {
        this.kills = this.deaths = this.assists = this.assistsAtStart = 0;
        this.damageGiven = this.damageReceived = 0;
        this.dead = this.alive = this.finalized = this.rated = false;
        this.mu0 = this.sigma0 = this.mu1 = this.sigma1 = 0;
        for (int w = 0; w < STATS_WEAPONS; w++) {
            this.shotsAtStart[w] = this.hitsAtStart[w] = this.damageAtStart[w] = 0;
            this.shots[w] = this.hits[w] = this.weaponDamage[w] = this.weaponKills[w] = 0;
        }
    }

    // The engine's per-weapon counters for this match, strong + weak ammo.
    int shotsOf(int w) {
        return this.client.stats.accuracyShots(AMMO_GUNBLADE + w) + this.client.stats.accuracyShots(AMMO_WEAK_GUNBLADE + w);
    }

    int hitsOf(int w) {
        return this.client.stats.accuracyHits(AMMO_GUNBLADE + w) + this.client.stats.accuracyHits(AMMO_WEAK_GUNBLADE + w);
    }

    int damageOf(int w) {
        return this.client.stats.accuracyDamage(AMMO_GUNBLADE + w) + this.client.stats.accuracyDamage(AMMO_WEAK_GUNBLADE + w);
    }

    void snapshot() {
        for (int w = 0; w < STATS_WEAPONS; w++) {
            this.shotsAtStart[w] = this.shotsOf(w);
            this.hitsAtStart[w] = this.hitsOf(w);
            this.damageAtStart[w] = this.damageOf(w);
        }
        this.assistsAtStart = statsAssistsOf(this.playerNum);
    }

    // Capture the counters the engine keeps for us. The engine clears them on a
    // team change, so never go negative.
    void finalize() {
        if (this.finalized || @this.client == null) {
            return;
        }
        this.finalized = true;

        for (int w = 0; w < STATS_WEAPONS; w++) {
            int s = this.shotsOf(w);
            int h = this.hitsOf(w);
            int d = this.damageOf(w);
            this.shots[w] = (s >= this.shotsAtStart[w]) ? s - this.shotsAtStart[w] : s;
            this.hits[w] = (h >= this.hitsAtStart[w]) ? h - this.hitsAtStart[w] : h;
            this.weaponDamage[w] = (d >= this.damageAtStart[w]) ? d - this.damageAtStart[w] : d;
        }

        int a = statsAssistsOf(this.playerNum);
        this.assists = (a >= this.assistsAtStart) ? a - this.assistsAtStart : a;
    }

    String toJson() {
        String j = "{\"id\":" + jsonString(this.steamId)
            + ",\"name\":" + jsonString(this.name)
            + ",\"team\":" + this.team
            + ",\"alive\":" + jsonBool(this.alive)
            + ",\"k\":" + this.kills
            + ",\"d\":" + this.deaths
            + ",\"a\":" + this.assists
            + ",\"dg\":" + rint(this.damageGiven)
            + ",\"dr\":" + rint(this.damageReceived);

        if (this.rated) {
            j += ",\"mu0\":" + jsonNumber(this.mu0) + ",\"sig0\":" + jsonNumber(this.sigma0)
                + ",\"mu1\":" + jsonNumber(this.mu1) + ",\"sig1\":" + jsonNumber(this.sigma1);
        }

        String w = "";
        for (int i = 0; i < STATS_WEAPONS; i++) {
            int dmg = this.weaponDamage[i];
            if (this.shots[i] == 0 && dmg == 0 && this.weaponKills[i] == 0) {
                continue;
            }
            w += (w.empty() ? "" : ",") + "\"" + statsWeaponKey(i) + "\":["
                + this.shots[i] + "," + this.hits[i] + "," + dmg + "," + this.weaponKills[i] + "]";
        }
        j += ",\"w\":{" + w + "}";

        String v = "";
        array<String@>@ keys = this.victims.getKeys();
        for (uint i = 0; i < keys.length(); i++) {
            int64 n;
            this.victims.get(keys[i], n);
            v += (v.empty() ? "" : ",") + jsonString(keys[i]) + ":" + int(n);
        }
        j += ",\"kills\":{" + v + "}";

        return j;
    }
}

class StatsLogger {
    String matchId;
    String mapName;
    bool matchOpen;
    int loggedRounds;

    array<RoundPlayerStats@> players; // this round's participants
    array<RoundPlayerStats@> bySlot;  // playerNum -> participant (null if none)
    uint roundStartTime;

    StatsLogger() {
        this.matchOpen = false;
        this.loggedRounds = 0;
        this.bySlot.resize(maxClients);
    }

    void write(const String &in line) {
        if (!G_AppendToFile(STATS_FILE, line + "\n")) {
            G_Print("^1Failed to append to " + STATS_FILE + "\n");
        }
    }

    String header(const String &in type) {
        return "{\"v\":" + STATS_VERSION + ",\"type\":\"" + type + "\",\"match\":" + jsonString(this.matchId)
            + ",\"t\":" + statsNow() + ",\"map\":" + jsonString(this.mapName);
    }

    String steamIdOf(Client@ client) {
        if (@client == null) {
            return "";
        }
        if (client.isBot()) {
            return g_jca_stats_bots.boolean ? "bot-" + client.name.removeColorTokens() : "";
        }
        return ratings.steamIdOf(client);
    }

    RoundPlayerStats@ slot(Entity@ ent) {
        if (@ent == null || @ent.client == null) {
            return null;
        }
        int n = ent.playerNum;
        if (n < 0 || n >= maxClients) {
            return null;
        }
        RoundPlayerStats@ p = this.bySlot[n];
        if (@p == null || @p.client != @ent.client) {
            return null;
        }
        return p;
    }

    void matchStarted() {
        this.matchEnded(false); // previous match never reached postmatch

        Cvar mapname("mapname", "", 0);
        Cvar port("sv_port", "", 0);
        Cvar hostname("sv_hostname", "", 0);

        this.mapName = mapname.string;
        this.matchId = statsNow() + "-" + port.string + "-" + this.mapName;
        this.matchOpen = true;
        this.loggedRounds = 0;
        this.roundCancelled();

        this.write(this.header("match_start") + ",\"server\":" + jsonString(hostname.string.removeColorTokens()) + "}");
    }

    // completed = reached postmatch normally (not aborted, restarted or map changed)
    void matchEnded(bool completed) {
        if (!this.matchOpen) {
            return;
        }
        this.matchOpen = false;
        this.roundCancelled();

        String roster = "";
        for (int t = TEAM_ALPHA; t <= TEAM_BETA; t++) {
            Team@ team = @G_GetTeam(t);
            for (int j = 0; @team.ent(j) != null; j++) {
                Client@ client = @team.ent(j).client;
                String id = this.steamIdOf(client);
                if (id.empty()) {
                    continue;
                }
                roster += (roster.empty() ? "" : ",") + "{\"id\":" + jsonString(id)
                    + ",\"name\":" + jsonString(client.name.removeColorTokens()) + ",\"team\":" + t + "}";
            }
        }

        this.write(this.header("match_end")
            + ",\"completed\":" + jsonBool(completed)
            + ",\"scoreAlpha\":" + G_GetTeam(TEAM_ALPHA).stats.score
            + ",\"scoreBeta\":" + G_GetTeam(TEAM_BETA).stats.score
            + ",\"rounds\":" + this.loggedRounds
            + ",\"players\":[" + roster + "]}");
    }

    void roundCancelled() {
        this.players.resize(0);
        for (int i = 0; i < maxClients; i++) {
            @this.bySlot[i] = null;
        }
    }

    // Call right after ratings.roundStarted() so rated players already exist.
    void roundStarted() {
        this.roundCancelled();
        this.roundStartTime = levelTime;
        if (!this.matchOpen) {
            return;
        }

        for (int t = TEAM_ALPHA; t <= TEAM_BETA; t++) {
            Team@ team = @G_GetTeam(t);
            for (int j = 0; @team.ent(j) != null; j++) {
                Entity@ ent = @team.ent(j);
                if (ent.isGhosting() || @ent.client == null) {
                    continue;
                }

                if (ent.client.isBot() && !g_jca_stats_bots.boolean) {
                    this.roundCancelled(); // rounds with bots aren't recorded, same as ratings
                    return;
                }

                String id = this.steamIdOf(ent.client);
                if (id.empty()) {
                    continue;
                }

                RoundPlayerStats@ p = RoundPlayerStats();
                p.steamId = id;
                p.name = ent.client.name.removeColorTokens();
                p.team = t;
                p.playerNum = ent.playerNum;
                @p.client = @ent.client;
                p.snapshot();

                PlayerRating@ r = ratings.find(id);
                if (@r != null) {
                    p.rated = true;
                    p.mu0 = r.mu;
                    p.sigma0 = r.sigma;
                }

                this.players.insertLast(p);
                @this.bySlot[ent.playerNum] = p;
            }
        }
    }

    void damaged(Entity@ target, Client@ attacker, double damage) {
        if (damage <= 0 || @target == null || @target.client == null) {
            return;
        }

        RoundPlayerStats@ victim = this.slot(target);
        RoundPlayerStats@ shooter = (@attacker == null) ? null : this.slot(attacker.getEnt());
        if (@victim != null && @shooter == @victim) {
            return; // self damage
        }
        if (@shooter != null && @victim != null && shooter.team == victim.team) {
            return; // team damage
        }

        if (@victim != null) {
            victim.damageReceived += damage;
        }
        if (@shooter != null && target.team != attacker.team) {
            shooter.damageGiven += damage;
        }
    }

    void killed(Entity@ target, Entity@ attacker, int mod) {
        RoundPlayerStats@ victim = this.slot(target);
        if (@victim != null) {
            if (victim.dead) {
                return; // the engine fires "kill" again if a corpse is gibbed
            }
            victim.dead = true;
            victim.deaths++;
        }

        RoundPlayerStats@ killer = this.slot(attacker);
        if (@killer == null || @killer == @victim || (@victim != null && killer.team == victim.team)) {
            return;
        }

        killer.kills++;
        int w = statsWeaponOfMod(mod);
        if (w >= 0) {
            killer.weaponKills[w]++;
        }
        if (@victim != null) {
            int64 n = 0;
            killer.victims.get(victim.steamId, n);
            killer.victims.set(victim.steamId, n + 1);
        }
    }

    // Keep what a leaving player did this round; their engine stats are about to go.
    void playerLeft(Client@ client) {
        if (@client == null) {
            return;
        }
        RoundPlayerStats@ p = this.slot(client.getEnt());
        if (@p == null) {
            return;
        }
        p.finalize();
        @p.client = null;
        @this.bySlot[p.playerNum] = null;
    }

    // Call right after ratings.roundFinished(). winningTeam is TEAM_ALPHA, TEAM_BETA or -1.
    void roundFinished(int winningTeam) {
        if (!this.matchOpen || this.players.length() == 0) {
            this.roundCancelled();
            return;
        }

        array<int> total(GS_MAX_TEAMS);
        array<int> alive(GS_MAX_TEAMS);
        for (int t = 0; t < GS_MAX_TEAMS; t++) {
            total[t] = alive[t] = 0;
        }

        for (uint i = 0; i < this.players.length(); i++) {
            RoundPlayerStats@ p = this.players[i];
            p.finalize();
            p.alive = @p.client != null && p.client.team == p.team && !p.client.getEnt().isGhosting();
            total[p.team]++;
            if (p.alive) {
                alive[p.team]++;
            }

            PlayerRating@ r = ratings.find(p.steamId);
            if (p.rated && @r != null) {
                p.mu1 = r.mu;
                p.sigma1 = r.sigma;
            }
        }

        if (total[TEAM_ALPHA] == 0 || total[TEAM_BETA] == 0) {
            this.roundCancelled();
            return;
        }

        String list = "";
        for (uint i = 0; i < this.players.length(); i++) {
            RoundPlayerStats@ p = this.players[i];
            int other = (p.team == TEAM_ALPHA) ? TEAM_BETA : TEAM_ALPHA;
            bool clutch = p.team == winningTeam && p.alive && alive[p.team] == 1 && total[p.team] > 1 && total[other] > 1;
            list += (list.empty() ? "" : ",") + p.toJson() + ",\"clutch\":" + jsonBool(clutch) + "}";
        }

        this.loggedRounds++;
        this.write(this.header("round")
            + ",\"num\":" + caRound.numRounds
            + ",\"winner\":" + winningTeam
            + ",\"durationMs\":" + (levelTime - this.roundStartTime)
            + ",\"winChance\":" + jsonNumber(ratings.lastWinChance)
            + ",\"rated\":" + jsonBool(ratings.lastRated)
            + ",\"baseline\":" + jsonNumber(ratings.baseline)
            + ",\"players\":[" + list + "]}");

        this.roundCancelled();
    }
}

StatsLogger statsLog;
