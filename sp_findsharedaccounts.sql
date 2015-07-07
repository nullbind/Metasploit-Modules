IF OBJECT_ID ( 'sp_findsharedaccounts', 'P' ) IS NOT NULL 
		DROP PROCEDURE sp_findsharedaccounts;
	GO
	CREATE PROCEDURE sp_findsharedaccounts
	AS

/*====================================
Filename: sp_findsharedaccounts.sql
Date: 10/10/2011
Author: Scott Sutherland
Email: scott.sutherland@netspi.com


--------------------------------------
DESCRIPTION/USE CASE SUMMARY
--------------------------------------
This script is intended to do the follwing:

Note: Queries against remote servers are
run with the privileges of the local 
SQL Server service account.

1) Locate SQL Servers on the same broadcast
   network that are configured with
   the same SQL Server service account
   and have the local administrators configured
   as with the sysadmin fixed server role
   (which is the default in 2005).

2) Locate SQL Server Express instances on 
   the same broadcast network AND Windows Domain 
   that are configured with a TCP listener, AND
   have 'connect' privileges assigned to
   the local 'BUILTIN\Users' group. 
   
   Note: This scenario is only a slight change
   FROM the default Express configuration.
   
3) Return a list of affected SQL Servers along
   with basic connection, AND service account
   information.
   
--------------------------------------
SCRIPT OUTPUT SUMMARY
--------------------------------------
Data is only returned for each server that meets the
criteria in the use case summary.  Below is 
the list of the columns that should be returned 
by the stored procedure along with a short
description of each.

AFFECTEDSERVER: 
The affected SQL server name AND instance name.

REMOTEDATABASEVERSION: 
The SQL Server version of the affected SQL server.

ACCOUNTUSEDTOCON:
The account used to connect to the remote SQL
server.  Usually the local SQL Server service
account.

DBCONNECTION:
Indicates if the account used to connect to the remote 
SQL Server Instance (Local SQL Server service account) 
has the 'connect' privileges.

CONNECTIONHASSYADMIN: 
Indicates if the account used to connect to the remote SQL Server Instance 
(Local SQL Server service account) has the 'Sysadmin' role on the remote server.

REMOTE_SERVICEACCOUNTNAME:
The remote service account name.

REMOTE_SVCACCNTISLOCALADMIN:
Indicates IF the remote SQL Server service account has local administrator 
privileges on the remote SQL Server.

REMOTE_SVCACCNTSDOMAINADMIN:
Indicates if the remote SQL Server service account has Domain Admin
privileges.
======================================*/

-- Turn off row counts
SET  NOCOUNT ON;

-------------------------------------------------------------------------
-- VERIFY THE CURRENT DATABASE USER IS A SYSADMIN
-------------------------------------------------------------------------
IF (SELECT IS_SRVROLEMEMBER('SYSADMIN')) = 0 
	SELECT 'This procedure requires the SYSADMIN fixed server role.';
ELSE
	BEGIN
	
	----------------------------------------------
	-- ENABLE SHOW ADVANCED OPTIONS - IF REQUIRED
	----------------------------------------------
	DECLARE @SAO_status VARCHAR(2);
	DECLARE @SAO_change VARCHAR(2);
	
	SET @SAO_change = '0';
	
	IF EXISTS(SELECT null FROM sysobjects WHERE name = 'configurations')
		SELECT @SAO_Status = CONVERT(INT, ISNULL(value, value_in_use))
		FROM  [master].[sys].[configurations] WHERE (name) = 'show advanced options';
	 	
	 	-- DETERMINE IF A CONFIGURATION CHANGE IS REQUIRED
		IF(SELECT @SAO_Status) = 0 SET @SAO_change = 1;
	
			-- CHANGE CONFIGURATION IF REQUIRED	
			IF(SELECT @SAO_change) = 1 EXEC [master].[DBO].[sp_configure] 'show advanced options',1;
			Reconfigure;
				
	------------------------------------------
	-- ENABLE XP_CMDSHELL - IF REQUIRED
	------------------------------------------
	DECLARE @XPCMD_status VARCHAR(2);
	DECLARE @XPCMD_change VARCHAR(2);

	SET @XPCMD_change = '0';
	
	IF EXISTS(SELECT null FROM sysobjects WHERE (name) = 'configurations')
		SELECT @XPCMD_Status = CONVERT(INT, ISNULL(value, value_in_use))
		FROM  [master].[sys].[configurations] WHERE (name) = 'XP_CMDSHELL'
	 	
	 	-- DETERMINE IF A CONFIGURATION CHANGE IS REQUIRED
		IF(SELECT @XPCMD_Status) = 0 SET @XPCMD_Change = 1;
	
			-- CHANGE CONFIGURATION IF REQUIRED	
			IF(SELECT @XPCMD_Change) = 1 EXEC [master]..sp_configure 'XP_CMDSHELL',1;
			Reconfigure;	

	-------------------------------------------------------------------------
	-- CREATE TEMP TABLES FOR ENUMERATED SQL SERVER INSTANCES 
	-- AND AFFECTED SERVERS CONFIGURED WITH SHARE SERVICE ACCOUNTS 
	-- AND/OR SQL SERVER EXPRESS ON SAME DOMAIN, W/BUILTIN\USERS W/PUBLIC
	-------------------------------------------------------------------------
	-- REMOVE PRE-EXISTING TEMP TABLES (IN CASE SCRIPT FAILS HALF WAY THROGH)
	IF OBJECT_ID('tempdb..#Instances') IS NOT NULL DROP TABLE #Instances;
	IF OBJECT_ID('tempdb..#AffectedServers') IS NOT NULL DROP TABLE #AffectedServers;
	
	-- CREATE TABLES
	CREATE TABLE #Instances (InstanceName VARCHAR(MAX));
	CREATE TABLE #AffectedServers (AffectedServer VARCHAR(MAX), RemoteDatabaseVersion VARCHAR(MAX),AccountUsedToCon VARCHAR(MAX),ConnectionHasPublic VARCHAR(MAX),ConnectionHasSysadmin VARCHAR(MAX),RemoteServiceAccount VARCHAR(MAX),SvcAccntIsLocalAdmin VARCHAR(MAX),SvcAccntIsDomainAdmin VARCHAR(MAX));
	
	-------------------------------------------------------------------------
	-- SEND REQUEST ACCROSS BROADCAST DOMAIN TO ENUMERATE SQL SERVERS
	-- AND WRITE THE OUTPUT TO THE TEMP TABLE INSTANCES
	-------------------------------------------------------------------------
	INSERT #Instances EXEC('XP_CMDSHELL "SQLCMD -L"');

	-- CHECK IF ANY SQL SERVERS WHERE FOUND ON THE BROADCAST NETWORK
	IF (SELECT COUNT(RTRIM(LTRIM([InstanceName]))) FROM #Instances WHERE InstanceName NOT LIKE 'Servers:' AND InstanceName NOT LIKE 'NULL' AND InstanceName NOT LIKE ' ') > 0 
	BEGIN
		-- SUPPORTING VARS
		DECLARE @myserver VARCHAR(MAX)	
		
		-- REMOVE CURSOR IF IT ALREADY EXISTS
		IF Cursor_Status('global','MY_CURSOR')>0 
		BEGIN
			CLOSE MY_CURSOR
			DEALLOCATE MY_CURSOR
		END 

		-- CREATE CURSOR FOR LOOPING THROUGH SQL SERVERS FOUND ON THE BROADCAST NETWORK
		DECLARE MY_CURSOR CURSOR
		FOR
		
		-- ITERATE THOUGH EVERY SQL SERVER THAT WAS FOUND ON THE BROADCAST NETWORK
		SELECT DISTINCT(RTRIM(LTRIM([InstanceName]))) FROM #Instances WHERE InstanceName NOT LIKE 'Servers:' AND InstanceName NOT LIKE 'NULL' AND InstanceName NOT LIKE ' '

		OPEN MY_CURSOR
		FETCH NEXT FROM MY_CURSOR INTO @myserver
		WHILE @@FETCH_STATUS = 0   
		BEGIN  

		------------------------------------------------------------------------------------------
		-- TEST CONNECTIVITY TO REMOTE DB AND TRY TO GET THE REMOTE DB SERVER NAME / INSTANCE NAME
		------------------------------------------------------------------------------------------	
		DECLARE @RemoteServerName VARCHAR(MAX);
		DECLARE @ServerNameQuery VARCHAR(MAX);
		
		-- REMOVE SHAREDINSTANCE TEMP TABLE IF IT EXISTS
		IF OBJECT_ID('tempdb..#SharedInstances') IS NOT NULL DROP TABLE #SharedInstances
		
		-- CREATE TEMP TABLE FOR LIST OF INSTANCES USING SHARED SERVICE ACCOUNTS
		CREATE TABLE #SharedInstances (AffectedServer VARCHAR(MAX));
		
		-- CREATE QUERY TO GET SERVER NAME
		SET @ServerNameQuery = 'INSERT #SharedInstances EXEC(''XP_CMDSHELL ''''SQLCMD -E -S "'+@myserver+'" -Q "SELECT ''''''''Shared Server: ''''''''+@@SERVERNAME"'''''')';		
		
		-- RUN QUERY
		EXEC(@ServerNameQuery);
		
		-- SET @RemoteServerName VAR
		SELECT @RemoteServerName = REPLACE(RTRIM(LTRIM([AffectedServer])),'Shared Server: ','') FROM #SharedInstances WHERE AffectedServer like 'Shared Server:%' AND AffectedServer NOT LIKE 'null';
						
		------------------------------------------------------------------------------------------------------------
		-- IF CONNECTIONS ARE POSSBILE TO THE REMOTE SYSTEM CONTINUE WITH OTHER TESTS. 
		------------------------------------------------------------------------------------------------------------
		-- SET PUBLLIC ACCESS STATUS
		DECLARE @ConHasPublic VARCHAR(MAX);
		SET @ConHasPublic = 'No';
		
		IF @RemoteServerName = @myserver 
			BEGIN
						
			-- MIN OF PUBLIC ROLE CONFIRMED
			SET @ConHasPublic = 'Yes';
			
			-----------------------------------------------------------------------------------------
			-- RECOVER THE CURRENT SQL SERVICE SERVICE ACCOUNT ON THE REMOTE SERVER FROM THE REGISTRY
			-- AND ASSIGN TO THE @REMOTESERVICEACCOUNT VARIABLE.
			-----------------------------------------------------------------------------------------
			DECLARE @SvcAccountQuery VARCHAR(MAX);
			DECLARE @SvcAccountQuery2 VARCHAR(MAX);
			DECLARE @RemoteServiceAccount VARCHAR(MAX);
				
			-- REMOVE CLEAN SERVIE DATABASE IS ALREADY PRESENT	
			IF OBJECT_ID('tempdb..#cleanservicename') IS NOT NULL DROP TABLE #cleanservicename	
			
			-- CREATE TEMP TABLE TO HELP DETERMINE SERVICES ACCOUNT NAME
			CREATE TABLE #cleanservicename ( RemoteServiceName VARCHAR(MAX));

			-- SETUP QUERY TO OBTAIN THE SERVICE ACCOUNT NAME RUNNING THE REMOTE DATABASE SERVER INSTANCE
			SET @SvcAccountQuery  = 'set nocount on;DECLARE @RegistryLocation VARCHAR(MAX)DECLARE @ServiceAccount VARCHAR(MAX);IF CHARINDEX(''''''''\'''''''',@@SERVERNAME) = 0 SET @RegistryLocation = ''''''''SYSTEM\CurrentControlSet\services\MSSQLSERVER''''''''; ELSE BEGIN SET @RegistryLocation = ''''''''SYSTEM\CurrentControlSet\services\MSSQL$''''''''+RIGHT(@@SERVERNAME,LEN(@@SERVERNAME)-CHARINDEX(''''''''\'''''''',@@SERVERNAME)); END CREATE TABLE #ServiceAccount( thekey VARCHAR(MAX),accountname VARCHAR(MAX));INSERT #ServiceAccount EXEC [master].dbo.xp_regread ''''''''HKEY_LOCAL_MACHINE'''''''',@RegistryLocation,''''''''ObjectName'''''''';SELECT @ServiceAccount = accountname FROM #ServiceAccount;SELECT @ServiceAccount;'
			
			-- SETUP QUERY TO RUN THE @SVCACCOUNTQUERY QUERY ON THE REMOTE DATABASE SERVER VIA XP_CMDSHELL AND SQLCMD
			SET @SvcAccountQuery2 = 'INSERT #cleanservicename EXEC(''XP_CMDSHELL ''''SQLCMD -E -S "'+@RemoteServerName+'" -Q "'+@SvcAccountQuery+'"|find /V /I "-" '''''') '	
			
			-- RUN THE QUERIES
			EXEC(@SvcAccountQuery2);
			
			-- SET THE @RemoteServiceAccount VAR
			SELECT @RemoteServiceAccount = ltrim(rtrim(RemoteServiceName)) FROM #cleanservicename WHERE RemoteServiceName NOT LIKE ' ';
			
			-- REMOVE UNEEDED TEMP TABLE
			IF OBJECT_ID('tempdb..#cleanservicename') IS NOT NULL DROP TABLE #cleanservicename;				
			
			-------------------------------------------------------------------------
			-- CHECK SERVICE ACCOUNT PRIVILEGES - LOCAL ADMINISTRATOR
			-------------------------------------------------------------------------
			DECLARE @IsLocalAdmin_query1 VARCHAR(MAX);
			DECLARE @IsLocalAdmin_query2 VARCHAR(MAX);
			DECLARE @IsLocalAdmin VARCHAR(MAX);
			
			-- REMOVE ISLOCALADMIN TEMP TABLE IF IT EXISTS 
			IF OBJECT_ID('tempdb..#IsLocalAdmin') IS NOT NULL DROP TABLE #IsLocalAdmin
			
			-- CREATE TEMP TABLE TO HELP DETERMINE SERVICES ACCOUNT NAME
			CREATE TABLE #IsLocalAdmin
			( IsLocalAdmin VARCHAR(MAX) );
			
			-- QUERY TO CHECK IF SERVICE ACCOUNT IS A LOCAL ADMIN ON THE REMOTE SERVER
			SET @IsLocalAdmin_query1 = 'DECLARE @SAO_status VARCHAR(2);DECLARE @SAO_change VARCHAR(2);SET @SAO_change = ''''''''0'''''''';IF EXISTS(SELECT null FROM sysobjects WHERE name = ''''''''configurations'''''''') SELECT @SAO_Status = CONVERT(INT, ISNULL(value, value_in_use)) FROM  [master].[sys].[configurations] WHERE (name) = ''''''''show advanced options'''''''';IF(SELECT @SAO_Status) = 0 SET @SAO_change = 1;IF(SELECT @SAO_change) = 1 EXEC [master].[DBO].[sp_configure] ''''''''show advanced options'''''''',1;Reconfigure;DECLARE @XPCMD_status VARCHAR(2);DECLARE @XPCMD_change VARCHAR(2);SET @XPCMD_change = ''''''''0'''''''';IF EXISTS(SELECT null FROM sysobjects WHERE (name) = ''''''''configurations'''''''')SELECT @XPCMD_Status = CONVERT(INT, ISNULL(value, value_in_use)) FROM  [master].[sys].[configurations] WHERE (name) = ''''''''XP_CMDSHELL'''''''' IF(SELECT @XPCMD_Status) = 0 SET @XPCMD_Change = 1;IF(SELECT @XPCMD_Change) = 1 EXEC [master]..sp_configure ''''''''XP_CMDSHELL'''''''',1;Reconfigure;DECLARE @IsLocalAdmin VARCHAR(MAX);DECLARE @LocalAdminCheck VARCHAR(MAX);DECLARE @RemoteServiceAccount VARCHAR(MAX);SET @RemoteServiceAccount = '''''''''+@RemoteServiceAccount+''''''''';IF OBJECT_ID(''''''''tempdb..#LocalAdmins'''''''') IS NOT NULL DROP TABLE #LocalAdmins;CREATE TABLE #LocalAdmins( LocalAdmin VARCHAR(MAX));SET @IsLocalAdmin = ''''''''No'''''''';IF (REPLACE(@RemoteServiceAccount,''''''''.\'''''''','''''''''''''''')) = ''''''''LocalSystem'''''''' SET @IsLocalAdmin = ''''''''Yes'''''''';IF (CHARINDEX(''''''''.'''''''',@RemoteServiceAccount)) > 0 INSERT #LocalAdmins EXEC [master].dbo.XP_CMDSHELL ''''''''net localgroup Administrators'''''''';SELECT @LocalAdminCheck = count(LocalAdmin) FROM #LocalAdmins WHERE LocalAdmin like REPLACE(@RemoteServiceAccount,''''''''.\'''''''','''''''''''''''');IF (SELECT @LocalAdminCheck) > 0 SET @IsLocalAdmin = ''''''''Yes'''''''';IF (CHARINDEX(''''''''.'''''''',@RemoteServiceAccount)) = 0 INSERT #LocalAdmins EXEC [master].dbo.XP_CMDSHELL ''''''''net localgroup Administrators'''''''';SELECT @LocalAdminCheck = count(LocalAdmin) FROM #LocalAdmins WHERE LocalAdmin like REPLACE(@RemoteServiceAccount,''''''''.\'''''''','''''''''''''''');IF (SELECT @LocalAdminCheck) > 0 SET @IsLocalAdmin = ''''''''Yes'''''''';SELECT @IsLocalAdmin;IF(SELECT @XPCMD_Change) = 1 EXEC [master].[DBO].[sp_configure] ''''''''XP_CMDSHELL'''''''',0;Reconfigure;IF(SELECT @SAO_change) = 1 EXEC [master].[DBO].[sp_configure] ''''''''show advanced options'''''''',0;Reconfigure;';
			
			-- SETUP QUERY TO RUN THE @ISLOCALADMIN_QUERY1 QUERY ON THE REMOTE DATABASE SERVER VIA XP_CMDSHELL AND SQLCMD
			SET @IsLocalAdmin_query2 = 'INSERT #IsLocalAdmin EXEC(''XP_CMDSHELL ''''SQLCMD -E -S "'+@RemoteServerName+'" -Q "'+@IsLocalAdmin_query1+'"|find /V /I "-" '''''') '	
			
			-- RUN THE QUERIES
			EXEC(@IsLocalAdmin_query2);
			
			-- SET LOCAL ADMIN STATUS
			SELECT @IsLocalAdmin = IsLocalAdmin FROM #IsLocalAdmin WHERE IsLocalAdmin = 'Yes' or IsLocalAdmin = 'No';
			
			-------------------------------------------------------------------------
			-- CHECK SERVICE ACCOUNT PRIVILEGES - DOMAIN ADMINISTRATOR - WITH REMOTE SQL SERVER
			-------------------------------------------------------------------------
			DECLARE @IsDomainAdmin_query1 VARCHAR(MAX);
			DECLARE @IsDomainAdmin_query2 VARCHAR(MAX);
			DECLARE @IsDomainAdmin VARCHAR(MAX);
			
			-- REMOVE ISDOMAINADMIN TEMP TABLE IF IT EXISTS
			IF OBJECT_ID('tempdb..#IsDomainAdmin') IS NOT NULL DROP TABLE #IsDomainAdmin
			
			-- CREATE TEMP TABLE TO HELP DETERMINE SERVICES ACCOUNT NAME
			CREATE TABLE #IsDomainAdmin
			( IsDomainAdmin VARCHAR(MAX) );
			
			-- QUERY TO CHECK IF SERVICE ACCOUNT IS A DOMAIN ADMIN 
			SET @IsDomainAdmin_query1 = 'DECLARE @SAO_status VARCHAR(2);DECLARE @SAO_change VARCHAR(2);SET @SAO_change = ''''''''0'''''''';IF EXISTS(SELECT null FROM sysobjects WHERE name = ''''''''configurations'''''''') SELECT @SAO_Status = CONVERT(INT, ISNULL(value, value_in_use)) FROM  [master].[sys].[configurations] WHERE (name) = ''''''''show advanced options'''''''';IF(SELECT @SAO_Status) = 0 SET @SAO_change = 1;IF(SELECT @SAO_change) = 1 EXEC [master].[DBO].[sp_configure] ''''''''show advanced options'''''''',1;Reconfigure;DECLARE @XPCMD_status VARCHAR(2);DECLARE @XPCMD_change VARCHAR(2);SET @XPCMD_change = ''''''''0'''''''';IF EXISTS(SELECT null FROM sysobjects WHERE (name) = ''''''''configurations'''''''')SELECT @XPCMD_Status = CONVERT(INT, ISNULL(value, value_in_use)) FROM  [master].[sys].[configurations] WHERE (name) = ''''''''XP_CMDSHELL'''''''' IF(SELECT @XPCMD_Status) = 0 SET @XPCMD_Change = 1;IF(SELECT @XPCMD_Change) = 1 EXEC [master]..sp_configure ''''''''XP_CMDSHELL'''''''',1;Reconfigure;DECLARE @DomainAdminCheck VARCHAR(MAX);DECLARE @MyDAQuery VARCHAR(MAX); DECLARE @AccountName VARCHAR(MAX); DECLARE @IsDomainAdmin VARCHAR(MAX); DECLARE @RemoteServiceAccount VARCHAR(MAX);SET @RemoteServiceAccount = '''''''''+ @RemoteServiceAccount +''''''''';SET @IsDomainAdmin = ''''''''No'''''''';IF OBJECT_ID(''''''''tempdb..#DomainAdmins'''''''') IS NOT NULL DROP TABLE #DomainAdmins;CREATE TABLE #DomainAdmins( DomainAdmin VARCHAR(MAX));IF (CHARINDEX(''''''''.'''''''',@RemoteServiceAccount)) = 0 IF (SELECT CHARINDEX(''''''''NT AUTHORITY'''''''',@RemoteServiceAccount)) = 0 IF (REPLACE(@RemoteServiceAccount,''''''''.\'''''''','''''''''''''''')) != ''''''''LocalSystem'''''''' SET @AccountName = substring(@RemoteServiceAccount,CHARINDEX(''''''''\'''''''',@RemoteServiceAccount)+1,LEN(@RemoteServiceAccount)-CHARINDEX(''''''''\'''''''',@RemoteServiceAccount));SET @MyDAQuery = ''''''''exec [master].dbo.XP_CMDSHELL ''''''''''''''''net user ''''''''+ @AccountName +'''''''' /Domain'''''''''''''''''''''''';INSERT #DomainAdmins EXEC (@MyDAQuery);SELECT @DomainAdminCheck = count(DomainAdmin) FROM #DomainAdmins WHERE DomainAdmin like ''''''''%Domain Admins%'''''''';IF (SELECT @DomainAdminCheck) > 0 SET @IsDomainAdmin = ''''''''Yes'''''''';SELECT @IsDomainAdmin IF(SELECT @XPCMD_Change) = 1 EXEC [master].[DBO].[sp_configure] ''''''''XP_CMDSHELL'''''''',0;Reconfigure;IF(SELECT @SAO_change) = 1 EXEC [master].[DBO].[sp_configure] ''''''''show advanced options'''''''',0;Reconfigure;';
						
			-- SETUP QUERY TO RUN THE @ISLOCALADMIN_QUERY1 QUERY ON THE REMOTE DATABASE SERVER VIA XP_CMDSHELL AND SQLCMD
			SET @IsDomainAdmin_query2 = 'INSERT #IsDomainAdmin EXEC(''XP_CMDSHELL ''''SQLCMD -E -S "'+@RemoteServerName+'" -Q "'+@IsDomainAdmin_query1+'"|find /V /I "-" '''''') '	

			-- RUN THE QUERIES
			EXEC(@IsDomainAdmin_query2);
			
			-- SET DOMAIN ADMIN STATUS
			IF @IsDomainAdmin != 'Yes' and @IsDomainAdmin != 'No' 
			BEGIN
				SET @IsDomainAdmin = 'No'; -- Typically means no rights to check
			END
			ELSE
			BEGIN
				SELECT @IsDomainAdmin = IsDomainAdmin FROM #IsDomainAdmin WHERE IsDomainAdmin = 'Yes' OR IsDomainAdmin = 'No';
			END
			
			----------------------------------------------------------------------------------
			-- CHECK SERVICE ACCOUNT PRIVILEGES - DOMAIN ADMINISTRATOR - WITH LOCAL SQL SERVER
			----------------------------------------------------------------------------------		
			-- ONLY RUN IF REMOTE ATTEMPT FAILED
			IF  @IsDomainAdmin != 'Yes'

				DECLARE @AccountName VARCHAR(MAX);
				DECLARE @DomainAdminCheck VARCHAR(MAX);
				DECLARE @MyDAQuery VARCHAR(MAX);

				-- Ensure service account IS NOT local	
				IF (CHARINDEX('.',@RemoteServiceAccount)) = 0 
			
				-- Ensure the service account IS NOT an 'nt' account (NT Authority\NetworkService or NT Authority\LocalService)
				IF (SELECT CHARINDEX('NT AUTHORITY',@RemoteServiceAccount)) = 0
				
					-- Ensure the service account IS NOT LocalSystem
					IF (REPLACE(@RemoteServiceAccount,'.\','')) != 'LocalSystem' 
						
						-- Check IF the service account is in the Domain Admins group
						SET @AccountName = substring(@RemoteServiceAccount,CHARINDEX('\',@RemoteServiceAccount)+1,LEN(@RemoteServiceAccount)-CHARINDEX('\',@RemoteServiceAccount)); 					
						SET @MyDAQuery = 'exec [master].dbo.XP_CMDSHELL ''net user "'+ @AccountName +'" /Domain''';
						DELETE FROM #IsDomainAdmin;
						INSERT #IsDomainAdmin
						EXEC (@MyDAQuery);					
						SELECT @DomainAdminCheck = count(IsDomainAdmin) FROM #IsDomainAdmin WHERE IsDomainAdmin like '%Domain Admins%';
						IF (SELECT @DomainAdminCheck) > 0 SET @IsDomainAdmin = 'Yes';
													
			-------------------------------------------------------------------------------
			-- CHECK IF LOCAL ADMIN PRIVS COULD BE READ FROM REMOTE SERVER WITH XP_CMDSHELL
			-------------------------------------------------------------------------------
			IF  @IsDomainAdmin = 'Yes' SET @IsLocalAdmin = 'Yes'
			IF  @IsLocalAdmin != 'Yes' AND  @IsLocalAdmin != 'No' 
				SET @IsLocalAdmin = 'Uknnown - No access to xp_cmdshell';

			----------------------------------------------------------------------------------
			-- CHECK IF DOMAIN ADMIN PRIVS COULD BE READ FROM REMOTE SERVER WITH XP_CMDSHELL
			----------------------------------------------------------------------------------
			IF  @IsDomainAdmin != 'Yes' AND  @IsDomainAdmin != 'No'
				SET @IsDomainAdmin = 'Uknnown - No access to xp_cmdshell';

			-------------------------------------------------------------------------
			-- GET REMOTE DB SERVER VERSION
			-------------------------------------------------------------------------
			DECLARE @RemoteDBVersion VARCHAR(MAX);
			DECLARE @VersionQuery1 VARCHAR(MAX);
			DECLARE @VersionQuery2 VARCHAR(MAX);
			
			-- REMOVE VERSION TEMP TABLE IF IT EXISTS
			IF OBJECT_ID('tempdb..#version') IS NOT NULL DROP TABLE #version
			
			-- CREATE VERSION TABLE TO HELP DETERMINE SERVICES ACCOUNT NAME
			CREATE TABLE #version
			( version VARCHAR(MAX));
			
			-- SET REMOTE DATABASE VERSION
			SET @VersionQuery1 = 'SELECT Left(@@Version,CHARINDEX(''''''''-'''''''',@@version)-1)+ rtrim(CONVERT(char(30), SERVERPROPERTY(''''''''Edition''''''''))) +'''''''' ''''''''+ RTRIM(CONVERT(char(20), SERVERPROPERTY(''''''''ProductLevel'''''''')))+ CHAR(10)';
			
			-- SETUP QUERY TO RUN THE @VERSION_QUERY1 QUERY ON THE REMOTE DATABASE SERVER VIA @@VERSION
			SET @VersionQuery2 = 'INSERT #version EXEC(''XP_CMDSHELL ''''SQLCMD -E -S "'+@RemoteServerName+'" -Q "' + @VersionQuery1 + '"'''''')';				

			-- RUN THE QUERIES
			EXEC(@VersionQuery2);
			
			-- SET LOCAL ADMIN STATUS
			SELECT @RemoteDBVersion = version FROM #version WHERE version like 'Microsoft%';

			-------------------------------------------------------------------------------------
			-- CHECK IF THE SERVICE ACCOUNT/MACHINE ACCOUNT HAS SYSADMIN ON THE REMOTE CONNCETION
			-------------------------------------------------------------------------------------
			DECLARE @SysadminCheck VARCHAR(MAX);
			DECLARE @SysadminStatus VARCHAR(MAX);
			DECLARE @SysadminQuery1 VARCHAR(MAX);
			DECLARE @SysadminQuery2 VARCHAR(MAX);
			
			-- REMOVE VERSION TEMP TABLE IF IT EXISTS
			IF OBJECT_ID('tempdb..#sysadmin') IS NOT NULL DROP TABLE #sysadmin
			
			-- CREATE VERSION TABLE TO HELP DETERMINE SERVICES ACCOUNT NAME
			CREATE TABLE #sysadmin
			( sysadmin VARCHAR(MAX));
			
			-- QUERY TO CHECK IF SERVICE ACCOUNT / DOMAIN ACCOUNT HAS SYSADMIN RIGHT ON REMOTE DB SERVER
			SET @SysadminQuery1 = 'SELECT IS_SRVROLEMEMBER(''''''''sysadmin'''''''')';
			
			-- SETUP QUERY TO RUN 
			SET @SysadminQuery2 = 'INSERT #sysadmin EXEC(''XP_CMDSHELL ''''SQLCMD -E -S "'+@RemoteServerName+'" -Q "' + @SysadminQuery1 + '"'''''')'				

			-- RUN THE QUERIES
			EXEC(@SysadminQuery2);					

			-- SET SYSADMIN STATUS
			SELECT @SysadminCheck = sysadmin FROM #sysadmin WHERE sysadmin NOT LIKE'%rows%' AND sysadmin NOT LIKE'%null%' AND sysadmin NOT LIKE'%-%'AND sysadmin NOT LIKE ' ';
			IF (SELECT @SysadminCheck) = 1 SET @SysadminStatus = 'Yes'
			IF (SELECT @SysadminCheck) = 0 SET @SysadminStatus = 'No'
			-------------------------------------------------------------------------------------
			-- GET SERVICE ACCOUNT USED DURING CONNECTION
			-------------------------------------------------------------------------------------
			DECLARE @MYSVCACCOUNT VARCHAR(MAX);		
			DECLARE @MYSVCQuery1 VARCHAR(MAX);
			DECLARE @MYSVCQuery2 VARCHAR(MAX);
			
			-- REMOVE VERSION TEMP TABLE IF IT EXISTS
			IF OBJECT_ID('tempdb..#GETACCOUNT') IS NOT NULL DROP TABLE #GETACCOUNT
			
			-- CREATE VERSION TABLE TO HELP DETERMINE SERVICES ACCOUNT NAME
			CREATE TABLE #GETACCOUNT
			( GETACCOUNT VARCHAR(MAX));
			
			-- QUERY TO CHECK IF SERVICE ACCOUNT / DOMAIN ACCOUNT HAS SYSADMIN RIGHT ON REMOTE DB SERVER
			SET @MYSVCQuery1 = 'SELECT SYSTEM_USER';
			
			-- SETUP QUERY TO RUN 
			SET @MYSVCQuery2 = 'INSERT #GETACCOUNT EXEC(''XP_CMDSHELL ''''SQLCMD -E -S "'+@RemoteServerName+'" -Q "' + @MYSVCQuery1 + '"'''''')'				

			-- RUN THE QUERIES
			EXEC(@MYSVCQuery2);					

			-- SET SYSADMIN STATUS
			SELECT @MYSVCACCOUNT = GETACCOUNT FROM #GETACCOUNT WHERE GETACCOUNT NOT LIKE'%rows%' AND GETACCOUNT NOT LIKE'%null%' AND GETACCOUNT NOT LIKE'%-%'AND GETACCOUNT NOT LIKE ' ';			
				
			-------------------------------------------------------------------------
			-- GENERATE AFFECTED SERVER RECORD FOR OUTPUT
			-------------------------------------------------------------------------		
			INSERT #AffectedServers
			SELECT @RemoteServerName,@RemoteDBVersion,@MYSVCACCOUNT,@ConHasPublic,@SysadminStatus,@RemoteServiceAccount,@IsLocalAdmin,@IsDomainAdmin
			
			END
				
			-- CLOSE CURSOR
			FETCH NEXT FROM MY_CURSOR INTO @myserver

			END   
			CLOSE MY_CURSOR
			DEALLOCATE MY_CURSOR
		
	 
			-------------------------------------------------------------------------
			-- LIST SQL SERVERS USING SHARED SERVICES ACCOUNT AND IF IT HAS LOCAL/DOMAIN 
			-- ADMIN PRIVILEGES; THIS WILL ALSO SHOW MOST SQL SERVER EXPRESS
			-- INSTANCES THAT ARE ON THE DOMAIN AND HAVE A LISTENER ENABLED.
			-------------------------------------------------------------------------
			SELECT AffectedServer,RemoteDatabaseVersion,AccountUsedToCon,ConnectionHasPublic as DBConnection,ConnectionHasSysadmin,RemoteServiceAccount as Remote_SvcAccntName,SvcAccntIsLocalAdmin as Remote_SvcAccntIsLocalAdmin,SvcAccntIsDomainAdmin as Remote_SvcAccntIsDomainAdmin  FROM #AffectedServers order by AffectedServer;
			 
		END	
		ELSE
		BEGIN
			SELECT 'No SQL Server exists on the broadcast network or the local/network firewall is blocking UDP traffic.'
		END
	-------------------------------------------------------------------------
	-- REMOVE TEMP TABLES
	-------------------------------------------------------------------------
	IF OBJECT_ID('tempdb..#instances') IS NOT NULL DROP TABLE #Instances;
	IF OBJECT_ID('tempdb..#AffectedServers') IS NOT NULL DROP TABLE #AffectedServers;
	IF OBJECT_ID('tempdb..#IsDomainAdmin') IS NOT NULL DROP TABLE #IsDomainAdmin;
	IF OBJECT_ID('tempdb..#SharedInstances') IS NOT NULL DROP TABLE #SharedInstances;
	IF OBJECT_ID('tempdb..#IsLocalAdmin') IS NOT NULL DROP TABLE #IsLocalAdmin;
	IF OBJECT_ID('tempdb..#sysadmin') IS NOT NULL DROP TABLE #sysadmin
	IF OBJECT_ID('tempdb..#version') IS NOT NULL DROP TABLE #version	
	
	------------------------------------------
	-- DISABLE XP_CMDSHELL - IF REQUIRED
	------------------------------------------
	IF(SELECT @XPCMD_Change) = 1 EXEC [master].[DBO].[sp_configure] 'XP_CMDSHELL',0
	Reconfigure;
	
	----------------------------------------------
	-- DISABLE SHOW ADVANCED OPTIONS - IF REQUIRED
	----------------------------------------------
	IF(SELECT @SAO_change) = 1 EXEC [master].[DBO].[sp_configure] 'show advanced options',0
	Reconfigure;
				
END
