/**
 * vim: set ts=4 :
 * =============================================================================
 * SourceMod SQL Admin Manager Plugin
 * Adds/managers admins and groups in an SQL database.
 *
 * SourceMod (C)2004-2008 AlliedModders LLC.  All rights reserved.
 * =============================================================================
 *
 * This program is free software; you can redistribute it and/or modify it under
 * the terms of the GNU General Public License, version 3.0, as published by the
 * Free Software Foundation.
 * 
 * This program is distributed in the hope that it will be useful, but WITHOUT
 * ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
 * FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more
 * details.
 *
 * You should have received a copy of the GNU General Public License along with
 * this program.  If not, see <http://www.gnu.org/licenses/>.
 *
 * As a special exception, AlliedModders LLC gives you permission to link the
 * code of this program (as well as its derivative works) to "Half-Life 2," the
 * "Source Engine," the "SourcePawn JIT," and any Game MODs that run on software
 * by the Valve Corporation.  You must obey the GNU General Public License in
 * all respects for all other code used.  Additionally, AlliedModders LLC grants
 * this exception to all derivative works.  AlliedModders LLC defines further
 * exceptions, found in LICENSE.txt (as of this writing, version JULY-31-2007),
 * or <http://www.sourcemod.net/license.php>.
 *
 * Version: $Id$
 */

/* We like semicolons */
#pragma semicolon 1

#include <sourcemod>

#define CURRENT_SCHEMA_VERSION		1409
#define SCHEMA_UPGRADE_1			1409

new current_version[4] = {1, 0, 0, CURRENT_SCHEMA_VERSION};

public Plugin:myinfo = 
{
	name = "SQL Admin Manager",
	author = "AlliedModders LLC",
	description = "Manages SQL admins",
	version = SOURCEMOD_VERSION,
	url = "http://www.sourcemod.net/"
};

public OnPluginStart()
{
	LoadTranslations("common.phrases");
	LoadTranslations("sqladmins.phrases");

	RegAdminCmd("sm_sql_addadmin", Command_AddAdmin, ADMFLAG_ROOT, "Adds an admin to the SQL database");
	RegAdminCmd("sm_sql_deladmin", Command_DelAdmin, ADMFLAG_ROOT, "Removes an admin from the SQL database");
	RegAdminCmd("sm_sql_addgroup", Command_AddGroup, ADMFLAG_ROOT, "Adds a group to the SQL database");
	RegAdminCmd("sm_sql_delgroup", Command_DelGroup, ADMFLAG_ROOT, "Removes a group from the SQL database");
	RegAdminCmd("sm_sql_setadmingroups", Command_SetAdminGroups, ADMFLAG_ROOT, "Sets an admin's groups in the SQL database");
	RegServerCmd("sm_create_adm_tables", Command_CreateTables);
	RegServerCmd("sm_update_adm_tables", Command_UpdateTables);
}

Handle:Connect()
{
	decl String:error[255];
	new Handle:db;
	
	if (SQL_CheckConfig("admins"))
	{
		db = SQL_Connect("admins", true, error, sizeof(error));
	} else {
		db = SQL_Connect("default", true, error, sizeof(error));
	}
	
	if (db == INVALID_HANDLE)
	{
		LogError("Could not connect to database: %s", error);
	}
	
	return db;
}

CreateMySQL(client, Handle:db)
{
	new String:queries[7][] = 
	{
		"CREATE TABLE sm_admins (id int(10) unsigned NOT NULL auto_increment, authtype enum('steam','name','ip') NOT NULL, identity varchar(65) NOT NULL, password varchar(65), flags varchar(30) NOT NULL, name varchar(65) NOT NULL, immunity int(10) unsigned NOT NULL, PRIMARY KEY (id))",
		"CREATE TABLE sm_groups (id int(10) unsigned NOT NULL auto_increment, flags varchar(30) NOT NULL, name varchar(120) NOT NULL, immunity_level int(1) unsigned NOT NULL, PRIMARY KEY (id))",
		"CREATE TABLE sm_group_immunity (group_id int(10) unsigned NOT NULL, other_id int(10) unsigned NOT NULL,  PRIMARY KEY (group_id, other_id))",
		"CREATE TABLE sm_group_overrides (group_id int(10) unsigned NOT NULL, type enum('command','group') NOT NULL, name varchar(32) NOT NULL, access enum('allow','deny') NOT NULL, PRIMARY KEY (group_id, type, name))",
		"CREATE TABLE sm_overrides (type enum('command','group') NOT NULL, name varchar(32) NOT NULL, flags varchar(30) NOT NULL, PRIMARY KEY (type,name))",
		"CREATE TABLE sm_admins_groups (admin_id int(10) unsigned NOT NULL, group_id int(10) unsigned NOT NULL, inherit_order int(10) NOT NULL, PRIMARY KEY (admin_id, group_id))",
		"CREATE TABLE IF NOT EXISTS sm_config (cfg_key varchar(32) NOT NULL, cfg_value varchar(255) NOT NULL, PRIMARY KEY (cfg_key))"
	};

	for (new i = 0; i < 7; i++)
	{
		if (!DoQuery(client, db, queries[i]))
		{
			return;
		}
	}

	decl String:query[256];
	Format(query, 
		sizeof(query), 
		"INSERT INTO sm_config (cfg_key, cfg_value) VALUES ('admin_version', '1.0.0.%d') ON DUPLICATE KEY UPDATE cfg_value = '1.0.0.%d'",
		CURRENT_SCHEMA_VERSION,
		CURRENT_SCHEMA_VERSION);

	if (!DoQuery(client, db, query))
	{
		return;
	}

	ReplyToCommand(client, "[SM] Admin tables have been created.");
}

CreateSQLite(client, Handle:db)
{
	new String:queries[7][] = 
	{
		"CREATE TABLE sm_admins (id INTEGER PRIMARY KEY AUTOINCREMENT, authtype varchar(16) NOT NULL CHECK(authtype IN ('steam', 'ip', 'name')), identity varchar(65) NOT NULL, password varchar(65), flags varchar(30) NOT NULL, name varchar(65) NOT NULL, immunity INTEGER NOT NULL)",
		"CREATE TABLE sm_groups (id INTEGER PRIMARY KEY AUTOINCREMENT, flags varchar(30) NOT NULL, name varchar(120) NOT NULL, immunity_level INTEGER NOT NULL)",
		"CREATE TABLE sm_group_immunity (group_id INTEGER NOT NULL, other_id INTEGER NOT NULL, PRIMARY KEY (group_id, other_id))",
		"CREATE TABLE sm_group_overrides (group_id INTEGER NOT NULL, type varchar(16) NOT NULL CHECK (type IN ('command', 'group')), name varchar(32) NOT NULL, access varchar(16) NOT NULL CHECK (access IN ('allow', 'deny')), PRIMARY KEY (group_id, type, name))",
		"CREATE TABLE sm_overrides (type varchar(16) NOT NULL CHECK (type IN ('command', 'group')), name varchar(32) NOT NULL, flags varchar(30) NOT NULL, PRIMARY KEY (type,name))",
		"CREATE TABLE sm_admins_groups (admin_id INTEGER NOT NULL, group_id INTEGER NOT NULL, inherit_order int(10) NOT NULL, PRIMARY KEY (admin_id, group_id))",
		"CREATE TABLE IF NOT EXISTS sm_config (cfg_key varchar(32) NOT NULL, cfg_value varchar(255) NOT NULL, PRIMARY KEY (cfg_key))"
	};

	for (new i = 0; i < 7; i++)
	{
		if (!DoQuery(client, db, queries[i]))
		{
			return;
		}
	}

	decl String:query[256];
	Format(query, 
		sizeof(query), 
		"REPLACE INTO sm_config (cfg_key, cfg_value) VALUES ('admin_version', '1.0.0.%d')",
		CURRENT_SCHEMA_VERSION);

	if (!DoQuery(client, db, query))
	{
		return;
	}

	ReplyToCommand(client, "[SM] Admin tables have been created.");
}

public Action:Command_CreateTables(args)
{
	new client = 0;
	new Handle:db = Connect();
	if (db == INVALID_HANDLE)
	{
		ReplyToCommand(client, "[SM] %t", "Could not connect to database");
		return Plugin_Handled;
	}

	new String:ident[16];
	SQL_ReadDriver(db, ident, sizeof(ident));

	if (strcmp(ident, "mysql") == 0)
	{
		CreateMySQL(client, db);
	} else if (strcmp(ident, "sqlite") == 0) {
		CreateSQLite(client, db);
	} else {
		ReplyToCommand(client, "[SM] Unknown driver type '%s', cannot create tables.", ident);
	}

	CloseHandle(db);

	return Plugin_Handled;
}

bool:GetUpdateVersion(client, Handle:db, versions[4])
{
	decl String:query[256];
	new Handle:hQuery;

	Format(query, sizeof(query), "SELECT cfg_value FROM sm_config WHERE cfg_key = 'admin_version'");
	if ((hQuery = SQL_Query(db, query)) == INVALID_HANDLE)
	{
		DoError(client, db, query, "Version lookup query failed");
		return false;
	}
	if (SQL_FetchRow(hQuery))
	{
		decl String:version_string[255];
		SQL_FetchString(hQuery, 0, version_string, sizeof(version_string));

		decl String:version_numbers[4][12];
		if (ExplodeString(version_string, ".", version_numbers, 4, 12) == 4)
		{
			for (new i = 0; i < 4; i++)
			{
				versions[i] = StringToInt(version_numbers[i]);
			}
		}
	}

	CloseHandle(hQuery);

	if (current_version[3] < versions[3])
	{
		ReplyToCommand(client, "[SM] The database is newer than the expected version.");
		return false;
	}

	if (current_version[3] == versions[3])
	{
		ReplyToCommand(client, "[SM] Your tables are already up to date.");
		return false;
	}


	return true;
}

UpdateSQLite(client, Handle:db)
{
	decl String:query[512];
	new Handle:hQuery;

	Format(query, sizeof(query), "SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'sm_config'");
	if ((hQuery = SQL_Query(db, query)) == INVALID_HANDLE)
	{
		DoError(client, db, query, "Table lookup query failed");
		return;
	}

	new bool:found = SQL_FetchRow(hQuery);

	CloseHandle(hQuery);

	new versions[4];
	if (found)
	{
		if (!GetUpdateVersion(client, db, versions))
		{
			return;
		}
	}

	/* We only know about one upgrade path right now... 
	 * 0 => 1
	 */
	if (versions[3] < SCHEMA_UPGRADE_1)
	{
		new String:queries[8][] = 
		{
			"ALTER TABLE sm_admins ADD immunity INTEGER DEFAULT 0 NOT NULL",
			"CREATE TABLE _sm_groups_temp (id INTEGER PRIMARY KEY AUTOINCREMENT, flags varchar(30) NOT NULL, name varchar(120) NOT NULL, immunity_level INTEGER DEFAULT 0 NOT NULL)",
			"INSERT INTO _sm_groups_temp (id, flags, name) SELECT id, flags, name FROM sm_groups",
			"UPDATE _sm_groups_temp SET immunity_level = 2 WHERE id IN (SELECT g.id FROM sm_groups g WHERE g.immunity = 'global')",
			"UPDATE _sm_groups_temp SET immunity_level = 1 WHERE id IN (SELECT g.id FROM sm_groups g WHERE g.immunity = 'default')",
			"DROP TABLE sm_groups",
			"ALTER TABLE _sm_groups_temp RENAME TO sm_groups",
			"CREATE TABLE IF NOT EXISTS sm_config (cfg_key varchar(32) NOT NULL, cfg_value varchar(255) NOT NULL, PRIMARY KEY (cfg_key))"
		};

		for (new i = 0; i < 8; i++)
		{
			if (!DoQuery(client, db, queries[i]))
			{
				return;
			}
		}

		Format(query, 
			sizeof(query), 
			"REPLACE INTO sm_config (cfg_key, cfg_value) VALUES ('admin_version', '1.0.0.%d')",
			SCHEMA_UPGRADE_1);

		if (!DoQuery(client, db, query))
		{
			return;
		}

		versions[3] = SCHEMA_UPGRADE_1;
	}

	ReplyToCommand(client, "[SM] Your tables are now up to date.");
}

UpdateMySQL(client, Handle:db)
{
	decl String:query[512];
	new Handle:hQuery;
	
	Format(query, sizeof(query), "SHOW TABLES");
	if ((hQuery = SQL_Query(db, query)) == INVALID_HANDLE)
	{
		DoError(client, db, query, "Table lookup query failed");
		return;
	}

	decl String:table[64];
	new bool:found = false;
	while (SQL_FetchRow(hQuery))
	{
		SQL_FetchString(hQuery, 0, table, sizeof(table));
		if (strcmp(table, "sm_config") == 0)
		{
			found = true;
		}
	}
	CloseHandle(hQuery);

	new versions[4];

	if (found && !GetUpdateVersion(client, db, versions))
	{
		return;
	}

	/* We only know about one upgrade path right now... 
	 * 0 => 1
	 */
	if (versions[3] < SCHEMA_UPGRADE_1)
	{
		new String:queries[6][] = 
		{
			"CREATE TABLE IF NOT EXISTS sm_config (cfg_key varchar(32) NOT NULL, cfg_value varchar(255) NOT NULL, PRIMARY KEY (cfg_key))",
			"ALTER TABLE sm_admins ADD immunity INT UNSIGNED NOT NULL",
			"ALTER TABLE sm_groups ADD immunity_level INT UNSIGNED NOT NULL",
			"UPDATE sm_groups SET immunity_level = 2 WHERE immunity = 'default'",
			"UPDATE sm_groups SET immunity_level = 1 WHERE immunity = 'global'",
			"ALTER TABLE sm_groups DROP immunity"
		};

		for (new i = 0; i < 6; i++)
		{
			if (!DoQuery(client, db, queries[i]))
			{
				return;
			}
		}

		decl String:upgr[48];
		Format(upgr, sizeof(upgr), "1.0.0.%d", SCHEMA_UPGRADE_1);

		Format(query, sizeof(query), "INSERT INTO sm_config (cfg_key, cfg_value) VALUES ('admin_version', '%s') ON DUPLICATE KEY UPDATE cfg_value = '%s'", upgr, upgr);
		if (!DoQuery(client, db, query))
		{
			return;
		}

		versions[3] = SCHEMA_UPGRADE_1;
	}

	ReplyToCommand(client, "[SM] Your tables are now up to date.");
}

public Action:Command_UpdateTables(args)
{
	new client = 0;
	new Handle:db = Connect();
	if (db == INVALID_HANDLE)
	{
		ReplyToCommand(client, "[SM] %t", "Could not connect to database");
		return Plugin_Handled;
	}

	new String:ident[16];
	SQL_ReadDriver(db, ident, sizeof(ident));

	if (strcmp(ident, "mysql") == 0)
	{
		UpdateMySQL(client, db);
	} else if (strcmp(ident, "sqlite") == 0) {
		UpdateSQLite(client, db);
	} else {
		ReplyToCommand(client, "[SM] Unknown driver type, cannot upgrade.");
	}

	CloseHandle(db);

	return Plugin_Handled;
}

public Action:Command_SetAdminGroups(client, args)
{
	if (args < 2)
	{
		ReplyToCommand(client, "[SM] Usage: sm_sql_setadmingroups <authtype> <identity> [group1] ... [group N]");
		return Plugin_Handled;
	}
	
	decl String:authtype[16];
	GetCmdArg(1, authtype, sizeof(authtype));
	
	if (!StrEqual(authtype, "steam")
		&& !StrEqual(authtype, "ip")
		&& !StrEqual(authtype, "name"))
	{
		ReplyToCommand(client, "[SM] %t", "Invalid authtype");
		return Plugin_Handled;
	}
	
	new Handle:db = Connect();
	if (db == INVALID_HANDLE)
	{
		ReplyToCommand(client, "[SM] %t", "Could not connect to database");
		return Plugin_Handled;
	}
	
	decl String:identity[65];
	decl String:safe_identity[140];
	GetCmdArg(2, identity, sizeof(identity));
	SQL_EscapeString(db, identity, safe_identity, sizeof(safe_identity));
	
	decl String:query[255];
	Format(query, 
		sizeof(query),
		"SELECT id FROM sm_admins WHERE authtype = '%s' AND identity = '%s'",
		authtype,
		safe_identity);
		
	new Handle:hQuery;
	if ((hQuery = SQL_Query(db, query)) == INVALID_HANDLE)
	{
		return DoError(client, db, query, "Admin lookup query failed");
	}
	
	if (!SQL_FetchRow(hQuery))
	{
		ReplyToCommand(client, "[SM] %t", "SQL Admin not found");
		CloseHandle(hQuery);
		CloseHandle(db);
		return Plugin_Handled;
	}
	
	new id = SQL_FetchInt(hQuery, 0);
	
	CloseHandle(hQuery);
	
	/**
	 * First delete all of the user's existing groups.
	 */
	Format(query, sizeof(query), "DELETE FROM sm_admins_groups WHERE admin_id = %d", id);
	if (!SQL_FastQuery(db, query))
	{
		return DoError(client, db, query, "Admin group deletion query failed");
	}
	
	if (args < 3)
	{
		ReplyToCommand(client, "[SM] %t", "SQL Admin groups reset");
		CloseHandle(db);
		return Plugin_Handled;
	}
	
	decl String:error[256];
	new Handle:hAddQuery, Handle:hFindQuery;
	
	Format(query, sizeof(query), "SELECT id FROM sm_groups WHERE name = ?");
	if ((hFindQuery = SQL_PrepareQuery(db, query, error, sizeof(error))) == INVALID_HANDLE)
	{
		return DoStmtError(client, db, query, error, "Group search prepare failed");
	}
	
	Format(query, 
		sizeof(query), 
		"INSERT INTO sm_admins_groups (admin_id, group_id, inherit_order) VALUES (%d, ?, ?)",
		id);
	if ((hAddQuery = SQL_PrepareQuery(db, query, error, sizeof(error))) == INVALID_HANDLE)
	{
		CloseHandle(hFindQuery);
		return DoStmtError(client, db, query, error, "Add admin group prepare failed");
	}
	
	decl String:name[80];
	new inherit_order = 0;
	for (new i=3; i<=args; i++)
	{
		GetCmdArg(i, name, sizeof(name));
		
		SQL_BindParamString(hFindQuery, 0, name, false);
		if (!SQL_Execute(hFindQuery) || !SQL_FetchRow(hFindQuery))
		{
			ReplyToCommand(client, "[SM] %t", "SQL Group X not found", name);
		} else {
			new gid = SQL_FetchInt(hFindQuery, 0);
			
			SQL_BindParamInt(hAddQuery, 0, gid);
			SQL_BindParamInt(hAddQuery, 1, ++inherit_order);
			if (!SQL_Execute(hAddQuery))
			{
				ReplyToCommand(client, "[SM] %t", "SQL Group X failed to bind", name);
				inherit_order--;
			}
		}
	}
	
	CloseHandle(hAddQuery);
	CloseHandle(hFindQuery);
	CloseHandle(db);
	
	if (inherit_order == 1)
	{
		ReplyToCommand(client, "[SM] %t", "Added group to user");
	} else if (inherit_order > 1) {
		ReplyToCommand(client, "[SM] %t", "Added groups to user", inherit_order);
	}
	
	return Plugin_Handled;
}

public Action:Command_DelGroup(client, args)
{
	if (args < 1)
	{
		ReplyToCommand(client, "[SM] Usage: sm_sql_delgroup <name>");
		return Plugin_Handled;
	}

	new Handle:db = Connect();
	if (db == INVALID_HANDLE)
	{
		ReplyToCommand(client, "[SM] %t", "Could not connect to database");
		return Plugin_Handled;
	}
	
	new len;
	decl String:name[80];
	decl String:safe_name[180];
	GetCmdArgString(name, sizeof(name));
	
	/* Strip quotes in case the user tries to use them */
	len = strlen(name);
	if (len > 1 && (name[0] == '"' && name[len-1] == '"'))
	{
		name[--len] = '\0';
		SQL_EscapeString(db, name[1], safe_name, sizeof(safe_name));
	} else {
		SQL_EscapeString(db, name, safe_name, sizeof(safe_name));
	}
	
	decl String:query[256];
	
	new Handle:hQuery;
	Format(query, sizeof(query), "SELECT id FROM sm_groups WHERE name = '%s'", safe_name);
	if ((hQuery = SQL_Query(db, query)) == INVALID_HANDLE)
	{
		return DoError(client, db, query, "Group retrieval query failed");
	}
	
	if (!SQL_FetchRow(hQuery))
	{
		ReplyToCommand(client, "[SM] %t", "SQL Group not found");
		CloseHandle(hQuery);
		CloseHandle(db);
		return Plugin_Handled;
	}
	
	new id = SQL_FetchInt(hQuery, 0);
	
	CloseHandle(hQuery);
	
	/* Delete admin inheritance for this group */
	Format(query, sizeof(query), "DELETE FROM sm_admins_groups WHERE group_id = %d", id);
	if (!SQL_FastQuery(db, query))
	{
		return DoError(client, db, query, "Admin group deletion query failed");
	}
	
	/* Delete group overrides */
	Format(query, sizeof(query), "DELETE FROM sm_group_overrides WHERE group_id = %d", id);
	if (!SQL_FastQuery(db, query))
	{
		return DoError(client, db, query, "Group override deletion query failed");
	}
	
	/* Delete immunity */
	Format(query, sizeof(query), "DELETE FROM sm_group_immunity WHERE group_id = %d OR other_id = %d", id, id);
	if (!SQL_FastQuery(db, query))
	{
		return DoError(client, db, query, "Group immunity deletion query failed");
	}
	
	/* Finally delete the group */
	Format(query, sizeof(query), "DELETE FROM sm_groups WHERE id = %d", id);
	if (!SQL_FastQuery(db, query))
	{
		return DoError(client, db, query, "Group deletion query failed");
	}
	
	ReplyToCommand(client, "[SM] %t", "SQL Group deleted");
	
	CloseHandle(db);
	
	return Plugin_Handled;
}

public Action:Command_AddGroup(client, args)
{
	if (args < 2)
	{
		ReplyToCommand(client, "[SM] Usage: sm_sql_addgroup <name> <flags> [immunity]");
		return Plugin_Handled;
	}

	new immunity;
	if (args >= 3)
	{
		new String:arg3[32];
		GetCmdArg(3, arg3, sizeof(arg3));
		if (!StringToIntEx(arg3, immunity))
		{
			ReplyToCommand(client, "[SM] %t", "Invalid immunity");
			return Plugin_Handled;
		}
	}
	
	new Handle:db = Connect();
	if (db == INVALID_HANDLE)
	{
		ReplyToCommand(client, "[SM] %t", "Could not connect to database");
		return Plugin_Handled;
	}
	
	decl String:name[64];
	decl String:safe_name[64];
	GetCmdArg(1, name, sizeof(name));
	SQL_EscapeString(db, name, safe_name, sizeof(safe_name));
	
	new Handle:hQuery;
	decl String:query[256];
	Format(query, sizeof(query), "SELECT id FROM sm_groups WHERE name = '%s'", safe_name);
	if ((hQuery = SQL_Query(db, query)) == INVALID_HANDLE)
	{
		return DoError(client, db, query, "Group retrieval query failed");
	}
	
	if (SQL_GetRowCount(hQuery) > 0)
	{
		ReplyToCommand(client, "[SM] %t", "SQL Group already exists");
		CloseHandle(hQuery);
		CloseHandle(db);
		return Plugin_Handled;
	}
	
	CloseHandle(hQuery);
	
	decl String:flags[30];
	decl String:safe_flags[64];
	GetCmdArg(2, flags, sizeof(safe_flags));
	SQL_EscapeString(db, flags, safe_flags, sizeof(safe_flags));
	
	Format(query, 
		sizeof(query),
		"INSERT INTO sm_groups (flags, name, immunity_level) VALUES ('%s', '%s', '%d')",
		safe_flags,
		safe_name,
		immunity);
	
	if (!SQL_FastQuery(db, query))
	{
		return DoError(client, db, query, "Group insertion query failed");
	}
	
	ReplyToCommand(client, "[SM] %t", "SQL Group added");
	
	CloseHandle(db);
		
	return Plugin_Handled;
}	

public Action:Command_DelAdmin(client, args)
{
	if (args < 2)
	{
		ReplyToCommand(client, "[SM] Usage: sm_sql_deladmin <authtype> <identity>");
		ReplyToCommand(client, "[SM] %t", "Invalid authtype");
		return Plugin_Handled;
	}
	
	decl String:authtype[16];
	GetCmdArg(1, authtype, sizeof(authtype));
	
	if (!StrEqual(authtype, "steam")
		&& !StrEqual(authtype, "ip")
		&& !StrEqual(authtype, "name"))
	{
		ReplyToCommand(client, "[SM] %t", "Invalid authtype");
		return Plugin_Handled;
	}
	
	new Handle:db = Connect();
	if (db == INVALID_HANDLE)
	{
		ReplyToCommand(client, "[SM] %t", "Could not connect to database");
		return Plugin_Handled;
	}
	
	decl String:identity[65];
	decl String:safe_identity[140];
	GetCmdArg(2, identity, sizeof(identity));
	SQL_EscapeString(db, identity, safe_identity, sizeof(safe_identity));
	
	decl String:query[255];
	Format(query, 
		sizeof(query),
		"SELECT id FROM sm_admins WHERE authtype = '%s' AND identity = '%s'",
		authtype,
		safe_identity);
		
	new Handle:hQuery;
	if ((hQuery = SQL_Query(db, query)) == INVALID_HANDLE)
	{
		return DoError(client, db, query, "Admin lookup query failed");
	}
	
	if (!SQL_FetchRow(hQuery))
	{
		ReplyToCommand(client, "[SM] %t", "SQL Admin not found");
		CloseHandle(hQuery);
		CloseHandle(db);
		return Plugin_Handled;
	}
	
	new id = SQL_FetchInt(hQuery, 0);
	
	CloseHandle(hQuery);
	
	/* Delete group bindings */
	Format(query, sizeof(query), "DELETE FROM sm_admins_groups WHERE admin_id = %d", id);
	if (!SQL_FastQuery(db, query))
	{
		return DoError(client, db, query, "Admin group deletion query failed");
	}
	
	Format(query, sizeof(query), "DELETE FROM sm_admins WHERE id = %d", id);
	if (!SQL_FastQuery(db, query))
	{
		return DoError(client, db, query, "Admin deletion query failed");
	}
	
	CloseHandle(db);
	
	ReplyToCommand(client, "[SM] %t", "SQL Admin deleted");
	
	return Plugin_Handled;
}

public Action:Command_AddAdmin(client, args)
{
	if (args < 4)
	{
		ReplyToCommand(client, "[SM] Usage: sm_sql_addadmin <alias> <authtype> <identity> <flags> [immunity] [password]");
		ReplyToCommand(client, "[SM] %t", "Invalid authtype");
		return Plugin_Handled;
	}
	
	decl String:authtype[16];
	GetCmdArg(2, authtype, sizeof(authtype));
	
	if (!StrEqual(authtype, "steam")
		&& !StrEqual(authtype, "ip")
		&& !StrEqual(authtype, "name"))
	{
		ReplyToCommand(client, "[SM] %t", "Invalid authtype");
		return Plugin_Handled;
	}

	new immunity;
	if (args >= 5)
	{
		new String:arg5[32];
		GetCmdArg(5, arg5, sizeof(arg5));
		if (!StringToIntEx(arg5, immunity))
		{
			ReplyToCommand(client, "[SM] %t", "Invalid immunity");
			return Plugin_Handled;
		}
	}
	
	decl String:identity[65];
	decl String:safe_identity[140];
	GetCmdArg(3, identity, sizeof(identity));
	
	decl String:query[256];
	new Handle:hQuery;
	new Handle:db = Connect();
	if (db == INVALID_HANDLE)
	{
		ReplyToCommand(client, "[SM] %t", "Could not connect to database");
		return Plugin_Handled;
	}
	
	SQL_EscapeString(db, identity, safe_identity, sizeof(safe_identity));
	
	Format(query, sizeof(query), "SELECT id FROM sm_admins WHERE authtype = '%s' AND identity = '%s'", authtype, identity);
	if ((hQuery = SQL_Query(db, query)) == INVALID_HANDLE)
	{
		return DoError(client, db, query, "Admin retrieval query failed");
	}
	
	if (SQL_GetRowCount(hQuery) > 0)
	{
		ReplyToCommand(client, "[SM] %t", "SQL Admin already exists");
		CloseHandle(hQuery);
		CloseHandle(db);
		return Plugin_Handled;
	}
	
	CloseHandle(hQuery);
	
	decl String:alias[64];
	decl String:safe_alias[140];
	GetCmdArg(1, alias, sizeof(alias));
	SQL_EscapeString(db, alias, safe_alias, sizeof(safe_alias));
	
	decl String:flags[30];
	decl String:safe_flags[64];
	GetCmdArg(4, flags, sizeof(flags));
	SQL_EscapeString(db, flags, safe_flags, sizeof(safe_flags));
	
	decl String:password[32];
	decl String:safe_password[80];
	if (args >= 6)
	{
		GetCmdArg(6, password, sizeof(password));
		SQL_EscapeString(db, password, safe_password, sizeof(safe_password));
	} else {
		safe_password[0] = '\0';
	}
	
	new len = 0;
	len += Format(query[len], sizeof(query)-len, "INSERT INTO sm_admins (authtype, identity, password, flags, name, immunity) VALUES");
	if (safe_password[0] == '\0')
	{
		len += Format(query[len], sizeof(query)-len, " ('%s', '%s', NULL, '%s', '%s', %d)", authtype, safe_identity, safe_flags, safe_alias, immunity);
	} else {
		len += Format(query[len], sizeof(query)-len, " ('%s', '%s', '%s', '%s', '%s', %d)", authtype, safe_identity, safe_password, safe_flags, safe_alias, immunity);
	}
	
	if (!SQL_FastQuery(db, query))
	{
		return DoError(client, db, query, "Admin insertion query failed");
	}
	
	ReplyToCommand(client, "[SM] %t", "SQL Admin added");
	
	CloseHandle(db);
		
	return Plugin_Handled;
}

stock bool:DoQuery(client, Handle:db, const String:query[])
{
	if (!SQL_FastQuery(db, query))
	{
		decl String:error[255];
		SQL_GetError(db, error, sizeof(error));
		LogError("Query failed: %s", error);
		LogError("Query dump: %s", query);
		ReplyToCommand(client, "[SM] %t", "Failed to query database");
		return false;
	}

	return true;
}

stock Action:DoError(client, Handle:db, const String:query[], const String:msg[])
{
		decl String:error[255];
		SQL_GetError(db, error, sizeof(error));
		LogError("%s: %s", msg, error);
		LogError("Query dump: %s", query);
		CloseHandle(db);
		ReplyToCommand(client, "[SM] %t", "Failed to query database");
		return Plugin_Handled;
}

stock Action:DoStmtError(client, Handle:db, const String:query[], const String:error[], const String:msg[])
{
		LogError("%s: %s", msg, error);
		LogError("Query dump: %s", query);
		CloseHandle(db);
		ReplyToCommand(client, "[SM] %t", "Failed to query database");
		return Plugin_Handled;
}

