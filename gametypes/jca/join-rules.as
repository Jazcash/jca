// Countdown ghosting and the join ping limit.

Cvar g_jca_maxping = Cvar("g_jca_maxping", "150", 0); // 0 = no limit

// Countdown ghosting: during the pre-round countdown players pass through each other
// (PMFEAT_GHOSTMOVE only changes what blocks their own movement, so shots still hit them).
// Collisions come back when the round starts, but only once a player isn't overlapping
// anyone, so nobody gets stuck inside another player.
class SpawnGhosting {
    bool[] ghosted;

    SpawnGhosting() {
        // fixed size: maxClients may not be set yet when globals are constructed
        this.ghosted.resize(256);
        for (uint i = 0; i < this.ghosted.length(); i++) {
            this.ghosted[i] = false;
        }
    }

    void setGhost(Client@ client, bool on) {
        if (on) {
            client.pmoveFeatures = client.pmoveFeatures | PMFEAT_GHOSTMOVE;
        } else {
            client.pmoveFeatures = client.pmoveFeatures & ~uint(PMFEAT_GHOSTMOVE);
        }
        this.ghosted[client.playerNum] = on;
    }

    // called from GT_PlayerRespawn (respawn resets pmove features to the defaults)
    void playerRespawned(Entity@ ent) {
        this.ghosted[ent.playerNum] = false;
        if (!ent.isGhosting() && caRound.state == CA_ROUNDSTATE_PREROUND) {
            this.setGhost(ent.client, true);
        }
    }

    bool overlapsAnyone(Entity@ ent) {
        Vec3 a = ent.origin;
        for (int i = 0; i < maxClients; i++) {
            if (i == ent.playerNum) {
                continue;
            }
            Entity@ other = @G_GetClient(i).getEnt();
            if (@other == null || !other.inuse || other.isGhosting() || other.team < TEAM_ALPHA) {
                continue;
            }
            Vec3 b = other.origin;
            // player boxes are 32x32x64 (less when crouched, so this errs on the safe side)
            float dx = a.x - b.x;
            float dy = a.y - b.y;
            float dz = a.z - b.z;
            if (dx < 0) dx = -dx;
            if (dy < 0) dy = -dy;
            if (dz < 0) dz = -dz;
            if (dx < 33 && dy < 33 && dz < 65) {
                return true;
            }
        }
        return false;
    }

    // called every frame: once the countdown is over, restore collisions for anyone who is clear
    void think() {
        if (caRound.state == CA_ROUNDSTATE_PREROUND) {
            return;
        }
        for (int i = 0; i < maxClients; i++) {
            if (!this.ghosted[i]) {
                continue;
            }
            Client@ client = @G_GetClient(i);
            Entity@ ent = @client.getEnt();
            if (@ent == null || !ent.inuse || ent.isGhosting() || !this.overlapsAnyone(ent)) {
                this.setGhost(client, false);
            }
        }
    }
}

SpawnGhosting spawnGhosting;

// Ping limit: players whose ping is above g_jca_maxping when they join a team are
// moved back to spectator. Only checked on joining, not while already playing.
class PingLimit {
    int[] pending;

    // called from GT_PlayerRespawn. Moving the player from inside that callback would
    // re-enter it, so the move happens in think() on the next frame.
    void playerRespawned(Entity@ ent, int old_team, int new_team) {
        if (g_jca_maxping.integer <= 0 || old_team != TEAM_SPECTATOR || new_team < TEAM_ALPHA) {
            return;
        }
        if (ent.client.isBot() || ent.client.ping <= g_jca_maxping.integer) {
            return;
        }
        this.pending.insertLast(ent.playerNum);
    }

    void think() {
        for (uint i = 0; i < this.pending.length(); i++) {
            Client@ client = @G_GetClient(this.pending[i]);
            if (client.team < TEAM_ALPHA) {
                continue; // already left the team
            }
            int ping = client.ping;
            client.team = TEAM_SPECTATOR;
            client.respawn(true);
            client.printMessage(S_COLOR_YELLOW + "Your ping (" + ping + ") is above this server's limit of "
                + g_jca_maxping.integer + ". You can still spectate.\n");
            G_PrintMsg(null, client.name + S_COLOR_YELLOW + " can't play: ping " + ping + " is above the limit of "
                + g_jca_maxping.integer + "\n");
        }
        this.pending.resize(0);
    }
}

PingLimit pingLimit;
