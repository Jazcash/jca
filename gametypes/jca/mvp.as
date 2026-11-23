// MVP: at the end of each round, whoever on each team dealt the most damage to
// enemies that round gets an MVP, so there is one per team. Ties all get one.
// A team gets none if nobody on it dealt damage.

class MvpTracker {
    array<int> mvps;          // by playerNum
    array<float> roundDamage; // by playerNum, this round only
    array<int> roundTeam;     // by playerNum: team the damage was dealt for

    MvpTracker() {
        this.mvps.resize(maxClients);
        this.roundDamage.resize(maxClients);
        this.roundTeam.resize(maxClients);
        this.resetAll();
    }

    void newRound() {
        for (int i = 0; i < maxClients; i++) {
            this.roundDamage[i] = 0;
            this.roundTeam[i] = TEAM_SPECTATOR;
        }
    }

    void reset(int playerNum) {
        if (playerNum < 0 || playerNum >= maxClients) {
            return;
        }
        this.mvps[playerNum] = 0;
        this.roundDamage[playerNum] = 0;
        this.roundTeam[playerNum] = TEAM_SPECTATOR;
    }

    // Drop this player's damage for the current round, keeping their MVP total.
    void clearRound(int playerNum) {
        if (playerNum < 0 || playerNum >= maxClients) {
            return;
        }
        this.roundDamage[playerNum] = 0;
        this.roundTeam[playerNum] = TEAM_SPECTATOR;
    }

    void resetAll() {
        for (int i = 0; i < maxClients; i++) {
            this.mvps[i] = 0;
        }
        this.newRound();
    }

    int get(int playerNum) {
        if (playerNum < 0 || playerNum >= maxClients) {
            return 0;
        }
        return this.mvps[playerNum];
    }

    void damaged(Entity@ target, Entity@ attacker, float damage) {
        if (@target == null || @attacker == null || @target.client == null || @attacker.client == null) {
            return;
        }
        if (@target == @attacker || target.team == attacker.team || damage <= 0) {
            return;
        }

        int a = attacker.playerNum;
        if (a >= 0 && a < maxClients) {
            this.roundDamage[a] += damage;
            this.roundTeam[a] = attacker.team;
        }
    }

    // Call when a round is decided (POSTROUND), before anyone respawns.
    void roundFinished() {
        this.awardTeam(TEAM_ALPHA);
        this.awardTeam(TEAM_BETA);
        this.newRound();
    }

    void awardTeam(int teamNum) {
        float best = 0;
        for (int i = 0; i < maxClients; i++) {
            if (this.roundTeam[i] == teamNum && this.roundDamage[i] > best) {
                best = this.roundDamage[i];
            }
        }
        if (best <= 0) {
            return;
        }

        String names = "";
        for (int i = 0; i < maxClients; i++) {
            if (this.roundTeam[i] == teamNum && this.roundDamage[i] == best) {
                this.mvps[i]++;
                Client@ client = @G_GetClient(i);
                if (@client != null) {
                    if (!names.empty()) {
                        names += S_COLOR_WHITE + " & ";
                    }
                    names += client.name;
                }
            }
        }
        if (!names.empty()) {
            G_PrintMsg(null, G_GetTeam(teamNum).name + S_COLOR_WHITE + " MVP: " + names + S_COLOR_WHITE
                + " (" + rint(best) + " damage)\n");
        }
    }
}

MvpTracker mvp;
