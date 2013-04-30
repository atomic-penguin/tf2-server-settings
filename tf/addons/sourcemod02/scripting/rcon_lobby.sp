#include <sourcemod>
#include <smrcon>

public Plugin:myinfo =
{
	name = "RCON Lobby",
	author = "atomic-penguin",
	description = "Plugin to set RCON for Lobby or PUG integration",
	version = "0.0.1",
	url = "https://github.com/atomic-penguin/rcon_lobby"
};

new Handle:rcon_lobby_address = INVALID_HANDLE;
new Handle:rcon_lobby_password = INVALID_HANDLE;

public OnPluginStart()
{
	rcon_lobby_address = CreateConVar("rcon_lobby_address", "174.133.76.250", "Default IP address for matching rcon_lobby_password")
	rcon_lobby_password = CreateConVar("rcon_lobby_password", "lobby", "Default RCON password for matching rcon_lobby_address")
	AutoExecConfig(true, "plugin.rcon_lobby")
}

public Action:SMRCon_OnAuth(rconId, const String:address[], const String:password[], &bool:allow)
{
	decl String:cvar_address[32]
	GetConVarString(rcon_lobby_address, cvar_address, sizeof(cvar_address));
	decl String:cvar_password[32]
	GetConVarString(rcon_lobby_password, cvar_password, sizeof(cvar_password));

	LogToGame("[SM] rcon id %d with address %s connected", rconId, address);

	if (!strcmp(password, cvar_password) && !strcmp(address, cvar_address))
	{
			allow = true;
			return Plugin_Changed;
	}
	return Plugin_Continue;
}

public SMRCon_OnDisconnect(rconId)
{
	LogToGame("[SM] rcon id %d with disconnected", rconId);
}
