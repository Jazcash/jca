// Welcome message shown to each player when they enter the game (the "enterGame" score
// event, after the client has loaded in). Called from GT_ScoreEvent. The script reloads on
// every map change, so players see it again on each new map.

Cvar g_inactivity_maxtime = Cvar("g_inactivity_maxtime", "", 0); // engine cvar, set in jca.cfg

void showWelcome(Client@ client) {
    if (@client == null || client.isBot()) {
        return;
    }

    String msg = S_COLOR_YELLOW + "Welcome to JCA" + S_COLOR_WHITE + " (Jaz's Clan Arena)\n"
        + "Clan Arena with a few differences:\n"
        + " - No armor: you spawn with " + S_COLOR_YELLOW + "300 HP" + S_COLOR_WHITE + "\n"
        + " - " + S_COLOR_YELLOW + "DG/DR" + S_COLOR_WHITE + " is damage given / damage received ("
            + S_COLOR_GREEN + "green" + S_COLOR_WHITE + " at 1 or above, " + S_COLOR_RED + "red" + S_COLOR_WHITE + " below)\n"
        + " - Damaging an enemy who later dies earns an " + S_COLOR_YELLOW + "assist" + S_COLOR_WHITE + "\n"
        + " - Every round is rated: see the " + S_COLOR_YELLOW + "Skill" + S_COLOR_WHITE + " column, and try "
            + S_COLOR_YELLOW + "callvote rebalance" + S_COLOR_WHITE + " for fair teams\n"
        + " - Players pass through each other during the countdown\n"
        + " - Your killer's HP isn't shown when you die\n";

    if (g_jca_maxping.integer > 0) {
        msg += " - You must have <" + g_jca_maxping.integer + " ping to play\n";
    }
    if (g_inactivity_maxtime.integer > 0) {
        msg += " - AFK removal is " + g_inactivity_maxtime.integer + "s\n";
    }

    msg += "Leaderboard, stats and profiles: " + S_COLOR_CYAN + "jazcash.com/jca" + S_COLOR_WHITE + "\n";

    client.printMessage(msg);
    G_CenterPrintMsg(client.getEnt(), S_COLOR_YELLOW + "Welcome to JCA" + S_COLOR_WHITE + " - check chat for how it differs from CA");
}
