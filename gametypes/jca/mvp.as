// MVP: at the end of each round, whoever dealt the most damage to enemies that
// round gets an MVP. Ties all get one. Nobody gets one if nobody dealt damage.

class MvpTracker {
    array<int> mvps;          // by playerNum
    array<float> roundDamage; // by playerNum, this round only

    MvpTracker() {
        this.mvps.resize(maxClients);
        this.roundDamage.resize(maxClients);
        this.resetAll();
    }

    void newRound() {
        for (int i = 0; i < maxClients; i++) {
            this.roundDamage[i] = 0;
        }
    }

    void reset(int playerNum) {
        if (playerNum < 0 || playerNum >= maxClients) {
            return;
        }
        this.mvps[playerNum] = 0;
        this.roundDamage[playerNum] = 0;
    }

    // Drop this player's damage for the current round, keeping their MVP total.
    void clearRound(int playerNum) {
        if (playerNum < 0 || playerNum >= maxClients) {
            return;
        }
        this.roundDamage[playerNum] = 0;
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
        }
    }

    // Call when a round is decided (POSTROUND), before anyone respawns.
    void roundFinished() {
        float best = 0;
        for (int i = 0; i < maxClients; i++) {
            if (this.roundDamage[i] > best) {
                best = this.roundDamage[i];
            }
        }

        if (best > 0) {
            String names = "";
            for (int i = 0; i < maxClients; i++) {
                if (this.roundDamage[i] == best) {
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
                G_PrintMsg(null, names + S_COLOR_YELLOW + " MVP!" + S_COLOR_WHITE + " (" + rint(best) + " damage)\n");
            }
        }

        this.newRound();
    }
}

MvpTracker mvp;
