#pragma semicolon 1

/* SM Includes */
#include <sourcemod>
#include <sdktools>
#include <smac>
#undef REQUIRE_PLUGIN
#include <updater>

/* Plugin Info */
public Plugin:myinfo =
{
	name = "SMAC Aimbot Detector",
	author = "GoD-Tony",
	description = "Analyzes clients to detect aimbots",
	version = SMAC_VERSION,
	url = SMAC_URL
};

/* Globals */
#define UPDATE_URL	"http://godtony.mooo.com/smac/smac_aimbot.txt"

#define AIM_RECORD_SIZE		32		// How many frames worth of angle data history to store
#define AIM_ANGLE_CHANGE	45.0	// Max angle change that a player should snap
#define AIM_BAN_MIN			4		// Minimum number of detections before an auto-ban is allowed

new Handle:g_hCvarAimbotBan = INVALID_HANDLE;
new Handle:g_IgnoreWeapons = INVALID_HANDLE;

new Float:g_fEyeAngles[MAXPLAYERS+1][AIM_RECORD_SIZE][3];
new g_iEyeIndex[MAXPLAYERS+1];

new g_iAimDetections[MAXPLAYERS+1];
new g_iAimbotBan = 0;

/* Plugin Functions */
public APLRes:AskPluginLoad2(Handle:myself, bool:late, String:error[], err_max)
{
	MarkNativeAsOptional("GameRules_GetPropEnt");
	return APLRes_Success;
}

public OnPluginStart()
{
	LoadTranslations("smac.phrases");
	
	// Convars.
	g_hCvarAimbotBan = SMAC_CreateConVar("smac_aimbot_ban", "0", "Number of aimbot detections before a player is banned. Minimum allowed is 4. (0 = Never ban)", FCVAR_PLUGIN, true, 0.0);
	OnSettingsChanged(g_hCvarAimbotBan, "", "");
	HookConVarChange(g_hCvarAimbotBan, OnSettingsChanged);
	
	// Weapons to ignore when analyzing.
	g_IgnoreWeapons = CreateTrie();
	switch (SMAC_GetGameType())
	{
		case Game_CSS:
		{
			SetTrieValue(g_IgnoreWeapons, "weapon_knife", 1);
		}
		case Game_DODS:
		{	
			SetTrieValue(g_IgnoreWeapons, "weapon_spade", 1);
			SetTrieValue(g_IgnoreWeapons, "weapon_amerknife", 1);
		}
		case Game_TF2:
		{	
			SetTrieValue(g_IgnoreWeapons, "tf_weapon_bottle", 1);
			SetTrieValue(g_IgnoreWeapons, "tf_weapon_sword", 1);
			SetTrieValue(g_IgnoreWeapons, "tf_weapon_wrench", 1);
			SetTrieValue(g_IgnoreWeapons, "tf_weapon_robot_arm", 1);
			SetTrieValue(g_IgnoreWeapons, "tf_weapon_fists", 1);
			SetTrieValue(g_IgnoreWeapons, "tf_weapon_bonesaw", 1);
			SetTrieValue(g_IgnoreWeapons, "tf_weapon_fireaxe", 1);
			SetTrieValue(g_IgnoreWeapons, "tf_weapon_bat", 1);
			SetTrieValue(g_IgnoreWeapons, "tf_weapon_bat_wood", 1);
			SetTrieValue(g_IgnoreWeapons, "tf_weapon_bat_fish", 1);
			SetTrieValue(g_IgnoreWeapons, "tf_weapon_club", 1);
			SetTrieValue(g_IgnoreWeapons, "tf_weapon_shovel", 1);
			SetTrieValue(g_IgnoreWeapons, "tf_weapon_knife", 1);
			SetTrieValue(g_IgnoreWeapons, "tf_weapon_stickbomb", 1);
			SetTrieValue(g_IgnoreWeapons, "tf_weapon_katana", 1);
			SetTrieValue(g_IgnoreWeapons, "tf_weapon_flamethrower", 1);
		}
		case Game_HL2DM:
		{
			SetTrieValue(g_IgnoreWeapons, "weapon_crowbar", 1);
			SetTrieValue(g_IgnoreWeapons, "weapon_stunstick", 1);
		}
	}
	
	// Hooks.
	HookEntityOutput("trigger_teleport", "OnEndTouch", Teleport_OnEndTouch);
	HookEvent("player_spawn", Event_PlayerSpawn, EventHookMode_Post);
	
	if (SMAC_GetGameType() == Game_TF2)
	{
		HookEvent("player_death", TF2_Event_PlayerDeath, EventHookMode_Post);
	}
	else if (!HookEventEx("entity_killed", Event_EntityKilled, EventHookMode_Post))
	{
		HookEvent("player_death", Event_PlayerDeath, EventHookMode_Post);
	}
	
	// Updater.
	if (LibraryExists("updater"))
	{
		Updater_AddPlugin(UPDATE_URL);
	}
}

public OnLibraryAdded(const String:name[])
{
	if (StrEqual(name, "updater"))
	{
		Updater_AddPlugin(UPDATE_URL);
	}
}

public OnClientPutInServer(client)
{
	if (IsClientNew(client))
	{
		g_iAimDetections[client] = 0;
		Aimbot_ClearAngles(client);
	}
}

public OnSettingsChanged(Handle:convar, const String:oldValue[], const String:newValue[])
{
	new iNewValue = GetConVarInt(convar);
	
	if (iNewValue > 0 && iNewValue < AIM_BAN_MIN)
	{
		SetConVarInt(convar, AIM_BAN_MIN);
		return;
	}

	g_iAimbotBan = iNewValue;
}

public Teleport_OnEndTouch(const String:output[], caller, activator, Float:delay)
{
	/* A client is being teleported in the map. */
	if (IS_CLIENT(activator) && IsClientConnected(activator))
	{
		Aimbot_ClearAngles(activator);
		CreateTimer(0.1 + delay, Timer_ClearAngles, GetClientUserId(activator), TIMER_FLAG_NO_MAPCHANGE);
	}
}

public Event_PlayerSpawn(Handle:event, const String:name[], bool:dontBroadcast)
{
	new userid = GetEventInt(event, "userid");
	new client = GetClientOfUserId(userid);
	
	if (IS_CLIENT(client))
	{
		Aimbot_ClearAngles(client);
		CreateTimer(0.1, Timer_ClearAngles, userid, TIMER_FLAG_NO_MAPCHANGE);
	}
}

public Event_PlayerDeath(Handle:event, const String:name[], bool:dontBroadcast)
{
	decl String:sWeapon[32];
	GetEventString(event, "weapon", sWeapon, sizeof(sWeapon));
	
	new dummy;
	if (GetTrieValue(g_IgnoreWeapons, sWeapon, dummy))
		return;
		
	new victim = GetClientOfUserId(GetEventInt(event, "userid"));
	new attacker = GetClientOfUserId(GetEventInt(event, "attacker"));
	
	if (IS_CLIENT(victim) && IS_CLIENT(attacker) && victim != attacker && IsClientInGame(attacker))
	{
		Aimbot_AnalyzeAngles(attacker);
	}
}

public Event_EntityKilled(Handle:event, const String:name[], bool:dontBroadcast)
{
	/* (OB Only) Inflictor support lets us ignore non-bullet weapons. */
	new victim = GetEventInt(event, "entindex_killed");
	new attacker = GetEventInt(event, "entindex_attacker");
	new inflictor = GetEventInt(event, "entindex_inflictor");
	
	if (IS_CLIENT(victim) && IS_CLIENT(attacker) && victim != attacker && attacker == inflictor && IsClientInGame(attacker))
	{
		decl String:sWeapon[32];
		GetClientWeapon(attacker, sWeapon, sizeof(sWeapon));
		
		new dummy;
		if (GetTrieValue(g_IgnoreWeapons, sWeapon, dummy))
			return;
		
		Aimbot_AnalyzeAngles(attacker);
	}
}

public TF2_Event_PlayerDeath(Handle:event, const String:name[], bool:dontBroadcast)
{
	/* TF2 custom death event */
	new victim = GetClientOfUserId(GetEventInt(event, "userid"));
	new attacker = GetClientOfUserId(GetEventInt(event, "attacker"));
	new inflictor = GetEventInt(event, "inflictor_entindex");
	
	if (IS_CLIENT(victim) && IS_CLIENT(attacker) && victim != attacker && attacker == inflictor && IsClientInGame(attacker))
	{
		decl String:sWeapon[32];
		GetClientWeapon(attacker, sWeapon, sizeof(sWeapon));
		
		new dummy;
		if (GetTrieValue(g_IgnoreWeapons, sWeapon, dummy))
			return;
		
		Aimbot_AnalyzeAngles(attacker);
	}
}

public Action:Timer_ClearAngles(Handle:timer, any:userid)
{
	/* Delayed because the client's angles can sometimes "spin" after being teleported. */
	new client = GetClientOfUserId(userid);
	
	if (IS_CLIENT(client))
	{
		Aimbot_ClearAngles(client);
	}
	
	return Plugin_Stop;
}

public Action:Timer_DecreaseCount(Handle:timer, any:userid)
{
	/* Decrease the detection count by 1. */
	new client = GetClientOfUserId(userid);
	
	if (IS_CLIENT(client) && g_iAimDetections[client])
	{
		g_iAimDetections[client]--;
	}
	
	return Plugin_Stop;
}

public Action:OnPlayerRunCmd(client, &buttons, &impulse, Float:vel[3], Float:angles[3], &weapon)
{
	g_fEyeAngles[client][g_iEyeIndex[client]] = angles;
	g_iEyeIndex[client]++;
	
	if (g_iEyeIndex[client] == AIM_RECORD_SIZE)
	{
		g_iEyeIndex[client] = 0;
	}
		
	return Plugin_Continue;
}

Aimbot_AnalyzeAngles(client)
{
	/* Analyze the client to see if their angles snapped. */
	decl Float:vLastAngles[3], Float:vAngles[3], Float:fAngleDiff;
	new idx = g_iEyeIndex[client];
	
	for (new i = 0; i < AIM_RECORD_SIZE; i++)
	{
		if (idx == AIM_RECORD_SIZE)
		{
			idx = 0;
		}
			
		if (IsVectorZero(g_fEyeAngles[client][idx]))
		{
			break;
		}
		
		// Nothing to compare on the first iteration.
		if (i == 0)
		{
			vLastAngles = g_fEyeAngles[client][idx];
			idx++;
			continue;
		}
		
		vAngles = g_fEyeAngles[client][idx];
		fAngleDiff = GetVectorDistance(vLastAngles, vAngles);
		
		// If the difference is being reported higher than 180, get the 'real' value.
		if (fAngleDiff > 180)
		{
			fAngleDiff = FloatAbs(fAngleDiff - 360);
		}

		if (fAngleDiff > AIM_ANGLE_CHANGE)
		{
			Aimbot_Detected(client, fAngleDiff);
			break;
		}
		
		vLastAngles = vAngles;
		idx++;
	}
}

Aimbot_Detected(client, const Float:deviation)
{
	// Extra checks must be done here because of data coming from two events.
	if (IsFakeClient(client) || !IsPlayerAlive(client))
		return;
	
	switch (SMAC_GetGameType())
	{
		case Game_L4D:
		{
			if (GetClientTeam(client) != 2 || L4D_IsSurvivorBusy(client))
				return;
		}
		
		case Game_L4D2:
		{
			if (GetClientTeam(client) != 2 || L4D2_IsSurvivorBusy(client))
				return;
		}
		
		case Game_ND:
		{	
			if (ND_IsPlayerCommander(client))
				return;
		}
	}
	
	if (SMAC_CheatDetected(client) == Plugin_Continue)
	{
		// Expire this detection after 10 minutes.
		CreateTimer(600.0, Timer_DecreaseCount, GetClientUserId(client));
		
		// Ignore the first detection as it's just as likely to be a false positive.
		if (++g_iAimDetections[client] > 1)
		{
			decl String:sName[MAX_NAME_LENGTH], String:sWeapon[32];
			GetClientName(client, sName, sizeof(sName));
			GetClientWeapon(client, sWeapon, sizeof(sWeapon));
			
			SMAC_PrintAdminNotice("%t", "SMAC_AimbotDetected", sName, g_iAimDetections[client], deviation, sWeapon);
			SMAC_LogAction(client, "is suspected of using an aimbot. (Detection #%i | Deviation: %.0f° | Weapon: %s)", g_iAimDetections[client], deviation, sWeapon);
			
			if (g_iAimbotBan && g_iAimDetections[client] >= g_iAimbotBan)
			{
				SMAC_LogAction(client, "was banned for using an aimbot.");
				SMAC_Ban(client, "Aimbot Detected");
			}
		}
	}
}

Aimbot_ClearAngles(client)
{
	/* Clear angle history and reset the index. */
	g_iEyeIndex[client] = 0;
	
	for (new i = 0; i < AIM_RECORD_SIZE; i++)
	{
		ZeroVector(g_fEyeAngles[client][i]);
	}
}
