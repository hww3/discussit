//
// This is a Roxen module.
//
// Written by Bill Welliver, <hww3@riverweb.com>
// (c) copyright 1999 Bill Welliver
//

string cvs_version = "$Id: discussit.pike,v 1.5 2001-02-08 00:15:27 hww3 Exp $";

#include <module.h>
#include <process.h>
inherit "module";
inherit "roxenlib";

#define SQLCONNECT(X) X=id->conf->sql_connect(dbserver)
#define ERROR(X) perror("DiscussIt!: " + X + "\n")
array register_module()
{
  return ({ MODULE_PARSER,
            "DiscussIt!",
            "Database driven discussion groups.<p>\n"
	"Usage:<p>"
	"&lt;forum&gt; "
	"&lt;forum_admin&gt; "
		, ({}), 1
            });
}

void create()
{

defvar("dbserver", "localhost", "Database Host",
	TYPE_STRING,
	"This is the name of the host running the SQL server. "
	"By using 'localhost' as the value, the same machine that Roxen "
	"is running on (recommended) will be used.\n");

defvar("autocreate", 0, "Forum auto creation?",
	TYPE_FLAG,
	"This flag toggles DiscussIt!'s ability to automatically "
	"create new forums.\n");

}

string|void check_variable(string variable, mixed set_to)
{

}

string dbserver;

void start()
{
 dbserver=query("dbserver");
 
 mixed err;

// ERROR("Starting up!");

 err=catch(object s=Sql.sql(query("dbserver")));
 if(err) { 
  ERROR("Unable to connect to db.");
  return;
  }

 if(sizeof(s->list_tables("forum_names"))!=1)
  s->query("CREATE TABLE forum_names ( "
   "id INTEGER AUTO_INCREMENT PRIMARY KEY, "
   "forum_name char(64), "
   "forum_description blob,"
   "stamp datetime) ");

 if(sizeof(s->list_tables("users"))!=1)
  s->query("CREATE TABLE users ( "
   "userid INTEGER AUTO_INCREMENT PRIMARY KEY, "
   "username char(16), "
   "password char(16), "
   "real_name char(64), "
   "email char(96),"
   "stamp datetime) ");

 if(sizeof(s->list_tables("read_entries"))!=1)
  s->query("CREATE TABLE read_entries ( "
   "userid INTEGER NOT NULL, "
   "article_id INTEGER NOT NULL, "
   "forum_id INTEGER, "
   "stamp datetime,"
   "KEY user_article (userid, article_id)) ");

 if(sizeof(s->list_tables("articles"))!=1)
  s->query("CREATE TABLE articles ( "
  "id integer auto_increment primary key, "
  "forum integer not null, "
  "parent integer default 0, "
  "subject char(255), "
  "userid INTEGER, "
  "text blob, "
  "stats integer, "
  "stamp datetime) ");

}

string do_post(object id, mixed v){

 mixed err;

 err=catch(SQLCONNECT(object s));
 if(err) { 
  ERROR("Unable to connect to database while doing create_forum().");
  return 0;
  }

  if(!id->cookies->userid || id->cookies->userid=="")
   return "<forumsgetauth>";

  array u=s->query("SELECT * FROM users WHERE userid=" +
   id->cookies->userid);
  if(sizeof(u)!=1)
   return "Unable to find your user id.";
  array r=s->query("SELECT * FROM forum_names WHERE id=" + v->forum);

  s->query("INSERT INTO articles VALUES(NULL, " + r[0]->id + "," +
    (v->in_reply_to ||"0") + ",'" + s->quote(v->subject) + "'," +
    u[0]->userid + ",'" + s->quote(v->post) + "',0,NOW())"); 

  return "Your post was added successfully.<p>"
     "<a href=\"" + id->not_query + "?forum=" + id->variables->forum + "&"
     + time() + "\">Continue...</a>";

}

int create_forum(string name, string description, object id)
{

 mixed err;

 err=catch(SQLCONNECT(object s));
 if(err) { 
  ERROR("Unable to connect to database while doing create_forum().");
  return 0;
  }

 string table=replace(lower_case(name)," ","_");

 s->query("INSERT INTO forum_names VALUES(NULL, '" + s->quote(name) +
  "','" + s->quote(description) + "',NOW())");

 return s->query("SELECT id FROM forum_names WHERE forum_name='" +
  s->quote(name) + "'")[0]->id;

}

int delete_forum(int forum, object id)
{

 mixed err;

 err=catch(SQLCONNECT(object s));
 if(err) { 
  ERROR("Unable to connect to database while doing delete_forum().");
  return 0;
  }

array r=s->query("SELECT * FROM forum_names WHERE id=" + forum );
s->query("DELETE FROM forum_names WHERE id=" + forum );
s->query("DELETE FROM articles WHERE forum=" + forum );
s->query("DELETE FROM read_entries WHERE forum_id=" + forum );
return 1;

}

string tag_forumsgetauth(string tag_name, mapping args,
	object id, mapping defines)
{

string retval="";

 mixed err;

 err=catch(SQLCONNECT(object s));
 if(err) { 
  ERROR("Unable to connect to database while doing create_forum().");
  return "An error occurred while connecting to the DiscussIt! database.";
  }

if(id->variables->username && id->variables->password) {
 array r=s->query("SELECT * FROM users WHERE username='" +
  id->variables->username + "' AND password='" + id->variables->password +
  "'");
 if(sizeof(r)==1)
  retval+="<set_cookie name=userid value=\"" + r[0]->userid + "\">"
   "<h3>Login Successful!</h3>\n"
   "<a href=\"" + id->not_query + "?" + id->query + "&" + time() +
   "\">Continue...</a>";
  else retval+="<h3>Login Incorrect</h3>\n<a href=\"" + id->not_query +
   "?" + id->query + "\">Try again.</a>";
  }
 else 
 retval+="<form method=post action=\"" + id->not_query + "?" + id->query + "\">\n"
  "<h3>Login</h3>\nUsername <input type=text name=username><br>"
  "Password <input type=password name=password><p>\n"
  "<input type=submit value=\"Login\"></form>";


return retval;
}

string tag_forum_index(string tag_name, mapping args,
	object id, mapping defines)
{

 string retval="";
 mixed err;

 err=catch(SQLCONNECT(object s));
 if(err) { 
  ERROR("Unable to connect to database while doing tag_forum_index().");
  return "An error occurred while connecting to the DiscussIt! database.";
  }

 array d=s->query("SELECT * FROM forum_names ORDER BY forum_name");

 retval+="<h2>Forums</h2>\n";

 retval+="<ul>\n";

 foreach(d, mapping row){
  array p=s->query("SELECT COUNT(*) as posts FROM articles WHERE forum=" 
   + row->id);
  int numposts=(int)p[0]->posts;
  int unreadposts=(int)numposts;
  if(id->cookies->userid && id->cookies->userid!="") {
   array p=s->query("SELECT *  FROM read_entries "
    "WHERE userid=" + id->cookies->userid + " AND forum_id=" + row->id + 
    " GROUP BY article_id ");

   if(sizeof(p)>0){
    int readposts=sizeof(p);
    unreadposts-=((int)readposts);
    }
   }
   retval+="<li><a href=\"" + id->not_query + "?forum=" + row->id + "\">" 
   + row->forum_name + "</a> ( <i>" + numposts + " posts, " +
   unreadposts + " unread</i> )\n";


 }

 return retval;

}

string tag_subpost(string tag_name, mapping args,
	object id, mapping defines)
{

 string retval="";
 mixed err;
 err=catch(SQLCONNECT(object s));
 if(err) { 
  ERROR("Unable to connect to database.");
  return "Unable to connect to database.";
  }

  array r=s->query("SELECT articles.*, DATE_FORMAT(" +
   "articles.stamp, "
   "'%e %M %Y') AS time, users.real_name AS name FROM articles "
   ",users WHERE parent=" + args->parent + " AND users.userid=" + 
   "articles.userid");

  foreach(r, mapping row){
   int unread=1;
   if(id->cookies->userid && id->cookies->userid!="") {
    array r=s->query("SELECT * FROM read_entries WHERE userid=" +
id->cookies->userid + " AND article_id=" +
row->id + " GROUP BY article_id");
// ERROR(sprintf("%O", r));
    if(sizeof(r)!=0) unread=0;
    }
   retval+="<ul><li>" + (unread?"<b>":"")+"<a href=\"" + id->not_query +
    "?forum=" + args->forum + "&id=" + row->id + "\">" +
html_encode_string(row->subject) +
    "</a>" + (unread?"</b>":"")+" (" + row->name +
    " <b>on</b> " + row->time + ")\n";
  if(id->misc->forum_admin_user)
    retval+=" &nbsp; <a href=\"" + id->not_query + "?forum=" + args->forum
     + "&id=" + row->id + "&delete=1\">DELETE POST</a>\n";
   retval+="<subpost parent=\"" + row->id + "\""
    " forum=" + args->forum + "></ul>\n";

   }

  if(args->loud && sizeof(r)==0)
   retval+="No follow up discussion found.";

return retval;
}

string tag_forum(string tag_name, mapping args,
	object id, mapping defines)
{
 string retval="";
 string name;
 int forum;
 mixed err;

// connect to the forums database.

 err=catch(SQLCONNECT(object s));
 if(err) { 
  ERROR("Unable to connect to database.");
  return "Unable to connect to database.";
  }

 if(args->id) id->variables->forum=args->id;

 if(id->variables->forum){

  array r=s->query("SELECT * FROM forum_names WHERE id=" +
   id->variables->forum );

  if(sizeof(r)==1) {
   name=r[0]->forum_name;
   forum=r[0]->id;
   }
 }

 else if(args->name) {
  name=args->name;
  array r=s->query("SELECT * FROM forum_names WHERE forum_name='" +
   args->name + "'");
  if(sizeof(r)==1) {
   name=r[0]->forum_name;
   forum=r[0]->id;
   }    
  }
 else if(!args->noindex){
  // we weren't given a forum to fetch, so return an index.

  retval=tag_forum_index("forum_index", args, id, defines);
  return retval;
  }  

  else return "Sorry, DiscussIt! needs a forum to continue.";

// name=replace(lower_case(name), " ", "_");

// see if we have the requested forum.

 if(forum){
  // we have the requested forum.
  retval+="<h2>" + name + "</h2>\n";

 }

 else if(query("autocreate")==1) {
  // forum doesn't exist, but we're allowed to create it.

  string description;
  int res;
  if(args->description) description=args->description;
  else if(id->variables->description)
   description=id->variables->description;
  if(description && args->name)
   res=create_forum(args->name, description, id);
  if(res) {
    forum=res;
    name=args->name;
    
    }
  else return "Sorry, DiscussIt! was unable to create your forum.";
  }
 else {
   return "Sorry, DiscussIt! is unable to find your forum.";
  }

  // put the new post, reply to post, etc code in here...

  if(id->variables->newpost) {

   if(id->variables->dopost){
    
    string res=do_post(id, id->variables);
    retval+=res;
   }
   else {
    retval+="<h3>New Post</h3>\n<form action=\"" + id->not_query + "\">"
     "<input type=hidden name=forum value=\"" + forum + "\">\n"
     "<input type=hidden name=newpost value=\"1\">\n"
     "<input type=hidden name=dopost value=\"1\">\n";

   if(id->variables->in_reply_to)
    /*{
     retval+="<input type=hidden name=in_reply_to value=\""
       + id->variables->in_reply_to + "\">\n"
      "Subject: <input type=text name=subject value=\"Re: \"><br>";
    }*/
   {
		   array r=s->query("SELECT subject from articles where id="+id->variables->in_reply_to);
		   string subject = "Re: ";
		   if(r && sizeof(r))
				   	if(!search(r[0]->subject, "Re: "))
							subject = r[0]->subject;
		   			else
							subject += r[0]->subject;
		   retval+="<input type=hidden name=in_reply_to value=\""
				   + id->variables->in_reply_to + "\">\n"
				   "Subject: <input type=text name=subject value=\""+subject+"\"><br>";
   }
   else
    retval+="Subject: <input type=text name=subject><br>";

    retval+="Post:<br><textarea name=post rows=5 cols=70 wrap></textarea>\n<p>";

    retval+="<input type=submit value=\"Post\"></form>\n";
    }

    }

 else if(!(id->variables->id)) {
  // we don't have a particular post in mind, so show them all.

  array r=s->query("SELECT articles.*, DATE_FORMAT(" 
   "articles.stamp, "
   "'%e %M %Y') AS time, users.real_name as name from articles " 
   ",users WHERE users.userid=articles.userid AND forum=" + 
   forum + " AND parent=0");

  if(sizeof(r)>0) retval+="<ul>\n";

  foreach(r, mapping row){
   int unread=1;
   if(id->cookies->userid && id->cookies->userid!="") {
    array r=s->query("SELECT * FROM read_entries WHERE userid=" +
id->cookies->userid + " AND forum_id=" + forum + " AND article_id=" +
row->id + " GROUP BY article_id");
// ERROR(sprintf("%O", r));
    if(sizeof(r)!=0) unread=0;
    }
    
   retval+="<li>" + (unread?"<b>":"") + "<a href=\"" + id->not_query +
"?forum=" + forum + "&"
    "id=" + row->id + "\">" + html_encode_string(row->subject) + "</a>" +
(unread?"</b>":"") +
   " (" + row->name + " <b>on</b> " + row->time + ")\n";

  if(id->misc->forum_admin_user)
    retval+=" &nbsp; <a href=\"" + id->not_query + "?forum=" + forum
     + "&id=" + row->id + "&delete=1\">DELETE POST</a>\n";

   retval+="<subpost parent=\"" + row->id + "\" "
    " forum=" + forum + ">";
   }
  
  if(sizeof(r)==0) retval+= "Sorry, DiscussIt! was unable to find any posts.";
  else retval+="</ul>\n";
  retval+="<p>[ <a href=\"" + id->not_query + "?newpost=1&forum=" + forum
   + "\">New Post</a> ] ";
  if(!args->noindex)
   retval+="&nbsp; [ <a href=\"" + id->not_query + "?" + time() +
     "\">Index of Forums</a> ] ";
 }

 else {
  // delete the requested post.
  if(id->variables->delete && id->misc->forum_admin_user)
  {  
   int parent=s->query("SELECT parent FROM articles WHERE id=" +
    id->variables->id)[0]->parent || 0;
   s->query("DELETE FROM articles WHERE id=" + id->variables->id);
   s->query("DELETE FROM read_entries WHERE article_id=" +
    id->variables->id);
   s->query("UPDATE articles SET parent=" + parent + " WHERE parent=" +
     id->variables->id);
   retval+="<b>Article Deleted Successfully.</b>"
    "<p><a href=\"" + id->not_query + "?forum=" +
    id->variables->forum + "&" + time() + "\">Continue...</a>"; 
  }
  else {
 // return the post requested.
  array r=s->query("SELECT articles.*, DATE_FORMAT(" +
   "articles.stamp, "
   "'%e %M %Y') AS time, users.real_name as name from articles " 
   ",users WHERE users.userid=articles.userid AND id=" +
   id->variables->id);

  if(sizeof(r)==1){
  if(args->no_html) r[0]->text=replace(r[0]->text, ({">","<"}),
({"&gt;","&lt;"}));
  retval+="<b>Subject:</b> " + html_encode_string(r[0]->subject) + "<br>" 
    "<b>Posted on:</b> " + r[0]->time + " <b>by</b> " +
	html_encode_string(r[0]->name) +
    "<br>\n"
    "<b>Post:</b><p><autoformat>" + html_encode_string(r[0]->text) +
	"</autoformat>"
    "<p>";
  if(id->cookies->userid && id->cookies->userid!="")
   s->query("INSERT INTO read_entries VALUES(" + id->cookies->userid +
    "," + r[0]->id + "," + id->variables->forum + ",NOW())");
  }

  retval+="[ <a href=\"" + id->not_query + "?newpost=1&forum=" + forum + 
   "\">New Post</a> ] " ;
  retval+=" &nbsp; [ <a href=\"" + id->not_query + "?newpost=1&forum=" +
   forum + "&in_reply_to=" + r[0]->id + "\">Post Reply</a> ] ";
  retval+=" &nbsp; [ Previous Post ] ";
  retval+=" &nbsp; [ Next Post ] ";
  retval+=" &nbsp; [ Previous in Thread ] ";
  retval+=" &nbsp; [ Next in Thread ] ";
  retval+=" &nbsp; [ <a href=\"" + id->not_query + "?forum=" +
   forum + "&" + time() + "\">Forum Index</a> ] ";

  if(!args->nofollowups)
   retval+="<h4>Follow Up:</h4>\n<subpost forum=" + forum + " parent=" +
    r[0]->id + " loud>";
 }
 }
return retval;
}

string tag_forum_admin(string tag_name, mapping args,
	object id, mapping defines)
{

string retval="";

id->misc->forum_admin_user=1;

if(id->variables->forum) {

 retval+="<forum id=" + id->variables->forum  + ">";

}

else if(id->variables->create && id->variables->name &&
  id->variables->description) {
 int res=create_forum(id->variables->name, id->variables->description, id);
 retval+="Forum #" + res + ", " + id->variables->name + " created successfully."
  "<p><a href=\"" + id->not_query + "?" + time() + "\">Continue...</a>"; 
 }

else if(id->variables->want_to_create) {

 retval+="<b>Add New Forum</b><p>\n"
  "<form action=\"" + id->not_query + "\">\n"
  "<input type=hidden name=create value=1>\n"
  "<input type=text name=name size=40> Forum Name<br>\n"
  "Description<br>\n"
  "<textarea rows=5 cols=50 wrap name=description></textarea><p>\n"
  "<input type=submit value=\"Add Forum\">\n<p></form>";

}

else if(id->variables->delete_forum) {

 int res=delete_forum(id->variables->delete_forum, id);
 retval+="Forum #" + id->variables->delete_forum + " deleted successfully."
  "<p><a href=\"" + id->not_query + "?" + time() + "\">Continue...</a>"; 


 }

 else {

 mixed err;

 err=catch(SQLCONNECT(object s));
 if(err) { 
  ERROR("Unable to connect to database while doing create_forum().");
  return "An error occurred while connecting to the DiscussIt! database.";
  }

 retval+="<h2>Forums</h2>";

 array d=s->query("SELECT * FROM forum_names ORDER BY forum_name");
  if(sizeof(d)>0)
  {
  retval+="<ul>\n";

 foreach(d, mapping row){
  array p=s->query("SELECT COUNT(*) as posts FROM articles where forum=" 
   + row->id);
  int numposts=(int)p[0]->posts;
  int unreadposts=numposts;
  if(id->cookies->userid && id->cookies->userid!="") {
   array p=s->query("SELECT *  FROM read_entries "
    "WHERE userid=" + id->cookies->userid + " AND forum_id=" + row->id + 
    " GROUP BY article_id ");
// ERROR(sprintf("%O", p));
   if(sizeof(p)>0){
    int readposts=sizeof(p);
    unreadposts-=((int)readposts);
    }
  }
 retval+="<li><a href=\"" + id->not_query + "?forum=" + row->id + "\">" 
  + row->forum_name + "</a> ( <i>" + numposts + " posts, " +
  unreadposts + " unread</i> ) "
  "<a href=\"" + id->not_query + "?delete_forum=" + row->id + "\">" 
  "DELETE</a>\n";

 }

  retval+="</ul>\n";
 }
 else retval+="No forums available.<p>";

 retval+="<a href=\"" + id->not_query + "?want_to_create=1\">Create New Forum</a>";
 }

// ERROR(retval);
return (retval);

}

mapping query_tag_callers() 
{
  return (["forum_index": tag_forum_index,
	"forum": tag_forum,
	"subpost": tag_subpost,
	"forumsgetauth": tag_forumsgetauth,
	"forum_admin": tag_forum_admin]); 
  }







