#pragma semicolon 1

/* SM Includes */
#include <sourcemod>
#include <sdktools>
#include <smac>
#include <colors>
#undef REQUIRE_PLUGIN
#include <updater>

/* Plugin Info */
public Plugin:myinfo =
{
	name = "SourceMod Anti-Cheat",
	author = "GoD-Tony, psychonic",
	description = "Open source anti-cheat plugin for SourceMod",
	version = SMAC_VERSION,
	url = SMAC_URL
};

/* Globals */
#define UPDATE_URL	"http://godtony.mooo.com/smac/smac.txt"

enum IrcChannel
{
	IrcChannel_Public  = 1,
	IrcChannel_Private = 2,
	IrcChannel_Both    = 3
}

native SBBanPlayer(client, target, time, String:reason[]);
native IRC_MsgFlaggedChannels(const String:flag[], const String:format[], any:...);
native IRC_Broadcast(IrcChannel:type, const String:format[], any:...);

new GameType:g_Game = Game_Unknown;
new Handle:g_hCvarVersion = INVALID_HANDLE;
new Handle:g_hCvarWelcomeMsg = INVALID_HANDLE;
new Handle:g_hCvarBanDuration = INVALID_HANDLE;
new Handle:g_hCvarLogVerbose = INVALID_HANDLE;
new String:g_sLogPath[PLATFORM_MAX_PATH];

/* Plugin Functions */
public APLRes:AskPluginLoad2(Handle:myself, bool:late, String:error[], err_max)
{
	// Detect game.
	decl String:sGame[64];
	GetGameFolderName(sGame, sizeof(sGame));

	if (StrEqual(sGame, "cstrike") || StrEqual(sGame, "cstrike_beta"))
		g_Game = Game_CSS;
	else if (StrEqual(sGame, "tf") || StrEqual(sGame, "tf_beta"))
		g_Game = Game_TF2;
	else if (StrEqual(sGame, "dod"))
		g_Game = Game_DODS;
	else if (StrEqual(sGame, "insurgency"))
		g_Game = Game_INSMOD;
	else if (StrEqual(sGame, "left4dead"))
		g_Game = Game_L4D;
	else if (StrEqual(sGame, "left4dead2"))
		g_Game = Game_L4D2;
	else if (StrEqual(sGame, "hl2mp"))
		g_Game = Game_HL2DM;
	else if (StrEqual(sGame, "fistful_of_frags"))
		g_Game = Game_FOF;
	else if (StrEqual(sGame, "garrysmod"))
		g_Game = Game_GMOD;
	else if (StrEqual(sGame, "hl2ctf"))
		g_Game = Game_HL2CTF;
	else if (StrEqual(sGame, "hidden"))
		g_Game = Game_HIDDEN;
	else if (StrEqual(sGame, "nucleardawn"))
		g_Game = Game_ND;
	else if (StrEqual(sGame, "csgo"))
		g_Game = Game_CSGO;
	
	// Path used for logging.
	BuildPath(Path_SM, g_sLogPath, sizeof(g_sLogPath), "logs/SMAC.log");
	
	// Optional dependencies.
	MarkNativeAsOptional("SBBanPlayer");
	MarkNativeAsOptional("IRC_MsgFlaggedChannels");
	MarkNativeAsOptional("IRC_Broadcast");
	
	API_Init();
	RegPluginLibrary("smac");
	
	return APLRes_Success;
}

public OnPluginStart()
{
	LoadTranslations("smac.phrases");

	// Convars.
	g_hCvarVersion = CreateConVar("smac_version", SMAC_VERSION, "SourceMod Anti-Cheat", FCVAR_PLUGIN|FCVAR_NOTIFY|FCVAR_DONTRECORD);
	OnVersionChanged(g_hCvarVersion, "", "");
	HookConVarChange(g_hCvarVersion, OnVersionChanged);
	
	g_hCvarWelcomeMsg = CreateConVar("smac_welcomemsg", "1", "Display a message saying that your server is protected.", FCVAR_PLUGIN, true, 0.0, true, 1.0);
	g_hCvarBanDuration = CreateConVar("smac_ban_duration", "0", "The duration in minutes used for automatic bans. (0 = Permanent)", FCVAR_PLUGIN, true, 0.0);
	g_hCvarLogVerbose = CreateConVar("smac_log_verbose", "0", "Include extra information about a client being logged.", FCVAR_PLUGIN, true, 0.0, true, 1.0);
	
	// Commands.
	RegAdminCmd("smac_status", Command_Status, ADMFLAG_GENERIC, "View the server's player status.");
	
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
	// Wait for other modules to create their convars.
	AutoExecConfig(true, "smac");
	
	PrintToServer("SourceMod Anti-Cheat %s has been successfully loaded.", SMAC_VERSION);
}

public OnVersionChanged(Handle:convar, const String:oldValue[], const String:newValue[])
{
	if (!StrEqual(newValue, SMAC_VERSION))
	{
		SetConVarString(g_hCvarVersion, SMAC_VERSION);
	}
}

public OnClientPutInServer(client)
{
	if (GetConVarBool(g_hCvarWelcomeMsg))
	{
		CreateTimer(10.0, Timer_WelcomeMsg, GetClientUserId(client), TIMER_FLAG_NO_MAPCHANGE);
	}
}

public Action:Timer_WelcomeMsg(Handle:timer, any:userid)
{
	new client = GetClientOfUserId(userid);
	
	if (client && IsClientInGame(client))
	{
		CPrintToChat(client, "%t%t", "SMAC_Tag", "SMAC_WelcomeMsg");
	}
		
	return Plugin_Stop;
}

public Action:Command_Status(client, args)
{
	PrintToConsole(client, "%s  %-24s %s", "UserID", "AuthID", "Name");

	decl String:sName[MAX_NAME_LENGTH], String:sAuthID[MAX_AUTHID_LENGTH], iUserID;

	for (new i = 1; i <= MaxClients; i++)
	{
		if (!IsClientConnected(i))
			continue;
		
		if (!GetClientName(i, sName, sizeof(sName)))
		{
			strcopy(sName, sizeof(sName), "");
		}
		if (!GetClientAuthString(i, sAuthID, sizeof(sAuthID)))
		{
			strcopy(sAuthID, sizeof(sAuthID), "");
		}
		iUserID = GetClientUserId(i);
		
		PrintToConsole(client, "%6d  %-24s %s", iUserID, sAuthID, sName);
	}

	return Plugin_Handled;
}

/* API - Natives & Forwards */

new Handle:g_OnCheatDetected = INVALID_HANDLE;

API_Init()
{
	CreateNative("SMAC_GetGameType", Native_GetGameType);
	CreateNative("SMAC_Log", Native_Log);
	CreateNative("SMAC_LogAction", Native_LogAction);
	CreateNative("SMAC_Ban", Native_Ban);
	CreateNative("SMAC_PrintAdminNotice", Native_PrintAdminNotice);
	CreateNative("SMAC_CreateConVar", Native_CreateConVar);
	CreateNative("SMAC_CheatDetected", Native_CheatDetected);
	
	g_OnCheatDetected = CreateGlobalForward("SMAC_OnCheatDetected", ET_Event, Param_Cell, Param_String);
}

// native GameType:SMAC_GetGameType();
public Native_GetGameType(Handle:plugin, numParams)
{
	return _:g_Game;
}

// native SMAC_Log(const String:format[], any:...);
public Native_Log(Handle:plugin, numParams)
{
	decl String:sFilename[64], String:sBuffer[256];
	GetPluginBasename(plugin, sFilename, sizeof(sFilename));
	FormatNativeString(0, 1, 2, sizeof(sBuffer), _, sBuffer);
	LogToFileEx(g_sLogPath, "[%s] %s", sFilename, sBuffer);
}

// native SMAC_LogAction(client, const String:format[], any:...);
public Native_LogAction(Handle:plugin, numParams)
{
	new client = GetNativeCell(1);
	if (!IS_CLIENT(client) || !IsClientConnected(client))
	{
		ThrowNativeError(SP_ERROR_INDEX, "Client index %i is invalid", client);
	}
	
	decl String:sName[MAX_NAME_LENGTH], String:sAuthID[MAX_AUTHID_LENGTH], String:sIP[17];
	if (!GetClientName(client, sName, sizeof(sName)))
	{
		strcopy(sName, sizeof(sName), "Unknown");
	}
	if (!GetClientAuthString(client, sAuthID, sizeof(sAuthID)))
	{
		strcopy(sAuthID, sizeof(sAuthID), "Unknown");
	}
	if (!GetClientIP(client, sIP, sizeof(sIP)))
	{
		strcopy(sIP, sizeof(sIP), "Unknown");
	}
	
	decl String:sFilename[64], String:sBuffer[256];
	GetPluginBasename(plugin, sFilename, sizeof(sFilename));
	FormatNativeString(0, 2, 3, sizeof(sBuffer), _, sBuffer);
	
	// Verbose client logging.
	if (GetConVarBool(g_hCvarLogVerbose) && IsClientInGame(client))
	{
		decl String:sVersion[16], String:sMap[MAX_MAPNAME_LENGTH], Float:vOrigin[3], Float:vAngles[3], String:sWeapon[32], iTeam, iLatency;
		GetPluginInfo(plugin, PlInfo_Version, sVersion, sizeof(sVersion));
		GetCurrentMap(sMap, sizeof(sMap));
		GetClientAbsOrigin(client, vOrigin);
		GetClientEyeAngles(client, vAngles);
		GetClientWeapon(client, sWeapon, sizeof(sWeapon));
		iTeam = GetClientTeam(client);
		iLatency = RoundToNearest(GetClientAvgLatency(client, NetFlow_Outgoing) * 1000.0);
		
		LogToFileEx(g_sLogPath,
			"[%s] %s (ID: %s | IP: %s) %s\n\tVersion: %s | Map: %s | Origin: %.0f %.0f %.0f | Angles: %.0f %.0f %.0f | Weapon: %s | Team: %i | Latency: %ims",
			sFilename,
			sName,
			sAuthID,
			sIP,
			sBuffer,
			sVersion,
			sMap,
			vOrigin[0], vOrigin[1], vOrigin[2],
			vAngles[0], vAngles[1], vAngles[2],
			sWeapon,
			iTeam,
			iLatency);
	}
	else
	{
		LogToFileEx(g_sLogPath, "[%s] %s (ID: %s | IP: %s) %s", sFilename, sName, sAuthID, sIP, sBuffer);
	}
}

// native SMAC_Ban(client, const String:reason[], any:...);
public Native_Ban(Handle:plugin, numParams)
{
	decl String:sReason[256];
	new client = GetNativeCell(1);
	new duration = GetConVarInt(g_hCvarBanDuration);
	
	FormatNativeString(0, 2, 3, sizeof(sReason), _, sReason);
	Format(sReason, sizeof(sReason), "SMAC: %s", sReason);
	
	if (GetFeatureStatus(FeatureType_Native, "SBBanPlayer") == FeatureStatus_Available)
	{
		SBBanPlayer(0, client, duration, sReason);
	}
	else
	{
		decl String:sKickMsg[256];
		FormatEx(sKickMsg, sizeof(sKickMsg), "%T", "SMAC_Banned", client);
		BanClient(client, duration, BANFLAG_AUTO, sReason, sKickMsg, "SMAC");
	}
}

// native SMAC_PrintAdminNotice(const String:format[], any:...);
public Native_PrintAdminNotice(Handle:plugin, numParams)
{
	decl String:sBuffer[192];

	for (new i = 1; i <= MaxClients; i++)
	{
		if (CheckCommandAccess(i, "smac_admin_notices", ADMFLAG_GENERIC, true))
		{
			SetGlobalTransTarget(i);
			FormatNativeString(0, 1, 2, sizeof(sBuffer), _, sBuffer);
			CPrintToChat(i, "%t%s", "SMAC_Tag", sBuffer);
		}
	}
	
	// SourceIRC
	if (GetFeatureStatus(FeatureType_Native, "IRC_MsgFlaggedChannels") == FeatureStatus_Available)
	{
		SetGlobalTransTarget(LANG_SERVER);
		FormatNativeString(0, 1, 2, sizeof(sBuffer), _, sBuffer);
		Format(sBuffer, sizeof(sBuffer), "%t%s", "SMAC_Tag", sBuffer);
		CRemoveTags(sBuffer, sizeof(sBuffer));
		IRC_MsgFlaggedChannels("ticket", sBuffer);
	}
	
	// IRC Relay
	if (GetFeatureStatus(FeatureType_Native, "IRC_Broadcast") == FeatureStatus_Available)
	{
		SetGlobalTransTarget(LANG_SERVER);
		FormatNativeString(0, 1, 2, sizeof(sBuffer), _, sBuffer);
		Format(sBuffer, sizeof(sBuffer), "%t%s", "SMAC_Tag", sBuffer);
		CRemoveTags(sBuffer, sizeof(sBuffer));
		IRC_Broadcast(IrcChannel_Private, sBuffer);
	}
}

// native Handle:SMAC_CreateConVar(const String:name[], const String:defaultValue[], const String:description[]="", flags=0, bool:hasMin=false, Float:min=0.0, bool:hasMax=false, Float:max=0.0);
public Native_CreateConVar(Handle:plugin, numParams)
{
	decl String:name[64], String:defaultValue[16], String:description[192];
	GetNativeString(1, name, sizeof(name));
	GetNativeString(2, defaultValue, sizeof(defaultValue));
	GetNativeString(3, description, sizeof(description));
	
	new flags = GetNativeCell(4);
	new bool:hasMin = bool:GetNativeCell(5);
	new Float:min = Float:GetNativeCell(6);
	new bool:hasMax = bool:GetNativeCell(7);
	new Float:max = Float:GetNativeCell(8);
	
	decl String:sFilename[64];
	GetPluginBasename(plugin, sFilename, sizeof(sFilename));
	Format(description, sizeof(description), "[%s] %s", sFilename, description);
	
	return _:CreateConVar(name, defaultValue, description, flags, hasMin, min, hasMax, max);
}

// native Action:SMAC_CheatDetected(client);
public Native_CheatDetected(Handle:plugin, numParams)
{
	new client = GetNativeCell(1);
	if (!IS_CLIENT(client) || !IsClientConnected(client))
	{
		ThrowNativeError(SP_ERROR_INDEX, "Client index %i is invalid", client);
	}
	
	decl String:sFilename[64];
	GetPluginBasename(plugin, sFilename, sizeof(sFilename));
	
	// forward Action:SMAC_OnCheatDetected(client, const String:module[]);
	new Action:result = Plugin_Continue;
	Call_StartForward(g_OnCheatDetected);
	Call_PushCell(client);
	Call_PushString(sFilename);
	Call_Finish(result);
	
	return _:result;
}
