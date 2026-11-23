// StatsCarry: keeps kills, deaths and damage on the scoreboard across team changes.
//
// The engine zeroes a client's stats (frags, deaths, damage, score...) whenever they
// change team, and callvote rebalance also zeroes everyone it doesn't move. The script
// can't write those counters back (only the score is settable), so instead we remember
// the last values we saw for each player. When the engine's values drop below them,
// the stats were wiped, and the old values are added to a carried-over total that the
// scoreboard shows on top of the engine's numbers.
//
// The engine's counters only ever go up between wipes, so "any counter went down"
// reliably means a wipe. Totals are cleared at match start and when a slot changes owner.

class StatsCarry {
    // by playerNum: the engine's values when last checked
    array<int> lastFrags, lastDeaths, lastDmgGiven, lastDmgTaken;
    // by playerNum: totals from before the most recent wipe(s)
    array<int> carryFrags, carryDeaths, carryDmgGiven, carryDmgTaken;

    StatsCarry() {
        this.lastFrags.resize(maxClients);
        this.lastDeaths.resize(maxClients);
        this.lastDmgGiven.resize(maxClients);
        this.lastDmgTaken.resize(maxClients);
        this.carryFrags.resize(maxClients);
        this.carryDeaths.resize(maxClients);
        this.carryDmgGiven.resize(maxClients);
        this.carryDmgTaken.resize(maxClients);
        this.resetAll();
    }

    // Forget a player's totals (connect/disconnect). Takes the engine's current
    // values as the new baseline so they aren't mistaken for a wipe later.
    void reset(Client@ client) {
        if (@client == null) {
            return;
        }
        int p = client.playerNum;
        if (p < 0 || p >= maxClients) {
            return;
        }
        this.carryFrags[p] = this.carryDeaths[p] = this.carryDmgGiven[p] = this.carryDmgTaken[p] = 0;
        this.lastFrags[p] = client.stats.frags;
        this.lastDeaths[p] = client.stats.deaths;
        this.lastDmgGiven[p] = client.stats.totalDamageGiven;
        this.lastDmgTaken[p] = client.stats.totalDamageReceived;
    }

    // Forget everyone's totals. Call after the engine stats are cleared at match start.
    void resetAll() {
        for (int i = 0; i < maxClients; i++) {
            this.carryFrags[i] = this.carryDeaths[i] = this.carryDmgGiven[i] = this.carryDmgTaken[i] = 0;
            this.lastFrags[i] = this.lastDeaths[i] = this.lastDmgGiven[i] = this.lastDmgTaken[i] = 0;
        }
    }

    // Notice a wipe of this player's engine stats and carry the old values over.
    void sync(Client@ client) {
        if (@client == null) {
            return;
        }
        int p = client.playerNum;
        if (p < 0 || p >= maxClients) {
            return;
        }

        int frags = client.stats.frags;
        int deaths = client.stats.deaths;
        int dmgGiven = client.stats.totalDamageGiven;
        int dmgTaken = client.stats.totalDamageReceived;

        if (frags < this.lastFrags[p] || deaths < this.lastDeaths[p]
                || dmgGiven < this.lastDmgGiven[p] || dmgTaken < this.lastDmgTaken[p]) {
            this.carryFrags[p] += this.lastFrags[p];
            this.carryDeaths[p] += this.lastDeaths[p];
            this.carryDmgGiven[p] += this.lastDmgGiven[p];
            this.carryDmgTaken[p] += this.lastDmgTaken[p];

            // the score is damage given during the match, and the wipe cleared it too
            if (match.getState() == MATCH_STATE_PLAYTIME) {
                client.stats.setScore(this.carryDmgGiven[p] + dmgGiven);
            }
        }

        this.lastFrags[p] = frags;
        this.lastDeaths[p] = deaths;
        this.lastDmgGiven[p] = dmgGiven;
        this.lastDmgTaken[p] = dmgTaken;
    }

    // Every frame, so the last values are always from before any wipe.
    void syncAll() {
        for (int i = 0; i < maxClients; i++) {
            Client@ client = @G_GetClient(i);
            if (@client != null) {
                this.sync(client);
            }
        }
    }

    int frags(Client@ client) {
        this.sync(client);
        return this.carryFrags[client.playerNum] + client.stats.frags;
    }

    int deaths(Client@ client) {
        this.sync(client);
        return this.carryDeaths[client.playerNum] + client.stats.deaths;
    }

    int damageGiven(Client@ client) {
        this.sync(client);
        return this.carryDmgGiven[client.playerNum] + client.stats.totalDamageGiven;
    }

    int damageTaken(Client@ client) {
        this.sync(client);
        return this.carryDmgTaken[client.playerNum] + client.stats.totalDamageReceived;
    }
}

StatsCarry statsCarry;
