#pragma semicolon 1

/* SM Includes */
#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <smac>
#undef REQUIRE_PLUGIN
#include <updater>

/* Plugin Info */
public Plugin:myinfo =
{
	name = "SMAC HL2:DM Exploit Fixes",
	author = "GoD-Tony",
	description = "Blocks general Half-Life 2: Deathmatch exploits",
	version = SMAC_VERSION,
	url = SMAC_URL
};

/* Globals */
#define UPDATE_URL	"http://godtony.mooo.com/smac/smac_hl2dm_fixes.txt"

new Float:g_fBlockTime[MAXPLAYERS+1];
new bool:g_bHasCrossbow[MAXPLAYERS+1];

/* Plugin Functions */
public OnPluginStart()
{
	if (SMAC_GetGameType() != Game_HL2DM)
	{
		SetFailState(SMAC_MOD_ERROR);
	}
	
	// Hooks.
	AddTempEntHook("Shotgun Shot", Hook_FireBullets);
	HookEvent("player_team", Event_PlayerTeam, EventHookMode_Pre);
	
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
	g_fBlockTime[client] = 0.0;
	g_bHasCrossbow[client] = false;
	
	SDKHook(client, SDKHook_WeaponCanSwitchTo, Hook_WeaponCanSwitchTo);
	SDKHook(client, SDKHook_WeaponSwitchPost, Hook_WeaponSwitchPost);
}

public Action:Hook_WeaponCanSwitchTo(client, weapon)
{
	decl String:sWeapon[32];
	
	if (!IsValidEdict(weapon) || !GetEdictClassname(weapon, sWeapon, sizeof(sWeapon)))
		return Plugin_Continue;
	
	// Block gravity gun toggle after a bullet has fired.
	if (g_fBlockTime[client] > GetGameTime() && StrEqual(sWeapon, "weapon_physcannon"))
		return Plugin_Handled;
	
	return Plugin_Continue;
}

public Hook_WeaponSwitchPost(client, weapon)
{
	// Monitor the crossbow for shots. OnEntityCreated/OnSpawn is too early.
	decl String:sWeapon[32];
	
	g_bHasCrossbow[client] = IsValidEdict(weapon) && 
			GetEdictClassname(weapon, sWeapon, sizeof(sWeapon)) && 
			StrEqual(sWeapon, "weapon_crossbow");
}

public Action:Hook_FireBullets(const String:te_name[], const Players[], numClients, Float:delay)
{
	new client = TE_ReadNum("m_iPlayer");

	if (IS_CLIENT(client))
	{
		g_fBlockTime[client] = GetGameTime() + 0.1;
	}

	return Plugin_Continue;
}

public Action:Event_PlayerTeam(Handle:event, const String:name[], bool:dontBroadcast)
{
	// Slay players that execute a team change while using an active gravity gun.
	new client = GetClientOfUserId(GetEventInt(event, "userid"));
	
	if (client && IsClientInGame(client) && IsPlayerAlive(client))
	{
		decl String:sWeapon[32];
		new weapon = GetEntPropEnt(client, Prop_Data, "m_hActiveWeapon");
		
		if (IsValidEdict(weapon) && 
			GetEdictClassname(weapon, sWeapon, sizeof(sWeapon)) && 
			StrEqual(sWeapon, "weapon_physcannon") && 
			GetEntProp(weapon, Prop_Send, "m_bActive", 1) && 
			SMAC_CheatDetected(client) == Plugin_Continue)
		{
			SMAC_LogAction(client, "was slayed for attempting to exploit the gravity gun.");
			ForcePlayerSuicide(client);
		}
	}
	
	return Plugin_Continue;
}

public Action:OnPlayerRunCmd(client, &buttons, &impulse, Float:vel[3], Float:angles[3], &weapon)
{
	// Detecting a crossbow shot.
	if ((buttons & IN_ATTACK) && g_bHasCrossbow[client])
	{
		new iWeapon = GetEntPropEnt(client, Prop_Data, "m_hActiveWeapon");
		
		if (IsValidEdict(iWeapon) && GetEntPropFloat(iWeapon, Prop_Send, "m_flNextPrimaryAttack") < GetGameTime())
		{
			g_fBlockTime[client] = GetGameTime() + 0.1;
		}
	}
	
	// Don't let the player crouch if they are in the process of standing up.
	if ((buttons & IN_DUCK) && GetEntProp(client, Prop_Send, "m_bDucked", 1) && GetEntProp(client, Prop_Send, "m_bDucking", 1))
	{
		buttons ^= IN_DUCK;
	}
	
	// Block flashlight/weapon toggle after a bullet has fired.
	if (impulse == 100 && g_fBlockTime[client] > GetGameTime())
	{
		impulse = 0;
	}
	if (weapon && IsValidEdict(weapon) && g_fBlockTime[client] > GetGameTime())
	{
		decl String:sWeapon[32];
		GetEdictClassname(weapon, sWeapon, sizeof(sWeapon));
	
		if (StrEqual(sWeapon, "weapon_physcannon"))
		{
			weapon = 0;
		}
	}
	
	return Plugin_Continue;
}
