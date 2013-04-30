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
	name = "SMAC Anti-Speedhack",
	author = "GoD-Tony",
	description = "Prevents speedhack cheats from working",
	version = SMAC_VERSION,
	url = SMAC_URL
};

/* Globals */
#define UPDATE_URL	"http://godtony.mooo.com/smac/smac_speedhack.txt"

new g_iTickCount[MAXPLAYERS+1];
new g_iTickRate;

/* Plugin Functions */
public OnPluginStart()
{
	// The server's tickrate * 1.5 as a buffer zone.
	g_iTickRate = RoundToCeil(1.0 / GetTickInterval() * 1.5);
	CreateTimer(1.0, Timer_ResetTicks, _, TIMER_REPEAT);

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

public Action:Timer_ResetTicks(Handle:timer)
{
	for (new i = 1; i <= MaxClients; i++)
	{
		g_iTickCount[i] = 0;
	}
	
	return Plugin_Continue;
}

public Action:OnPlayerRunCmd(client, &buttons, &impulse, Float:vel[3], Float:angles[3], &weapon)
{
	if (++g_iTickCount[client] > g_iTickRate)
	{
		return Plugin_Handled; 
	}
	
	return Plugin_Continue;
}
