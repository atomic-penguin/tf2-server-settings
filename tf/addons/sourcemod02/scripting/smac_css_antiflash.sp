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
	name = "SMAC CS:S Anti-Flash",
	author = "GoD-Tony",
	description = "Prevents anti-flashbang cheats from working",
	version = SMAC_VERSION,
	url = SMAC_URL
};

/* Globals */
#define UPDATE_URL	"http://godtony.mooo.com/smac/smac_css_antiflash.txt"

new g_iFlashDuration = -1;
new g_iFlashAlpha = -1;

new Float:g_fFlashedUntil[MAXPLAYERS+1];
new bool:g_bFlashHooked = false;

/* Plugin Functions */
public OnPluginStart()
{
	if (SMAC_GetGameType() != Game_CSS)
	{
		SetFailState(SMAC_MOD_ERROR);
	}
	
	// Find offsets.
	if ((g_iFlashDuration = FindSendPropOffs("CCSPlayer", "m_flFlashDuration")) == -1)
	{
		SetFailState("Failed to find CCSPlayer::m_flFlashDuration offset");
	}
	
	if ((g_iFlashAlpha = FindSendPropOffs("CCSPlayer", "m_flFlashMaxAlpha")) == -1)
	{
		SetFailState("Failed to find CCSPlayer::m_flFlashMaxAlpha offset");
	}
	
	// Hooks.
	HookEvent("player_blind", Event_PlayerBlind, EventHookMode_Post);
	
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
	if (g_bFlashHooked)
	{
		SDKHook(client, SDKHook_SetTransmit, Hook_SetTransmit);
	}
}

public OnClientDisconnect(client)
{
	g_fFlashedUntil[client] = 0.0;
}

public Event_PlayerBlind(Handle:event, const String:name[], bool:dontBroadcast)
{
	new client = GetClientOfUserId(GetEventInt(event, "userid"));
	
	if (IS_CLIENT(client) && !IsFakeClient(client))
	{
		new Float:alpha = GetEntDataFloat(client, g_iFlashAlpha);
		
		if (alpha < 255.0)
		{
			return;
		}
		
		new Float:duration = GetEntDataFloat(client, g_iFlashDuration);
		
		if (duration > 2.9)
		{
			g_fFlashedUntil[client] = GetGameTime() + duration - 2.9;
		}
		else
		{
			g_fFlashedUntil[client] = GetGameTime() + duration * 0.1;
		}
		
		if (!g_bFlashHooked)
		{
			AntiFlash_HookAll();
		}
			
		CreateTimer(duration, Timer_FlashEnded);
	}
}

public Action:Timer_FlashEnded(Handle:timer)
{
	/* Check if there are any other flashes being processed. Otherwise, we can unhook. */
	new Float:fGameTime = GetGameTime();
	
	for (new i = 1; i <= MaxClients; i++)
	{
		if (g_fFlashedUntil[i] > fGameTime)
		{
			return Plugin_Stop;
		}
	}
	
	if (g_bFlashHooked)
	{
		AntiFlash_UnhookAll();
	}
	
	return Plugin_Stop;
}

public Action:Hook_SetTransmit(entity, client)
{
	/* Don't send client data to players that are fully blind. */
	if (!IS_CLIENT(client) || entity == client)
	{
		return Plugin_Continue;
	}
	
	if (g_fFlashedUntil[client] && g_fFlashedUntil[client] > GetGameTime())
	{
		return Plugin_Handled;
	}
	
	g_fFlashedUntil[client] = 0.0;
	return Plugin_Continue;
}

AntiFlash_HookAll()
{
	g_bFlashHooked = true;
	
	for (new i = 1; i <= MaxClients; i++)
	{
		if (IsClientInGame(i))
		{
			SDKHook(i, SDKHook_SetTransmit, Hook_SetTransmit);
		}
	}
}

AntiFlash_UnhookAll()
{
	g_bFlashHooked = false;

	for (new i = 1; i <= MaxClients; i++)
	{
		if (IsClientInGame(i))
		{
			SDKUnhook(i, SDKHook_SetTransmit, Hook_SetTransmit);
		}
	}
}
