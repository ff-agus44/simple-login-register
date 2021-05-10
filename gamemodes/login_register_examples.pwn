#include <a_samp>
#include <a_mysql>
#include <samp_bcrypt>

#define COLOR_WHITE 0xFFFFFFFF

// Change this if you want!
#define MYSQL_HOSTNAME "127.0.0.1"
#define MYSQL_USERNAME "root"
#define MYSQL_PASSWORD ""
#define MYSQL_DATABASE "test"

// Default spawn pos i got from mysql examples
#define 	DEFAULT_POS_X 		1958.3783
#define 	DEFAULT_POS_Y 		1343.1572
#define 	DEFAULT_POS_Z 		15.3746
#define 	DEFAULT_POS_A 		270.1425

// This is the the length of bcrypt i have using until now
#if !defined BCRYPT_HASH_LENGTH
	#define BCRYPT_HASH_LENGTH 250
#endif 

// And this is the default bcrypt cost
#if !defined BCRYPT_COST
	#define BCRYPT_COST 12
#endif

// This is my MySQL handle, to handle the query using connection ID
new MySQL:gSQLHandle;

// I need this race check, see explanations below
static g_MysqlRaceCheck[MAX_PLAYERS];

// This is same as define, but it automatically increased by one
// and this is why i have choosen enum like this
enum {
	E_DIALOG_REGISTER,
	E_DIALOG_LOGIN
};

// This code is how do i get the name, please do not edit any parts in it
forward [25]GetName(playerid);
GetName(playerid)
{
	#emit PUSH.C 25
	#emit PUSH.S 16
	#emit PUSH.S playerid
	#emit PUSH.C 12
	#emit SYSREQ.C GetPlayerName
	#emit STACK 16
	#emit RETN
}

// I used OnPlayerCheck to checking if the query exists or not
forward OnPlayerCheck(playerid);
public OnPlayerCheck(playerid)
{
	// Needed to increase it by one so it does not collide with each other.
	g_MysqlRaceCheck[playerid]++;

	// And then run the query
	new queryCheck[103];
	mysql_format(gSQLHandle, queryCheck, sizeof(queryCheck), "SELECT * FROM accounts WHERE name = '%e' LIMIT 1", GetName(playerid));
	mysql_tquery(gSQLHandle, queryCheck, #OnMySQLResponse, "ii", playerid, g_MysqlRaceCheck[playerid]);
	return 1;
}


forward OnMySQLResponse(playerid, race_check);
public OnMySQLResponse(playerid, race_check)
{
	/*	race condition check:
		player A connects -> SELECT query is fired -> this query takes very long
		while the query is still processing, player A with playerid 2 disconnects
		player B joins now with playerid 2 -> our laggy SELECT query is finally finished, but for the wrong player
		what do we do against it?
		we create a connection count for each playerid and increase it everytime the playerid connects or disconnects
		we also pass the current value of the connection count to our OnPlayerDataLoaded callback
		then we check if current connection count is the same as connection count we passed to the callback
		if yes, everything is okay, if not, we just kick the player
	*/
	if (race_check != g_MysqlRaceCheck[playerid]) return Kick(playerid);

	// Here i am checking if rows is exists/higher than zero
	if (cache_num_rows() > 0)
	{
		ShowPlayerDialog(playerid, E_DIALOG_LOGIN, DIALOG_STYLE_PASSWORD, "Your Roleplay - Login", 
			"{FFFFFF}Selamat datang di Your Roleplay, silahkan masuk untuk melanjutkan.",
			"Masuk", "Keluar"
		);
	}
	// and when it is not zero, tell player to login instead.
	else
	{
		ShowPlayerDialog(playerid, E_DIALOG_REGISTER, DIALOG_STYLE_PASSWORD, "Your Roleplay - Register",
			"{FFFFFF}Selamat datang di Your Roleplay, silahkan mendaftar untuk melanjutkan.",
			"Daftar", "Keluar"
		);	
	}
	return 1;
}

// Here i made the function to store the current hashing into mysql
forward OnPlayerPasswordHashed(playerid, hashid);
public OnPlayerPasswordHashed(playerid, hashid)
{
	// First i declare the local variables that i needed
	new 
		insertQuery[320],
		hash[BCRYPT_HASH_LENGTH];

	// then i grab the hashes and store it into 'hash' variable
	bcrypt_get_hash(hash, sizeof(hash));

	// after that, i format and run the query to insert the hash value
	mysql_format(gSQLHandle, insertQuery, sizeof(insertQuery), "INSERT INTO accounts (name, password) VALUES ('%e', '%e')", GetName(playerid), hash);
	mysql_query(gSQLHandle, insertQuery, false);

	// when it is done storing, i tell player to login now!
	ShowPlayerDialog(playerid, E_DIALOG_LOGIN, DIALOG_STYLE_PASSWORD, "Your Roleplay - Login", 
		"{FFFFFF}Selamat datang di Your Roleplay, silahkan masuk untuk melanjutkan.",
		"Masuk", "Keluar"
	);
	return 1;
}

// This is the function to check if the hash compare is success or not
forward OnPlayerPasswordChecked(playerid, bool:success);
public OnPlayerPasswordChecked(playerid, bool:success)
{
	// if not success, then tell the player the hash is not same
	if (!success)
		return ShowPlayerDialog(playerid, E_DIALOG_LOGIN, DIALOG_STYLE_PASSWORD, "Your Roleplay - Login", 
			"{FF0000}(ERROR: Password tidak sama!)\n\n"\
			"{FFFFFF}Selamat datang di Your Roleplay, silahkan masuk untuk melanjutkan.",
			"Masuk", "Keluar"
		);

	// but if success is true, you can call anything like OnAccountLoad, etc
	// depends on you.
	OnAccountLoad(playerid); //or CallLocalFunction(#OnAccountLoad, "i", playerid);
	SendClientMessage(playerid, COLOR_WHITE, "SERVER: Sukses login kedalam server!");
	return 1;
}

forward OnAccountLoad(playerid);
public OnAccountLoad(playerid)
{
	// when OnAccountLoad was called, then we set the default pos for player to spawn
	// Since this is a example, i will just use this instead implementing the actual save/load positions.
	SetSpawnInfo(playerid, 0, 1, DEFAULT_POS_X, DEFAULT_POS_Y, DEFAULT_POS_Z, DEFAULT_POS_A, 0, 0, 0, 0, 0, 0);

	// And then trigger the spawn, no need to use SpawnPlayer(playerid)
	TogglePlayerSpectating(playerid, false);
	return 1;
}

main() 
{
	print("------------------------------------------------");
	print(" Very basic login register dibuat oleh ff-agus44");
	print(" This only means for learning how bcrypt works  ");
	print(" you can submit pull request if something wrong ");
	print("------------------------------------------------");
}

public OnGameModeInit()
{
	// This script connects the MySQL server and returns an connection ID
	gSQLHandle = mysql_connect(MYSQL_HOSTNAME, MYSQL_USERNAME, MYSQL_PASSWORD, MYSQL_DATABASE);

	// Check if connection ID that is in gSQLHandle is invalid or is error
	if (gSQLHandle == MYSQL_INVALID_HANDLE || mysql_errno(gSQLHandle) != 0)
	{
		// if so, print this and exit
		printf("Connection to "MYSQL_HOSTNAME" failed, make sure your MySQL server is running!");
		SendRconCommand("exit");
		return 1;
	}

	// but if not invalid or error, print this.
	printf("Connection to "MYSQL_HOSTNAME" is successfull!");

	// Create the simple table that holds id, name, and password
	mysql_query(gSQLHandle, "CREATE TABLE IF NOT EXISTS acounts (id INT(16) NOT NULL AUTO_INCREMENT PRIMARY KEY, name VARCHAR(25) NOT NULL, password VARCHAR(250) NOT NULL)", false);
	
	// do anything you want below here
	//
	return 1;
}

public OnPlayerConnect(playerid)
{
	// This is the bypass to hides the "spawn" button
	TogglePlayerSpectating(playerid, true);
	SetTimerEx(#OnPlayerCheck, 800, false, "i", playerid);
	return 1;
}

// When player is pressing either ESC/ENTER/BUTTON 1/BUTTON 2, this callback will be called.
public OnDialogResponse(playerid, dialogid, response, listitem, inputtext[])
{
	switch (dialogid)
	{
		case E_DIALOG_REGISTER:
		{
			// Lets check the input that user given, if is below 5 then tell the player the password is not valid
			if (strlen(inputtext) < 5)
				return ShowPlayerDialog(playerid, E_DIALOG_REGISTER, DIALOG_STYLE_PASSWORD, "Your Roleplay - Register",
						"{FF0000}(ERROR: Password Tidak valid!)\n\n"\
						"{FFFFFF}Selamat datang di Your Roleplay, silahkan mendaftar untuk melanjutkan.",
						"Daftar", "Keluar"
				);
			
			// but if more than 5 characters/length, it is good enough to hash the passwod, and the result will be 
			// OnPlayerPasswordHashed functions.
			bcrypt_hash(playerid, #OnPlayerPasswordHashed, inputtext, BCRYPT_COST);
			return 1;
		}
		case E_DIALOG_LOGIN:
		{
			// Lets check the input that user given, if is below 0 or more than 127 then tell the player the password is not valid
			if (!strlen(inputtext) || strlen(inputtext) > 127) 
				return ShowPlayerDialog(playerid, E_DIALOG_LOGIN, DIALOG_STYLE_PASSWORD, "Your Roleplay - Login", 
					"{FF0000}(ERROR: Password tidak valid!)\n\n"\
					"{FFFFFF}Selamat datang di Your Roleplay, silahkan masuk untuk melanjutkan.",
					"Masuk", "Keluar"
				);

			// We execute the query once more to get the hash that we store in the database
			new queryCheck[256];
			mysql_format(gSQLHandle, queryCheck, sizeof(queryCheck), "SELECT password FROM accounts WHERE name = '%e' LIMIT 1", GetName(playerid));
			mysql_query(gSQLHandle, queryCheck);

			// if success!
			if (cache_num_rows() > 0)
			{
				new 
					hash[BCRYPT_HASH_LENGTH];

				// get the hash and then compare it!
				cache_get_value_name(0, "password", hash, sizeof(hash));
				bcrypt_verify(playerid, #OnPlayerPasswordChecked, inputtext, hash);
			}

			// after everyting done, we can safely unset the active cache.
			cache_unset_active();
			return 1;
		}
	}
	return 0;
}

public OnPlayerDisconnect(playerid, reason)
{
	// you can do saving here, or creates another function to save the user accounts
	// but it is best to do the get the data first before saving it to database
	return 1;
}

public OnGameModeExit()
{
	// this code just close the current connection ID that was stored inside gSQLHandle.
	mysql_close(gSQLHandle);
	return 1;
}