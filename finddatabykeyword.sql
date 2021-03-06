/* ================================================
 Filename: FindDataByKeyword_v1.4.sql
 Date: 06/28/2012
 Author: Scott Sutherland
 Email: scott.sutherland@netspi.com
-----------------------------------------
Description: 
This script will search through all of the non-default 
databases on the SQL Server for columns that match the 
keywords defined in the �WHERE� clause.  If columns 
names are found that match the defined keywords and 
data is present in the associated tables, the script 
will select a sample of up to five records from each 
of the affected tables. For more information please 
refer to the comments in the script.  

Note: This only works on SQL Server 2000, 2k5 and 2k8 

 The basic logic in this script includes
 the following:
 - Check if there are non-default databases.
 - Check if the user has access to the existing 
   non-default databases.
 - Check if any columns of interest exist in the
   available non-default databases.
 - Check if there is any data available in the
   accessible columns of interest.
 - Return a sample of up to X rows for each 
   column containing interesting data.
================================================ */

-- CHECK IF VERSION IS COMPATABLE => than 2000
		IF (SELECT SUBSTRING(CAST(SERVERPROPERTY('ProductVersion') as VARCHAR), 1, CHARINDEX('.',cast(SERVERPROPERTY('ProductVersion') as VARCHAR),1)-1)) >	0
		BEGIN
			
			-- TURN OFF ROW COUNT
			SET NOCOUNT ON;			
			--------------------------------------------------
			-- SETUP UP SAMPLE SIZE
			--------------------------------------------------
			DECLARE @SAMPLE_COUNT varchar(800);
			SET @SAMPLE_COUNT = 1;

			--------------------------------------------------
			-- SETUP KEYWORDS TO SEARCH
			--------------------------------------------------
			DECLARE @KEYWORDS varchar(800);	
			SET @KEYWORDS = 'pass|credit|ssn|';
			
			--------------------------------------------------
			--SETUP WHERE STATEMENT CONTAINING KEYWORDS
			--------------------------------------------------
			DECLARE @SEARCH_TERMS varchar(800);	
			SET @SEARCH_TERMS = ''; -- Leave this blank

			-- START WHILE LOOP HERE -- BEGIN TO ITTERATE THROUGH KEYWORDS
				
				WHILE LEN(@KEYWORDS) > 0 
					BEGIN
						--SET VARIABLES UP FOR PARSING PROCESS
						DECLARE @change int
						DECLARE @keyword varchar(800)
							
						--SET KEYWORD CHANGE TRACKER
						SELECT @change = CHARINDEX('|',@KEYWORDS); 		
							
						--PARSE KEYWORD	
						SELECT @keyword = SUBSTRING(@KEYWORDS,0,@change) ;
							
						-- PROCESS KEYWORD AND GENERATE WHERE CLAUSE FOR IT	
						SELECT @SEARCH_TERMS = 'LOWER(COLUMN_NAME) like ''%'+@keyword+'%'' or '+@SEARCH_TERMS

						-- REMOVE PROCESSED KEYWORD
						SET @KEYWORDS = SUBSTRING(@KEYWORDS,@change+1,LEN(@KEYWORDS));
						
					END
			    		
				-- REMOVE UNEEDED 					
				SELECT @SEARCH_TERMS = SUBSTRING(@SEARCH_TERMS,0,LEN(@SEARCH_TERMS)-2);

			--------------------------------------------------
			-- CREATE GLOBAL TEMP TABLES
			--------------------------------------------------
			USE master;

			IF OBJECT_ID('tempdb..##mytable') IS NOT NULL DROP TABLE ##mytable;
			IF OBJECT_ID('tempdb..##mytable') IS NULL 
			BEGIN 
				CREATE TABLE ##mytable (
					server_name varchar(800),
					database_name varchar(800),
					table_schema varchar(800),
					table_name varchar(800),		
					column_name varchar(800),
					column_data_type varchar(800)
				) 
			END

			IF OBJECT_ID('tempdb..##mytable2') IS NOT NULL DROP TABLE ##mytable2;
			IF OBJECT_ID('tempdb..##mytable2') IS NULL 
			BEGIN 
				CREATE TABLE ##mytable2 (
					server_name varchar(800),
					database_name varchar(800),
					table_schema varchar(800),
					table_name varchar(800),
					column_name varchar(800),
					column_data_type varchar(800),
					column_value varchar(800),
					column_data_row_count varchar(800)
				) 
			END

			--------------------------------------------------
			-- CURSOR1
			-- ENUMERATE COLUMNS FROM EACH DATABASE THAT 
			-- CONTAIN KEYWORD AND WRITE THEM TO A TEMP TABLE 
			--------------------------------------------------

			-- SETUP SOME VARIABLES FOR THE MYCURSOR1
			DECLARE @var1 varchar(800);
			DECLARE @var2 varchar(800);

			--------------------------------------------------------------------
			-- CHECK IF ANY NON-DEFAULT DATABASE EXIST
			--------------------------------------------------------------------
			IF (SELECT count(*) FROM master..sysdatabases WHERE name NOT IN ('master','tempdb','model','msdb') and HAS_DBACCESS(name) <> 0) <> 0 
			BEGIN
				DECLARE MY_CURSOR1 CURSOR
				FOR

				SELECT name FROM master..sysdatabases WHERE name NOT IN ('master','tempdb','model','msdb') and HAS_DBACCESS(name) <> 0;

				OPEN MY_CURSOR1
				FETCH NEXT FROM MY_CURSOR1 INTO @var1
				WHILE @@FETCH_STATUS = 0   
				BEGIN  	
				------------------------------------------------------------------------------------------------
				-- SEARCH FOR KEYWORDS and INSERT AFFECTEED SERVER/DATABASE/SCHEMA/TABLE/COLUMN INTO MYTABLE			
				------------------------------------------------------------------------------------------------
				SET @var2 = ' 	
				INSERT INTO ##mytable
				SELECT @@SERVERNAME as SERVER_NAME,TABLE_CATALOG as DATABASE_NAME,TABLE_SCHEMA,TABLE_NAME,COLUMN_NAME,DATA_TYPE
				FROM ['+@var1+'].[INFORMATION_SCHEMA].[COLUMNS] WHERE '
				
				--APPEND KEYWORDS TO QUERY
				DECLARE @fullquery varchar(800);
				SET @fullquery = @var2+@SEARCH_TERMS;				
					
				EXEC(@fullquery);	
				FETCH NEXT FROM MY_CURSOR1 INTO @var1

				END   
				CLOSE MY_CURSOR1
				DEALLOCATE MY_CURSOR1

				 -------------------------------------------------
				 -- CURSOR2
				 -- TAKE A X RECORD SAMPLE FROM EACH OF THE COLUMNS
				 -- THAT MATCH THE DEFINED KEYWORDS
				 -- NOTE: THIS WILL NOT SAMPLE EMPTY TABLES
				 -------------------------------------------------
				
				IF (SELECT COUNT(*) FROM ##mytable) < 1
					BEGIN	
						SELECT 'No columns where found that match the defined keywords.' as Message;
					END
				ELSE
					BEGIN			
						DECLARE @var_server varchar(800)
						DECLARE @var_database varchar(800)
						DECLARE @var_table varchar(800)
						DECLARE @var_table_schema varchar(800)
						DECLARE @var_column_data_type varchar(800)
						DECLARE @var_column varchar(800)
						DECLARE @myquery varchar(800)
						DECLARE @var_column_data_row_count varchar(800)
						
						DECLARE MY_CURSOR2 CURSOR
						FOR
						SELECT server_name,database_name,table_schema,table_name,column_name,column_data_type FROM ##mytable

							OPEN MY_CURSOR2
							FETCH NEXT FROM MY_CURSOR2 INTO @var_server,@var_database,@var_table_schema,@var_table,@var_column,@var_column_data_type
							WHILE @@FETCH_STATUS = 0   
							BEGIN  
							----------------------------------------------------------------------
							-- ADD AFFECTED SERVER/SCHEMA/TABLE/COLUMN/DATATYPE/SAMPLE DATA TO MYTABLE2
							----------------------------------------------------------------------
							-- GET COUNT
							DECLARE @mycount_query as varchar(800);
							DECLARE @mycount as varchar(800);

							-- CREATE TEMP TABLE TO GET THE COLUMN DATA ROW COUNT
							IF OBJECT_ID('tempdb..#mycount') IS NOT NULL DROP TABLE #mycount
							CREATE TABLE #mycount(mycount varchar(800));
							
							-- SETUP AND EXECUTE THE COLUMN DATA ROW COUNT QUERY
							SET @mycount_query = 'INSERT INTO #mycount SELECT DISTINCT 
												  COUNT('+@var_column+') FROM '+@var_database+'.
												  '+@var_table_schema+'.'+@var_table;
							EXEC(@mycount_query);

							-- SET THE COLUMN DATA ROW COUNT
							SELECT @mycount = mycount FROM #mycount;		
							
							-- REMOVE TEMP TABLE
							IF OBJECT_ID('tempdb..#mycount') IS NOT NULL DROP TABLE #mycount				

							SET @myquery = ' 	
							INSERT INTO ##mytable2 
										(server_name,
										database_name,
										table_schema,
										table_name,
										column_name,
										column_data_type,
										column_value,
										column_data_row_count) 
							SELECT TOP '+@SAMPLE_COUNT+' ('''+@var_server+''') as server_name,
										('''+@var_database+''') as database_name,
										('''+@var_table_schema+''') as table_schema,
										('''+@var_table+''') as table_name,
										('''+@var_column+''') as comlumn_name,
										('''+@var_column_data_type+''') as column_data_type,
										'+@var_column+','+@mycount+' as column_data_row_count 
							FROM ['+@var_database+'].['+@var_table_schema++'].['+@var_table+'] 
							WHERE '+@var_column+' IS NOT NULL;
							'	
							EXEC(@myquery);

							FETCH NEXT FROM MY_CURSOR2 INTO 
										@var_server,
										@var_database,
										@var_table_schema,
										@var_table,@var_column,
										@var_column_data_type
							END   
						CLOSE MY_CURSOR2
						DEALLOCATE MY_CURSOR2

						-----------------------------------
						-- SELECT THE RESULTS OF THE SEARCH
						-----------------------------------
						IF (SELECT @SAMPLE_COUNT)= 1
							BEGIN
								SELECT DISTINCT cast(server_name as CHAR) as server_name,cast(database_name as char) as database_name,cast(table_schema as char) as table_schema,cast(table_name as char) as table_schema,cast(column_name as char) as column_name,cast(column_data_type as char) as column_data_type,cast(column_value as char) as column_data_sample,cast(column_data_row_count as char) as column_data_row_count FROM ##mytable2 --ORDER BY server_name,database_name,table_schema,table_name,column_name,column_value asc
								
							END	
						ELSE
							BEGIN
								SELECT DISTINCT cast(server_name as CHAR) as server_name,cast(database_name as char) as database_name,cast(table_schema as char) as table_schema,cast(table_name as char) as table_schema,cast(column_name as char) as column_name,cast(column_data_type as char) as column_data_type,cast(column_value as char) as column_data_sample,cast(column_data_row_count as char) as column_data_row_count FROM ##mytable2 --ORDER BY server_name,database_name,table_schema,table_name,column_name,column_value asc							
							END
					END
			-----------------------------------
			-- REMOVE GLOBAL TEMP TABLES
			-----------------------------------
			IF OBJECT_ID('tempdb..##mytable') IS NOT NULL DROP TABLE ##mytable;
			IF OBJECT_ID('tempdb..##mytable2') IS NOT NULL DROP TABLE ##mytable2;
				
			END
			ELSE
			BEGIN
				----------------------------------------------------------------------
				-- RETURN ERROR MESSAGES IF THERE ARE NOT DATABASES TO ACCESS
				----------------------------------------------------------------------
				IF (SELECT count(*) FROM master..sysdatabases WHERE name NOT IN ('master','tempdb','model','msdb')) < 1	
					SELECT 'No non-default databases exist to search.' as Message;
				ELSE
					SELECT 'Non-default databases exist, but the current user does not have the privileges to access them.' as Message;				
				END
		END
		else
		BEGIN
			SELECT 'This module only works on SQL Server 2005 and above.';
		END
		
		SET NOCOUNT OFF;