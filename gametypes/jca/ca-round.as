uint caTimelimit1v1;

Cvar g_ca_timelimit1v1( "g_ca_timelimit1v1", "60", 0 );

Cvar g_noclass_inventory( "g_noclass_inventory", "gb mg rg gl rl pg lg eb cells shells grens rockets plasma lasers bullets", 0 );
Cvar g_class_strong_ammo( "g_class_strong_ammo", "1 75 20 20 40 150 150 15", 0 ); // GB MG RG GL RL PG LG EB

const int CA_ROUNDSTATE_NONE = 0;
const int CA_ROUNDSTATE_PREROUND = 1;
const int CA_ROUNDSTATE_ROUND = 2;
const int CA_ROUNDSTATE_ROUNDFINISHED = 3;
const int CA_ROUNDSTATE_POSTROUND = 4;

const int CA_LAST_MAN_STANDING_BONUS = 0; // 0 points for each frag

int[] caBonusScores(maxClients);
int[] caLMSCounts(GS_MAX_TEAMS); // last man standing bonus for each team

class cCARound {
    int state;
    int numRounds;
    uint roundStateStartTime;
    uint roundStateEndTime;
    int countDown;
    Entity@ alphaSpawn;
    Entity@ betaSpawn;
    uint minuteLeft;
    int timelimit;
    int alpha_oneVS;
    int beta_oneVS;

    cCARound() {
        this.state = CA_ROUNDSTATE_NONE;
        this.numRounds = 0;
        this.roundStateStartTime = 0;
        this.countDown = 0;
        this.minuteLeft = 0;
        this.timelimit = 0;
        @this.alphaSpawn = null;
        @this.betaSpawn = null;
        
        this.alpha_oneVS = 0;
        this.beta_oneVS = 0;
    }

    ~cCARound() { }

    void setupSpawnPoints() {
        String className("info_player_deathmatch");
        Entity@ spot1;
        Entity@ spot2;
        Entity@ spawn;
        float dist, bestDistance;

        // pick a random spawn first
        @spot1 = @GENERIC_SelectBestRandomSpawnPoint(null, className);

        // pick the furthest spawn second
        array<Entity@>@ spawns = G_FindByClassname(className);
        @spawn = null;
        bestDistance = 0;
        @spot2 = null;
		
        for (
            uint i = 0; i < spawns.size(); i++) {
            @spawn = spawns[i];
            dist = spot1.origin.distance(spawn.origin);
            if (dist > bestDistance || @spot2 == null) {
                bestDistance = dist;
                @spot2 = @spawn;
            }
        }

        if (random() > 0.5f) {
            @this.alphaSpawn = @spot1;
            @this.betaSpawn = @spot2;
        } else {
            @this.alphaSpawn = @spot2;
            @this.betaSpawn = @spot1;
        }
    }

    void newGame() {
        gametype.readyAnnouncementEnabled = false;
        gametype.scoreAnnouncementEnabled = true;
        gametype.countdownEnabled = false;

        // set spawnsystem type to not respawn the players when they die
        for (
            int team = TEAM_PLAYERS; team < GS_MAX_TEAMS; team++)
            gametype.setTeamSpawnsystem(team, SPAWNSYSTEM_HOLD, 0, 0, true);

        // clear scores

        Entity@ ent;
        Team@ team;
        int i;

        for (i = TEAM_PLAYERS; i < GS_MAX_TEAMS; i++) {
            @team = @G_GetTeam(i);
            team.stats.clear();

            // respawn all clients inside the playing teams
            for (
                int j = 0; @team.ent(j) != null; j++) {
                @ent = @team.ent(j);
                ent.client.stats.clear(); // clear player scores & stats
            }
        }

        // clear bonuses
        for (i = 0; i < maxClients; i++)
            caBonusScores[i] = 0;

        this.clearLMSCounts();

        this.numRounds = 0;
        this.newRound();
        
        this.alpha_oneVS = 0;
        this.beta_oneVS = 0;

    }

    void addPlayerBonus(Client@ client, int bonus) {
        if (@client == null)
            return;

        caBonusScores[client.playerNum] += bonus;
    }

    int getPlayerBonusScore(Client@ client) {
        if (@client == null)
            return 0;

        return caBonusScores[client.playerNum];
    }

    void clearLMSCounts() {
		// clear last-man-standing counts
        for (
            int i = TEAM_PLAYERS; i < GS_MAX_TEAMS; i++)
            caLMSCounts[i] = 0;
    }

    void endGame() {
        this.newRoundState(CA_ROUNDSTATE_NONE);

        GENERIC_SetUpEndMatch();
    }

    void newRound() {
        G_RemoveDeadBodies();
        G_RemoveAllProjectiles();

        this.newRoundState(CA_ROUNDSTATE_PREROUND);
        this.numRounds++;
    }

    void newRoundState(int newState) {
        if (newState > CA_ROUNDSTATE_POSTROUND) {
            this.newRound();
            return;
        }

        this.state = newState;
        this.roundStateStartTime = levelTime;

        switch(this.state) {
        case CA_ROUNDSTATE_NONE:
            this.roundStateEndTime = 0;
            this.countDown = 0;
            this.timelimit = 0;
            this.minuteLeft = 0;
            break;

        case CA_ROUNDSTATE_PREROUND: {
            this.roundStateEndTime = levelTime + 7000;
            this.countDown = 5;
            this.timelimit = 0;
            this.minuteLeft = 0;

            // respawn everyone and disable shooting
            gametype.shootingDisabled = true;
            gametype.removeInactivePlayers = false;

            this.setupSpawnPoints();
	
            this.alpha_oneVS = 0;
            this.beta_oneVS = 0;

            Entity@ ent;
            Team@ team;

            for (
                int i = TEAM_PLAYERS; i < GS_MAX_TEAMS; i++) {
                @team = @G_GetTeam(i);

                // respawn all clients inside the playing teams
                for (
                    int j = 0; @team.ent(j) != null; j++) {
                    @ent = @team.ent(j);
                    ent.client.respawn(false);
                }
            }

            this.clearLMSCounts();
        }
        break;

        case CA_ROUNDSTATE_ROUND: {
            gametype.shootingDisabled = false;
            gametype.removeInactivePlayers = true;
            this.countDown = 0;
            this.roundStateEndTime = 0;
            int soundIndex = G_SoundIndex("sounds/announcer/countdown/fight0" + (1 + (rand() & 1)));
            G_AnnouncerSound(null, soundIndex, GS_MAX_TEAMS, false, null);
            G_CenterPrintMsg(null, 'Fight!');
        }
        break;

        case CA_ROUNDSTATE_ROUNDFINISHED:
            gametype.shootingDisabled = true;
            this.roundStateEndTime = levelTime + 1500;
            this.countDown = 0;
            this.timelimit = 0;
            this.minuteLeft = 0;
            break;

        case CA_ROUNDSTATE_POSTROUND: {
            this.roundStateEndTime = levelTime + 3000;

            // add score to round-winning team
            Entity@ ent;
            Entity@ lastManStanding = null;
            Team@ team;
            int count_alpha, count_beta;
            int count_alpha_total, count_beta_total;

            count_alpha = count_alpha_total = 0;
            @team = @G_GetTeam(TEAM_ALPHA);
            for (
                int j = 0; @team.ent(j) != null; j++) {
                @ent = @team.ent(j);
                if (!ent.isGhosting()) {
                    count_alpha++;
                    @lastManStanding = @ent;
                    // ch : add round
                    if (@ent.client != null)
                        ent.client.stats.addRound();
                }
                count_alpha_total++;
            }

            count_beta = count_beta_total = 0;
            @team = @G_GetTeam(TEAM_BETA);
            for (
                int j = 0; @team.ent(j) != null; j++) {
                @ent = @team.ent(j);
                if (!ent.isGhosting()) {
                    count_beta++;
                    @lastManStanding = @ent;
                    // ch : add round
                    if (@ent.client != null)
                        ent.client.stats.addRound();
                }
                count_beta_total++;
            }

            int soundIndex;

            if (count_alpha > count_beta) {
                G_GetTeam(TEAM_ALPHA).stats.addScore(1);

                soundIndex = G_SoundIndex("sounds/announcer/ctf/score_team0" + (1 + (rand() & 1)));
                G_AnnouncerSound(null, soundIndex, TEAM_ALPHA, false, null);
                soundIndex = G_SoundIndex("sounds/announcer/ctf/score_enemy0" + (1 + (rand() & 1)));
                G_AnnouncerSound(null, soundIndex, TEAM_BETA, false, null);

                if (!gametype.isInstagib && count_alpha == 1) { // he's the last man standing. Drop a bonus 
                    if (count_beta_total > 1) {
                        lastManStanding.client.addAward(S_COLOR_GREEN + "Last Player Standing!");
                        // ch :
                        if (alpha_oneVS > ONEVS_AWARD_COUNT)
                        	// lastManStanding.client.addMetaAward( "Last Man Standing" );
                            lastManStanding.client.addAward("Last Man Standing");

                        this.addPlayerBonus(lastManStanding.client, caLMSCounts[TEAM_ALPHA] * CA_LAST_MAN_STANDING_BONUS);
                        GT_updateScore(lastManStanding.client);
                    }
                }
            } else if (count_beta > count_alpha) {
                G_GetTeam(TEAM_BETA).stats.addScore(1);

                soundIndex = G_SoundIndex("sounds/announcer/ctf/score_team0" + (1 + (rand() & 1)));
                G_AnnouncerSound(null, soundIndex, TEAM_BETA, false, null);
                soundIndex = G_SoundIndex("sounds/announcer/ctf/score_enemy0" + (1 + (rand() & 1)));
                G_AnnouncerSound(null, soundIndex, TEAM_ALPHA, false, null);

                if (!gametype.isInstagib && count_beta == 1) { // he's the last man standing. Drop a bonus
                    if (count_alpha_total > 1) {
                        lastManStanding.client.addAward(S_COLOR_GREEN + "Last Player Standing!");
                        // ch :
                        if (beta_oneVS > ONEVS_AWARD_COUNT)
                        	// lastManStanding.client.addMetaAward( "Last Man Standing" );
                            lastManStanding.client.addAward("Last Man Standing");

                        this.addPlayerBonus(lastManStanding.client, caLMSCounts[TEAM_BETA] * CA_LAST_MAN_STANDING_BONUS);
                        GT_updateScore(lastManStanding.client);
                    }
                }
            } else { // draw round
                G_CenterPrintMsg(null, "Draw Round!");
            }
        }
        break;

        default:
            break;
        }
    }

    void think() {
        if (this.state == CA_ROUNDSTATE_NONE)
            return;
		
        if (match.getState() != MATCH_STATE_PLAYTIME) {
            this.endGame();
            return;
        }

        if (this.roundStateEndTime != 0) {
            if (this.roundStateEndTime < levelTime) {
                this.newRoundState(this.state + 1);
                return;
            }

            if (this.countDown > 0) {
                // we can't use the authomatic countdown announces because their are based on the
                // matchstate timelimit, and prerounds don't use it. So, fire the announces "by hand".
                int remainingSeconds = int((this.roundStateEndTime - levelTime) * 0.001f) + 1;
                if (remainingSeconds < 0)
                    remainingSeconds = 0;

                if (remainingSeconds < this.countDown) {
                    this.countDown = remainingSeconds;

                    if (this.countDown == 4) {
                        int soundIndex = G_SoundIndex("sounds/announcer/countdown/ready0" + (1 + (rand() & 1)));
                        G_AnnouncerSound(null, soundIndex, GS_MAX_TEAMS, false, null);
                    } else if (this.countDown <= 3) {
                        int soundIndex = G_SoundIndex("sounds/announcer/countdown/" + this.countDown + "_0" + (1 + (rand() & 1)));
                        G_AnnouncerSound(null, soundIndex, GS_MAX_TEAMS, false, null);

                    }
                    G_CenterPrintMsg(null, String(this.countDown));
                }
            }
        }

        // if one of the teams has no player alive move from CA_ROUNDSTATE_ROUND
        if (this.state == CA_ROUNDSTATE_ROUND) {
			// 1 minute left if 1v1
            if (this.minuteLeft > 0) {
                uint left = this.minuteLeft - levelTime;

                if (caTimelimit1v1 != 0 && (caTimelimit1v1 * 1000) == left) {
                    if (caTimelimit1v1 < 60) {
                        G_CenterPrintMsg(null, caTimelimit1v1 + " seconds left. Hurry up!");
                    } else {
                        uint minutes;					
                        uint seconds = caTimelimit1v1 % 60;
						
                        if (seconds == 0) {
                            minutes = caTimelimit1v1 / 60;
                            if (minutes == 1) {
                                G_CenterPrintMsg(null, minutes + " minute left. Hurry up!");
                            } else {
                                G_CenterPrintMsg(null, minutes + " minutes left. Hurry up!");							
                            }
                        } else {
                            minutes = (caTimelimit1v1 - seconds) / 60;
                            G_CenterPrintMsg(null, minutes + " minutes and " + seconds + " seconds left. Hurry up!");
                        }
                    }
                }
				
                int remainingSeconds = int(left * 0.001f) + 1;
                if (remainingSeconds < 0)
                    remainingSeconds = 0;
				
                this.timelimit = remainingSeconds;
                match.setClockOverride(minuteLeft - levelTime);
				
                if (levelTime > this.minuteLeft) {
                    G_CenterPrintMsg(null, S_COLOR_RED + 'Timelimit hit!');
                    this.newRoundState(this.state + 1);
                }
            }
		
			// if one of the teams has no player alive move from CA_ROUNDSTATE_ROUND
            Entity@ ent;
            Team@ team;
            int count;

            for (
                int i = TEAM_ALPHA; i < GS_MAX_TEAMS; i++) {
                @team = @G_GetTeam(i);
                count = 0;

                for (
                    int j = 0; @team.ent(j) != null; j++) {
                    @ent = @team.ent(j);
                    if (!ent.isGhosting())
                        count++;
                }

                if (count == 0) {
                    this.newRoundState(this.state + 1);
                    break; // no need to continue
                }
            }
        }
    }

    void playerKilled(Entity@ target, Entity@ attacker, Entity@ inflictor) {
        Entity@ ent;
        Team@ team;

        if (this.state != CA_ROUNDSTATE_ROUND)
            return;

        if (@target != null && @target.client != null && @attacker != null && @attacker.client != null) {
            if (gametype.isInstagib) {
                G_PrintMsg(target, "You were fragged by " + attacker.client.name + "\n");
            } else {
				// report remaining health/armor of the killer
                G_PrintMsg(target, "You were fragged by " + attacker.client.name + "\n");
            }

            // if the attacker is the only remaining player on the team,
            // report number or remaining enemies

            int attackerCount = 0, targetCount = 0;

            // count attacker teammates
            @team = @G_GetTeam(attacker.team);
            for (
                int j = 0; @team.ent(j) != null; j++) {
                @ent = @team.ent(j);
                if (!ent.isGhosting())
                    attackerCount++;
            }

            // count target teammates
            @team = @G_GetTeam(target.team);
            for (
                int j = 0; @team.ent(j) != null; j++) {
                @ent = @team.ent(j);
                if (!ent.isGhosting() && @ent != @target)
                    targetCount++;
            }

			// amount of enemies for the last-man-standing award
            if (targetCount == 1 && caLMSCounts[target.team] == 0)
                caLMSCounts[target.team] = attackerCount;

            if (attackerCount == 1 && targetCount == 1) {
                G_PrintMsg(null, "1v1! Good luck!\n");
                attacker.client.addAward("1v1! Good luck!");

                // find the alive player in target team again (doh)
                @team = @G_GetTeam(target.team);
                for (
                    int j = 0; @team.ent(j) != null; j++) {
                    @ent = @team.ent(j);
                    if (ent.isGhosting() || @ent == @target)
                        continue;

                    ent.client.addAward(S_COLOR_ORANGE + "1v1! Good luck!");
                    break;
                }
				
                this.minuteLeft = levelTime + (caTimelimit1v1 * 1000);
            } else if (attackerCount == 1 && targetCount > 1) {
                attacker.client.addAward("1v" + targetCount + "! You're on your own!");

                // console print for the team
                @team = @G_GetTeam(attacker.team);
                for (
                    int j = 0; @team.ent(j) != null; j++) {
                    G_PrintMsg(team.ent(j), "1v" + targetCount + "! " + attacker.client.name + " is on its own!\n");
                }
                
                // ch : update last man standing count
                if (attacker.team == TEAM_ALPHA && targetCount > alpha_oneVS)
                    alpha_oneVS = targetCount; else if (attacker.team == TEAM_BETA && targetCount > beta_oneVS)
                    beta_oneVS = targetCount;
            } else if (attackerCount > 1 && targetCount == 1) {
                Entity@ survivor;

                // find the alive player in target team again (doh)
                @team = @G_GetTeam(target.team);
                for (
                    int j = 0; @team.ent(j) != null; j++) {
                    @ent = @team.ent(j);
                    if (ent.isGhosting() || @ent == @target)
                        continue;

                    ent.client.addAward("1v" + attackerCount + "! You're on your own!");
                    @survivor = @ent;
                    break;
                }

                // console print for the team
                for (
                    int j = 0; @team.ent(j) != null; j++) {
                    @ent = @team.ent(j);
                    G_PrintMsg(ent, "1v" + attackerCount + "! " + survivor.client.name + " is on its own!\n");
                }
                
                // ch : update last man standing count
                if (target.team == TEAM_ALPHA && attackerCount > alpha_oneVS)
                    alpha_oneVS = attackerCount; else if (target.team == TEAM_BETA && attackerCount > beta_oneVS)
                    beta_oneVS = attackerCount;
            }
            
            // check for generic awards for the frag
            if (attacker.team != target.team)
                award_playerKilled(@target, @attacker, @inflictor);
        }
        
        // ch : add a round for victim
        if (@target != null && @target.client != null)
            target.client.stats.addRound();
    }
};

cCARound caRound;
