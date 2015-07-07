<html>
<body>

<table align="left" border="0" width="200">
<tr>
 <td align="center">
	<font size="20">MBA</font><br>
 	My Bad Application
 </td>
</tr>
<tr>
<td align="center">
<a href="/search.asp">Employee Search</a>
 </td>
</tr>
</table>
<Br><Br><Br><Br><Br><Br>
<table border="0" width="200">
<tr>
 <td align="left"><br><br>
<h3>Employee Search</h3>
<form action="" method="GET" name="searchform">
<input type="text" name="search" id="search">
<input type="submit" value="Search">
</form>	
<%

'Sample Database Connection Syntax for ASP and SQL Server.
Dim oConn, oRs
Dim qry, connectstr
Dim db_name, db_username, db_userpassword
Dim db_server
Dim my_search

' update the db_server with your server and instance
db_server = "mybox\server1"
db_name = "AdventureWorks2008"
db_username = "s1user"
db_password = "s1password"

'setup database handler
Set oConn = Server.CreateObject("ADODB.Connection")
oConn.Open("Driver={SQL Server};Server=" & db_server & ";Database=" & db_name &";UID=" & db_username & ";PWD=" & db_password & ";Trusted_Connection=NO;")

'setup query
qry = "SELECT LoginID,BusinessEntityID FROM HumanResources.Employee WHERE LoginID LIKE '%" & Request("search") & "%'"

'execute query
Set oRS = oConn.Execute(qry)

'output status to user
Response.Write "<strong>Search Results for:</strong>&nbsp;" & Request("search") & "<br>"

'loop through and print results
Do until oRs.EOF
   Response.Write "<a href=/employee.asp?id=" & oRs.Fields("BusinessEntityID") & ">" & oRs.Fields("LoginID") & "</a><br>"
   oRS.MoveNext
Loop
oRs.Close


Set oRs = nothing
Set oConn = nothing

%>

</body>
</html>