# JCA

The JCA gametype for Warfork is the standard Clan Arena experience with few notable differences:

- Armor is removed, total health is 250
- Scoreboard shows total damage dealt, kills, deaths, assists, damage given/taken ratio and skill rating
- An assist is any damage dealt to an enemy who dies later in the same round, if you didn't get the kill
- Killer's HP is no longer shown upon your death
- Players are rated per round and their rating is shown in the scoreboard (Skill column)

## Player Ratings

Every round updates each player's rating with the Weng-Lin (OpenSkill) Bradley-Terry model. Each player has a skill estimate `mu` and an uncertainty `sigma`, and team strength is the sum of the players' `mu`, so uneven rounds (e.g. 3v2) are handled.

- A player counts for a round if they're alive on a team when it starts. Leaving mid-round still counts as playing the round.
- If the winners' predicted win chance was 90% or more, nobody's rating changes, so stomping much weaker players earns nothing. Upsets still count.
- Each round moves ratings at half strength, and 1v1 rounds at a quarter, because single rounds are noisy.
- Draws count as half a win. Rounds ended by a team shuffle/rebalance are ignored.
- Rounds with any bot in them aren't rated. Players without a Steam ID aren't rated and count as average players when working out team strength.
- The scoreboard shows the conservative estimate `mu - 3*sigma`, shifted so new players show 0 and scaled by 4. An established average player sits around 80 and only very weak players go negative.
- `callvote rebalance` splits the players into the two teams with the closest total `mu` (team sizes differ by at most one), moving as few players as possible, and prints the predicted win chance. `callvote shuffle` is unchanged.
- Players see their new rating and the change in the console after each round.
- Ratings are saved after every rated round to `ratings/jca.txt` in the server's write directory (e.g. `~/.local/share/warfork-2.1/basewf/`), one line per player: `<steam_id> <mu> <sigma> <rounds> <name>`.

Tuning constants are at the top of `gametypes/jca/ratings.as`.