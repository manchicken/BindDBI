BindDBI
=======

NAME
----
       BindDBI - Value binding wrapper for the DBI module

SYNOPSIS
--------
           use DBI;
           use DBI qw(:sql_types);

           use BindDBI;
           my $db = BindDBI->new();

           # Create data bindings
           my @colums = qw/FIRST_NAME LAST_NAME ADDRESS CITY STATE ZIP/;
           my %data   = $db->record("",@columns);
           my %bind   = $db->binding(%data);

           # Register an error handler routine
           $db->err_handler(\&db_error_handler);

           # Connect to the database
           my $dbh = $db->connectOracleStr("$user/$pass\@$inst");

           # Simple select example
           my $il = "IL";
           my $sql = "select ".$db->select_list(@columns)
                   . "  from my_table"
                   . " where state = :IL"
                   . "   and address is not null";
           $db->prepare(__LINE__, $sql, "IL" => \$il, %bind);
           $db->execute();
           while ($db->fetch())
           {
               print "Name: $data{FIRST_NAME} $data{LAST_NAME}\n";
               print "Addr: $data{ADDRESS}\n";
               print "      $data{CITY}, $data{STATE} $data{ZIP}\n";
               print "\n";
               $table = uc($table);
           }
           $db->finish();

           # Simple insert example
           my $sql = "insert into my_table (".join(",",@columns).")"
                   . "     values (".$db->values_list(@columns).")";
           $db->prepare(__LINE__, $sql, %bind);
           $db->execute();
           $db->finish();

           # Simple update example
           $data{STATE} = "KY";
           my $sql = "update my_table"
                   . "   set STATE = :STATE
                   . " where STATE = :IL";
           $db->prepare(__LINE__, $sql, "IL" => \$il, %bind);
           $db->execute();
           $db->finish();

DESCRIPTION
-----------

       This packages the wraps standard perl DBI module providing convientent data binding which
       speeds up SQL execution as well as providing better user entered data protection along
       with error trapping.  Each wrapping method is named the same as the DBI method it wraps.

       The wrapped methods are:

       * new - constructor
       * connectOracleStr - Connect to an Oracle database
       * connect - Connect to an Oracle database
       * prepare - Prepare SQL for execution
       * execute - Execute the SQL
       * fetch - Fetch the results of a SELECT statement
       * finish - Clean up after executing the SQL
       * commit - Commit a database transaction
       * rollback - Rollback a database transaction
       * disconnect - Disconnect from the database
       * err - Return DBI error code
       * errstr - Return DBI error message string

       Additional methods:

       * select_list - returns bound string for SELECT values
       * select_list_alias - returns bound string for SELECT values with table aliases
       * where_list - returns bound string for WHERE clause values
       * where_list_alias - returns bound string for WHERE clause values with table aliases
       * values_list - returns bound string for INSERT VALUES
       * record - returns record hash
       * binding - returns record bindings for prepare method
       * col_type - optionally registers special column datatypes
       * sqlSafe - escapes SQL values for placing in an SQL string
       * err_handler - Registers an error handler routine

new( )
------
       Creates a new BindDBI object.

connectOracleStr($str)
----------------------
       This method connects a BindDBI object to an Oracle database.

       Arguments:

       * $str - Oracle connection string. Typically format is: {user}/{pass}@{inst}

connect($instance, $username, $password)
----------------------------------------
       This method connects a BindDBI object to an Oracle database.

       Arguments:

       * $instance - Database instance
       * $username - Database user name
       * $password - Database password

prepare($id, $sql, %bind)
-------------------------
       This method prepares an SQL statement to be processed after applying the supplied bindings

       Arguments:

       * $id - ID to display with error messages resulting from executing the SQL that was pre-
       pared.  Typlically this specified as the __LINE__ perl variable so that the error can be
       traced back the line where it was prepared.
       * $sql - SQL Statement
       * %bind - Bindings hash

       The bindings hash (%bind) has a "binding name" as it key and a the address of variable to
       bind that binding name to.  Typically the binding name is the same as the column it is
       being bond to.  However, there are cases when it shouldn't.  For example, if a column is
       being updated from one value to another you will need a binding name for the variable that
       contains the new value and a binding name for the variable with the old value.

       Bindind names are specified in the SQL string ($sql) by preceeding it with a semicolon (;)
       for columns returning values in select statements and a colon (:) all other places (like
       in a where clause).

       For example:

           SELECT FIRST_NAME;NAME, ZIP;ZIP FROM MY_TABLE WHERE ZIP > :MIN_ZIP

       The bindings names would be:

           %bind{NAME}    = \$first_name; # Value from FIRST_NAME column
           %bind{ZIP}     = \$zip_code;   # Value from ZIP column
           %bind{MIN_ZIP} = \$min_zip;    # Value with minimum value of ZIP

execute( )
----------
       This method wraps and executes the Perl DBI::execute method.

fetch( )
--------
       This method wraps and executes the Perl DBI::fetch method.

       The values returned will be placed into the variables they were bound to.

finish( )
       This method wraps and executes the Perl DBI::finish method.

commit( )
---------
       This method wraps and executes the Perl DBI::commit method.

rollback( )
-----------
       This method wraps and executes the Perl DBI::rollback method.

disconnect( )
-------------
       This method wraps and executes the Perl DBI::disconnect method.

err( )
------
       This method calls the DBI::err method to return the error code.

errstr( )
---------
       This method calls the DBI::errstr method to return the error code.

select_list(@columns)
---------------------
       This method returns a bound string to use as the list in a SELECT statement.

       Arguments:

       * @columns - An array of column names

       The string returned will be in the format of:

           "$col[0];$col[0], $col[1];$col[1], ..."

       However, for any column name that had its format registered via the col_type method the
       string returned will be modified in accordance with the registered format.

select_list_alias($alias, @columns)
-----------------------------------
       This method returns a bound string to use as the list in a SELECT statement.

       Arguments:

       * $alias - Table alias to used for column names
       * @columns - An array of column names

       The string returned will be in the format of:

           "$alias.$col[0];$col[0], $alias.$col[1];$col[1], ..."

       However, for any column name that had its format registered via the col_type method the
       string returned will be modified in accordance with the registered format.

where_list(@columns)
--------------------
       This method returns a bound string to use as a WHERE clause

       Arguments:

       * @columns - An array of column names

       The string returned will be in the format of:

           "$col[0] = :$col[0] and $col[1] = :$col[1] and ..."

       However, for any column name that had its format registered via the col_type method the
       string returned will be modified in accordance with the registered format.

where_list_alias($alias, @columns)
----------------------------------
       This method returns a bound string to use as a WHERE clause.

       Arguments:

       * $alias - Table alias to used for column names
       * @columns - An array of column names

       The string returned will be in the format of:

           "$alias.$col[0] = :$col[0] and $alias.$col[1] = :$col[1] and ..."

       However, for any column name that had its format registered via the col_type method the
       string returned will be modified in accordance with the registered format.

values_list(@columns)
---------------------
       This method returns a bound string to use as the list in values clause of an INSERT state-
       ment.

       Arguments:

       * @columns - An array of column names

       The string returned will be in the format of:

           ":$col[0], :$col[1], ..."

       However, for any column name that had its format registered via the col_type method the
       string returned will be modified in accordance with the registered format.

update_list(@columns)
---------------------
       This method returns a bound string to use as the list in UPDATE statement.

       Arguments:

       * @columns - An array of column names

       The string returned will be in the format of:

           "$col[0] = :$col[0], $col[1] = :$col[1], ..."

       However, for any column name that had its format registered via the col_type method the
       string returned will be modified in accordance with the registered format.

record($table, @columns)
------------------------
       This method returns a record hash of the column names passed.

       Arguments:

       * $table - Optional table name or alias to use with the column names
       * @columns - An array of column names

       The record hash returned is in one of the following two forms:

           1) $table eq "":   "column" => ""

           2) $table ne "":   "table.column" => ""

binding(%record)
----------------
       This method returns a bound hash useable with the prepare method.

       Arguments:

       * %record - A record hash

       The record hash, %record, should be in format returned by the record method:

           COLUMN => ""

col_type(%typing)
-----------------
       This method registers data types that are naturally handled by DBI and Oracle for special
       handling with the BindDBI::*_list methods.

       Arguments:

       * %typing - Hash of extened datatype definitions

       The typing hash (%type) has a column name as its key and a the datatype definition string.

       Currently defined datatype definitions are:

       "DATE({fmt})" - Use Oracle to_date() format, {fmt}.
       "SYSDATE({fmt})" - Same as DATE() format, but uses SYSDATE for inserts
       "SINCE({yyyymmddhh24miss})" - Returns seconds since date in 'yyymmddhh24miss' format. Adds
       value to past to that date when inserting or updating.

       Example:

           $db->col_type(CREATION_DATE     => "DATE(yyyymmddhh24miss)");
           $db->col_type(SYS_CREATION_DATE => "SYSDATE(yyyymmddhh24miss)");

sqlSafe($value)
---------------
       This method returned an SQL safe string where backslashes and single quotes are escaped.

       Arguments:

       * $value - String to escape

err_handler(\&routine)
----------------------
       This method resgisters an error handling routine to be called whenever BindDBI or DBI
       encounters and error.


       * \&routine - Error handler routine name

       The default error handler is 'die'.

DIAGNOSTICS
-----------
           -- to do --

DEPENDENCIES
------------
           use DBI;
           use DBI qw(:sql_types);

AUTHOR
------
           Michael Stemle
           Amdocs Champaign
           mstemle@amdocs.com

