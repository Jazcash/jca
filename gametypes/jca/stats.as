class GameStats {
    uint durationMs;
    uint startTimeUnix;
    RoundStats[] rounds();

    GameStats() {

    }
}

class RoundStats {
    int winningTeamId; // -1 is a draw
    TeamStats[] teams();

    RoundStats() {

    }
}

class TeamStats {
    uint damageGiven;
    uint damageReceived;
    uint kills;
    uint deaths;
    PlayerStats[] players();

    TeamStats() {

    }
}

class PlayerStats {
    WeaponStats accuracy;
    Dictionary damageDealt;
    Dictionary damageReceived;

    PlayerStats() {

    }
}

class WeaponStats {
    uint gb = 0;
    uint mg = 0;
    uint rg = 0;
    uint gl = 0;
    uint rl = 0;
    uint pg = 0;
    uint lg = 0;
    uint eb = 0;

    WeaponStats() {

    }
}