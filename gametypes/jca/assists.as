// Assists: when a player dies during a round, every enemy who damaged them
// earlier in that round (other than the killer) gets an assist.

class AssistTracker {
    array<int> assists;           // by playerNum
    array<array<bool>> damagedBy; // [victim playerNum][attacker playerNum], this round only
    array<bool> dead;             // by playerNum, this round only

    AssistTracker() {
        this.assists.resize(maxClients);
        this.damagedBy.resize(maxClients);
        this.dead.resize(maxClients);
        for (int i = 0; i < maxClients; i++) {
            this.assists[i] = 0;
            this.damagedBy[i].resize(maxClients);
        }
        this.newRound();
    }

    void newRound() {
        for (int v = 0; v < maxClients; v++) {
            this.dead[v] = false;
            for (int a = 0; a < maxClients; a++) {
                this.damagedBy[v][a] = false;
            }
        }
    }

    void reset(int playerNum) {
        if (playerNum < 0 || playerNum >= maxClients) {
            return;
        }

        this.assists[playerNum] = 0;
        this.dead[playerNum] = false;
        for (int i = 0; i < maxClients; i++) {
            this.damagedBy[playerNum][i] = false;
            this.damagedBy[i][playerNum] = false;
        }
    }

    void resetAll() {
        for (int i = 0; i < maxClients; i++) {
            this.assists[i] = 0;
        }
        this.newRound();
    }

    int get(int playerNum) {
        if (playerNum < 0 || playerNum >= maxClients) {
            return 0;
        }
        return this.assists[playerNum];
    }

    void damaged(Entity@ target, Entity@ attacker) {
        if (@target == null || @attacker == null || @target.client == null || @attacker.client == null) {
            return;
        }
        if (@target == @attacker || target.team == attacker.team) {
            return;
        }

        int v = target.playerNum;
        int a = attacker.playerNum;
        if (v >= 0 && v < maxClients && a >= 0 && a < maxClients && !this.dead[v]) {
            this.damagedBy[v][a] = true;
        }
    }

    // attacker may be null (world kills); then everyone who damaged the target assisted
    void killed(Entity@ target, Entity@ attacker) {
        if (@target == null || @target.client == null) {
            return;
        }

        int v = target.playerNum;
        if (v < 0 || v >= maxClients || this.dead[v]) {
            return; // the engine fires "kill" again if a corpse is gibbed
        }
        this.dead[v] = true;

        int killer = (@attacker != null && @attacker.client != null) ? attacker.playerNum : -1;
        for (int a = 0; a < maxClients; a++) {
            if (this.damagedBy[v][a] && a != killer) {
                this.assists[a]++;
            }
            this.damagedBy[v][a] = false;
        }
    }
}

AssistTracker assists;
