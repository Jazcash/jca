uint caTimelimit1v1;

Cvar g_ca_timelimit1v1 = Cvar("g_ca_timelimit1v1", "60", 0);

Cvar g_noclass_inventory = Cvar( "g_noclass_inventory", "gb mg rg gl rl pg lg eb cells shells grens rockets plasma lasers bullets", 0 );
Cvar g_class_strong_ammo = Cvar( "g_class_strong_ammo", "1 75 20 20 40 125 180 15", 0 ); // GB MG RG GL RL PG LG EB

const int CA_ROUNDSTATE_NONE = 0;
const int CA_ROUNDSTATE_PREROUND = 1;
const int CA_ROUNDSTATE_ROUND = 2;
const int CA_ROUNDSTATE_ROUNDFINISHED = 3;
const int CA_ROUNDSTATE_POSTROUND = 4;

cCARound caRound;