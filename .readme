# JCA

The JCA gametype for Warfork is the standard Clan Arena experience with few notable differences:

- Armor is removed, total health is 250
- Scoreboard shows total damage dealt, kills, deaths, assists and damage given/taken ratio
- Killer's HP is no longer shown upon your death

## Round Stats

JCA stores some statistics about each round and sends the data to a local endpoint running on port 3675 using Curl. The data has the following JSON structure:

```
[
    {
        "round_winner": 0,
        "teamStats": [
            {
                "damageDealt": 1234,
                "damageReceived": 890,
                "kills": 4,
                "deaths": 2,
                "players": [
                    {
                        "id": 0,
                        "steamId": 3434,
                        "name": "Jazcash",
                        "damageDealt": {
                            "4": {
                                "rg": 45,
                                "eb": 50
                            }
                        },
                        "damageReceived": {
                            "5": {
                                "rl": 30
                            }
                        },
                        "killed": [
                            4,
                            5
                        ],
                        "killer": -1
                    }
                ]
            }
        ]
    }
]
```