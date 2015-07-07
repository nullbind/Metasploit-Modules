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

<Br><Br><Br><Br><Br><Br><Br><Br>
<table border="0"
<tr>
 <td align="left">
<h3>Employee Information</h3>
<%

'Sample Database Connection Syntax for ASP and SQL Server.

Dim oConn, oRs
Dim qry, connectstr
Dim db_name, db_username, db_userpassword
Dim db_server
Dim myid

' update the db_server with your server and instance
db_server = "mybox\server1"
db_name = "AdventureWorks2008"
db_username = "s1user"
db_password = "s1password"

'setup database handler
Set oConn = Server.CreateObject("ADODB.Connection")
oConn.Open("Driver={SQL Server};Server=" & db_server & ";Database=" & db_name &";UID=" & db_username & ";PWD=" & db_password & ";Trusted_Connection=NO;")

'setup query
qry = "SELECT * FROM HumanResources.Employee WHERE BusinessEntityID = " & Request("id")

'execute query
Set oRS = oConn.Execute(qry)

'loop through and display records
Do until oRs.EOF

   Response.Write "<strong>ID:</strong>&nbsp;" & oRs.Fields("BusinessEntityID") & "<br>"
   Response.Write "<strong>Title:&nbsp;</strong>" & oRs.Fields("JobTitle") & "<br>"
   Response.Write "<strong>User:&nbsp;</strong>" & oRs.Fields("LoginID") & "<br>"
   Response.Write "<strong>Birth Date:&nbsp;</strong>" & oRs.Fields("BirthDate") & "<br>"

   oRS.MoveNext
Loop
oRs.Close


Set oRs = nothing
Set oConn = nothing

%>
 </td>
</tr>
</table>
</body>
</html>
