/************************************************************************
*************************************************************************
gScramble autoscramble settings
Description:
	Auto-sramble logic for the gscramble addon
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
$Id: gscramble_autoscramble.sp 163 2012-08-20 09:08:31Z brutalgoergectf@gmail.com $
$Author: brutalgoergectf@gmail.com $
$Revision: 163 $
$Date: 2012-08-20 03:08:31 -0600 (Mon, 20 Aug 2012) $
$LastChangedBy: brutalgoergectf@gmail.com $
$LastChangedDate: 2012-08-20 03:08:31 -0600 (Mon, 20 Aug 2012) $
$URL: https://tf2tmng.googlecode.com/svn/trunk/gscramble/addons/sourcemod/scripting/gscramble/gscramble_autoscramble.sp $
$Copyright: (c) Tf2Tmng 2009-2011$
*************************************************************************
*************************************************************************
*/

stock bool:ScrambleCheck()
{
	if (g_bScrambleNextRound)
	{
		return true;
	}
	
	if (!g_iLastRoundWinningTeam)
	{
		return false;
	}

	new bool:bOkayToCheck = false;
	if (g_iVoters >= GetConVarInt(cvar_MinAutoPlayers))
	{
		if (g_RoundState == bonusRound)
		{
			g_RoundState = normal;
			if (g_bNoSequentialScramble)
			{
				if (!g_bScrambledThisRound)
				{
					bOkayToCheck = true;
				}
			}
			else
			{
				bOkayToCheck = true;
			}
		}
	}
	if (bOkayToCheck)
	{
		if (WinStreakCheck(g_iLastRoundWinningTeam) || (!g_bScrambleOverride && g_bAutoScramble && AutoScrambleCheck(g_iLastRoundWinningTeam)))
		{
			if (GetConVarBool(cvar_AutoscrambleVote))
			{
				StartScrambleVote(g_iDefMode, 15);
				return false;
			}
			else			
				return true;
		}		
	}
	return false;
}

stock bool:WinStreakCheck(winningTeam)
{
	if (g_bScrambleNextRound || !g_bWasFullRound)
		return false;
	if (GetConVarBool(cvar_AutoScrambleRoundCount) && g_iRoundTrigger == g_iCompleteRounds)
	{
		PrintToChatAll("\x01\x04[SM]\x01 %t", "RoundMessage");
		LogAction(0, -1, "Rount limit reached");
		return true;
	}
	if (!GetConVarBool(cvar_AutoScrambleWinStreak))
		return false;
	if (winningTeam == TEAM_RED)
	{
		if (g_aTeams[iBluWins] >= 1)
			g_aTeams[iBluWins] = 0;	
		g_aTeams[iRedWins]++;
		if (g_aTeams[iRedWins] >= GetConVarInt(cvar_AutoScrambleWinStreak))
		{
			PrintToChatAll("\x01\x04[SM]\x01 %t", "RedStreak");
			LogAction(0, -1, "Red win limit reached");
			return true;
		}
	}
	if (winningTeam == TEAM_BLUE)
	{
		if (g_aTeams[iRedWins] >= 1)
			g_aTeams[iRedWins] = 0;
		g_aTeams[iBluWins]++;
		if (g_aTeams[iBluWins] >= GetConVarInt(cvar_AutoScrambleWinStreak))
		{
			PrintToChatAll("\x01\x04[SM]\x01 %t", "BluStreak");
			LogAction(0, -1, "Blu win limit reached");
			return true;
		}
	}
	return false;
}

stock StartScrambleDelay(Float:delay = 5.0, bool:respawn = false, e_ScrambleModes:mode = invalid)
{
	if (g_hScrambleDelay != INVALID_HANDLE)
	{
		KillTimer(g_hScrambleDelay);
		g_hScrambleDelay = INVALID_HANDLE;
	}
	if (mode == invalid)
		mode = e_ScrambleModes:GetConVarInt(cvar_SortMode);
	
	new Handle:data;
	g_hScrambleDelay = CreateDataTimer(delay, timer_ScrambleDelay, data, TIMER_FLAG_NO_MAPCHANGE|TIMER_DATA_HNDL_CLOSE );
	WritePackCell(data, respawn);
	WritePackCell(data, _:mode);
	if (delay == 0.0)
		delay = 1.0;	
	if (delay >= 2.0)
	{
		PrintToChatAll("\x01\x04[SM]\x01 %t", "ScrambleDelay", RoundFloat(delay));
		if (g_RoundState != bonusRound)
		{	
			EmitSoundToAll(EVEN_SOUND, SOUND_FROM_PLAYER, SNDCHAN_AUTO, SNDLEVEL_NORMAL);
			CreateTimer(1.7, TimerStopSound);
		}
	}
}

public Action:timer_AfterScramble(Handle:timer, any:spawn)
{
	
	new iEnt = -1;
	while ((iEnt = FindEntityByClassname(iEnt, "tf_ammo_pack")) != -1)
		AcceptEntityInput(iEnt, "Kill");
	TF2_RemoveRagdolls();
	
	if (spawn)
	{
		for (new i = 1; i <= MaxClients; i++)
		{
			if (IsClientInGame(i) && IsValidTeam(i))
			{
				if (!IsPlayerAlive(i))
				{
					TF2_RespawnPlayer(i);
				}
				if (TF2_GetPlayerClass(i) == TFClass_Unknown)
				{
					TF2_SetPlayerClass(i, TFClass_Scout);
				}
			}
		}
	}
	if (GetTime() - g_iRoundStartTime <= 3)
	{
		return Plugin_Handled;
	}
	if (g_RoundState == setup && GetConVarBool(cvar_SetupCharge))	
	{
		LogAction(0, -1, "Filling up medic cannons due to setting");
		for (new i= 1; i<=MaxClients; i++)
		{
			if (IsClientInGame(i) && IsValidTeam(i))
			{
				new TFClassType:class = TF2_GetPlayerClass(i);
				if (class == TFClass_Medic)
				{
					new index = GetPlayerWeaponSlot(i, 1);
					if (index)
					{
						decl String:sClass[33];
						GetEntityNetClass(index, sClass, sizeof(sClass));
						if (StrEqual(sClass, "CWeaponMedigun", true))
						{
							SetEntPropFloat(index, Prop_Send, "m_flChargeLevel", 1.0);	
						}
					}
				}		
			}
		}
	}
	return Plugin_Handled;
}

bool:AutoScrambleCheck(winningTeam)
{
	if (g_bFullRoundOnly && !g_bWasFullRound)
		return false;
	if (g_bKothMode)
	{
		if (!g_bRedCapped || !g_bBluCapped)
		{
			decl String:team[3];
			g_bRedCapped ? (team = "BLU") : (team = "RED");
			PrintToChatAll("\x01\x04[SM]\x01 %t", "NoCapMessage", team);
			LogAction(0, -1, "%s did not cap a point on KOTH", team);
			return true;
		}
	}
	new totalFrags = g_aTeams[iRedFrags] + g_aTeams[iBluFrags],
		losingTeam = winningTeam == TEAM_RED ? TEAM_BLUE : TEAM_RED,
		dominationDiffVar = GetConVarInt(cvar_DominationDiff);
	if (dominationDiffVar && totalFrags > 20)
	{
		new winningDoms = TF2_GetTeamDominations(winningTeam),
			losingDoms = TF2_GetTeamDominations(losingTeam);
		if (winningDoms > losingDoms)
		{
			new teamDominationDiff = RoundFloat(FloatAbs(float(winningDoms) - float(losingDoms)));
			if (teamDominationDiff >= dominationDiffVar)
			{
				LogAction(0, -1, "domination difference detected");
				PrintToChatAll("\x01\x04[SM]\x01 %t", "DominationMessage");
				return true;
			}	
		}
	}
	new Float:iDiffVar = GetConVarFloat(cvar_AvgDiff);
	if (totalFrags > 20 && iDiffVar > 0.0 && GetAvgScoreDifference(winningTeam) >= iDiffVar)
	{
		LogAction(0, -1, "Average score diff detected");
		PrintToChatAll("\x01\x04[SM]\x01 %t", "RatioMessage");
		return true;
	}
	new winningFrags = winningTeam == TEAM_RED ? g_aTeams[iRedFrags] : g_aTeams[iBluFrags],
		losingFrags	= winningTeam == TEAM_RED ? g_aTeams[iBluFrags] : g_aTeams[iRedFrags],
		Float:ratio = float(winningFrags) / float(losingFrags),
		iSteamRollVar = GetConVarInt(cvar_Steamroll),
		roundTime = GetTime() - g_iRoundStartTime;
	if (iSteamRollVar && winningFrags > losingFrags && iSteamRollVar >= roundTime && ratio >= GetConVarFloat(cvar_SteamrollRatio))
	{
		new minutes = iSteamRollVar / 60;
		new seconds = iSteamRollVar % 60;
		PrintToChatAll("\x01\x04[SM]\x01 %t", "WinTime", minutes, seconds);
		LogAction(0, -1, "steam roll detected");
		return true;		
	}
	new Float:iFragRatioVar = GetConVarFloat(cvar_FragRatio);
	if (totalFrags > 20 && winningFrags > losingFrags && iFragRatioVar > 0.0)	
	{		
		if (ratio >= iFragRatioVar)
		{
			PrintToChatAll("\x01\x04[SM]\x01 %t", "FragDetection");
			LogAction(0, -1, "Frag ratio detected");
			return true;			
		}
	}
	return false;
}

public Action:Timer_ScrambleSound(Handle:timer)
{
	EmitSoundToAll(SCRAMBLE_SOUND, SOUND_FROM_PLAYER, SNDCHAN_AUTO, SNDLEVEL_NORMAL); // TEAMS ARE BEING SCRAMBLED!
	return Plugin_Handled;
}

public Action:timer_ScrambleDelay(Handle:timer, any:data)  // scramble logic
{
	g_hScrambleDelay = INVALID_HANDLE;
	g_bScrambleNextRound = false;
	g_bScrambledThisRound = true;
	ResetPack(data);
	new respawn = ReadPackCell(data),
		e_ScrambleModes:scrambleMode = e_ScrambleModes:ReadPackCell(data);
	g_aTeams[iRedWins] = 0;
	g_aTeams[iBluWins] = 0;
	g_aTeams[bImbalanced] = false;	
	if (g_bPreGameScramble)
	{
		scrambleMode = random;
	}
	else
	{
		if (gameMe_Rank <= scrambleMode <= gameMe_SkillChange && !g_bUseGameMe)
		{
			LogError("GameMe function set in CFG, but GameMe is not loaded");
			scrambleMode = randomSort;
		}
		
		if ((scrambleMode == hlxCe_Rank || scrambleMode == hlxCe_Skill) && !g_bUseHlxCe)
		{
			LogError("HLXCE function set in CFG, but HLXCE is not loaded");
			scrambleMode = randomSort;
		}
		
		if (scrambleMode == randomSort)
		{
			decl Random[14];
			new iSelection;
			for (new i; i < sizeof(Random); i++)
			{
				Random[i] = GetRandomInt(0,100);
				if (6 <= i <=10 && !g_bUseGameMe)
				{
					Random[i] = 0;
				}
				if (11 <= i <= 12 && !g_bUseHlxCe)
				{
					Random[i] = 0;
				}
			}
			for (new i; i < sizeof(Random); i++)
			{
				if (Random[i] > iSelection)
				{
					iSelection = Random[i];
				}
			}
			scrambleMode = e_ScrambleModes:iSelection;
		}
	}
	ScramblePlayers(scrambleMode);
	
	CreateTimer(1.0, Timer_ScrambleSound);
	DelayPublicVoteTriggering(true);
	new bool:spawn = false;
	if (respawn || g_bPreGameScramble)
		spawn = true;
	CreateTimer(0.1, timer_AfterScramble, spawn, TIMER_FLAG_NO_MAPCHANGE);	
	if (g_bPreGameScramble)
	{
		PrintToChatAll("\x01\x04[SM]\x01 %t", "PregameScrambled");
		g_bPreGameScramble = false;
	}
	else
		PrintToChatAll("\x01\x04[SM]\x01 %t", "Scrambled");		
	if (g_bIsTimer && g_RoundState == setup && GetConVarBool(cvar_SetupRestore))
		TF2_ResetSetup();
	return Plugin_Handled;
}

stock PerformTopSwap()
{
	g_bBlockDeath = true;
	new iTeam1 = GetTeamClientCount(TEAM_RED),
		iTeam2 = GetTeamClientCount(TEAM_BLUE),
		iSwaps = GetConVarInt(cvar_TopSwaps),
		iArray1[MaxClients][2],
		iArray2[MaxClients][2],
		iCount1,
		iCount2;
	if (iSwaps > iTeam1 || iSwaps > iTeam2)
	{
		if (iTeam1 > iTeam2)
		{
			iSwaps = iTeam2 / 2;
		}
		else
		{
			iSwaps = iTeam1 / 2;
		}
	}
	for (new i = 1; i <= MaxClients; i++)
	{
		if (IsClientInGame(i) && IsValidTarget(i, scramble))
		{
			if (GetClientTeam(i) == TEAM_RED)
			{
				iArray1[iCount1][0] = i;
				iArray1[iCount1][1] = RoundFloat(GetClientScrambleScore(i, score));
				iCount1++;
			}
			else if (GetClientTeam(i) == TEAM_BLUE)
			{
				iArray2[iCount2][0] = i;
				iArray2[iCount2][1] = RoundFloat(GetClientScrambleScore(i, score));
				iCount2++;
			}
		}
	}
	if (!iCount1 || !iCount2)
	{
		return;
	}
	SortCustom2D(iArray1, iCount1, SortIntsDesc);
	SortCustom2D(iArray2, iCount2, SortIntsDesc);
	for (new i = 0; i < iSwaps; i++)
	{		
		if (iArray1[i][0])
		{
			ChangeClientTeam(iArray1[i][0], TEAM_BLUE);
			if (!IsFakeClient(iArray1[i][0]))
			{
				PrintCenterText(iArray1[i][0], "%t", "TeamChangedOne");
			}
		}
	}
	for (new i = 0; i < iSwaps; i++)
	{
		if (iArray2[i][0])
		{
			ChangeClientTeam(iArray2[i][0], TEAM_RED);
			if (!IsFakeClient(iArray2[i][0]))
			{
				PrintCenterText(iArray2[i][0], "%t", "TeamChangedOne");
			}
		}
	}
	g_bBlockDeath = false;
	PrintScrambleStats(iSwaps*2);	
}

stock DoRandomSort(array[], count)
{
	new iRedSelections,
		iBluSelections,
		iRedValidCount,
		iBluValidCount,
		iBluCount = GetTeamClientCount(TEAM_BLUE),
		iRedCount = GetTeamClientCount(TEAM_RED),
		iTeamDiff, iLargerTeam, iAddToLarger,
		Float:fSelections = GetConVarFloat(cvar_RandomSelections);
	new aReds[count][2],
		aBlus[count][2];
	for (new i = 0; i < count; i++)
	{
		if (!array[i])
			continue;
		if (GetClientTeam(array[i]) == TEAM_RED)
		{
			aReds[iRedValidCount][0] = array[i];
			aReds[iRedValidCount][1] = 0;
			iRedValidCount++;
		}
		else
		{
			aBlus[iBluValidCount][0] = array[i];
			aBlus[iBluValidCount][1] = 0;
			iBluValidCount++;
		}
	}
	iRedSelections = RoundToFloor(FloatDiv(FloatMul(fSelections, (float(iRedCount) + float(iBluCount))), 2.0));
	iBluSelections = iRedSelections;
	if ((iTeamDiff = RoundFloat(FloatAbs(FloatSub(float(iRedCount),float(iBluCount))))) >= 2)
	{
		iLargerTeam = GetLargerTeam();
		iAddToLarger = iTeamDiff / 2;
		iLargerTeam == TEAM_RED ? (iRedSelections += iAddToLarger):(iBluSelections+=iAddToLarger);
	}
	if (iRedSelections > iRedValidCount || iBluSelections > iBluValidCount)
	{
		if (iRedValidCount > iBluValidCount)
		{
			iRedSelections = iBluValidCount;
		}
		else if (iBluValidCount > iRedValidCount)
		{
			iBluSelections = iRedValidCount;
		}
		else
		{
			iRedSelections = iRedValidCount;
			iBluSelections = iBluValidCount;
		}
		new iTestRed, iTestBlu, iTestDiff;
		iTestBlu -= iBluSelections;
		iTestBlu += iRedSelections;
		iTestRed -= iRedSelections;
		iTestRed += iBluSelections;
		iTestDiff = RoundFloat(FloatAbs(FloatSub(float(iTestRed), float(iTestBlu))));
		iTestDiff /= 2;
		if (iTestDiff >= 1)
		{
			if (iTestRed > iTestBlu)
			{
				iBluSelections -= iTestDiff;
			}
			else
			{
				iRedSelections -= iTestDiff;
			}
		}
	
	}
	SelectRandom(aReds, iRedValidCount, iRedSelections);
	SelectRandom(aBlus, iBluValidCount, iBluSelections);
	g_bBlockDeath = true;
	for (new i = 0; i < count; i++)
	{
		if (i < iBluValidCount)
		{
			if (aBlus[i][1] == 1 && aBlus[i][0])
			{
				ChangeClientTeam(aBlus[i][0], GetClientTeam(aBlus[i][0]) == TEAM_RED ? TEAM_BLUE:TEAM_RED);
				if (!IsFakeClient(aBlus[i][0]))
				{
					PrintCenterText(aBlus[i][0], "%t", "TeamChangedOne");
				}
			}
		}
		if (i < iRedValidCount)
		{
			if (aReds[i][1] == 1 && aReds[i][0])
			{
				ChangeClientTeam(aReds[i][0], GetClientTeam(aReds[i][0]) == TEAM_RED ? TEAM_BLUE:TEAM_RED);
				if (!IsFakeClient(aReds[i][0]))
				{
					PrintCenterText(aReds[i][0], "%t", "TeamChangedOne");
				}
			}
		}
	}
	g_bBlockDeath = false;
	PrintScrambleStats(iRedSelections+iBluSelections);
}

stock SelectRandom(arr[][], size, numSelectsToMake) 
{ 
	new temp[size], deselected;	 
	while(numSelectsToMake-- > 0) 
	{ 
		deselected = 0; 
		for(new i = 0; i < size; i++)
		{
			if (!arr[i][1]) 
			{
				temp[deselected++] = i;
			}
		}
		if (!deselected)
		{
			return;
		}
		new n = GetRandomInt(0, deselected - 1); 
		arr[temp[n]][1] = 1;
	}
} 

/**
Force recent spectators onto a team before certain scramble modes
*/
stock ForceSpecToTeam()
{
	if (!g_bSelectSpectators)
		return;
	new iLarger = GetLargerTeam(),
		iSwapped = 1;
	if (iLarger)
	{
		new iDiff = GetAbsValue(GetTeamClientCount(TEAM_RED), GetTeamClientCount(TEAM_BLUE));	
		if (iDiff)
		{
			for (new i = 1; i< MaxClients; i++)
			{
				if (iDiff && IsClientInGame(i) && IsValidSpectator(i))
				{
					ChangeClientTeam(i, iLarger == TEAM_RED ? TEAM_BLUE : TEAM_RED);
					TF2_SetPlayerClass(i, TFClass_Scout);
					iSwapped = i;
					iDiff--;
				}
			}
		}
		new bool:boolyBool;
		for (new i = iSwapped; i < MaxClients; i++)
		{
			if (IsClientInGame(i) && IsValidSpectator(i))
			{
				ChangeClientTeam(i, boolyBool ? TEAM_RED:TEAM_BLUE);
				TF2_SetPlayerClass(i, TFClass_Scout);
				boolyBool = !boolyBool;
			}
		}		
	}
}

Float:GetClientScrambleScore(client, e_ScrambleModes:mode)
{
	switch (mode)
	{
		case score:
		{
#if defined DEBUG
	LogToFile("gscramble.debug.txt", "GRABBING TOTAL SCORE");
#endif
			return float(TF2_GetPlayerResourceData(client, TFResource_TotalScore));
		}
		case kdRatio:		
		{
			return FloatDiv(float(g_aPlayers[client][iFrags]), float(g_aPlayers[client][iDeaths]));
		}
		case gameMe_Rank:
		{		
			return float(g_aPlayers[client][iGameMe_Rank]);
		}
		case gameMe_Skill:
		{
			return float(g_aPlayers[client][iGameMe_Skill]);
		}
		case gameMe_gRank:
		{
			return float(g_aPlayers[client][iGameMe_gRank]);
		}
		case gameMe_gSkill:
		{
			return float(g_aPlayers[client][iGameMe_gSkill]);
		}
		case gameMe_SkillChange:
		{
			if (!IsFakeClient(client))
			{
				return FloatDiv(float(g_aPlayers[client][iGameMe_SkillChange]), GetClientTime(client));
			}
		}
		case hlxCe_Rank:
		{
			return float(g_aPlayers[client][iHlxCe_Rank]);
		}
		case hlxCe_Skill:
		{
			return float(g_aPlayers[client][iHlxCe_Skill]);
		}
		case playerClass:
		{
			return float(_:TF2_GetPlayerClass(client));
		}
		default:
		{
			new Float:fScore = float(TF2_GetPlayerResourceData(client, TFResource_TotalScore));
			fScore = FloatMul(fScore, fScore);
			if (!IsFakeClient(client))
			{
				new Float:fClientTime = GetClientTime(client);
				new Float:fTime = FloatDiv(fClientTime, 60.0);
				fScore = FloatDiv(fScore, fTime);
			}
			else
			{
				fScore = GetRandomFloat(0.0, 1.0);
			}
			return fScore;
		}
	}
	return 0.0;
}

/**
helps decide how many people to swap to the team opposite the team with more
immune clients
*/
stock ScramblePlayers(e_ScrambleModes:scrambleMode)
{
	if (scrambleMode == topSwap)
	{
		ForceSpecToTeam();
		PerformTopSwap();
		BlockAllTeamChange();
		return;
	}
	new i, iCount, iRedImmune, iBluImmune, iSwaps, iTempTeam,
		bool:bToRed, iImmuneTeam, iImmuneDiff, client;
	new iValidPlayers[GetClientCount()];
	
	/**
	Start of by getting a list of the valid players and finding out who are immune
	*/
	for (i = 1; i <= MaxClients; i++)
	{
		if (IsClientInGame(i) && (IsValidTeam(i) || IsValidSpectator(i)))
		{
			if (IsValidTarget(i, scramble))
			{
				iValidPlayers[iCount] = i;
				iCount++;
			}
			else
			{
#if defined DEBUG
				LogToFile("gscramble.debug.txt", "Found a scramble immune person");
#endif
				if (GetClientTeam(i) == TEAM_RED)
					iRedImmune++;
				if (GetClientTeam(i) == TEAM_BLUE)
					iBluImmune++;
			}
		}
	}
	if (g_iLastRoundWinningTeam)
	{
		bToRed = g_iLastRoundWinningTeam == TEAM_BLUE;
	}
	else
	{
		bToRed = GetRandomInt(0,1) == 0;
	}
	/**
	handle imbalance in imune teams
	find out which team has more immune members than the other
	*/
	if ((iBluImmune || iRedImmune) && iRedImmune != iBluImmune)
	{
		if ((iImmuneDiff = (iRedImmune - iBluImmune)) > 0)
		{
			iImmuneTeam = TEAM_RED;
		}
		else
		{
			iImmuneDiff = RoundFloat(FloatAbs(float(iImmuneDiff)));
			iImmuneTeam = TEAM_BLUE;
		}
		bToRed = iImmuneTeam == TEAM_BLUE;
	}
	
	/**
	setup the swapping
	*/
	if (scrambleMode != random)
	{
		new Float:scoreArray[iCount][2];
		for (i = 0; i < iCount; i++)
		{
			scoreArray[i][0] = float(iValidPlayers[i]);
			scoreArray[i][1] = GetClientScrambleScore(iValidPlayers[i], scrambleMode);
		}
#if defined DEBUG
		// print the array bore and after sorting
		for (i = 0; i < iCount; i++)
		{
			LogToFile("gscramble.debug.txt", "%f %f", scoreArray[i][0], scoreArray[i][1]);
		}
		LogToFile("gscramble.debug.txt", "---------------------------");
#endif
		
		/** 
		now sort score descending 
		and copy the array into the integer one
		*/
		SortCustom2D(_:scoreArray, iCount, SortScoreAsc);
#if defined DEBUG
		// print the array bore and after sorting
		for (i = 0; i < iCount; i++)
		{
			LogToFile("gscramble.debug.txt", "%f %f", scoreArray[i][0], scoreArray[i][1]);
		}
		LogToFile("gscramble.debug.txt", "---------------------------\nEND\n");
#endif
		for (i = 0; i < iCount; i++)
		{
			iValidPlayers[i] = RoundFloat(scoreArray[i][0]);
		}	
	}
	
	if (scrambleMode == random)
	{
		ForceSpecToTeam();
		iCount = 0;
		for (i = 1; i <= MaxClients; i++)
		{
			if (IsClientInGame(i) && IsValidTeam(i))
			{
				if (IsValidTarget(i, scramble))
				{
					iValidPlayers[iCount] = i;
					iCount++;
				}
			}
		}
		SortIntegers(iValidPlayers, iCount, Sort_Random);
		DoRandomSort(iValidPlayers, iCount);
		BlockAllTeamChange();
		return;
	}
	g_bBlockDeath = true;
	if (iImmuneTeam)
	{
		iImmuneTeam == TEAM_RED ? (bToRed = false):(bToRed = true);
	}
	for (i = 0; i < iCount; i++)
	{
		client = iValidPlayers[i];
		iTempTeam = GetClientTeam(client);
		if (iImmuneDiff > 0)
		{
			ChangeClientTeam(client, iImmuneTeam == TEAM_RED ? TEAM_BLUE:TEAM_RED);
			iImmuneDiff--;
		}
		else
		{
			ChangeClientTeam(client, bToRed ? TEAM_RED:TEAM_BLUE);
			bToRed = !bToRed;
		}
		if (GetClientTeam(client) != iTempTeam)
		{
			iSwaps++;
			if (!IsFakeClient(client))
			{
				PrintCenterText(client, "%t", "TeamChangedOne");
			}
		}
		if (iTempTeam == 1)
		{
			TF2_SetPlayerClass(client, TFClass_Scout);
		}
	}
	g_bBlockDeath = false;
	LogMessage("Scramble changed %i client's teams", iSwaps);
	PrintScrambleStats(iSwaps);
	BlockAllTeamChange();
}

PrintScrambleStats(swaps)
{
	if (GetConVarBool(cvar_PrintScrambleStats))
	{
		new Float:fScrPercent = FloatDiv(float(swaps),float(GetClientCount(true)));
		decl String:sPercent[6];
		fScrPercent = FloatMul(fScrPercent, 100.0);
		FloatToString(fScrPercent, sPercent, sizeof(sPercent));
		PrintToChatAll("\x01\x04[SM]\x01 %t", "StatsMessage", swaps, GetClientCount(true), sPercent);	
	}
}