/* SwapTeam
 
Allows admins to switch people in the opposite team
This can either be done immediately, or on player death,
or - if available in the mod - on round end.
The plugin configures itself for the different mods automatically,
so there is no $mod Edition neccessary.

Changes:
1.2.4:
      * No longer requires a gamedata file (Thanks dataviruset)
1.2.3:
			* Fixed warnings on compile
			* Added sm_team which will move players to any specified team
			* Fixed a PrintToChat bug when using sm_swapteam_death
			* Fixed plugin always thinking an arena map was being played when used on TF2
			* Fixed always requiring gamedata file on games which don't even use it
			* Updated to include the latest gamedata file
1.2.2:
			* Two plugins are annoying. I figured out a way to make it one plugin again, and it works :)
1.2.1:
			* Fixed not being able to move clients to spectate on any other games other than TF2 Arena maps
1.2:
			* Fixed a small ReplyToTargetError bug
			* Fixed moving a client to spectate in TF2 arena maps. A major thanks to Rothgar and his AFK plugin
			* Fixed some warnings when compiling        
1.1:
			* Added logging support
			* Fixed a bug where it would say the admin had been swapteamed, instead of the target when using sm_swapteam
SwapTeam 1.0:
			* Changed command "teamswitch" to "sm_swapteam"
			* Changed command "teamswitch_death" to "sm_swapteam_death"
			* Changed command "teamswitch_roundend" to "sm_swapteam_d"
			* Changed command "teamswitch_spec" to "sm_spec"
			* Fixed a bug where it would move a random player if the requested client was not on the server. */

#pragma semicolon 1

#include <sourcemod>
#include <sdktools>
#include <sdkhooks>

#undef REQUIRE_PLUGIN
#include <adminmenu>

#undef REQUIRE_EXTENSIONS
#include <cstrike>
#define REQUIRE_EXTENSIONS


// Team indices
#define TEAM_1    2
#define TEAM_2    3
#define TEAM_SPEC 1
#define SPECTATOR_TEAM 0


#define SWAPTEAM_VERSION	"1.2.4"
#define TEAMSWITCH_ADMINFLAG	ADMFLAG_KICK
#define TEAMSWITCH_ARRAY_SIZE 64
new bool:colour = true;
new bool:g_TF2Arena = false;
new bool:TF2 = false;

public Plugin:myinfo = {
	name = "SwapTeam",
	author = "MistaGee Fixed by Rogue",
	description = "Switch people to spec or the other team immediately, at round end, on death",
	version = SWAPTEAM_VERSION,
	url = "http://www.sourcemod.net/"
};

new	Handle:hAdminMenu = INVALID_HANDLE,
bool:onRoundEndPossible = false,
bool:cstrikeExtAvail = false,
String:teamName1[2],
String:teamName2[3],
bool:switchOnRoundEnd[TEAMSWITCH_ARRAY_SIZE],
bool:switchOnDeath[TEAMSWITCH_ARRAY_SIZE];

enum TeamSwitchEvent
{
	SwapTeamEvent_Immediately = 0,
	SwapTeamEvent_OnDeath = 1,
	SwapTeamEvent_OnRoundEnd = 2,
	SwapTeamEvent_ToSpec = 3
};

public OnPluginStart()
{
	CreateConVar("swapteam_version", SWAPTEAM_VERSION, "SwapTeam Version", FCVAR_PLUGIN|FCVAR_SPONLY|FCVAR_REPLICATED|FCVAR_NOTIFY);
	
	RegAdminCmd("sm_swapteam", Command_SwitchImmed, TEAMSWITCH_ADMINFLAG);
	RegAdminCmd("sm_swapteam_death", Command_SwitchDeath, TEAMSWITCH_ADMINFLAG);
	RegAdminCmd("sm_swapteam_d", Command_SwitchRend, TEAMSWITCH_ADMINFLAG);
	RegAdminCmd("sm_spec", Command_SwitchSpec, TEAMSWITCH_ADMINFLAG);
	RegAdminCmd("sm_team", Command_Team, TEAMSWITCH_ADMINFLAG);
	
	HookEvent("player_death", Event_PlayerDeath);
	
	// Hook game specific round end events - if none found, round end is not shown in menu
	decl String:theFolder[40];
	GetGameFolderName(theFolder, sizeof(theFolder));
	
	PrintToServer("[SM] Hooking round end events for game: %s", theFolder);
	
	if(StrEqual(theFolder, "dod"))
	{
		HookEvent("dod_round_win", Event_RoundEnd, EventHookMode_PostNoCopy);
		onRoundEndPossible = true;
	}
	else if(StrEqual(theFolder, "tf"))
	{
		decl String:mapname[128];
		GetCurrentMap(mapname, sizeof(mapname));
		HookEvent("teamplay_round_win",	Event_RoundEnd, EventHookMode_PostNoCopy);
		HookEvent("teamplay_round_stalemate",	Event_RoundEnd, EventHookMode_PostNoCopy);
		onRoundEndPossible = true;
		TF2 = true;
		if (strncmp(mapname, "arena_", 6, false) == 0)
		{
			g_TF2Arena = true;
		}
	}
	else if(StrEqual(theFolder, "cstrike"))
	{
		HookEvent("round_end", Event_RoundEnd, EventHookMode_PostNoCopy);
		onRoundEndPossible = true;
	}
	
	new Handle:topmenu;
	if(LibraryExists("adminmenu") && (( topmenu = GetAdminTopMenu()) != INVALID_HANDLE))
	{
		OnAdminMenuReady(topmenu);
	}
	
	// Check for cstrike extension - if available, CS_SwitchTeam is used
	cstrikeExtAvail = (GetExtensionFileStatus("game.cstrike.ext") == 1);
	
	LoadTranslations("common.phrases");
	LoadTranslations("swapteam.phrases");
}

public OnMapStart()
{
	GetTeamName(2, teamName1, sizeof(teamName1));
	GetTeamName(3, teamName2, sizeof(teamName2));
	
	PrintToServer(
	"[SM] Team Names: %s %s - OnRoundEnd available: %s",
	teamName1, teamName2,
	(onRoundEndPossible ? "yes" : "no")
	);
}

public Action:Command_Team(client, args)
{
	if (args < 2)
	{
		if (cstrikeExtAvail)
		{
			ReplyToCommand(client, "[SM] Usage: sm_team <#userid|name> <1 - Spectator | 2 - T | 3 - CT>");
		}
		else if (TF2)
		{
			ReplyToCommand(client, "[SM] Usage: sm_team <#userid|name> <1 - Spectator | 2 - RED | 3 - BLU>");
		}
		else
		{
			ReplyToCommand(client, "[SM] Usage: sm_team <#userid|name> <1 - Spectator | 2 - Team 1 | 3 - Team 2>");
		}
		return Plugin_Handled;
	}
	
	decl String:arg[65];
	decl String:teamarg[65];
	decl teamargBuffer;
	GetCmdArg(1, arg, sizeof(arg));
	GetCmdArg(2, teamarg, sizeof(teamarg));
	teamargBuffer = StringToInt(teamarg);
	
	decl String:target_name[MAX_TARGET_LENGTH];
	decl target_list[MAXPLAYERS], target_count, bool:tn_is_ml;
	
	if ((target_count = ProcessTargetString(
	arg,
	client,
	target_list,
	MAXPLAYERS,
	COMMAND_FILTER_NO_MULTI,
	target_name,
	sizeof(target_name),
	tn_is_ml)) <= 0)
	{
		ReplyToTargetError(client, target_count);
		return Plugin_Handled;
	}
	
	for (new i = 0; i < target_count; i++)
	{
		if (teamargBuffer == 0)
		{
			if (g_TF2Arena)
			{
				PerformSwitchToSpec(target_list[i], true);
			}
			else
			{			
				ChangeClientTeam(target_list[i], TEAM_SPEC);
			}
			
			if (tn_is_ml)
			{
				ShowActivity2(client, "[SM] ", "%t", "Moved to spec", target_name);
			}
			else
			{
				ShowActivity2(client, "[SM] ", "%t", "Moved to spec", "_s", target_name);
			}
		}
		else if (teamargBuffer == 1)
		{
			if (g_TF2Arena)
			{
				PerformSwitchToSpec(target_list[i], true);
			}
			else
			{			
				ChangeClientTeam(target_list[i], TEAM_SPEC);
			}
			
			if (tn_is_ml)
			{
				ShowActivity2(client, "[SM] ", "%t", "Moved to spec", target_name);
			}
			else
			{
				ShowActivity2(client, "[SM] ", "%t", "Moved to spec", "_s", target_name);
			}
		}
		else if (teamargBuffer == 2)
		{
			ChangeClientTeam(target_list[i], TEAM_1);
			
			if (tn_is_ml)
			{
				ShowActivity2(client, "[SM] ", "%t", "Moved to team1", target_name);
			}
			else
			{
				ShowActivity2(client, "[SM] ", "%t", "Moved to team1", "_s", target_name);
			}
		}
		else if (teamargBuffer == 3)
		{
			ChangeClientTeam(target_list[i], TEAM_2);
			if (tn_is_ml)
			{
				ShowActivity2(client, "[SM] ", "%t", "Moved to team2", target_name);
			}
			else
			{
				ShowActivity2(client, "[SM] ", "%t", "Moved to team2", "_s", target_name);
			}
		}
	}
	
	return Plugin_Handled;
}

public Action:Command_SwitchImmed(client, args)
{
	if(args != 1)
	{
		ReplyToCommand(client, "[SM] %t", "ts usage immediately");
		return Plugin_Handled;
	}
	
	// Try to find a target player
	decl String:targetArg[50];
	GetCmdArg(1, targetArg, sizeof(targetArg));
	
	decl String:name[64];
	
	new target = FindTarget(client, targetArg);
	if(target != -1)
	{
		GetClientName(client, name, sizeof(name));
		PerformSwitch(target);
		LogAction(client, target, "\"%L\" swapteamed \"%L\"", client, target);
	}
	{
		if (target<=0)
			return Plugin_Handled;
	}
	{
		ReplyToTargetError(client, Command_SwitchImmed);
		return Plugin_Handled;
	}
}

public Action:Command_SwitchDeath(client, args)
{
	if(args != 1)
	{
		ReplyToCommand(client, "[SM] %t", "ts usage death");
		return Plugin_Handled;
	}
	
	// Try to find a target player
	decl String:targetArg[50];
	GetCmdArg(1, targetArg, sizeof(targetArg));
	
	decl String:name[64];
	new target = FindTarget(client, targetArg);
	if(target != -1)
	{
		switchOnDeath[target] = !switchOnDeath[target];
		GetClientName(target, name, sizeof(name));
		if(switchOnDeath[target])
		{
			if (target<=0)
				return Plugin_Handled;

			if(colour)
			{ 
				PrintToChatAll("\x01[SM] \x03%s \x01%t", name, "ts will be switch to opposite team on death");
				LogAction(client, target, "\"%L\" swapteamed (death) \"%L\"", client, target);
			}
			else
			{ 
				PrintToChatAll("[SM] %s %t", name, "ts will be switch to opposite team on death");
			} 
		}
		else
		{ 
			if(colour)
			{ 
				PrintToChatAll("\x01[SM] \x03%s \x01%t", name, "ts will not be switch to opposite team on death");
			}
			else
			{ 
				PrintToChatAll("[SM] %s %t", name, "ts will not be switch to opposite team on death");
			} 
		}
	}
	{
		ReplyToTargetError(client, Command_SwitchDeath);
		return Plugin_Handled;
	}
}

public Action:Command_SwitchRend(client, args)
{
	if(args != 1)
	{
		ReplyToCommand(client, "[SM] %t", "ts usage roundend");
		return Plugin_Handled;
	}
	
	if(!onRoundEndPossible)
	{
		ReplyToCommand(client, "[SM] %t", "ts usage roundend error");
		return Plugin_Handled;
	}
	
	// Try to find a target player
	decl String:targetArg[50];
	GetCmdArg(1, targetArg, sizeof(targetArg));
	
	new target = FindTarget(client, targetArg);
	
	if(target != -1)
	{
		decl String:name[64];
		switchOnRoundEnd[target] = !switchOnRoundEnd[target];
		GetClientName(target, name, sizeof(name));
		{
			if (target<=0)
				return Plugin_Handled;
		}
		if(switchOnRoundEnd[target])
		{ 
			if(colour)
			{
				PrintToChatAll("\x01[SM] \x03%s \x01%t", name, "ts will be switch to opposite team on rounend");
				LogAction(client, target, "\"%L\" swapteamed (round end) \"%L\"", client, target);
			}
			else
			{
				PrintToChatAll("[SM] %s %t", name, "ts will be switch to opposite team on rounend");
			} 
		}
		else
		{ 
			if(colour)
			{
				PrintToChatAll("\x01[SM] \x03%s \x01%t", name, "ts will not be switch to opposite team on rounend");
			}
			else
			{
				PrintToChatAll("[SM] %s %t", name, "ts will not be switch to opposite team on rounend");
			} 
		}
	}
	{
		ReplyToTargetError(client, Command_SwitchRend);
		return Plugin_Handled;
	}
}

public Action:Command_SwitchSpec(client, args)
{
	if(args != 1)
	{
		ReplyToCommand(client, "[SM] %t", "ts usage spec");
		return Plugin_Handled;
	}
	
	// Try to find a target player
	decl String:targetArg[50];
	GetCmdArg(1, targetArg, sizeof(targetArg));
	
	decl String:name[64];
	
	new target = FindTarget(client, targetArg);
	if(target != -1)
	{
		GetClientName(target, name, sizeof(name));
		PerformSwitchToSpec(target, true);
	}
	{
		if (target<=0)
			return Plugin_Handled;
	}
	if(colour)
	{
		PrintToChatAll("\x01[SM] \x01%t \x03%s \x01%t", "ts admin switch", name, "ts to spectators");
		LogAction(client, target, "\"%L\" teamswitched (to spec) \"%L\"", client, target);
	}
	else
	{
		PrintToChatAll("[SM] %t %s %t", "ts admin switch", name, "ts to spectators");
	}
	{
		ReplyToTargetError(client, Command_SwitchSpec);
		return Plugin_Handled;
	}
}

public Event_PlayerDeath(Handle:event, const String:name[], bool:dontBroadcast)
{
	new victim = GetClientOfUserId(GetEventInt(event, "userid"));
	
	if(switchOnDeath[victim])
	{
		PerformTimedSwitch(victim);
		switchOnDeath[victim] = false;
	}
}

public Event_RoundEnd(Handle:event, const String:name[], bool:dontBroadcast)
{
	if(!onRoundEndPossible)
		return;
	
	for(new i = 0; i < TEAMSWITCH_ARRAY_SIZE; i++)
	{
		if(switchOnRoundEnd[i])
		{
			PerformTimedSwitch(i);
			switchOnRoundEnd[i] = false;
		}
	}
}


/******************************************************************************************
*                                   ADMIN MENU HANDLERS                                  *
******************************************************************************************/

public OnLibraryRemoved(const String:name[])
{
	if(StrEqual(name, "adminmenu"))
	{
		hAdminMenu = INVALID_HANDLE;
	}
}

public OnAdminMenuReady(Handle:topmenu)
{
	// ?????????? ?????? ???? ??????
	if(topmenu == hAdminMenu)
	{
		return;
	}
	hAdminMenu = topmenu;
	
	// Now add stuff to the menu: My very own category *yay*
	new TopMenuObject:menu_category = AddToTopMenu(
	hAdminMenu,		// Menu
	"ts_commands",		// Name
	TopMenuObject_Category,	// Type
	Handle_Category,	// Callback
	INVALID_TOPMENUOBJECT	// Parent
	);
	
	if(menu_category == INVALID_TOPMENUOBJECT)
	{
		// Error... lame...
		return;
	}
	
	// Now add items to it
	AddToTopMenu(
	hAdminMenu,			// Menu
	"ts_immed",			// Name
	TopMenuObject_Item,		// Type
	Handle_ModeImmed,		// Callback
	menu_category,			// Parent
	"ts_immed",			// cmdName
	TEAMSWITCH_ADMINFLAG		// Admin flag
	);
	
	AddToTopMenu(
	hAdminMenu,			// Menu
	"ts_death",			// Name
	TopMenuObject_Item,		// Type
	Handle_ModeDeath,		// Callback
	menu_category,			// Parent
	"ts_death",			// cmdName
	TEAMSWITCH_ADMINFLAG		// Admin flag
	);
	
	if(onRoundEndPossible)
	{
		AddToTopMenu(
		hAdminMenu,			// Menu
		"ts_rend",			// Name
		TopMenuObject_Item,		// Type
		Handle_ModeRend,		// Callback
		menu_category,			// Parent
		"ts_rend",			// cmdName
		TEAMSWITCH_ADMINFLAG		// Admin flag
		);
	}
	
	AddToTopMenu(
	hAdminMenu,			// Menu
	"ts_spec",			// Name
	TopMenuObject_Item,		// Type
	Handle_ModeSpec,		// Callback
	menu_category,			// Parent
	"ts_spec",			// cmdName
	TEAMSWITCH_ADMINFLAG		// Admin flag
	);
	
}

public Handle_Category(Handle:topmenu, TopMenuAction:action, TopMenuObject:object_id, param, String:buffer[], maxlength)
{
	switch(action)
	{
		case TopMenuAction_DisplayTitle:
		Format(buffer, maxlength, "%t", "ts when");
		case TopMenuAction_DisplayOption:
		Format(buffer, maxlength, "%t", "ts commands");
	}
}

public Handle_ModeImmed(Handle:topmenu, TopMenuAction:action, TopMenuObject:object_id, param, String:buffer[], maxlength)
{
	if (action == TopMenuAction_DisplayOption)
	{
		Format(buffer, maxlength, "%t", "ts immediately");
	}
	else if(action == TopMenuAction_SelectOption)
	{
		ShowPlayerSelectionMenu(param, SwapTeamEvent_Immediately);
	}
}

public Handle_ModeDeath(Handle:topmenu, TopMenuAction:action, TopMenuObject:object_id, param, String:buffer[], maxlength)
{
	if (action == TopMenuAction_DisplayOption)
	{
		Format(buffer, maxlength, "%t", "ts on death");
	}
	else if(action == TopMenuAction_SelectOption)
	{
		ShowPlayerSelectionMenu(param, SwapTeamEvent_OnDeath);
	}
}

public Handle_ModeRend(Handle:topmenu, TopMenuAction:action, TopMenuObject:object_id, param, String:buffer[], maxlength)
{
	if (action == TopMenuAction_DisplayOption)
	{
		Format(buffer, maxlength, "%t", "ts on round end");
	}
	else if(action == TopMenuAction_SelectOption)
	{
		ShowPlayerSelectionMenu(param, SwapTeamEvent_OnRoundEnd);
	}
}

public Handle_ModeSpec(Handle:topmenu, TopMenuAction:action, TopMenuObject:object_id, param, String:buffer[], maxlength)
{
	if (action == TopMenuAction_DisplayOption)
	{
		Format(buffer, maxlength, "%t", "ts to spec");
	}
	else if(action == TopMenuAction_SelectOption)
	{
		ShowPlayerSelectionMenu(param, SwapTeamEvent_ToSpec);
	}
}


/******************************************************************************************
*                           PLAYER SELECTION MENU HANDLERS                               *
******************************************************************************************/

void:ShowPlayerSelectionMenu( client, TeamSwitchEvent:event, item = 0 )
{
	new Handle:playerMenu = INVALID_HANDLE;
	
	// Create Menu with the correct Handler, so I don't have to store which player chose
	// which action...
	switch(event)
	{
		case SwapTeamEvent_Immediately:
		playerMenu = CreateMenu(Handle_SwitchImmed);
		case SwapTeamEvent_OnDeath:
		playerMenu = CreateMenu(Handle_SwitchDeath);
		case SwapTeamEvent_OnRoundEnd:
		playerMenu = CreateMenu(Handle_SwitchRend);
		case SwapTeamEvent_ToSpec:
		playerMenu = CreateMenu(Handle_SwitchSpec);
	}
	
	SetMenuTitle(playerMenu, "%t", "ts choose player");
	SetMenuExitButton(playerMenu, true);
	SetMenuExitBackButton(playerMenu, true);
	
	// Now add players to it
	// I'm aware there is a function AddTargetsToMenu in the SourceMod API, but I don't
	// use that one because it does not display the team the clients are in.
	new cTeam = 0,
	mc = GetMaxClients();
	
	decl String:cName[45],
	String:buffer[50],
	String:cBuffer[5];
	
	for(new i = 1; i < mc; i++)
	{
		if(IsClientInGame(i))
		{
			cTeam = GetClientTeam(i);
			if(cTeam < 2)
				continue;
			
			GetClientName(i, cName, sizeof(cName));
			
			switch(event)
			{
				case SwapTeamEvent_Immediately,
				SwapTeamEvent_ToSpec:
				Format(buffer, sizeof(buffer),
				"[%s] %s", 
				(cTeam == 2 ? teamName1 : teamName2),
				cName
				);
				case SwapTeamEvent_OnDeath:
				{
					Format(buffer, sizeof(buffer),
					"[%s] [%s] %s",
					(switchOnDeath[i] ? 'x' : ' '),
					(cTeam == 2 ? teamName1 : teamName2),
					cName
				);
				}
				case SwapTeamEvent_OnRoundEnd:
				{
					Format(buffer, sizeof(buffer),
					"[%s] [%s] %s",
					(switchOnRoundEnd[i] ? 'x' : ' '),
					(cTeam == 2 ? teamName1 : teamName2),
					cName
				);
				}
			}
			
			IntToString(i, cBuffer, sizeof(cBuffer));
			
			AddMenuItem(playerMenu, cBuffer, buffer);
		}
	}
	
	// ????????? ???? ??? ????? ???????
	if(item == 0)
		DisplayMenu(playerMenu, client, 30);
	else	DisplayMenuAtItem(playerMenu, client, item-1, 30);
}

public Handle_SwitchImmed(Handle:playerMenu, MenuAction:action, client, target)
{
	Handle_Switch(SwapTeamEvent_Immediately, playerMenu, action, client, target);
}

public Handle_SwitchDeath(Handle:playerMenu, MenuAction:action, client, target)
{
	Handle_Switch(SwapTeamEvent_OnDeath, playerMenu, action, client, target);
}

public Handle_SwitchRend(Handle:playerMenu, MenuAction:action, client, target)
{
	Handle_Switch(SwapTeamEvent_OnRoundEnd, playerMenu, action, client, target);
}

public Handle_SwitchSpec(Handle:playerMenu, MenuAction:action, client, target)
{
	Handle_Switch(SwapTeamEvent_ToSpec, playerMenu, action, client, target);
}

void:Handle_Switch(TeamSwitchEvent:event, Handle:playerMenu, MenuAction:action, client, param)
{
	switch(action)
	{
		case MenuAction_Select:
		{
			decl String:info[5];
			GetMenuItem(playerMenu, param, info, sizeof(info));
			new target = StringToInt(info);
			
			switch(event)
			{
				case SwapTeamEvent_Immediately:
				{
					PerformSwitch(target);
					if(colour)
					{ 
						decl String:target_name[50];
						GetClientName(target, target_name, sizeof(target_name));
						PrintToChatAll("\x01[SM] \x01%t \x03%s \x01%t", "ts admin switch", target_name, "ts opposite team");
					}
					else
					{ 
						decl String:target_name[50];
						GetClientName(target, target_name, sizeof(target_name));
						PrintToChatAll("[SM] %t %s %t", "ts admin switch", target_name, "ts opposite team");
					}
				}
				case SwapTeamEvent_OnDeath:
				{
					// If alive: player must be listed in OnDeath array
					if(IsPlayerAlive(target))
					{
						// If alive, toggle status
						switchOnDeath[target] = !switchOnDeath[target];
					}
					else	// Switch right away
					PerformSwitch(target);
					if(switchOnDeath[target])
					{
						if(colour)
						{
							decl String:target_name[50];
							GetClientName( target, target_name, sizeof(target_name));
							PrintToChatAll("\x01[SM] \x03%s \x01%t", target_name, "ts will be switch to opposite team on death");
						}
						else
						{
							decl String:target_name[50];
							GetClientName(target, target_name, sizeof(target_name));
							PrintToChatAll("[SM] %s %t", target_name, "ts will be switch to opposite team on death");
						}
					}
					else
					{ 
						if(colour)
						{
							decl String:target_name[50];
							GetClientName(target, target_name, sizeof(target_name));
							PrintToChatAll("\x01[SM] \x03%s \x01%t", target_name, "ts will not be switch to opposite team on death");
						}
						else
						{
							decl String:target_name[50];
							GetClientName(target, target_name, sizeof(target_name));
							PrintToChatAll("[SM] %s %t", target_name, "ts will not be switch to opposite team on death" );
						} 
					}
				}
				case SwapTeamEvent_OnRoundEnd:
				{
					// Toggle status
					switchOnRoundEnd[target] = !switchOnRoundEnd[target];
					if(switchOnRoundEnd[target])
					{
						if(colour)
						{
							decl String:target_name[50];
							GetClientName(target, target_name, sizeof(target_name));
							PrintToChatAll("\x01[SM] \x03%s \x01%t", target_name, "ts will be switch to opposite team on rounend");
						}
						else
						{
							decl String:target_name[50];
							GetClientName(target, target_name, sizeof(target_name));
							PrintToChatAll("[SM] %s %t", target_name, "ts will be switch to opposite team on rounend");
						} 
					}
					else
					{ 
						if(colour)
						{
							decl String:target_name[50];
							GetClientName(target, target_name, sizeof(target_name));
							PrintToChatAll("\x01[SM] \x03%s \x01%t", target_name, "ts will not be switch to opposite team on rounend");
						}
						else
						{
							decl String:target_name[50];
							GetClientName(target, target_name, sizeof(target_name));
							PrintToChatAll("[SM] %s %t", target_name, "ts will not be switch to opposite team on rounend");
						} 
					}
				}
				case SwapTeamEvent_ToSpec:
				{
					PerformSwitchToSpec(target, true);
					if(colour)
					{
						decl String:target_name[50];
						GetClientName(target, target_name, sizeof(target_name));
						PrintToChatAll("\x01[SM] \x01%t \x03%s \x01%t", "ts admin switch", target_name, "ts to spectators");
					}
					else
					{
						decl String:target_name[50];
						GetClientName(target, target_name, sizeof(target_name));
						PrintToChatAll("[SM] %t %s %t", "ts admin switch", target_name, "ts to spectators");
					}
				}
			}
			// Now display the menu again
			ShowPlayerSelectionMenu(client, event, target);
		}
		
		case MenuAction_Cancel:
		// param gives us the reason why the menu was cancelled
		if(param == MenuCancel_ExitBack)
			RedisplayAdminMenu(hAdminMenu, client);
		
		case MenuAction_End:
		CloseHandle(playerMenu);
	}
}


void:PerformTimedSwitch(client)
{
	CreateTimer(0.5, Timer_TeamSwitch, client);
}

public Action:Timer_TeamSwitch(Handle:timer, any:client)
{
	if(IsClientInGame(client))
		PerformSwitch(client);
	return Plugin_Stop;
}

void:PerformSwitch(client, bool:toSpec = false)
{
	new cTeam = GetClientTeam(client),
	toTeam = (toSpec ? TEAM_SPEC : TEAM_1 + TEAM_2 - cTeam);
	
	if(cstrikeExtAvail && !toSpec)
	{
		CS_SwitchTeam(client, toTeam);
		
		if(cTeam == TEAM_2)
		{
			SetEntityModel(client, "models/player/t_leet.mdl");
		}
		else
		{
			SetEntityModel(client, "models/player/ct_sas.mdl");
		}
		
		if(GetPlayerWeaponSlot(client, CS_SLOT_C4) != -1)
		{
			new ent;
			if ((ent = GetPlayerWeaponSlot(client, CS_SLOT_C4)) != -1)
			SDKHooks_DropWeapon(client, ent);
		}
	}
	
	else	ChangeClientTeam(client, toTeam);
	
	decl String:plName[40];
	GetClientName(client, plName, sizeof(plName));
	if(colour)
	{
		PrintToChatAll("\x01[SM] \x03%s \x01%t", plName, "ts switch by admin");
	}
	else
	{
		PrintToChatAll("[SM] %s %t", plName, "ts switch by admin");
	}
}

void:PerformSwitchToSpec(client, bool:toSpec = false)
{
	new cTeam = GetClientTeam(client), toTeam = (toSpec ? TEAM_SPEC : TEAM_1 + TEAM_2 - cTeam);
	
	if(cstrikeExtAvail && !toSpec)
	{
		CS_SwitchTeam(client, toTeam);
	}
	else if (TF2)
	{
		if (g_TF2Arena)
		{
			// Arena Spectator Fix by Rothgar
			SetEntProp(client, Prop_Send, "m_nNextThinkTick", -1);
			SetEntProp(client, Prop_Send, "m_iDesiredPlayerClass", 0);
			SetEntProp(client, Prop_Send, "m_bArenaSpectator", 1);
		}
		ChangeClientTeam(client, toTeam);
	} 
	else
	{
		ChangeClientTeam(client, toTeam); 
	}
	
	decl String:plName[40];
	GetClientName(client, plName, sizeof(plName));
	if (colour)
	{
		PrintToChatAll("\x01[SM] \x03%s \x01%t", plName, "ts switch by admin");
	}
	else
	{
		PrintToChatAll("[SM] %s %t", plName, "ts switch by admin");
	}
}
