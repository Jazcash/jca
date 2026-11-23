// Countdown ghosting and the join ping limit.

Cvar g_jca_maxping = Cvar("g_jca_maxping", "0", 0); // 0 = no limit (disabled for now, was 150)

// Countdown ghosting: during the pre-round countdown players pass through each other
// (PMFEAT_GHOSTMOVE only changes what blocks their own movement, so shots still hit them).
// It ends at "Fight!": everyone not standing inside another player gets collisions back on
// that frame. Players who are inside each other at that moment would get stuck if both turned
// solid, so they keep ghost move only until they're clear of each other (overlaps with players
// who are already solid don't count, so a leftover ghost can't keep walking through people),
// and never for longer than GHOST_RELEASE_MAX_MS.
const uint GHOST_RELEASE_MAX_MS = 1500;

class SpawnGhosting {
    bool[] ghosted;
    uint releaseDeadline = 0;

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

    // called from GT_PlayerRespawn (respawn resets pmove features to the defaults, which
    // don't include ghost move, so anyone respawned outside the countdown is solid)
    void playerRespawned(Entity@ ent) {
        this.ghosted[ent.playerNum] = false;
        if (!ent.isGhosting() && caRound.state == CA_ROUNDSTATE_PREROUND) {
            this.setGhost(ent.client, true);
        }
    }

    bool isLivePlayer(Entity@ ent) {
        return @ent != null && ent.inuse && !ent.isGhosting() && ent.team >= TEAM_ALPHA;
    }

    // onlyGhosted: only count players who still have ghost move
    bool overlapsAnyone(Entity@ ent, bool onlyGhosted) {
        Vec3 a = ent.origin;
        for (int i = 0; i < maxClients; i++) {
            if (i == ent.playerNum || (onlyGhosted && !this.ghosted[i])) {
                continue;
            }
            Entity@ other = @G_GetClient(i).getEnt();
            if (!this.isLivePlayer(other)) {
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

    // called from cCARound when the round state goes to ROUND ("Fight!")
    void roundStarted() {
        this.releaseDeadline = levelTime + GHOST_RELEASE_MAX_MS;
        // decide who's overlapping before changing anyone, so the order doesn't matter
        bool[] keep(maxClients);
        for (int i = 0; i < maxClients; i++) {
            keep[i] = false;
            if (this.ghosted[i]) {
                Entity@ ent = @G_GetClient(i).getEnt();
                keep[i] = this.isLivePlayer(ent) && this.overlapsAnyone(ent, false);
            }
        }
        for (int i = 0; i < maxClients; i++) {
            if (this.ghosted[i] && !keep[i]) {
                this.setGhost(@G_GetClient(i), false);
            }
        }
    }

    // called every frame: outside the countdown, release anyone still ghosted once they're
    // clear of the other ghosts (or the time cap runs out)
    void think() {
        if (caRound.state == CA_ROUNDSTATE_PREROUND) {
            return;
        }
        bool timeUp = levelTime >= this.releaseDeadline;
        for (int i = 0; i < maxClients; i++) {
            if (!this.ghosted[i]) {
                continue;
            }
            Client@ client = @G_GetClient(i);
            Entity@ ent = @client.getEnt();
            if (timeUp || !this.isLivePlayer(ent) || !this.overlapsAnyone(ent, true)) {
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

// Handicap block: the engine's "handicap" userinfo setting scales down the damage a player
// deals, which skews damage stats and ratings. The game module can't be told to ignore it,
// so anyone with a handicap set is moved to spectator until they set it back to 0.
class HandicapBlock {
    int[] pending;

    // mirrors the engine: values outside [0, 90] are ignored (treated as 0)
    int handicapOf(Client@ client) {
        int h = client.getUserInfoKey("handicap").toInt();
        return (h > 0 && h <= 90) ? h : 0;
    }

    void check(Client@ client) {
        if (@client == null || client.isBot() || client.team < TEAM_ALPHA || this.handicapOf(client) == 0) {
            return;
        }
        // moving the player from inside a callback could re-enter it, so do it in think()
        this.pending.insertLast(client.playerNum);
    }

    // called from GT_PlayerRespawn
    void playerRespawned(Entity@ ent) {
        this.check(ent.client);
    }

    // called from GT_ScoreEvent on "userinfochanged" (the handicap command changes userinfo)
    void userinfoChanged(Client@ client) {
        this.check(client);
    }

    void think() {
        for (uint i = 0; i < this.pending.length(); i++) {
            Client@ client = @G_GetClient(this.pending[i]);
            if (client.team < TEAM_ALPHA || this.handicapOf(client) == 0) {
                continue; // already left the team or cleared it
            }
            client.team = TEAM_SPECTATOR;
            client.respawn(true);
            client.printMessage(S_COLOR_YELLOW + "Handicap is disabled on this server. Type "
                + S_COLOR_WHITE + "handicap 0" + S_COLOR_YELLOW + " in the console to play.\n");
            G_PrintMsg(null, client.name + S_COLOR_YELLOW + " was moved to spectator for using a handicap\n");
        }
        this.pending.resize(0);
    }
}

HandicapBlock handicapBlock;
