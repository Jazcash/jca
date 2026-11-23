// Team assignment: player cap, join queue and skill-based placement.
//
// The engine's "join", "enterqueue" and "leavequeue" commands are replaced by this file
// (registering an existing command name from script routes it to GT_Command instead; the
// engine re-registers its own commands on every map load, so this can't leak into other
// gametypes). The engine's own challengers queue only runs between matches, which is no use
// for a team gametype, so the queue lives here.
//
// - At most g_teams_maxplayers per team (8 = 8v8). Spectators are unlimited (sv_maxclients).
// - A spectator who joins while both teams are full goes into a first-come first-served
//   queue, and is put in as soon as a slot frees up. Mid-round they wait as a ghost for the
//   next round, like any other mid-round join.
// - Joiners go to the team with fewer players, or if equal, the one with less total skill
//   (sum of rating mu), so the newcomer goes where they help the most.
// - g_jca_autoteam 1 (default): players can't pick or switch teams, and between rounds the
//   bigger team gives a player to the smaller one if they differ by 2 or more. 0 lets
//   players pick a team (still subject to the cap and g_teams_allow_uneven).

Cvar g_jca_autoteam = Cvar("g_jca_autoteam", "1", 0);
Cvar g_teams_maxplayers = Cvar("g_teams_maxplayers", "0", 0);     // engine cvar, set in jca.cfg
Cvar g_teams_allow_uneven = Cvar("g_teams_allow_uneven", "1", 0); // engine cvar, set in jca.cfg

class TeamManager {
    array<int> queue; // playerNums, front is next in

    int maxPerTeam() {
        int cap = g_teams_maxplayers.integer;
        return (cap > 0) ? cap : maxClients;
    }

    int count(int team) {
        return G_GetTeam(team).numPlayers;
    }

    double teamMu(int team) {
        double total = 0;
        Team@ t = @G_GetTeam(team);
        for (int j = 0; @t.ent(j) != null; j++) {
            if (@t.ent(j).client != null) {
                total += ratings.muOf(t.ent(j).client);
            }
        }
        return total;
    }

    // Best team for a new player, or -1 if both are full.
    int pickTeam() {
        int cap = this.maxPerTeam();
        int a = this.count(TEAM_ALPHA);
        int b = this.count(TEAM_BETA);

        if (a >= cap && b >= cap) {
            return -1;
        }
        if (a >= cap) {
            return TEAM_BETA;
        }
        if (b >= cap) {
            return TEAM_ALPHA;
        }
        if (a != b) {
            return (a < b) ? TEAM_ALPHA : TEAM_BETA;
        }

        double muA = this.teamMu(TEAM_ALPHA);
        double muB = this.teamMu(TEAM_BETA);
        if (muA < muB - 0.0001) {
            return TEAM_ALPHA;
        }
        if (muB < muA - 0.0001) {
            return TEAM_BETA;
        }
        return ((rand() & 1) == 0) ? TEAM_ALPHA : TEAM_BETA;
    }

    // Whether a player may choose to move to `team` (g_jca_autoteam 0 only).
    bool canChoose(Client@ client, int team, bool announce) {
        int joining = this.count(team) + 1;
        if (joining > this.maxPerTeam()) {
            if (announce) {
                client.printMessage("Team " + G_GetTeam(team).name + S_COLOR_WHITE + " is full\n");
            }
            return false;
        }

        if (g_teams_allow_uneven.integer == 0) {
            int other = (team == TEAM_ALPHA) ? TEAM_BETA : TEAM_ALPHA;
            int otherCount = this.count(other);
            if (client.team == other) {
                otherCount--;
            }
            if (joining > otherCount + 1) {
                if (announce) {
                    client.printMessage("Can't join " + G_GetTeam(team).name + S_COLOR_WHITE + ": teams would be uneven\n");
                }
                return false;
            }
        }

        return true;
    }

    bool pingAllowed(Client@ client) {
        if (g_jca_maxping.integer <= 0 || client.isBot() || client.ping <= g_jca_maxping.integer) {
            return true;
        }
        client.printMessage(S_COLOR_YELLOW + "Your ping (" + client.ping + ") is above this server's limit of "
            + g_jca_maxping.integer + ". You can still spectate.\n");
        return false;
    }

    // Puts a player on a team. During the countdown they spawn straight away and play
    // the coming round; at any other point of a match they wait as a ghost for the next one.
    void put(Client@ client, int team) {
        bool ghost = match.getState() == MATCH_STATE_PLAYTIME && caRound.state != CA_ROUNDSTATE_PREROUND;
        client.team = team;
        client.respawn(ghost);
        G_PrintMsg(null, client.name + S_COLOR_WHITE + " joined the " + G_GetTeam(team).name + S_COLOR_WHITE + " team.\n");
    }

    int queuePosition(Client@ client) {
        return this.queue.find(client.playerNum);
    }

    void tellPosition(Client@ client, int pos) {
        String msg = "You are " + S_COLOR_YELLOW + "#" + (pos + 1) + S_COLOR_WHITE + " in the queue to play";
        client.printMessage(msg + ". Type " + S_COLOR_YELLOW + "leavequeue" + S_COLOR_WHITE + " to leave it.\n");
        G_CenterPrintMsg(client.getEnt(), msg);
    }

    void tellAllPositions() {
        for (uint i = 0; i < this.queue.length(); i++) {
            this.tellPosition(G_GetClient(this.queue[i]), int(i));
        }
    }

    void enqueue(Client@ client) {
        if (this.queuePosition(client) < 0) {
            this.queue.insertLast(client.playerNum);
        }
        this.tellPosition(client, this.queuePosition(client));
    }

    void leaveQueue(Client@ client, bool announce) {
        int pos = this.queuePosition(client);
        if (pos < 0) {
            if (announce) {
                client.printMessage("You are not in the queue.\n");
            }
            return;
        }
        this.queue.removeAt(uint(pos));
        if (announce) {
            client.printMessage("You left the queue.\n");
        }
        // everyone behind them moved up
        for (uint i = uint(pos); i < this.queue.length(); i++) {
            this.tellPosition(G_GetClient(this.queue[i]), int(i));
        }
    }

    void moveToSpectator(Client@ client) {
        this.leaveQueue(client, false);
        if (client.team == TEAM_SPECTATOR) {
            client.printMessage("You are already a spectator.\n");
            return;
        }
        client.team = TEAM_SPECTATOR;
        client.respawn(true);
        G_PrintMsg(null, client.name + S_COLOR_WHITE + " is now spectating.\n");
    }

    int teamFromName(const String &in name) {
        String n = name.tolower();
        if (n == "spec" || n == "spectator" || n == "spectators") {
            return TEAM_SPECTATOR;
        }
        for (int t = TEAM_ALPHA; t <= TEAM_BETA; t++) {
            Team@ team = @G_GetTeam(t);
            if (n == team.name.removeColorTokens().tolower() || n == team.defaultName.tolower()) {
                return t;
            }
        }
        if (n == "alpha") {
            return TEAM_ALPHA;
        }
        if (n == "beta") {
            return TEAM_BETA;
        }
        return -1;
    }

    // "join" / "join <team>" / "enterqueue"
    void cmdJoin(Client@ client, const String &in argsString) {
        String arg = argsString.getToken(0);
        int requested = -1;
        if (!arg.empty()) {
            requested = this.teamFromName(arg);
            if (requested < 0) {
                client.printMessage("No such team.\n");
                return;
            }
            if (requested == TEAM_SPECTATOR) {
                this.moveToSpectator(client);
                return;
            }
        }

        if (match.getState() > MATCH_STATE_PLAYTIME) {
            client.printMessage("Can't join at this moment.\n");
            return;
        }

        bool autoteam = g_jca_autoteam.integer != 0;

        // already playing: only a deliberate team switch, and only without autoteam
        if (client.team >= TEAM_ALPHA) {
            if (autoteam) {
                client.printMessage("Teams are picked automatically to keep them balanced. Type "
                    + S_COLOR_YELLOW + "spec" + S_COLOR_WHITE + " to stop playing.\n");
                return;
            }
            if (requested < 0 || requested == client.team) {
                client.printMessage("You are already in the " + G_GetTeam(client.team).name + S_COLOR_WHITE + " team.\n");
                return;
            }
            if (this.canChoose(client, requested, true)) {
                this.put(client, requested);
            }
            return;
        }

        if (!this.pingAllowed(client)) {
            this.leaveQueue(client, false);
            return;
        }

        // nobody skips the queue: if people are waiting, get in line behind them
        if (this.queuePosition(client) >= 0 || this.queue.length() > 0) {
            this.enqueue(client);
            return;
        }

        int team = this.pickTeam();
        if (team < 0) {
            this.enqueue(client);
            return;
        }

        if (autoteam) {
            if (requested >= 0 && requested != team) {
                client.printMessage("Teams are picked automatically to keep them balanced.\n");
            }
        } else if (requested >= 0 && this.canChoose(client, requested, true)) {
            team = requested;
        }

        this.put(client, team);
    }

    // a client connected or disconnected: their slot number can be reused
    void clientChanged(Client@ client) {
        if (@client != null) {
            this.leaveQueue(client, false);
        }
    }

    // every frame: fill free slots from the front of the queue
    void think() {
        bool changed = false;

        // drop anyone who left, or got onto a team some other way
        for (int i = int(this.queue.length()) - 1; i >= 0; i--) {
            Client@ client = @G_GetClient(this.queue[uint(i)]);
            if (client.state() < CS_SPAWNED || client.team != TEAM_SPECTATOR) {
                this.queue.removeAt(uint(i));
                changed = true;
            }
        }

        if (match.getState() <= MATCH_STATE_PLAYTIME) {
            while (this.queue.length() > 0) {
                int team = this.pickTeam();
                if (team < 0) {
                    break;
                }
                Client@ client = @G_GetClient(this.queue[0]);
                this.queue.removeAt(0);
                changed = true;
                if (this.pingAllowed(client)) {
                    this.put(client, team);
                }
            }
        }

        if (changed) {
            this.tellAllPositions();
        }
    }

    // Called at the start of each round's countdown (before everyone is respawned). If
    // players left and the queue couldn't refill the gap, move players from the bigger
    // team to the smaller one until the sizes differ by at most one, each time picking
    // whoever leaves the total skill closest.
    void evenTeams() {
        if (g_jca_autoteam.integer == 0) {
            return;
        }

        for (int guard = 0; guard < maxClients; guard++) {
            int a = this.count(TEAM_ALPHA);
            int b = this.count(TEAM_BETA);
            if (abs(a - b) < 2) {
                return;
            }

            int big = (a > b) ? TEAM_ALPHA : TEAM_BETA;
            int small = (a > b) ? TEAM_BETA : TEAM_ALPHA;
            double muBig = this.teamMu(big);
            double muSmall = this.teamMu(small);

            Client@ best = null;
            double bestDiff = -1;
            Team@ team = @G_GetTeam(big);
            for (int j = 0; @team.ent(j) != null; j++) {
                Client@ client = @team.ent(j).client;
                if (@client == null) {
                    continue;
                }
                double mu = ratings.muOf(client);
                double diff = abs((muBig - mu) - (muSmall + mu));
                if (bestDiff < 0 || diff < bestDiff) {
                    bestDiff = diff;
                    @best = @client;
                }
            }

            if (@best == null) {
                return;
            }

            best.team = small;
            best.respawn(true); // the countdown respawns everyone on a team right after this
            G_PrintMsg(null, best.name + S_COLOR_WHITE + " was moved to " + G_GetTeam(small).name
                + S_COLOR_WHITE + " to even the teams.\n");
        }
    }
}

TeamManager teamManager;
