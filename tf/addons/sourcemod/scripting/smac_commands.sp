#pragma semicolon 1

/* SM Includes */
#include <sourcemod>
#include <smac>
#undef REQUIRE_PLUGIN
#include <updater>

/* Plugin Info */
public Plugin:myinfo =
{
	name = "SMAC Command Monitor",
	author = "GoD-Tony, psychonic, Kigen",
	description = "Blocks general command exploits",
	version = SMAC_VERSION,
	url = SMAC_URL
};

/* Globals */
#define UPDATE_URL	"http://godtony.mooo.com/smac/smac_commands.txt"

new Handle:g_hBlockedCmds = INVALID_HANDLE;
new Handle:g_hIgnoredCmds = INVALID_HANDLE;
new g_iCmdSpam = 30;
new g_iCmdCount[MAXPLAYERS+1] = {0, ...};
new Handle:g_hCvarCmdSpam = INVALID_HANDLE;

/* Plugin Functions */
public OnPluginStart()
{
	LoadTranslations("smac.phrases");
	
	// Convars.
	g_hCvarCmdSpam = SMAC_CreateConVar("smac_antispam_cmds", "30", "Amount of commands allowed in one second before kick. (0 = Disabled)", FCVAR_PLUGIN, true, 0.0);
	OnSettingsChanged(g_hCvarCmdSpam, "", "");
	HookConVarChange(g_hCvarCmdSpam, OnSettingsChanged);

	// Hooks.
	AddCommandListener(Commands_FilterSay, "say");
	AddCommandListener(Commands_FilterSay, "say_team");
	AddCommandListener(Commands_BlockExploit, "sm_menu");
	
	// Exploitable needed commands.  Sigh....
	AddCommandListener(Commands_BlockEntExploit, "ent_create");
	AddCommandListener(Commands_BlockEntExploit, "ent_fire");
	
	// L4D2 uses this for confogl.
	if ( SMAC_GetGameType() != Game_L4D2 )
	{
		AddCommandListener(Commands_BlockEntExploit, "give");
	}
	
	if ( GuessSDKVersion() != SOURCE_SDK_EPISODE2VALVE )
	{
		HookEvent("player_disconnect", Commands_EventDisconnect, EventHookMode_Pre);
	}
	
	// Init...
	g_hBlockedCmds = CreateTrie();
	g_hIgnoredCmds = CreateTrie();

	//- Blocked Commands -// Note: True sets them to ban, false does not.
	SetTrieValue(g_hBlockedCmds, "ai_test_los", 			false);
	SetTrieValue(g_hBlockedCmds, "changelevel", 			true);
	SetTrieValue(g_hBlockedCmds, "cl_fullupdate",			false);
	SetTrieValue(g_hBlockedCmds, "dbghist_addline", 		false);
	SetTrieValue(g_hBlockedCmds, "dbghist_dump", 			false);
	SetTrieValue(g_hBlockedCmds, "drawcross",			false);
	SetTrieValue(g_hBlockedCmds, "drawline",			false);
	SetTrieValue(g_hBlockedCmds, "dump_entity_sizes", 		false);
	SetTrieValue(g_hBlockedCmds, "dump_globals", 			false);
	SetTrieValue(g_hBlockedCmds, "dump_panels", 			false);
	SetTrieValue(g_hBlockedCmds, "dump_terrain", 			false);
	SetTrieValue(g_hBlockedCmds, "dumpcountedstrings", 		false);
	SetTrieValue(g_hBlockedCmds, "dumpentityfactories", 		false);
	SetTrieValue(g_hBlockedCmds, "dumpeventqueue", 			false);
	SetTrieValue(g_hBlockedCmds, "dumpgamestringtable", 		false);
	SetTrieValue(g_hBlockedCmds, "editdemo", 			false);
	SetTrieValue(g_hBlockedCmds, "endround", 			false);
	SetTrieValue(g_hBlockedCmds, "groundlist", 			false);
	SetTrieValue(g_hBlockedCmds, "listdeaths", 			false);
	SetTrieValue(g_hBlockedCmds, "listmodels", 			false);
	SetTrieValue(g_hBlockedCmds, "map_showspawnpoints",		false);
	SetTrieValue(g_hBlockedCmds, "mem_dump", 			false);
	SetTrieValue(g_hBlockedCmds, "mp_dump_timers", 			false);
	SetTrieValue(g_hBlockedCmds, "npc_ammo_deplete", 		false);
	SetTrieValue(g_hBlockedCmds, "npc_heal", 			false);
	SetTrieValue(g_hBlockedCmds, "npc_speakall", 			false);
	SetTrieValue(g_hBlockedCmds, "npc_thinknow", 			false);
	SetTrieValue(g_hBlockedCmds, "physics_budget",			false);
	SetTrieValue(g_hBlockedCmds, "physics_debug_entity", 		false);
	SetTrieValue(g_hBlockedCmds, "physics_highlight_active", 	false);
	SetTrieValue(g_hBlockedCmds, "physics_report_active", 		false);
	SetTrieValue(g_hBlockedCmds, "physics_select", 			false);
	SetTrieValue(g_hBlockedCmds, "q_sndrcn", 			true);
	SetTrieValue(g_hBlockedCmds, "report_entities", 		false);
	SetTrieValue(g_hBlockedCmds, "report_touchlinks", 		false);
	SetTrieValue(g_hBlockedCmds, "report_simthinklist", 		false);
	SetTrieValue(g_hBlockedCmds, "respawn_entities",		false);
	SetTrieValue(g_hBlockedCmds, "rr_reloadresponsesystems", 	false);
	SetTrieValue(g_hBlockedCmds, "scene_flush", 			false);
	SetTrieValue(g_hBlockedCmds, "send_me_rcon", 			true);
	SetTrieValue(g_hBlockedCmds, "snd_digital_surround",		false);
	SetTrieValue(g_hBlockedCmds, "snd_restart", 			false);
	SetTrieValue(g_hBlockedCmds, "soundlist", 			false);
	SetTrieValue(g_hBlockedCmds, "soundscape_flush", 		false);
	SetTrieValue(g_hBlockedCmds, "speed.toggle", 			true);
	SetTrieValue(g_hBlockedCmds, "sv_benchmark_force_start", 	false);
	SetTrieValue(g_hBlockedCmds, "sv_findsoundname", 		false);
	SetTrieValue(g_hBlockedCmds, "sv_soundemitter_filecheck", 	false);
	SetTrieValue(g_hBlockedCmds, "sv_soundemitter_flush", 		false);
	SetTrieValue(g_hBlockedCmds, "sv_soundscape_printdebuginfo", 	false);
	SetTrieValue(g_hBlockedCmds, "wc_update_entity", 		false);
	
	//- Ignored Commands -//
	switch (SMAC_GetGameType())
	{
		case Game_L4D, Game_L4D2:
		{
			SetTrieValue(g_hIgnoredCmds, "choose_closedoor", 	true);
			SetTrieValue(g_hIgnoredCmds, "choose_opendoor",		true);
		}
		
		case Game_ND:
		{
			SetTrieValue(g_hIgnoredCmds, "bitcmd", 	true);
			SetTrieValue(g_hIgnoredCmds, "sg", 		true);
		}
	}

	SetTrieValue(g_hIgnoredCmds, "buy",				true);
	SetTrieValue(g_hIgnoredCmds, "buyammo1",			true);
	SetTrieValue(g_hIgnoredCmds, "buyammo2",			true);
	SetTrieValue(g_hIgnoredCmds, "use",				true);
	SetTrieValue(g_hIgnoredCmds, "vmodenable",			true);
	SetTrieValue(g_hIgnoredCmds, "vban",				true);

	CreateTimer(1.0, Timer_CountReset, _, TIMER_REPEAT);
	
	AddCommandListener(Commands_CommandListener);

	RegAdminCmd("smac_addcmd",          Commands_AddCmd,           ADMFLAG_ROOT,  "Adds a command to be blocked by SMAC.");
	RegAdminCmd("smac_addignorecmd",    Commands_AddIgnoreCmd,     ADMFLAG_ROOT,  "Adds a command to ignore on command spam.");
	RegAdminCmd("smac_removecmd",       Commands_RemoveCmd,        ADMFLAG_ROOT,  "Removes a command from the block list.");
	RegAdminCmd("smac_removeignorecmd", Commands_RemoveIgnoreCmd,  ADMFLAG_ROOT,  "Remove a command to ignore.");
	
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

public Action:Commands_EventDisconnect(Handle:event, const String:name[], bool:dontBroadcast)
{
	decl String:f_sReason[512], String:f_sTemp[512], f_iLength, client;
	client = GetClientOfUserId(GetEventInt(event, "userid"));
	GetEventString(event, "reason", f_sReason, sizeof(f_sReason));
	GetEventString(event, "name", f_sTemp, sizeof(f_sTemp));
	f_iLength = strlen(f_sReason)+strlen(f_sTemp);
	GetEventString(event, "networkid", f_sTemp, sizeof(f_sTemp));
	
	f_iLength += strlen(f_sTemp);
	if ( f_iLength > 235 )
	{
		if ( IS_CLIENT(client) && IsClientConnected(client) )
		{
			SMAC_LogAction(client, "submitted a bad disconnect reason, length %d, \"%s\"", f_iLength, f_sReason);
		}
		else
		{
			SMAC_Log("Bad disconnect reason, length %d, \"%s\"", f_iLength, f_sReason);
		}
		
		SetEventString(event, "reason", "Bad disconnect message");
		return Plugin_Continue;
	}
	
	f_iLength = strlen(f_sReason);
	for (new i = 0; i < f_iLength; i++)
	{
		if ( f_sReason[i] < 32 && f_sReason[i] != '\n' )
		{
			if ( IS_CLIENT(client) && IsClientConnected(client) )
			{
				SMAC_LogAction(client, "submitted a bad disconnect reason, \"%s\" len = %d. Possible corruption or attack.", f_sReason, f_iLength);
			}
			else
			{
				SMAC_Log("Bad disconnect reason, \"%s\" len = %d. Possible corruption or attack.", f_sReason, f_iLength);
			}
			
			SetEventString(event, "reason", "Bad disconnect message");
			return Plugin_Continue;
		}
	}
	
	return Plugin_Continue;
}

//- Admin Commands -//

public Action:Commands_AddCmd(client, args)
{
	if ( args != 2 )
	{
		ReplyToCommand(client, "Usage: smac_addcmd <command name> <ban (1 or 0)>");
		return Plugin_Handled;
	}

	decl String:f_sCmdName[64], String:f_sTemp[8], bool:f_bBan;
	GetCmdArg(1, f_sCmdName, sizeof(f_sCmdName));

	GetCmdArg(2, f_sTemp, sizeof(f_sTemp));
	if ( StringToInt(f_sTemp) != 0 || StrEqual(f_sTemp, "ban") || StrEqual(f_sTemp, "yes") || StrEqual(f_sTemp, "true") )
		f_bBan = true;
	else
		f_bBan = false;

	if ( SetTrieValue(g_hBlockedCmds, f_sCmdName, f_bBan) )
		ReplyToCommand(client, "You have successfully added %s to the command block list.", f_sCmdName);
	else
		ReplyToCommand(client, "%s already exists in the command block list.", f_sCmdName);
	return Plugin_Handled;
}

public Action:Commands_AddIgnoreCmd(client, args)
{
	if ( args != 1 )
	{
		ReplyToCommand(client, "Usage: smac_addignorecmd <command name>");
		return Plugin_Handled;
	}

	decl String:f_sCmdName[64];

	GetCmdArg(1, f_sCmdName, sizeof(f_sCmdName));

	if ( SetTrieValue(g_hIgnoredCmds, f_sCmdName, true) )
		ReplyToCommand(client, "You have successfully added %s to the command ignore list.", f_sCmdName);
	else
		ReplyToCommand(client, "%s already exists in the command ignore list.", f_sCmdName);
	return Plugin_Handled;
}

public Action:Commands_RemoveCmd(client, args)
{
	if ( args != 1 )
	{
		ReplyToCommand(client, "Usage: smac_removecmd <command name>");
		return Plugin_Handled;
	}

	decl String:f_sCmdName[64];
	GetCmdArg(1, f_sCmdName, sizeof(f_sCmdName));

	if ( RemoveFromTrie(g_hBlockedCmds, f_sCmdName) )
		ReplyToCommand(client, "You have successfully removed %s from the command block list.", f_sCmdName);
	else
		ReplyToCommand(client, "%s is not in the command block list.", f_sCmdName);
	return Plugin_Handled;
}

public Action:Commands_RemoveIgnoreCmd(client, args)
{
	if ( args != 1 )
	{
		ReplyToCommand(client, "Usage: smac_removeignorecmd <command name>");
		return Plugin_Handled;
	}

	decl String:f_sCmdName[64];
	GetCmdArg(1, f_sCmdName, sizeof(f_sCmdName));

	if ( RemoveFromTrie(g_hIgnoredCmds, f_sCmdName) )
		ReplyToCommand(client, "You have successfully removed %s from the command ignore list.", f_sCmdName);
	else
		ReplyToCommand(client, "%s is not in the command ignore list.", f_sCmdName);
	return Plugin_Handled;
}

//- Console Commands -//

public Action:Commands_BlockExploit(client, const String:command[], args)
{
	if ( args > 0 )
	{
		decl String:f_sArg[64];
		GetCmdArg(1, f_sArg, sizeof(f_sArg));
		if ( StrEqual(f_sArg, "rcon_password") )
		{
			decl String:f_sCmdString[256];
			GetCmdArgString(f_sCmdString, sizeof(f_sCmdString));
			SMAC_PrintAdminNotice("%N was banned for command usage violation of command: sm_menu %s", client, f_sCmdString);
			SMAC_LogAction(client, "was banned for command usage violation of command: sm_menu %s", f_sCmdString);
			SMAC_Ban(client, "Exploit violation");
			return Plugin_Stop;
		}
	}
	return Plugin_Continue;
}

public Action:Commands_FilterSay(client, const String:command[], args)
{
	if (!IS_CLIENT(client))
		return Plugin_Continue;

	new iSpaceNum;
	decl String:f_sMsg[256], f_iLen, String:f_cChar;
	GetCmdArgString(f_sMsg, sizeof(f_sMsg));
	f_iLen = strlen(f_sMsg);
	for(new i=0;i<f_iLen;i++)
	{
		f_cChar = f_sMsg[i];
		
		if ( f_cChar == ' ' )
		{
			if ( iSpaceNum++ >= 64 )
			{
				PrintToChat(client, "%t", "SMAC_SayBlock");
				return Plugin_Stop;
			}
		}
			
		if ( f_cChar < 32 && !IsCharMB(f_cChar) )
		{
			PrintToChat(client, "%t", "SMAC_SayBlock");
			return Plugin_Stop;
		}
	}
	return Plugin_Continue;
}

public Action:Commands_BlockEntExploit(client, const String:command[], args)
{
	if ( !IS_CLIENT(client) )
		return Plugin_Continue;
	
	if ( !IsClientInGame(client) )
		return Plugin_Stop;
	
	decl String:f_sCmd[512];
	GetCmdArgString(f_sCmd, sizeof(f_sCmd));
	if ( strlen(f_sCmd) > 500 )
		return Plugin_Stop; // Too long to process.
	if ( StrContains(f_sCmd, "point_servercommand") != -1 	|| StrContains(f_sCmd, "point_clientcommand") != -1 
	  || StrContains(f_sCmd, "logic_timer") != -1 	   	|| StrContains(f_sCmd, "quit") != -1
	  || StrContains(f_sCmd, "sm") != -1 		   	|| StrContains(f_sCmd, "quti") != -1 
	  || StrContains(f_sCmd, "restart") != -1 		|| StrContains(f_sCmd, "alias") != -1
	  || StrContains(f_sCmd, "admin") != -1 		|| StrContains(f_sCmd, "ma_") != -1 
	  || StrContains(f_sCmd, "rcon") != -1 			|| StrContains(f_sCmd, "sv_") != -1 
	  || StrContains(f_sCmd, "mp_") != -1 			|| StrContains(f_sCmd, "meta") != -1 
	  || StrContains(f_sCmd, "taketimer") != -1 		|| StrContains(f_sCmd, "logic_relay") != -1 
	  || StrContains(f_sCmd, "logic_auto") != -1 		|| StrContains(f_sCmd, "logic_autosave") != -1 
	  || StrContains(f_sCmd, "logic_branch") != -1 		|| StrContains(f_sCmd, "logic_case") != -1 
	  || StrContains(f_sCmd, "logic_collision_pair") != -1  || StrContains(f_sCmd, "logic_compareto") != -1 
	  || StrContains(f_sCmd, "logic_lineto") != -1 		|| StrContains(f_sCmd, "logic_measure_movement") != -1 
	  || StrContains(f_sCmd, "logic_multicompare") != -1 	|| StrContains(f_sCmd, "logic_navigation") != -1 )
	{
		return Plugin_Stop;
	}
	return Plugin_Continue;
}

public Action:Commands_CommandListener(client, const String:command[], argc)
{
	if ( !IS_CLIENT(client) || (IsClientConnected(client) && IsFakeClient(client)) )
		return Plugin_Continue;
		
	if ( !IsClientInGame(client) )
		return Plugin_Stop;

	decl bool:f_bBan, String:f_sCmd[64];
	
	strcopy(f_sCmd, sizeof(f_sCmd),	command);
	StringToLower(f_sCmd);

	// Check to see if this person is command spamming.
	if ( g_iCmdSpam && !GetTrieValue(g_hIgnoredCmds, f_sCmd, f_bBan) && ++g_iCmdCount[client] > g_iCmdSpam )
	{
		if ( !IsClientInKickQueue(client) && SMAC_CheatDetected(client) == Plugin_Continue )
		{
			decl String:f_sCmdString[128];
			GetCmdArgString(f_sCmdString, sizeof(f_sCmdString));
			SMAC_PrintAdminNotice("%N was kicked for command spamming: %s %s", client, command, f_sCmdString);
			SMAC_LogAction(client, "was kicked for command spamming: %s %s", command, f_sCmdString);
			KickClient(client, "%t", "SMAC_CommandSpamKick");
		}
		
		return Plugin_Stop;
	}

	if ( GetTrieValue(g_hBlockedCmds, f_sCmd, f_bBan) )
	{
		if ( f_bBan && SMAC_CheatDetected(client) == Plugin_Continue )
		{
			decl String:f_sCmdString[256];
			GetCmdArgString(f_sCmdString, sizeof(f_sCmdString));
			SMAC_PrintAdminNotice("%N was banned for command usage violation of command: %s %s", client, command, f_sCmdString);
			SMAC_LogAction(client, "was banned for command usage violation of command: %s %s", command, f_sCmdString);
			SMAC_Ban(client, "Command %s violation", command);
		}
		
		return Plugin_Stop;
	}

	return Plugin_Continue;
}

//- Timers -//

public Action:Timer_CountReset(Handle:timer, any:args)
{
	for (new i = 1; i <= MaxClients; i++)
	{
		g_iCmdCount[i] = 0;
	}
	
	return Plugin_Continue;
}

public OnSettingsChanged(Handle:convar, const String:oldValue[], const String:newValue[])
{
	g_iCmdSpam = GetConVarInt(convar);
}

//- Private -//

stock StringToLower(String:f_sInput[])
{
	new f_iSize = strlen(f_sInput);
	for(new i=0;i<f_iSize;i++)
		f_sInput[i] = CharToLower(f_sInput[i]);
}
