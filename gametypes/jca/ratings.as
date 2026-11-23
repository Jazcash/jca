// Player skill ratings using the Weng-Lin Bayesian approximation (Bradley-Terry
// full-pairing model, as used by OpenSkill). Every player has a skill estimate
// (mu) and an uncertainty (sigma). Ratings are updated once per round from the
// round result, so players can join and leave at any time.
//
// Ratings persist in a flat text file, one player per line:
//   <steam_id> <mu> <sigma> <rounds> <last known name>

const String RATINGS_FILE = "ratings/jca.txt";

const double RATING_MU = 25.0;
const double RATING_SIGMA = RATING_MU / 3.0;
const double RATING_BETA = RATING_MU / 6.0;    // skill gap that gives a ~76% win chance
const double RATING_TAU = RATING_MU / 300.0;   // added uncertainty per round, stops ratings freezing
const double RATING_KAPPA = 0.0001;            // lower bound on sigma shrink factor

// Displayed rating is the conservative estimate (mu - 3 sigma: the player is
// very likely at least this good), shifted so a brand new player shows 0:
//
//   ((mu - 3 sigma) - (baseline - 3 RATING_SIGMA)) * RATING_DISPLAY_SCALE
//
// baseline is the average mu of all rated players. New players start at 0 and
// climb as the system becomes confident in them; an established average player
// sits around 80. Only very weak players go negative.
//
// Team strength is the sum of player mu, so in uneven rounds (3v2) the average
// mu effectively becomes "how much an extra player is worth" and the whole
// population drifts until that matches reality. Displaying relative to the
// average, and starting new players at the average, cancels that drift out.
const double RATING_DISPLAY_SCALE = 4.0;

const double RATING_CONSERVATIVE_SIGMAS = 3.0;

// No update when the winners' predicted win chance was at least this high, so
// repeatedly stomping a much weaker player earns nothing. Upsets still count.
const double RATING_STOMP_THRESHOLD = 0.9;

// Scales every update (mu change and sigma shrink). Rounds are short and noisy,
// so each one should move ratings less than a whole match would.
const double RATING_UPDATE_WEIGHT = 0.5;

// Extra scale for 1v1 rounds (on top of RATING_UPDATE_WEIGHT).
const double RATING_1V1_WEIGHT = 0.5;

const double RATING_E = 2.718281828459045; // the script API has pow() but no exp()

class PlayerRating {
    String steamId;
    String name;
    double mu;
    double sigma;
    int rounds;

    PlayerRating() {
        this.mu = RATING_MU;
        this.sigma = RATING_SIGMA;
        this.rounds = 0;
    }
}

// One participant of the round being played, captured when the round starts.
class RoundParticipant {
    int team;
    PlayerRating@ rating; // null for players without a steam id (unrated)
    Client@ client;       // only used for the end-of-round console message
}

class RatingSystem {
    array<PlayerRating@> players;
    Dictionary index; // steamId -> position in players
    array<RoundParticipant@> participants;
    double baseline; // average mu, recalculated on load so values stay stable during a map

    // Outcome of the last roundFinished(), for the stats log.
    double lastWinChance; // alpha's predicted win chance, -1 if not computed
    bool lastRated;       // ratings actually changed

    RatingSystem() {
        this.baseline = RATING_MU;
        this.lastWinChance = -1;
        this.lastRated = false;
    }

    int displayValue(PlayerRating@ r) {
        double conservative = r.mu - RATING_CONSERVATIVE_SIGMAS * r.sigma;
        double newPlayer = this.baseline - RATING_CONSERVATIVE_SIGMAS * RATING_SIGMA;
        return rint((conservative - newPlayer) * RATING_DISPLAY_SCALE);
    }

    // Best skill estimate for a client; unrated clients count as average.
    double muOf(Client@ client) {
        PlayerRating@ r = this.find(this.steamIdOf(client));
        return (@r == null) ? this.baseline : r.mu;
    }

    double sigmaSqOf(Client@ client) {
        PlayerRating@ r = this.find(this.steamIdOf(client));
        double sigma = (@r == null) ? RATING_SIGMA : r.sigma;
        return sigma * sigma;
    }

    // Chance that a team with the given totals beats the other one.
    double winChance(double muA, double sigmaSqA, double muB, double sigmaSqB) {
        double c = sqrt(sigmaSqA + sigmaSqB + 2.0 * RATING_BETA * RATING_BETA);
        return 1.0 / (1.0 + pow(RATING_E, (muB - muA) / c));
    }

    // Splits everyone on alpha/beta into two teams (sizes differ by at most one)
    // with the closest total skill, moving as few players as possible.
    void balanceTeams() {
        array<Client@> clients;
        array<double> mus;
        for (int t = TEAM_ALPHA; t <= TEAM_BETA; t++) {
            Team@ team = @G_GetTeam(t);
            for (int j = 0; @team.ent(j) != null; j++) {
                Client@ client = @team.ent(j).client;
                if (@client != null) {
                    clients.insertLast(client);
                    mus.insertLast(this.muOf(client));
                }
            }
        }

        uint n = clients.length();
        if (n < 2) {
            return;
        }

        // bit i of an assignment set = client i goes to alpha
        uint bestMask = 0;
        if (n <= 14) {
            double bestDiff = -1;
            int bestMoves = 0;
            uint small = n / 2;
            for (uint mask = 0; mask < (uint(1) << n); mask++) {
                uint count = 0;
                double diff = 0;
                int moves = 0;
                for (uint i = 0; i < n; i++) {
                    bool alpha = (mask & (uint(1) << i)) != 0;
                    if (alpha) {
                        count++;
                        diff += mus[i];
                    } else {
                        diff -= mus[i];
                    }
                    if (alpha != (clients[i].team == TEAM_ALPHA)) {
                        moves++;
                    }
                }

                if (count != small && count != n - small) {
                    continue;
                }

                diff = abs(diff);
                if (bestDiff < 0 || diff < bestDiff - 0.0001 || (diff < bestDiff + 0.0001 && moves < bestMoves)) {
                    bestDiff = diff;
                    bestMoves = moves;
                    bestMask = mask;
                }
            }
        } else {
            // too many players to try every split: hand out strongest first
            // to whichever team is currently weaker (and not full)
            array<bool> used(n);
            double sumAlpha = 0, sumBeta = 0;
            uint countAlpha = 0, countBeta = 0;
            uint cap = n - n / 2;
            for (uint k = 0; k < n; k++) {
                int best = -1;
                for (uint i = 0; i < n; i++) {
                    if (!used[i] && (best < 0 || mus[i] > mus[uint(best)])) {
                        best = i;
                    }
                }
                used[uint(best)] = true;
                if (countBeta >= cap || (countAlpha < cap && sumAlpha <= sumBeta)) {
                    bestMask |= uint(1) << uint(best);
                    sumAlpha += mus[uint(best)];
                    countAlpha++;
                } else {
                    sumBeta += mus[uint(best)];
                    countBeta++;
                }
            }
        }

        double muAlpha = 0, muBeta = 0, sigmaSqAlpha = 0, sigmaSqBeta = 0;
        for (uint i = 0; i < n; i++) {
            int newTeam = ((bestMask & (uint(1) << i)) != 0) ? TEAM_ALPHA : TEAM_BETA;
            if (newTeam == TEAM_ALPHA) {
                muAlpha += mus[i];
                sigmaSqAlpha += this.sigmaSqOf(clients[i]);
            } else {
                muBeta += mus[i];
                sigmaSqBeta += this.sigmaSqOf(clients[i]);
            }

            if (clients[i].team != newTeam) {
                clients[i].team = newTeam;
                // during a match the round is restarted, so wait as a ghost
                clients[i].respawn(match.getState() == MATCH_STATE_PLAYTIME);
            }
        }

        int chance = rint(this.winChance(muAlpha, sigmaSqAlpha, muBeta, sigmaSqBeta) * 100.0);
        G_PrintMsg(null, "Teams balanced by rating. Win chance: " + G_GetTeam(TEAM_ALPHA).name + S_COLOR_WHITE + " "
            + chance + "% - " + (100 - chance) + "% " + G_GetTeam(TEAM_BETA).name + "\n");
    }

    void updateBaseline() {
        double total = 0;
        int count = 0;
        for (uint i = 0; i < this.players.length(); i++) {
            if (this.players[i].rounds > 0) {
                total += this.players[i].mu;
                count++;
            }
        }

        this.baseline = (count > 0) ? total / count : RATING_MU;
    }

    // Returns the client's steam id, or "" if the client can't be rated.
    String steamIdOf(Client@ client) {
        if (@client == null || client.isBot()) {
            return "";
        }

        String steamId = client.getUserInfoKey("steam_id");
        if (steamId.empty() || steamId == "0") {
            return "";
        }

        return steamId;
    }

    PlayerRating@ find(const String &in steamId) {
        int64 i;
        if (steamId.empty() || !this.index.get(steamId, i)) {
            return null;
        }

        return this.players[uint(i)];
    }

    PlayerRating@ findOrCreate(Client@ client) {
        String steamId = this.steamIdOf(client);
        if (steamId.empty()) {
            return null;
        }

        PlayerRating@ rating = this.find(steamId);
        if (@rating == null) {
            @rating = PlayerRating();
            rating.steamId = steamId;
            rating.mu = this.baseline;
            this.index.set(steamId, int64(this.players.length()));
            this.players.insertLast(rating);
        }

        rating.name = client.name.removeColorTokens();

        return rating;
    }

    void load() {
        this.players.resize(0);
        this.index.deleteAll();
        this.baseline = RATING_MU;

        if (!G_FileExists(RATINGS_FILE)) {
            return;
        }

        String content = G_LoadFile(RATINGS_FILE);
        array<String@>@ lines = StringUtils::Split(content, "\n");

        for (uint i = 0; i < lines.length(); i++) {
            String line = lines[i].trim();
            if (line.empty()) {
                continue;
            }

            String steamId = line.getToken(0);
            if (steamId.empty() || this.index.exists(steamId)) {
                continue;
            }

            PlayerRating@ rating = PlayerRating();
            rating.steamId = steamId;
            rating.mu = line.getToken(1).toFloat();
            rating.sigma = line.getToken(2).toFloat();
            rating.rounds = line.getToken(3).toInt();
            rating.name = "";
            for (uint t = 4;; t++) {
                String token = line.getToken(t);
                if (token.empty()) {
                    break;
                }
                rating.name += (t > 4 ? " " : "") + token;
            }

            if (rating.sigma <= 0) {
                continue; // corrupt line
            }

            this.index.set(steamId, int64(this.players.length()));
            this.players.insertLast(rating);
        }

        this.updateBaseline();

        G_Print("Loaded " + this.players.length() + " player ratings from " + RATINGS_FILE + "\n");
    }

    void save() {
        String content = "";
        for (uint i = 0; i < this.players.length(); i++) {
            PlayerRating@ r = this.players[i];
            content += r.steamId + " " + float(r.mu) + " " + float(r.sigma) + " " + r.rounds + " " + r.name + "\n";
        }

        if (!G_WriteFile(RATINGS_FILE, content)) {
            G_Print("^1Failed to write " + RATINGS_FILE + "\n");
        }
    }

    // Called when a round goes live: remember who is playing for which team.
    void roundStarted() {
        this.participants.resize(0);

        for (int t = TEAM_ALPHA; t <= TEAM_BETA; t++) {
            Team@ team = @G_GetTeam(t);
            for (int j = 0; @team.ent(j) != null; j++) {
                Entity@ ent = @team.ent(j);
                if (ent.isGhosting() || @ent.client == null) {
                    continue;
                }

                if (ent.client.isBot()) {
                    // rounds with bots aren't rated at all
                    this.participants.resize(0);
                    return;
                }

                RoundParticipant@ p = RoundParticipant();
                p.team = t;
                @p.client = @ent.client;
                @p.rating = this.findOrCreate(ent.client);
                this.participants.insertLast(p);
            }
        }
    }

    // Discard the current round, e.g. when teams are shuffled mid-round.
    void roundCancelled() {
        this.participants.resize(0);
    }

    // winningTeam is TEAM_ALPHA, TEAM_BETA, or -1 for a draw.
    void roundFinished(int winningTeam) {
        this.lastWinChance = -1;
        this.lastRated = false;

        if (this.participants.length() == 0) {
            return;
        }

        // team totals; unrated participants (no steam id) count as average players.
        // Rated players get tau added to sigma first so it never collapses to zero.
        array<double> teamMu(GS_MAX_TEAMS);
        array<double> teamSigmaSq(GS_MAX_TEAMS);
        array<int> ratedCount(GS_MAX_TEAMS);
        array<int> playerCount(GS_MAX_TEAMS);
        for (int t = 0; t < GS_MAX_TEAMS; t++) {
            teamMu[t] = 0;
            teamSigmaSq[t] = 0;
            ratedCount[t] = 0;
            playerCount[t] = 0;
        }

        for (uint i = 0; i < this.participants.length(); i++) {
            RoundParticipant@ p = this.participants[i];
            playerCount[p.team]++;
            if (@p.rating != null) {
                teamMu[p.team] += p.rating.mu;
                teamSigmaSq[p.team] += p.rating.sigma * p.rating.sigma + RATING_TAU * RATING_TAU;
                ratedCount[p.team]++;
            } else {
                teamMu[p.team] += this.baseline;
                teamSigmaSq[p.team] += RATING_SIGMA * RATING_SIGMA;
            }
        }

        // need someone to rate and an opponent on both sides
        if (teamSigmaSq[TEAM_ALPHA] == 0 || teamSigmaSq[TEAM_BETA] == 0
            || ratedCount[TEAM_ALPHA] + ratedCount[TEAM_BETA] == 0) {
            this.participants.resize(0);
            return;
        }

        // Bradley-Terry update for each of the two teams against the other
        array<double> omega(GS_MAX_TEAMS);
        array<double> delta(GS_MAX_TEAMS);

        double c = sqrt(teamSigmaSq[TEAM_ALPHA] + teamSigmaSq[TEAM_BETA] + 2.0 * RATING_BETA * RATING_BETA);
        double pAlpha = this.winChance(teamMu[TEAM_ALPHA], teamSigmaSq[TEAM_ALPHA], teamMu[TEAM_BETA], teamSigmaSq[TEAM_BETA]);
        this.lastWinChance = pAlpha;

        // the expected team won comfortably: nothing learned, nobody moves
        if ((winningTeam == TEAM_ALPHA && pAlpha >= RATING_STOMP_THRESHOLD)
            || (winningTeam == TEAM_BETA && 1.0 - pAlpha >= RATING_STOMP_THRESHOLD)) {
            for (uint i = 0; i < this.participants.length(); i++) {
                RoundParticipant@ p = this.participants[i];
                if (@p.rating != null && @p.client != null && this.steamIdOf(p.client) == p.rating.steamId) {
                    G_PrintMsg(p.client.getEnt(), "Rating: " + this.displayValue(p.rating) + " (no change, "
                        + (p.team == winningTeam ? "expected win" : "expected loss") + ")\n");
                }
            }
            this.participants.resize(0);
            return;
        }

        this.lastRated = true;
        double weight = RATING_UPDATE_WEIGHT;
        if (playerCount[TEAM_ALPHA] == 1 && playerCount[TEAM_BETA] == 1) {
            weight *= RATING_1V1_WEIGHT;
        }

        for (int t = TEAM_ALPHA; t <= TEAM_BETA; t++) {
            double p = (t == TEAM_ALPHA) ? pAlpha : 1.0 - pAlpha;
            double score = 0.5;
            if (winningTeam == t) {
                score = 1.0;
            } else if (winningTeam != -1) {
                score = 0.0;
            }

            double gamma = sqrt(teamSigmaSq[t]) / c;
            omega[t] = teamSigmaSq[t] / c * (score - p);
            delta[t] = gamma * teamSigmaSq[t] / (c * c) * p * (1.0 - p);
        }

        for (uint i = 0; i < this.participants.length(); i++) {
            RoundParticipant@ p = this.participants[i];
            PlayerRating@ r = p.rating;
            if (@r == null) {
                continue;
            }

            int before = this.displayValue(r);
            double sigmaSq = r.sigma * r.sigma + RATING_TAU * RATING_TAU;
            double share = sigmaSq / teamSigmaSq[p.team];

            r.mu += weight * share * omega[p.team];
            double shrink = 1.0 - weight * share * delta[p.team];
            if (shrink < RATING_KAPPA) {
                shrink = RATING_KAPPA;
            }
            r.sigma = sqrt(sigmaSq * shrink);
            r.rounds++;

            int change = this.displayValue(r) - before;
            if (@p.client != null && this.steamIdOf(p.client) == r.steamId) {
                G_PrintMsg(p.client.getEnt(), "Rating: " + this.displayValue(r) + " (" + (change >= 0 ? "+" : "") + change + ")\n");
            }
        }

        this.participants.resize(0);
        this.save();
    }

    // Printed to everyone at the start of each round: the model's predicted win
    // chance for the stronger team (same maths as the rating update).
    void printTeamSkills() {
        array<double> mu(GS_MAX_TEAMS);
        array<double> sigmaSq(GS_MAX_TEAMS);
        for (int t = TEAM_ALPHA; t <= TEAM_BETA; t++) {
            mu[t] = 0;
            sigmaSq[t] = 0;
            Team@ team = @G_GetTeam(t);
            for (int j = 0; @team.ent(j) != null; j++) {
                Client@ client = @team.ent(j).client;
                if (@client != null) {
                    mu[t] += this.muOf(client);
                    sigmaSq[t] += this.sigmaSqOf(client);
                }
            }
        }
        if (sigmaSq[TEAM_ALPHA] == 0 || sigmaSq[TEAM_BETA] == 0) {
            return;
        }

        double pAlpha = this.winChance(mu[TEAM_ALPHA], sigmaSq[TEAM_ALPHA], mu[TEAM_BETA], sigmaSq[TEAM_BETA]);
        int favoured = (pAlpha >= 0.5) ? TEAM_ALPHA : TEAM_BETA;
        int percent = rint(100.0 * ((favoured == TEAM_ALPHA) ? pAlpha : 1.0 - pAlpha));
        if (percent <= 50) {
            G_PrintMsg(null, "Teams are evenly matched\n");
        } else {
            G_PrintMsg(null, G_GetTeam(favoured).name + S_COLOR_WHITE + " is " + S_COLOR_YELLOW + percent + "%"
                + S_COLOR_WHITE + " favoured\n");
        }
    }

    // Scoreboard text for a player's rating.
    String scoreboardValue(Client@ client) {
        String steamId = this.steamIdOf(client);
        if (steamId.empty()) {
            return "-";
        }

        PlayerRating@ r = this.find(steamId);
        if (@r == null) {
            return S_COLOR_WHITE + "0";
        }

        return S_COLOR_WHITE + this.displayValue(r);
    }
}

RatingSystem ratings;
