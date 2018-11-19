#include <sourcemod>
#include <events>
#include <cstrike>
#include <sdktools>

#pragma semicolon 1
#pragma newdecls required

public Plugin myinfo = {
	name		= "Team GunGame",
	author		= "github.com/BeepFelix",
	description	= "Basically Arms-Race but your entire team has the same weapon",
	version		= "1.0"
};

// Weapon tracking constants (Never change throughout the match)
CSWeaponID weaponLevels[512]; // To track which weapon we are on and which is next. Maximum 512 weapons. Who would need more anyways
char rawWeaponLevels[512][512]; // To track which weapon we are on as raw weapon name.
int weaponKills[512]; // To track how many kills are required with that weapon.
int internalIdentifiers[512]; // For randomization
int weaponAmount = 0; // To track the amount of weapons in our array above.

// Weapon tracking (Change throughout the match)
int ctLevel = 0;
int tLevel = 0;
int ctKills = 0;
int tKills = 0;

// Default convars
ConVar defaultWinner = null;
ConVar maxRounds = null;

// Custom convars
ConVar randomizeWeaponList = null;
ConVar maxWeapons = null;

public void OnPluginStart() {
	defaultWinner = FindConVar("mp_default_team_winner_no_objective");
	maxRounds = FindConVar("mp_maxrounds");

	randomizeWeaponList = CreateConVar("sm_tgg_randomize_weapon_list", "0", "Should we randomize the weapon list after loading it?", _, true, 0.0, true, 1.0);
	maxWeapons = CreateConVar("sm_tgg_max_weapons", "0", "Maxmimum amount of weapons in the list. If we have too many the last few weapons will be removed. 0 for infinite", _, true, 0.0);

	HookEvent("player_death", Event_PlayerDeath);
	HookEvent("player_spawn", Event_PlayerSpawn);
	HookEvent("round_start", Event_RoundStart);

	// Strip notify flag from max rounds
	int flags = maxRounds.Flags;
	flags &= ~FCVAR_NOTIFY;
	maxRounds.Flags = flags;

	AutoExecConfig(true, "teamgungame");
}

public Action CS_OnTerminateRound(float& delay, CSRoundEndReason& reason) {
	// If this is a draw then it is due to time running out. There should NEVER be a draw otherwise.
	// End match on a time out
	if (reason != CSRoundEnd_Draw) return Plugin_Continue;

	defaultWinner.SetInt(0);
	maxRounds.SetInt(0);

	return Plugin_Continue;
}

public void OnMapStart() {
	// Remove map objective
	// Source: https://forums.alliedmods.net/showthread.php?p=1771777
	int iEnt = -1;
	while( // While at least one of those below is not -1 then kill the entity
		(iEnt = FindEntityByClassname(iEnt, "func_bomb_target")) != -1 // Find bombsites
		&& (iEnt = FindEntityByClassname(iEnt, "func_hostage_rescue")) != -1 // Find rescue points
		&& (iEnt = FindEntityByClassname(iEnt, "hostage_entity")) != -1 // Find the hostages themselves and destroy them
	) {
		AcceptEntityInput(iEnt, "kill");
	}

	// Precache sound
	PrecacheSound("music/kill_01.wav");

	// Start display loop for all players
	CreateTimer(1.0, WeaponProgressDisplay, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);

	// Reset variables
	ctLevel = 0;
	tLevel = 0;
	ctKills = 0;
	tKills = 0;
	weaponAmount = 0;

	// Read configuration file if exists
	char path[PLATFORM_MAX_PATH];
	char line[1024];

	BuildPath(Path_SM, path, PLATFORM_MAX_PATH, "team_gungame_configuration.txt");

	if (!FileExists(path)) {
		LogMessage("Failed to find team_gungame_configuration.txt");

		weaponLevels[0] = CSWeapon_M4A1_SILENCER;
		weaponKills[0] = 5;
		rawWeaponLevels[0] = "m4a1_silencer";
		weaponAmount = 1;
	} else {
		// Open file and parse it
		File fileHandle = OpenFile(path, "r");
		while (!IsEndOfFile(fileHandle) && ReadFileLine(fileHandle, line, sizeof(line))) {
			TrimString(line);
			if (strlen(line) <= 0) continue;

			// Split line into arguments
			char arguments[64][64];
			int amount = ExplodeString(line, " ", arguments, sizeof(arguments), sizeof(arguments[]));
			if (amount < 3) continue; // We should always have at least 3 arguments. 0 = WeaponID, 1 = Amount, 2 = Chance

			TrimString(arguments[0]);
			TrimString(arguments[1]);
			TrimString(arguments[2]);

			// Remove comments
			if (StrContains(arguments[0], "//", true) != -1 || StrContains(arguments[1], "//", true) != -1 || StrContains(arguments[2], "//", true) != -1) continue;

			// Parse weaponID
			CSWeaponID weaponID = CS_AliasToWeaponID(arguments[0]);
			if (!CS_IsValidWeaponID(weaponID)) continue;

			// Parse kills (Can be "1-5" or "3")
			int killsRequired = -1;
			if (StrContains(arguments[1], "-", true) != -1) { // 5-10
				char values[64][64];
				amount = ExplodeString(arguments[1], "-", values, sizeof(values), sizeof(values[]));
				if (amount < 2) continue; // We should always have at least 2 arguments. 0 = Min kills, 1 = Max kills
				killsRequired = GetRandomInt(StringToInt(values[0]), StringToInt(values[1]));
			} else if (StrContains(arguments[1], ",", true) != -1) { // 5,10,15
				char killsRequired_ary_og[64][64];
				int killsRequired_ary[64];
				amount = ExplodeString(arguments[1], ",", killsRequired_ary_og, sizeof(killsRequired_ary_og), sizeof(killsRequired_ary_og[]));
				for (int i = 0; i < amount; i++) {
					TrimString(killsRequired_ary_og[i]);
					killsRequired_ary[i] = StringToInt(killsRequired_ary_og[i]);
				}
				killsRequired = killsRequired_ary[GetRandomInt(0, (amount - 1))];
			} else { // 5
				killsRequired = StringToInt(arguments[1]);
			}
			if (killsRequired <= 0) continue;

			// Parse chance
			int chance = StringToInt(arguments[2]);
			if (chance <= 0) continue;
			if (GetRandomInt(0, 100) > chance) continue;

			// Save values
			weaponLevels[weaponAmount] = weaponID;
			weaponKills[weaponAmount] = killsRequired;
			rawWeaponLevels[weaponAmount] = arguments[0];
			internalIdentifiers[weaponAmount] = weaponAmount;
			weaponAmount++;

			// Log
			LogMessage("Added %s as ID %d with %d kills required", arguments[0], weaponID, killsRequired);
		}
		fileHandle.Close();
	}

	if (weaponAmount <= 0) {
		LogMessage("Failed to load team_gungame_configuration.txt");

		weaponLevels[0] = CSWeapon_M4A1_SILENCER;
		weaponKills[0] = 5;
		rawWeaponLevels[0] = "m4a1_silencer";
		weaponAmount = 1;
	}

	// Should we randomize the array?
	if (randomizeWeaponList.BoolValue) {
		// Randomize identifier array and later sort the other arrays to match the identifier
		// Source: https://stackoverflow.com/a/2450976
		int currentIndex = weaponAmount - 1;
		int temporaryValue = -1;
		int randomIndex = -1;

		while (0 != currentIndex) {
			randomIndex = GetRandomInt(0, currentIndex);
			currentIndex--;

			temporaryValue = internalIdentifiers[currentIndex];
			internalIdentifiers[currentIndex] = internalIdentifiers[randomIndex];
			internalIdentifiers[randomIndex] = temporaryValue;
		}

		// Sort all the other arrays to match with the "internalIdentifiers" array
		CSWeaponID weaponLevels_copy[512];
		char rawWeaponLevels_copy[512][512];
		int weaponKills_copy[512];

		for (int i = 0; i < weaponAmount; i++) {
			weaponLevels_copy[i] = weaponLevels[internalIdentifiers[i]];
			rawWeaponLevels_copy[i] = rawWeaponLevels[internalIdentifiers[i]];
			weaponKills_copy[i] = weaponKills[internalIdentifiers[i]];
		}

		weaponLevels = weaponLevels_copy;
		for (int i = 0; i < weaponAmount; i++) rawWeaponLevels[i] = rawWeaponLevels_copy[i]; // Mfw cant do "rawWeaponLevels = rawWeaponLevels_copy;"
		weaponKills = weaponKills_copy;
	}

	// Limit amount of weapons if required
	if (maxWeapons.IntValue >= 1 && weaponAmount > maxWeapons.IntValue) {
		weaponAmount = maxWeapons.IntValue;
	}
}

public Action WeaponProgressDisplay(Handle timer) {
	char CTTeamString[512];
	char TTeamString[512];
	char SpecTeamString[512];
	char CTColor[7] = "#909CA7"; // Blueish color
	char TColor[7] = "#C9B983"; // Yellowish color

	// Each team gets their own string, so it is properly sorted. Your own team is at the top the enemy team is at the bottom
	Format(CTTeamString, sizeof(CTTeamString), "Kills: %d/%d\n<font color=\"%s\">Level: %d/%d</font>\n<font color=\"%s\">Level: %d/%d</font>", ctKills, weaponKills[ctLevel], CTColor, (ctLevel + 1), weaponAmount, TColor, (tLevel + 1), weaponAmount);
	Format(TTeamString, sizeof(TTeamString), "Kills: %d/%d\n<font color=\"%s\">Level: %d/%d</font>\n<font color=\"%s\">Level: %d/%d</font>", tKills, weaponKills[tLevel], TColor, (tLevel + 1), weaponAmount, CTColor, (ctLevel + 1), weaponAmount);
	Format(SpecTeamString, sizeof(SpecTeamString), "<font color=\"%s\">Level: %d/%d Kills: %d/%d</font>\n<font color=\"%s\">Level: %d/%d Kills: %d/%d</font>", CTColor, (ctLevel + 1), weaponAmount, ctKills, weaponKills[ctLevel], TColor, (tLevel + 1), weaponAmount, tKills, weaponKills[tLevel]);

	for (int i = 1; i <= MaxClients; i++) {
		if (!IsClientInGame(i)) continue;

		int clientTeam = GetClientTeam(i);

		if (clientTeam == CS_TEAM_CT) {
			PrintHintText(i, CTTeamString);
		} else if (clientTeam == CS_TEAM_T) {
			PrintHintText(i, TTeamString);
		} else {
			PrintHintText(i, SpecTeamString);
		}
	}
}

public Action Event_RoundStart(Event event, const char[] name, bool dontBroadcast) {
	// Remove hostages because they respawn on each round start
	// Source: https://forums.alliedmods.net/showthread.php?p=1771777
	int iEnt = -1;
	while((iEnt = FindEntityByClassname(iEnt, "hostage_entity")) != -1) { // Find the hostages themselves and destroy them
		AcceptEntityInput(iEnt, "kill");
	}

	// Reset variables
	ctLevel = 0;
	tLevel = 0;
	ctKills = 0;
	tKills = 0;
}

public Action Event_PlayerSpawn(Event event, const char[] name, bool dontBroadcast) {
	RequestFrame(spawnGiveWeapons, event.GetInt("userid")); // Give weapon 1 frame later, else giving weapon fails
}

void spawnGiveWeapons(int userid) {
	int client = GetClientOfUserId(userid); // Get client and validate
	if (client <= 0 || client > MaxClients || !IsClientConnected(client)) return;
	if (!IsClientInGame(client)) return;

	int clientTeam = GetClientTeam(client);
	if (clientTeam != CS_TEAM_T && clientTeam != CS_TEAM_CT) return; // Only care about CT and T

	// Strip all weapons
	// Source: https://forums.alliedmods.net/showthread.php?t=133756
	int weapon = -1;
	int slot = -1;
	for (slot = CS_SLOT_PRIMARY ; slot <= CS_SLOT_GRENADE ; slot++) {
		weapon = GetPlayerWeaponSlot(client, slot);
		while (weapon != -1 && (GetEntPropEnt(weapon, Prop_Data, "m_hOwnerEntity") == client)) {
			RemovePlayerItem(client, weapon);
			weapon = GetPlayerWeaponSlot(client, slot);
		}
	}
	GivePlayerItem(client, "weapon_knife");

	// Give level specific weapon
	char giveWeapon[512];
	Format(giveWeapon, sizeof(giveWeapon), "weapon_%s", rawWeaponLevels[clientTeam == CS_TEAM_CT ? ctLevel : tLevel]);
	GivePlayerItem(client, giveWeapon);
}

public Action Event_PlayerDeath(Event event, const char[] name, bool dontBroadcast) {
	if (GameRules_GetProp("m_bWarmupPeriod") != 0) return; // Do not count kills during warmup

	int client = GetClientOfUserId(event.GetInt("attacker"));

	char weaponName[512]; // Get weapon name
	event.GetString("weapon", weaponName, sizeof(weaponName));

	int clientTeam = GetClientTeam(client);
	CSWeaponID weaponID = CS_AliasToWeaponID(weaponName);

	if (clientTeam != CS_TEAM_T && clientTeam != CS_TEAM_CT) return; // How the fuck did you kill someone?

	int teamWeaponLevel = clientTeam == CS_TEAM_CT ? ctLevel : tLevel; // Get the current weapon level depending on team. The only valid teams are CT and T, this is already checked above to ensure no other team comes down to this line of code

	if (weaponID != weaponLevels[teamWeaponLevel]) { // Check if the weapon the user killed with is the same weapon as the required one
		if (weaponID == CSWeapon_KNIFE || weaponID == CSWeapon_KNIFE_T) { // Special case for knife kills
			clientTeam == CS_TEAM_CT ? ctKills++ : tKills++; // Increase it here once and at the bottom once. A knife kill counts as 2 kills!
		} else { // If not strip the player of weapons and give them the correct ones
			// Strip all weapons
			// Source: https://forums.alliedmods.net/showthread.php?t=133756
			int weapon = -1;
			int slot = -1;
			for (slot = CS_SLOT_PRIMARY ; slot <= CS_SLOT_GRENADE ; slot++) {
				weapon = GetPlayerWeaponSlot(client, slot);
				while (weapon != -1 && (GetEntPropEnt(weapon, Prop_Data, "m_hOwnerEntity") == client)) {
					RemovePlayerItem(client, weapon);
					weapon = GetPlayerWeaponSlot(client, slot);
				}
			}
			GivePlayerItem(client, "weapon_knife");

			// Give level specific weapon
			char giveWeapon[512];
			Format(giveWeapon, sizeof(giveWeapon), "weapon_%s", rawWeaponLevels[clientTeam == CS_TEAM_CT ? ctLevel : tLevel]);
			GivePlayerItem(client, giveWeapon);
			return; // This should typically never happen but you never know
		}
	}

	// Increase kill counter depending on team
	clientTeam == CS_TEAM_CT ? ctKills++ : tKills++;
	int teamKills = clientTeam == CS_TEAM_CT ? ctKills : tKills;

	// Does the client's team have enough kills to level up?
	if (teamKills >= weaponKills[teamWeaponLevel]) {
		// Increase level and reset kill count
		clientTeam == CS_TEAM_CT ? ctLevel++ : tLevel++;
		clientTeam == CS_TEAM_CT ? (ctKills = 0) : (tKills = 0);

		// Did we run out of weapon levels?
		if ((clientTeam == CS_TEAM_CT ? ctLevel : tLevel) >= weaponAmount) {
			// If so set default winner to the client team and end the round. The game will handle the rest for us
			defaultWinner.SetInt(clientTeam);
			GameRules_SetProp("m_iRoundTime", 0);
			return;
		}

		// if not loop through all players and validate them
		for (int i = 1; i <= MaxClients; i++) {
			if (!IsClientInGame(i)) continue;
			if (GetClientTeam(i) != clientTeam) continue; // Ignore players who aren't on the client's team

			// Play weapon upgrade audio
			EmitSoundToClient(i, "music/kill_01.wav");

			// Strip all weapons
			// Source: https://forums.alliedmods.net/showthread.php?t=133756
			int weapon = -1;
			int slot = -1;
			for (slot = CS_SLOT_PRIMARY ; slot <= CS_SLOT_GRENADE ; slot++) {
				weapon = GetPlayerWeaponSlot(i, slot);
				while (weapon != -1 && (GetEntPropEnt(weapon, Prop_Data, "m_hOwnerEntity") == i)) {
					RemovePlayerItem(i, weapon);
					weapon = GetPlayerWeaponSlot(i, slot);
				}
			}
			GivePlayerItem(i, "weapon_knife");

			// Give level specific weapon
			char giveWeapon[512];
			Format(giveWeapon, sizeof(giveWeapon), "weapon_%s", rawWeaponLevels[clientTeam == CS_TEAM_CT ? ctLevel : tLevel]);
			GivePlayerItem(i, giveWeapon);
		}
	}
}
