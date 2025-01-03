void CA_SetUpWarmup() {
    GENERIC_SetUpWarmup();

    // set spawnsystem type to instant while players join
    for (int team = TEAM_PLAYERS; team < GS_MAX_TEAMS; team++) {
        gametype.setTeamSpawnsystem(team, SPAWNSYSTEM_INSTANT, 0, 0, false);
    }
}

void CA_SetUpCountdown() {
    gametype.shootingDisabled = true;
    gametype.readyAnnouncementEnabled = false;
    gametype.scoreAnnouncementEnabled = false;
    gametype.countdownEnabled = false;
    G_RemoveAllProjectiles();

    // lock teams
    bool anyone = false;
    if (gametype.isTeamBased) {
        for (int team = TEAM_ALPHA; team < GS_MAX_TEAMS; team++) {
            if (G_GetTeam(team).lock()) {
                anyone = true;
            }
        }
    } else {
        if (G_GetTeam(TEAM_PLAYERS).lock()) {
            anyone = true;
        }
    }

    if (anyone) {
        G_PrintMsg(null, "Teams locked.\n");
    }

    // Countdowns should be made entirely client side, because we now can

    int soundIndex = G_SoundIndex("sounds/announcer/countdown/get_ready_to_fight0" + (1 + (rand() & 1)));
    G_AnnouncerSound(null, soundIndex, GS_MAX_TEAMS, false, null);
}

String formatFloat(float floatVal, int decimals) {
    String value = String(floatVal);
    uint i;
    for (i = 0; i<value.len(); i++) {
        if (value[i] == "46") { // period
            break;
        }
    }
    return value.substr(0, i+decimals+1);
}
