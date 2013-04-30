#if defined _smac_included
  #endinput
#endif
#define _smac_included

#include <smac_stocks>

/* Globals */
#define SMAC_VERSION	"0.8.0.4"
#define SMAC_URL		"http://forums.alliedmods.net/forumdisplay.php?f=133"
#define SMAC_MOD_ERROR	"This module will not work for this mod and should be removed."

enum GameType {
	Game_Unknown = 0,
	Game_CSS,
	Game_TF2,
	Game_DODS,
	Game_INSMOD,
	Game_L4D,
	Game_L4D2,
	Game_HL2DM,
	Game_FOF,
	Game_GMOD,
	Game_HL2CTF,
	Game_HIDDEN,
	Game_ND,
	Game_CSGO,
};

/* Natives */
native GameType:SMAC_GetGameType();
native SMAC_Log(const String:format[], any:...);
native SMAC_LogAction(client, const String:format[], any:...);
native SMAC_Ban(client, const String:reason[], any:...);
native SMAC_PrintAdminNotice(const String:format[], any:...);
native Handle:SMAC_CreateConVar(const String:name[], const String:defaultValue[], const String:description[]="", flags=0, bool:hasMin=false, Float:min=0.0, bool:hasMax=false, Float:max=0.0);
native Action:SMAC_CheatDetected(client);

/* Forwards */
forward Action:SMAC_OnCheatDetected(client, const String:module[]);


public SharedPlugin:__pl_smac = 
{
	name = "smac",
	file = "smac.smx",
#if defined REQUIRE_PLUGIN
	required = 1,
#else
	required = 0,
#endif
};

#if !defined REQUIRE_PLUGIN
public __pl_updater_SetNTVOptional()
{
	MarkNativeAsOptional("SMAC_GetGameType");
	MarkNativeAsOptional("SMAC_Log");
	MarkNativeAsOptional("SMAC_LogAction");
	MarkNativeAsOptional("SMAC_Ban");
	MarkNativeAsOptional("SMAC_PrintAdminNotice");
	MarkNativeAsOptional("SMAC_CreateConVar");
	MarkNativeAsOptional("SMAC_CheatDetected");
}
#endif
