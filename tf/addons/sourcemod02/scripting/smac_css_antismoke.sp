#pragma semicolon 1

/* SM Includes */
#include <sourcemod>
#include <sdkhooks>
#include <smac>
#undef REQUIRE_PLUGIN
#include <updater>

/* Plugin Info */
public Plugin:myinfo =
{
	name = "SMAC CS:S Anti-Smoke",
	author = "GoD-Tony",
	description = "Prevents anti-smoke cheats from working",
	version = SMAC_VERSION,
	url = SMAC_URL
};

/* Globals */
#define UPDATE_URL	"http://godtony.mooo.com/smac/smac_css_antismoke.txt"

#define SMOKE_FADETIME	15.0	// Seconds until a smoke begins to fade away
#define SMOKE_RADIUS	2025	// (45^2) Radius to check for a player inside a smoke cloud

new Handle:g_hSmokeLoop = INVALID_HANDLE;
new Handle:g_hSmokes = INVALID_HANDLE;
new bool:g_bIsInSmoke[MAXPLAYERS+1];
new bool:g_bSmokeHooked;

/* Plugin Functions */
public OnPluginStart()
{
	if (SMAC_GetGameType() != Game_CSS)
	{
		SetFailState(SMAC_MOD_ERROR);
	}
	
	g_hSmokes = CreateArray(3);
	
	// Hooks.
	HookEvent("smokegrenade_detonate", Event_SmokeDetonate, EventHookMode_Post);
	HookEvent("round_start", Event_RoundChanged, EventHookMode_PostNoCopy);
	HookEvent("round_end", Event_RoundChanged, EventHookMode_PostNoCopy);

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
	if (g_bSmokeHooked)
	{
		AntiSmoke_UnhookAll();
	}
}

public OnClientPutInServer(client)
{
	if (g_bSmokeHooked)
	{
		SDKHook(client, SDKHook_SetTransmit, Hook_SetTransmit);
	}
}

public OnClientDisconnect(client)
{
	g_bIsInSmoke[client] = false;
}

public Event_SmokeDetonate(Handle:event, const String:name[], bool:dontBroadcast)
{
	decl Float:vSmoke[3];
	vSmoke[0] = GetEventFloat(event, "x");
	vSmoke[1] = GetEventFloat(event, "y");
	vSmoke[2] = GetEventFloat(event, "z");
	
	PushArrayArray(g_hSmokes, vSmoke);
	
	if (!g_bSmokeHooked)
	{
		AntiSmoke_HookAll();
	}
	
	CreateTimer(SMOKE_FADETIME, Timer_SmokeEnded);
}

public Event_RoundChanged(Handle:event, const String:name[], bool:dontBroadcast)
{
	/* Smokes disappear when a round starts or ends. */
	if (g_bSmokeHooked)
	{
		AntiSmoke_UnhookAll();
	}
}

public Action:Timer_SmokeEnded(Handle:timer)
{
	/* If this was the last active smoke, unhook everything. */
	if (GetArraySize(g_hSmokes))
	{
		RemoveFromArray(g_hSmokes, 0);
	}
	
	if (!GetArraySize(g_hSmokes) && g_bSmokeHooked)
	{
		AntiSmoke_UnhookAll();
	}
	
	return Plugin_Stop;
}

public Action:Timer_SmokeCheck(Handle:timer)
{
	/* Check if a player is immersed in a smoke. */
	decl Float:vClient[3], Float:vSmoke[3], Float:fDistance;
	
	for (new i = 1; i <= MaxClients; i++)
	{
		if (IsClientInGame(i) && !IsFakeClient(i))
		{
			GetClientAbsOrigin(i, vClient);
			
			for (new idx = 0; idx < GetArraySize(g_hSmokes); idx++)
			{
				GetArrayArray(g_hSmokes, idx, vSmoke);
				fDistance = GetVectorDistance(vClient, vSmoke, true);
				
				if (fDistance < SMOKE_RADIUS)
				{
					g_bIsInSmoke[i] = true;
					break;
				}
				
				g_bIsInSmoke[i] = false;
			}
		}
	}
	
	return Plugin_Continue;
}

public Action:Hook_SetTransmit(entity, client)
{
	/* Don't send client data to players that are immersed in smoke. */
	if (!IS_CLIENT(client) || entity == client)
		return Plugin_Continue;
	
	if (g_bIsInSmoke[client])
	{
		return Plugin_Handled;
	}
	
	return Plugin_Continue;
}

AntiSmoke_HookAll()
{
	g_bSmokeHooked = true;
	
	if (g_hSmokeLoop == INVALID_HANDLE)
	{
		g_hSmokeLoop = CreateTimer(0.1, Timer_SmokeCheck, _, TIMER_REPEAT);
	}
	
	for (new i = 1; i <= MaxClients; i++)
	{
		if (IsClientInGame(i))
		{
			SDKHook(i, SDKHook_SetTransmit, Hook_SetTransmit);
		}
	}
}

AntiSmoke_UnhookAll()
{
	g_bSmokeHooked = false;
	
	if (g_hSmokeLoop != INVALID_HANDLE)
	{
		KillTimer(g_hSmokeLoop);
		g_hSmokeLoop = INVALID_HANDLE;
	}

	for (new i = 1; i <= MaxClients; i++)
	{
		if (IsClientInGame(i))
		{
			SDKUnhook(i, SDKHook_SetTransmit, Hook_SetTransmit);
		}
	}
	
	ClearArray(g_hSmokes);
}
