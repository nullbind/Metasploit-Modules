<html>
<body>

<table align="left" border="0" width="200">
<tr>
 <td align="center">
	<font size="20">SSL v.3</font><br>
 	Super Spy Lookup Version 3
 </td>
</tr>
</table>

<Br><Br><Br><Br><Br><Br>
<table border="0"
<tr>
 <td align="left">
<h3>NOC List Search Results</h3>
<%

'Sample Database Connection Syntax for ASP and SQL Server.

Dim oConn, oRs
Dim qry, connectstr
Dim db_name, db_username, db_userpassword
Dim db_server
Dim my_search

id = Request("id")
db_server = "LVA"
db_name = "MyAppDB"
db_username = "MyPublicUser"
db_userpassword = "MyPassword!"
fieldname = "ID"
tablename = "noclist"

connectstr = "Driver={SQL Server};SERVER=" & db_server & ";DATABASE=" & db_name & ";UID=" & db_username & ";PWD=" & db_userpassword

Set oConn = Server.CreateObject("ADODB.Connection")
oConn.Open connectstr
 
'standard search query
qry = "SELECT * FROM " & tablename & " WHERE ID = " & Request("id")
'qry = "SELECT * FROM " & tablename

Set oRS = oConn.Execute(qry)

Do until oRs.EOF

   Response.Write "<strong>ID:</strong>&nbsp;" & oRs.Fields("id") & "<br>"
   Response.Write "<strong>Title:&nbsp;</strong>" & oRs.Fields("spyname") & "<br>"
   Response.Write "<strong>User:&nbsp;</strong>" & oRs.Fields("realname") & "<br><br>"

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
