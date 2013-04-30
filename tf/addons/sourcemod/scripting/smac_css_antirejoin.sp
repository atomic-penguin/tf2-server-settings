#pragma semicolon 1

/* SM Includes */
#include <sourcemod>
#include <smac>
#undef REQUIRE_PLUGIN
#include <updater>

/* Plugin Info */
public Plugin:myinfo =
{
	name = "SMAC CS:S Anti-Rejoin",
	author = "Kigen",
	description = "Prevents players from rejoining to repsawn",
	version = SMAC_VERSION,
	url = SMAC_URL
};

/* Globals */
#define UPDATE_URL	"http://godtony.mooo.com/smac/smac_css_antirejoin.txt"

new Handle:g_hClientSpawned = INVALID_HANDLE;
new g_iClientClass[MAXPLAYERS+1] = {-1, ...};
new bool:g_bClientMapStarted = false;
new Handle:g_hCvarRestartGame;

/* Plugin Functions */
public OnPluginStart()
{
	if (SMAC_GetGameType() != Game_CSS)
	{
		SetFailState(SMAC_MOD_ERROR);
	}

	g_hClientSpawned = CreateTrie();

	HookEvent("player_spawn", Event_PlayerSpawn);
	HookEvent("player_death", Event_PlayerDeath);
	HookEvent("round_start", Event_RoundStart);
	HookEvent("round_end", Event_RoundEnd);
	
	// Detect game restarts via "mp_restartgame"
	g_hCvarRestartGame = FindConVar("mp_restartgame");
	HookConVarChange(g_hCvarRestartGame, Hook_RestartGame);

	AddCommandListener(Command_JoinClass, "joinclass");
	
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

public OnMapEnd()
{
	g_bClientMapStarted = false;
	ClearData();
}

public Action:Command_JoinClass(client, const String:command[], args)
{
	if ( !g_bClientMapStarted || !client || IsFakeClient(client) || GetClientTeam(client) < 2 )
		return Plugin_Continue;

	decl String:f_sAuthID[MAX_AUTHID_LENGTH], String:f_sTemp[64];
	new f_iTemp;
	if ( !GetClientAuthString(client, f_sAuthID, sizeof(f_sAuthID)) )
		return Plugin_Continue;

	if ( !GetTrieValue(g_hClientSpawned, f_sAuthID, f_iTemp) )
		return Plugin_Continue;

	GetCmdArgString(f_sTemp, sizeof(f_sTemp));

	g_iClientClass[client] = StringToInt(f_sTemp);
	if ( g_iClientClass[client] < 0 )
		g_iClientClass[client] = 0;

	FakeClientCommandEx(client, "spec_mode");
	return Plugin_Handled;
}

public Action:Event_PlayerSpawn(Handle:event, const String:name[], bool:dontBroadcast)
{
	new client = GetClientOfUserId(GetEventInt(event, "userid")), String:f_sAuthID[MAX_AUTHID_LENGTH];
	if ( !client || GetClientTeam(client) < 2 || !GetClientAuthString(client, f_sAuthID, sizeof(f_sAuthID)) )
		return Plugin_Continue;
	
	RemoveFromTrie(g_hClientSpawned, f_sAuthID);

	return Plugin_Continue;
}

public Action:Event_PlayerDeath(Handle:event, const String:name[], bool:dontBroadcast)
{
	new client = GetClientOfUserId(GetEventInt(event, "userid")), String:f_sAuthID[MAX_AUTHID_LENGTH];
	if ( !client || !GetClientAuthString(client, f_sAuthID, sizeof(f_sAuthID)) )
		return Plugin_Continue;
	
	SetTrieValue(g_hClientSpawned, f_sAuthID, true);

	return Plugin_Continue;
}

public Action:Event_RoundStart(Handle:event, const String:name[], bool:dontBroadcast)
{
	g_bClientMapStarted = true;
	ClearData();
}

public Action:Event_RoundEnd(Handle:event, const String:name[], bool:dontBroadcast)
{
	ClearData();
}

public Hook_RestartGame(Handle:convar, const String:oldValue[], const String:newValue[])
{
	if (StringToInt(newValue) > 0)
	{
		ClearData();
	}
}

ClearData()
{
	ClearTrie(g_hClientSpawned);

	for(new i=1;i<=MaxClients;i++)
	{
		if ( IsClientInGame(i) && g_iClientClass[i] != -1 )
		{
			FakeClientCommandEx(i, "joinclass %d", g_iClientClass[i]);
			g_iClientClass[i] = -1;
		}
	}
}
