/************************************************************************
*************************************************************************
gScramble tf2 extras
Description:
	Snippets that make working with tf2 more fun! 
*************************************************************************
*************************************************************************

This plugin is free software: you can redistribute 
it and/or modify it under the terms of the GNU General Public License as
published by the Free Software Foundation, either version 3 of the License, or
later version. 

This plugin is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this plugin.  If not, see <http://www.gnu.org/licenses/>.
*************************************************************************
*************************************************************************
File Information
$Id: gscramble_tf2_extras.sp 163 2012-08-20 09:08:31Z brutalgoergectf@gmail.com $
$Author: brutalgoergectf@gmail.com $
$Revision: 163 $
$Date: 2012-08-20 03:08:31 -0600 (Mon, 20 Aug 2012) $
$LastChangedBy: brutalgoergectf@gmail.com $
$LastChangedDate: 2012-08-20 03:08:31 -0600 (Mon, 20 Aug 2012) $
$URL: https://tf2tmng.googlecode.com/svn/trunk/gscramble/addons/sourcemod/scripting/gscramble/gscramble_tf2_extras.sp $
$Copyright: (c) Tf2Tmng 2009-2011$
*************************************************************************
*************************************************************************
*/
public TF2_GetRoundTimeLeft(Handle:plugin, numparams)
{
	if (g_RoundState == normal)
	{
		return g_iRoundTimer;
	}
	else return 0;
}

stock bool:TF2_HasBuilding(client)
{
	if (TF2_ClientBuilding(client, "obj_*"))
		return true;
	return false;
}

stock TF2_ResetSetup()
{
	g_iTimerEnt = FindEntityByClassname(-1, "team_round_timer");
	new setupDuration = GetTime() - g_iRoundStartTime; 
	SetVariantInt(setupDuration);
	AcceptEntityInput(g_iTimerEnt, "AddTime");
	g_iRoundStartTime = GetTime();
}

stock bool:TF2_IsClientUberCharged(client)
{
	if (!IsPlayerAlive(client))
		return false;
	new TFClassType:class = TF2_GetPlayerClass(client);
	if (class == TFClass_Medic)
	{			
		new iIdx = GetPlayerWeaponSlot(client, 1);
		if (iIdx > 0)
		{
			decl String:sClass[33];
			GetEntityNetClass(iIdx, sClass, sizeof(sClass));
			if (StrEqual(sClass, "CWeaponMedigun", true))
			{
				new Float:chargeLevel = GetEntPropFloat(iIdx, Prop_Send, "m_flChargeLevel");
				if (chargeLevel >= 0.55)	
				{
					return true;
				}
			}
		}
	}
	return false;
}

stock bool:TF2_IsClientUbered(client)
{
	
	if (TF2_IsPlayerInCondition(client, TFCond_Ubercharged) || TF2_IsPlayerInCondition(client, TFCond_Kritzkrieged) || TF2_IsPlayerInCondition(client, TFCond_UberchargeFading))
		return true;
	return false;
}

stock bool:TF2_ClientBuilding(client, const String:building[])
{
	new iEnt = -1;
	while ((iEnt = FindEntityByClassname(iEnt, building)) != -1)
	{
		if (GetEntDataEnt2(iEnt, FindSendPropInfo("CBaseObject", "m_hBuilder")) == client)
			return true;
	}
	return false;
}

stock TF2_GetPlayerDominations(client)
{
	new offset = FindSendPropInfo("CTFPlayerResource", "m_iActiveDominations"),
		ent = FindEntityByClassname(-1, "tf_player_manager");
	if (ent != -1)
		return GetEntData(ent, (offset + client*4), 4);
	return 0;
}

stock TF2_GetTeamDominations(team)
{
	new dominations;
	for (new i = 1; i <= MaxClients; i++)
	{
		if (IsClientInGame(i) && GetClientTeam(i) == team)
			dominations += TF2_GetPlayerDominations(i);
	}
	return dominations;
}

stock bool:TF2_IsClientOnlyMedic(client)
{
	if (TFClassType:TF2_GetPlayerClass(client) != TFClass_Medic)
		return false;
	new clientTeam = GetClientTeam(client);
	for (new i = 1; i <= MaxClients; i++)
	{
		if (i != client && IsClientInGame(i) && GetClientTeam(i) == clientTeam && TFClassType:TF2_GetPlayerClass(i) == TFClass_Medic)
			return false;
	}
	return true;
}

public Action:UserMessageHook_Class(UserMsg:msg_id, Handle:bf, const players[], playersNum, bool:reliable, bool:init) 
{	
	new String:strMessage[50];
	BfReadString(bf, strMessage, sizeof(strMessage), true);
	if (StrContains(strMessage, "#TF_TeamsSwitched", true) != -1)
	{
		SwapPreferences();
		new oldRed = g_aTeams[iRedWins], oldBlu = g_aTeams[iBluWins];
		g_aTeams[iRedWins] = oldBlu;
		g_aTeams[iBluWins] = oldRed;
		g_iTeamIds[0] == TEAM_RED ? (g_iTeamIds[0] = TEAM_BLUE) :  (g_iTeamIds[0] = TEAM_RED);
		g_iTeamIds[1] == TEAM_RED ? (g_iTeamIds[1] = TEAM_BLUE) :  (g_iTeamIds[1] = TEAM_RED);
	}
	return Plugin_Continue;
}

stock TF2_RemoveRagdolls()
{
	new iEnt = -1;
	while ((iEnt = FindEntityByClassname(iEnt, "tf_ragdoll")) != -1)
		AcceptEntityInput(iEnt, "Kill");
}