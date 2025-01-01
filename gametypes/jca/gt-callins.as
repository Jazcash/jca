bool GT_Command(Client@ client, const String& cmdString, const String& argsString, int argc) {
    if (cmdString == "gametype") {
        String response = "";
        Cvar fs_game("fs_game", "", 0);
        String manifest = gametype.manifest;

        response += "\n";
        response += "Gametype " + gametype.name + " : " + gametype.title + "\n";
        response += "----------------\n";
        response += "Version: " + gametype.version + "\n";
        response += "Author: " + gametype.author + "\n";
        response += "Mod: " + fs_game.string + (!manifest.empty() ? " (manifest: " + manifest + ")" : "") + "\n";
        response += "----------------\n";

        G_PrintMsg(client.getEnt(), response);
        return true;
    } else if (cmdString == "cvarinfo") {
            GENERIC_CheatVarResponse(client, cmdString, argsString, argc);
            return true;
        } else if (cmdString == "fish") {
            G_PrintMsg(client.getEnt(), client.getUserInfoKey("steam_id") + "\n");
        
            return true;
        }

    return false;
}

// When this function is called the weights of items have been reset to their default values,
// this means, the weights *are set*, and what this function does is scaling them depending
// on the current bot status.
// Player, and non-item entities don't have any weight set. So they will be ignored by the bot
// unless a weight is assigned here.
bool GT_UpdateBotStatus(Entity@ ent) {
    Entity@ goal;
    Bot@ bot;

    @bot = @ent.client.getBot();
    if (@bot == null)
        return false;

    float offensiveStatus = GENERIC_OffensiveStatus(ent);

    // loop all the goal entities
    for (
        int i = AI::GetNextGoal(AI::GetRootGoal()); i != AI::GetRootGoal(); i = AI::GetNextGoal(i)) {
        @goal = @AI::GetGoalEntity(i);

        // by now, always full-ignore not solid entities
        if (goal.solid == SOLID_NOT) {
            bot.setGoalWeight(i, 0);
            continue;
        }

        if (@goal.client != null) {
            bot.setGoalWeight(i, GENERIC_PlayerWeight(ent, goal) * 2.5 * offensiveStatus);
            continue;
        }

        // ignore it
        bot.setGoalWeight(i, 0);
    }

    return true; // handled by the script
}

void GT_updateScore(Client@ client) {
    if (@client != null) {
        if (gametype.isInstagib)
            client.stats.setScore(client.stats.frags + caRound.getPlayerBonusScore(client)); else
            client.stats.setScore(int(client.stats.totalDamageGiven * 0.01) + caRound.getPlayerBonusScore(client));
    }
}

// Some game actions trigger score events. These are events not related to killing
// oponents, like capturing a flag
// Warning: client can be null
void GT_ScoreEvent(Client@ client, const String& score_event, const String& args) {
    if (score_event == "dmg") {
        if (match.getState() == MATCH_STATE_PLAYTIME) {
            GT_updateScore(client);
        }
    } else if (score_event == "kill") {
            Entity@ attacker = null;

            if (@client != null)
                @attacker = @client.getEnt();

            int arg1 = args.getToken(0).toInt();
            int arg2 = args.getToken(1).toInt();

        // target, attacker, inflictor
            caRound.playerKilled(G_GetEntity(arg1), attacker, G_GetEntity(arg2));

            if (match.getState() == MATCH_STATE_PLAYTIME) {
                GT_updateScore(client);
            }
        } else if (score_event == "award") {
            } else if (score_event == "rebalance" || score_event == "shuffle") {
		// end round when in match
                    if ((@client == null) && (match.getState() == MATCH_STATE_PLAYTIME)) {
                        caRound.newRoundState(CA_ROUNDSTATE_ROUNDFINISHED);
                    }	
                }
}

// a player is being respawned. This can happen from several ways, as dying, changing team,
// being moved to ghost state, be placed in respawn queue, being spawned from spawn queue, etc
void GT_PlayerRespawn(Entity@ ent, int old_team, int new_team) {
    if (ent.isGhosting()) {
        ent.svflags &= ~SVF_FORCETEAM;
        return;
    }

    if (gametype.isInstagib) {
        ent.client.inventoryGiveItem(WEAP_INSTAGUN);
        ent.client.inventorySetCount(AMMO_INSTAS, 1);
        ent.client.inventorySetCount(AMMO_WEAK_INSTAS, 1);
    } else {
    	// give the weapons and ammo as defined in cvars
        String token, weakammotoken, ammotoken;
        String itemList = g_noclass_inventory.string;
        String ammoCounts = g_class_strong_ammo.string;

        ent.client.inventoryClear();

        for (
            int i = 0;; i++) {
            token = itemList.getToken(i);
            if (token.len() == 0)
                break; // done

            Item@ item = @G_GetItemByName(token);
            if (@item == null)
                continue;

            ent.client.inventoryGiveItem(item.tag);

            // if it's ammo, set the ammo count as defined in the cvar
            if ((item.type & IT_AMMO) != 0) {
                token = ammoCounts.getToken(item.tag - AMMO_GUNBLADE);

                if (token.len() > 0) {
                    ent.client.inventorySetCount(item.tag, token.toInt());
                }
            }
        }

        // give armor
        ent.client.armor = 150;

        // select rocket launcher
        ent.client.selectWeapon(WEAP_ROCKETLAUNCHER);
    }

    // auto-select best weapon in the inventory
    if (ent.client.pendingWeapon == WEAP_NONE)
        ent.client.selectWeapon(-1);

    ent.svflags |= SVF_FORCETEAM;

    // add a teleportation effect
    ent.respawnEffect();
}

// Thinking function. Called each frame
void GT_ThinkRules() {
    if (match.scoreLimitHit() || match.timeLimitHit() || match.suddenDeathFinished())
        match.launchState(match.getState() + 1);

    GENERIC_Think();

    // print count of players alive and show class icon in the HUD

    Team@ team;
    int[] alive(GS_MAX_TEAMS);

    alive[TEAM_SPECTATOR] = 0;
    alive[TEAM_PLAYERS] = 0;
    alive[TEAM_ALPHA] = 0;
    alive[TEAM_BETA] = 0;

    for (
        int t = TEAM_ALPHA; t < GS_MAX_TEAMS; t++) {
        @team = @G_GetTeam(t);
        for (
            int i = 0; @team.ent(i) != null; i++) {
            if (!team.ent(i).isGhosting())
                alive[t]++;
        }
    }

    G_ConfigString(CS_GENERAL, "" + alive[TEAM_ALPHA]);
    G_ConfigString(CS_GENERAL + 1, "" + alive[TEAM_BETA]);

    for (
        int i = 0; i < maxClients; i++) {
        Client@ client = @G_GetClient(i);

        if (match.getState() >= MATCH_STATE_POSTMATCH || match.getState() < MATCH_STATE_PLAYTIME) {
            client.setHUDStat(STAT_MESSAGE_ALPHA, 0);
            client.setHUDStat(STAT_MESSAGE_BETA, 0);
            client.setHUDStat(STAT_IMAGE_BETA, 0);
        } else {
            client.setHUDStat(STAT_MESSAGE_ALPHA, CS_GENERAL);
            client.setHUDStat(STAT_MESSAGE_BETA, CS_GENERAL + 1);
        }

        if (client.getEnt().isGhosting()
            || match.getState() >= MATCH_STATE_POSTMATCH) {
            client.setHUDStat(STAT_IMAGE_BETA, 0);
        }
    }

    if (match.getState() >= MATCH_STATE_POSTMATCH)
        return;

    caRound.think();
}

// The game has detected the end of the match state, but it
// doesn't advance it before calling this function.
// This function must give permission to move into the next
// state by returning true.
bool GT_MatchStateFinished(int incomingMatchState) {
    // ** MISSING EXTEND PLAYTIME CHECK **

    if (match.getState() <= MATCH_STATE_WARMUP && incomingMatchState > MATCH_STATE_WARMUP
        && incomingMatchState < MATCH_STATE_POSTMATCH)
        match.startAutorecord();

    if (match.getState() == MATCH_STATE_POSTMATCH)
        match.stopAutorecord();

    return true;
}

// the match state has just moved into a new state. Here is the
// place to set up the new state rules
void GT_MatchStateStarted() {
    switch(match.getState()) {
    case MATCH_STATE_WARMUP:
        CA_SetUpWarmup();
        break;

    case MATCH_STATE_COUNTDOWN:
        CA_SetUpCountdown();
        break;

    case MATCH_STATE_PLAYTIME:
        caRound.newGame();
        break;

    case MATCH_STATE_POSTMATCH:
        caRound.endGame();
        break;

    default:
        break;
    }
}

// the gametype is shutting down cause of a match restart or map change
void GT_Shutdown() {
}

// The map entities have just been spawned. The level is initialized for
// playing, but nothing has yet started.
void GT_SpawnGametype() {
}

// Important: This function is called before any entity is spawned, and
// spawning entities from it is forbidden. If you want to make any entity
// spawning at initialization do it in GT_SpawnGametype, which is called
// right after the map entities spawning.

void GT_InitGametype() {
    gametype.title = "Jaz's Clan Arena";
    gametype.version = "1.01";
    gametype.author = "Jazcash";

    // if the gametype doesn't have a config file, create it
    if (!G_FileExists("configs/server/gametypes/" + gametype.name + ".cfg")) {
        String config;

        // the config file doesn't exist or it's empty, create it
        config = "// '" + gametype.title + "' gametype configuration file\n"
            + "// This config will be executed each time the gametype is started\n"
                + "\n\n// map rotation\n"
                    + "set g_maplist \"wfca1\" // list of maps in automatic rotation\n"
                        + "set g_maprotation \"0\"   // 0 = same map, 1 = in order, 2 = random\n"
                            + "\n// game settings\n"
                                + "set g_scorelimit \"11\"\n"
                                    + "set g_timelimit \"0\"\n"
                                        + "set g_warmup_timelimit \"1\"\n"
                                            + "set g_match_extendedtime \"0\"\n"
                                                + "set g_allow_falldamage \"0\"\n"
                                                    + "set g_allow_selfdamage \"0\"\n"
                                                        + "set g_allow_teamdamage \"0\"\n"
                                                            + "set g_allow_stun \"0\"\n"
                                                                + "set g_teams_maxplayers \"5\"\n"
                                                                    + "set g_teams_allow_uneven \"0\"\n"
                                                                        + "set g_countdown_time \"3\"\n"
                                                                            + "set g_maxtimeouts \"1\" // -1 = unlimited\n"
                                                                                + "\n// gametype settings\n"
                                                                                    + "set g_ca_timelimit1v1 \"60\"\n"
                                                                                        + "\n// classes settings\n"
                                                                                            + "set g_noclass_inventory \"gb mg rg gl rl pg lg eb cells shells grens rockets plasma lasers bolts bullets\"\n"
                                                                                                + "set g_class_strong_ammo \"1 75 15 20 40 150 150 15\" // GB MG RG GL RL PG LG EB\n"
                                                                                                    + "\necho \"" + gametype.name + ".cfg executed\"\n";

        G_WriteFile("configs/server/gametypes/" + gametype.name + ".cfg", config);
        G_Print("Created default config file for '" + gametype.name + "'\n");
        G_CmdExecute("exec configs/server/gametypes/" + gametype.name + ".cfg silent");
    }

    caTimelimit1v1 = g_ca_timelimit1v1.integer;

    gametype.spawnableItemsMask = 0;
    gametype.respawnableItemsMask = 0;
    gametype.dropableItemsMask = 0;
    gametype.pickableItemsMask = 0;

    gametype.isTeamBased = true;
    gametype.isRace = false;
    gametype.hasChallengersQueue = false;
    gametype.maxPlayersPerTeam = 0;

    gametype.ammoRespawn = 20;
    gametype.armorRespawn = 25;
    gametype.weaponRespawn = 15;
    gametype.healthRespawn = 25;
    gametype.powerupRespawn = 90;
    gametype.megahealthRespawn = 20;
    gametype.ultrahealthRespawn = 60;

    gametype.readyAnnouncementEnabled = false;
    gametype.scoreAnnouncementEnabled = false;
    gametype.countdownEnabled = false;
    gametype.mathAbortDisabled = false;
    gametype.shootingDisabled = false;
    gametype.infiniteAmmo = false;
    gametype.canForceModels = true;
    gametype.canShowMinimap = false;
    gametype.teamOnlyMinimap = true;
    gametype.removeInactivePlayers = true;

    gametype.mmCompatible = true;
	
    gametype.spawnpointRadius = 256;

    if (gametype.isInstagib)
        gametype.spawnpointRadius *= 2;

    // set spawnsystem type to instant while players join
    for (
        int team = TEAM_PLAYERS; team < GS_MAX_TEAMS; team++)
        gametype.setTeamSpawnsystem(team, SPAWNSYSTEM_INSTANT, 0, 0, false);

    // define the scoreboard layout
    G_ConfigString(CS_SCB_PLAYERTAB_TITLES, "AVATAR Name Score Frags DG/DR Ping R");
    G_ConfigString(CS_SCB_PLAYERTAB_LAYOUT, "%a l1 %n 112 %i 50 %i 40 %s 42 %l 38 %r l1");

    // add commands
    G_RegisterCommand("gametype");
    G_RegisterCommand("fish");

    G_Print("Gametype '" + gametype.title + "' initialized\n");
}

// select a spawning point for a player
Entity@ GT_SelectSpawnPoint(Entity@ self) {
    if (caRound.state == CA_ROUNDSTATE_PREROUND) {
        if (self.team == TEAM_ALPHA)
            return @caRound.alphaSpawn;

        if (self.team == TEAM_BETA)
            return @caRound.betaSpawn;
    }

    return GENERIC_SelectBestRandomSpawnPoint(self, "info_player_deathmatch");
}

String@ GT_ScoreboardMessage(uint maxlen) {
    String scoreboardMessage = "";
    String entry;
    Team@ team;
    Entity@ ent;
    int i, t;

    for (t = TEAM_ALPHA; t < GS_MAX_TEAMS; t++) {
        @team = @G_GetTeam(t);

        // &t = team tab, team tag, team score (doesn't apply), team ping (doesn't apply)
        entry = "&t " + t + " " + team.stats.score + " " + team.ping + " ";
        if (scoreboardMessage.len() + entry.len() < maxlen)
            scoreboardMessage += entry;

        for (i = 0; @team.ent(i) != null; i++) {
            @ent = @team.ent(i);

            int playerID = (ent.isGhosting() && (match.getState() == MATCH_STATE_PLAYTIME)) ? -(ent.playerNum + 1) : ent.playerNum;

            // int frags = ent.client.stats.frags;
            // int deaths = ent.client.stats.deaths;
            // float kd = ( deaths == 0) ? frags : float(frags) / float(deaths);

            int dmgGiven = ent.client.stats.totalDamageGiven;
            int dmgTaken = ent.client.stats.totalDamageReceived;
            float dmgRatio = (dmgTaken == 0) ? float(dmgGiven) : float(dmgGiven) / float(dmgTaken);
            String dmgRatioStr;
            if (dmgRatio < 1.0) {
                dmgRatioStr = "^1" + formatFloat(dmgRatio, 2); // Red for <1
            } else {
                dmgRatioStr = "^2" + formatFloat(dmgRatio, 2); // Green for >=1
            }


            // "Name Score Frags DG/DR Ping R"
            entry = 
                "&p " + playerID + " " +
                playerID + " " +
                ent.client.stats.score + " " + 
                ent.client.stats.frags + " " + 
                dmgRatioStr + " " + 
                ent.client.ping + " " + 
                (ent.client.isReady() ? "1" : "0") + " ";

            if (scoreboardMessage.len() + entry.len() < maxlen)
                scoreboardMessage += entry;
        }
    }

    return scoreboardMessage;
}
