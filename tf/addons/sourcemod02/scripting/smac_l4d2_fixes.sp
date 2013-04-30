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
	name = "SMAC L4D2 Exploit Fixes",
	author = "Buster \"Mr. Zero\" Nielsen",
	description = "Blocks general Left 4 Dead 2 cheats & exploits",
	version = SMAC_VERSION,
	url = SMAC_URL
};

/* Globals */
#define UPDATE_URL	"http://godtony.mooo.com/smac/smac_l4d2_fixes.txt"

#define L4D2_ZOMBIECLASS_TANK 8
#define RESET_USE_TIME 0.5
#define RECENT_TEAM_CHANGE_TIME 1.0

new bool:g_bProhibitUse[MAXPLAYERS+1];
new bool:g_didRecentlyChangeTeam[MAXPLAYERS + 1];

/* Plugin Functions */
public OnPluginStart()
{
	if (SMAC_GetGameType() != Game_L4D2)
	{
		SetFailState(SMAC_MOD_ERROR);
	}
	
	// Hooks.
	HookEvent("player_use", Event_PlayerUse, EventHookMode_Post);
	HookEvent("player_team", Event_PlayerTeam, EventHookMode_Post);
	
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

public OnAllPluginsLoaded()
{
	for (new client = 1; client <= MaxClients; client++)
	{
		if (IsClientInGame(client))
		{
			SDKHook(client, SDKHook_OnTakeDamage, Hook_OnTakeDamage);
		}
	}
}

public OnClientPutInServer(client)
{
	SDKHook(client, SDKHook_OnTakeDamage, Hook_OnTakeDamage);
}

public Event_PlayerTeam(Handle:event, const String:name[], bool:dontBroadcast)
{
	if (GetEventBool(event, "disconnect"))
	{
		return;
	}

	new client = GetClientOfUserId(GetEventInt(event, "userid"));
	if (!IS_CLIENT(client) || !IsClientInGame(client) || IsFakeClient(client))
	{
		return;
	}

	g_didRecentlyChangeTeam[client] = true;
	CreateTimer(RECENT_TEAM_CHANGE_TIME, Timer_ResetRecentTeamChange, client);
}

public Action:Timer_ResetRecentTeamChange(Handle:timer, any:client)
{
	g_didRecentlyChangeTeam[client] = false;
	return Plugin_Stop;
}

public Action:Hook_OnTakeDamage(victim, &attacker, &inflictor, &Float:damage, &damagetype, &weapon, Float:damageForce[3], Float:damagePosition[3])
{
	// Prevent infected players from killing survivor bots by changing teams in trigger_hurt areas
	if (IS_CLIENT(victim) && g_didRecentlyChangeTeam[victim])
	{
		return Plugin_Handled;
	}

	return Plugin_Continue;
}

public Event_PlayerUse(Handle:event, const String:name[], bool:dontBroadcast)
{
	new entity = GetEventInt(event, "targetid");

	if (entity <= MaxClients || entity >= MAX_EDICTS || !IsValidEntity(entity))
	{
		return;
	}

	decl String:netclass[16];
	GetEntityNetClass(entity, netclass, 16);

	if (!StrEqual(netclass, "CPistol"))
	{
		return;
	}

	new client = GetClientOfUserId(GetEventInt(event, "userid"));
	if (!IS_CLIENT(client) || !IsClientInGame(client) || IsFakeClient(client) || g_bProhibitUse[client])
	{
		return;
	}

	g_bProhibitUse[client] = true;
	CreateTimer(RESET_USE_TIME, Timer_ResetUse, client);
}

public Action:Timer_ResetUse(Handle:timer, any:client)
{
	g_bProhibitUse[client] = false;
	return Plugin_Stop;
}

public Action:OnPlayerRunCmd(client, &buttons, &impulse, Float:vel[3], Float:angles[3], &weapon)
{
	// Block pistol spam.
	if (g_bProhibitUse[client] && (buttons & IN_USE))
	{
		buttons ^= IN_USE;
	}

	// Block tank double-attack.
	if ((buttons & IN_ATTACK) && (buttons & IN_ATTACK2) && 
		GetClientTeam(client) == 3 && IsPlayerAlive(client) && 
		GetEntProp(client, Prop_Send, "m_zombieClass") == L4D2_ZOMBIECLASS_TANK)
	{
		buttons ^= IN_ATTACK2;
	}

	return Plugin_Continue;
}
