package BindDBI;
use strict;

use DBI;
use DBI qw(:sql_types);

use Data::Dumper;

################################################################################

=head1 NAME

BindDBI - Value binding wrapper for the DBI module

=head1 SYNOPSIS

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

=head1 DESCRIPTION

This packages the wraps standard perl DBI module providing convientent data
binding which speeds up SQL execution as well as providing better user entered
data protection along with error trapping.  Each wrapping method is named the 
same as the DBI method it wraps.  

The wrapped methods are:

=over

=item * B<new> - constructor

=item * B<connectOracleStr> - Connect to an Oracle database

=item * B<connect> - Connect to an Oracle database

=item * B<prepare> - Prepare SQL for execution

=item * B<execute> - Execute the SQL

=item * B<fetch> - Fetch the results of a SELECT statement

=item * B<finish> - Clean up after executing the SQL

=item * B<commit> - Commit a database transaction

=item * B<rollback> - Rollback a database transaction

=item * B<disconnect> - Disconnect from the database

=item * B<err> - Return DBI error code

=item * B<errstr> - Return DBI error message string

=back

Additional methods:

=over

=item * B<select_list> - returns bound string for SELECT values

=item * B<select_list_alias> - returns bound string for SELECT values with table aliases

=item * B<where_list> - returns bound string for WHERE clause values

=item * B<where_list_alias> - returns bound string for WHERE clause values with table aliases

=item * B<values_list> - returns bound string for INSERT VALUES

=item * B<record> - returns record hash

=item * B<binding> - returns record bindings for prepare method

=item * B<col_type> - optionally registers special column datatypes

=item * B<sqlSafe> - escapes SQL values for placing in an SQL string

=item * B<err_handler> - Registers an error handler routine

=back

=cut

################################################################################
=pod

=head1 new( )

Creates a new BindDBI object.

=cut

sub new
{
    my ($class) = @_;
    my $self  = {};

    $self->{_DBH}        = undef;
    $self->{_STH}        = undef;
    $self->{_SQL}        = undef;
    $self->{_SCHEMA}     = undef;
    $self->{_BIND}       = undef;
    $self->{_SELECTBIND} = undef;
    $self->{_SQLID}      = 0;
    $self->{_TRACE}      = 0;
    $self->{_ERRNO}      = 0;
    $self->{_ERRSTR}     = 0;

    bless ($self, $class);

    $self->{_ERRHANDLER} = \&BindDBIdefErrHandler;

    return $self;
}

################################################################################
=pod

=head1 connectOracleStr($str)

This method connects a BindDBI object to an Oracle database.

Arguments:

=over

=item * B<$str> - Oracle connection string.  
Typically format is: {user}/{pass}@{inst}

=back

=cut

sub connectOracleStr
{
    my ($self, $str) = @_;
    if ($self->{_TRACE}) { print STDERR "BindDBI::connectOracleStr('".join("','",@_).")\n"; }

    $self->{_ERRNO} = 0;
    $self->{_ERRSTR}= 0;

    my ($username,$password,$instance) = split(/[\/\@]/,$str);

    return $self->connect("dbi:Oracle:$instance", $username, $password);
}

################################################################################
=pod

=head1 connect($instance, $username, $password)

This method connects a BindDBI object to an Oracle database.

Arguments:

=over

=item * B<$instance> - Database instance

=item * B<$username> - Database user name

=item * B<$password> - Database password

=back

=cut

sub connect
{
    my ($self, $instance, $username, $password) = @_;
    if ($self->{_TRACE}) { print STDERR "BindDBI::connect('".join("','",@_).")\n"; }

    $self->{_ERRNO} = 0;
    $self->{_ERRSTR}= 0;

    $self->{_DBH} = DBI->connect($instance, $username, $password)
                 || return $self->dbError("?BindDBI::connect - Cannot connect to database\n"
                                         . "$DBI::errstr\n"
                                         . " Instance = '$instance'\n"
                                         . " Username = '$username'\n"
                                         . " Password = '$password'\n");

    # Turn on caching to speed things and lighten the load on the server
    if (defined $self->{_DBH})
    {
        $self->{_DBH}->{RowCacheSize} = 1000;
    }

    return $self->{_DBH};
}

################################################################################
=pod

=head1 prepare($id, $sql, %bind)

This method prepares an SQL statement to be processed after applying the
supplied bindings

Arguments:

=over

=item * B<$id> - ID to display with error messages resulting from executing
the SQL that was prepared.  Typlically this specified as the __LINE__ perl
variable so that the error can be traced back the line where it was prepared.

=item * B<$sql> - SQL Statement

=item * B<%bind> - Bindings hash

=back

The bindings hash (%bind) has a "binding name" as it key and a the address of
variable to bind that binding name to.  Typically the binding name is the same
as the column it is being bond to.  However, there are cases when it shouldn't.
For example, if a column is being updated from one value to another you will
need a binding name for the variable that contains the new value and a binding
name for the variable with the old value.

Bindind names are specified in the SQL string ($sql) by preceeding it with a 
semicolon (;) for columns returning values in select statements and a colon (:)
all other places (like in a where clause).

For example:

    SELECT FIRST_NAME;NAME, ZIP;ZIP FROM MY_TABLE WHERE ZIP > :MIN_ZIP

The bindings names would be:

    %bind{NAME}    = \$first_name; # Value from FIRST_NAME column
    %bind{ZIP}     = \$zip_code;   # Value from ZIP column
    %bind{MIN_ZIP} = \$min_zip;    # Value with minimum value of ZIP

=cut

sub prepare
{
    my ($self, $sqlid, $statement, %external) = @_;
    if ($self->{_TRACE}) { print STDERR "BindDBI::prepare('".join("','",@_).")\n"; }

    $self->{_SQLID} = $sqlid;
    $self->{_ERRNO} = 0;

    my $sql = "";
    my @bindings = ();
    my @select_bindings = ();
    my @sizes = ();

    my $string = 0;
    for my $part (split(/('|[\:\;][[:alpha:]][[:alnum:]\._]+)/,$statement))
    {
        if ($part eq "'")
        {
            $string = ($string + 1) % 2;
        }
        elsif ($string != 0)
        {
            # ignore the contents of SQL strings
        }        
        elsif ($part =~ /^[\:\;]/)
        {
            $part = uc($part);
            my $table = undef;
            my $column = undef;
            my $bind = $part;
            my $kind = substr($bind,0,1);
            $bind = substr($bind,1);
            if (exists $external{$bind})
            {
                if ($kind eq ";") 
                { 
                    push (@select_bindings, $external{$bind}); 
                }
                else
                {
                    push(@bindings, $external{$bind});
                }
            }
            elsif ($bind =~ /\./)
            {
                ($table,$column,my $extra) = split(/\./,$bind);
                if (length($extra) > 0)
                {
                    return $self->dbError("?BindDBI::prepare - "
                            . "Invalid variable binding '$part' in statement '"
                            . "$statement'\n");
                }
                elsif (!exists $self->{$table})
                {
                    return $self->dbError("?BindDBI::prepare - "
                            . "Unknown table '$table' in variable binding '$part' "
                            . "in statement '$statement'\n");
                }
                elsif ((!exists $self->{$table}{$column}) || ($column =~ /^_/))
                {
                    return $self->dbError("?BindDBI::prepare - "
                            . "Unknown column name '$column' for table '$table'"
                            . " in varaible finding '$part'"
                            . " in statement '$statement'\n");
                }
                if ($kind eq ";") 
                { 
                    push(@select_bindings, \$self->{$table}{$column});
                }
                else
                {
                    push(@bindings, \$self->{$table}{$column});
                }
            }
            else
            {
                $column = $bind;
                for my $tbl (keys %{$self})
                {
                    if ($tbl =~ /^_/) { next; }
                    if (exists $self->{$tbl}{$column})
                    {
                        if (defined $table)
                        {
                            return $self->dbError("?BindDBI::prepare - ambiguous column "
                                    . "'$column' in variable binding"
                                    . " in statement '$statement'\n");
                        }
                        $table = $tbl;
                    }    
                }
                if (!defined $table)
                {
                    return $self->dbError("?BindDBI::prepare - "
                            . "Unknown variable binding column '$column'"
                            . " in statement '$statement'\n");
                }
                if ($kind eq ";") 
                { 
                    push(@select_bindings, \$self->{$table}{$column});
                }
                else
                {
                    push(@bindings, \$self->{$table}{$column});
                }
            }

            if ($kind eq ":")
            {
                $part = "?";
            }
            else
            {
                $part = "";
            }

            if ((defined $table) &&
                (exists $self->{_SCHEMA}{$table}) && 
                (exists $self->{_SCHEMA}{$table}{$column}))
            {
                my $datatype = $self->{_SCHEMA}{$table}{$column};
                if ($datatype =~ /\(.\d+\)/)
                {
                    $datatype =~ s/^.*\(//;
                    $datatype =~ s/\).*$//;
                }
                else
                {
                    $datatype = 20;
                }
                push(@sizes, 2000);
            }
            else
            {
                push(@sizes, 2000);
            }
        }
        else
        {
            $part = uc($part);
        }
        $sql .= $part;
    }

    if (!defined $self->{_DBH})
    {
        return $self->dbError("BindDBI::prepare - Not connected to a database\n");
    }

    $self->{_STH} = $self->{_DBH}->prepare($sql)
        || return $self->dbError("BindDBI::prepare - DBI::prepared failed"
                    . " in statement '$statement'\n");

    $self->{_SQL} = $sql;

    @{$self->{_BIND}}       = @bindings;
    @{$self->{_SELECTBIND}} = @select_bindings;

    for my $i (0..$#bindings)
    {
        $self->{_STH}->bind_param_inout($i+1, $bindings[$i], $sizes[$i])
            || return $self->dbError("BindDBI::prepare - DBI::bind_param_inout failed"
                        . " in statement '$statement'\n");
    }
}

################################################################################
=pod

=head1 execute( )

This method wraps and executes the Perl DBI::execute method.

=cut

sub execute
{
    my ($self) = @_;
    if ($self->{_TRACE}) { print STDERR "BindDBI::execute('".join("','",@_).")\n"; }

    if (!defined $self->{_STH})
    {
        return $self->dbError("BindDBI::execute - no SQL prepared\n");
    }

    $self->{_STH}->execute()
        || return $self->dbError("BindDBI::execute - DBI::execute failed\n"
                    . $self->{_SQL}."\n");

    if ($self->{_SQL} =~ /^\s*SELECT/)
    {
        $self->{_STH}->bind_columns(undef,@{$self->{_SELECTBIND}})
            || return $self->dbError("BindDBI::execute - DBI::bind_columns failed\n"
                        . $self->{_SQL}."\n");
    }
}

################################################################################
=pod

=head1 fetch( )

This method wraps and executes the Perl DBI::fetch method.

The values returned will be placed into the variables they were bound to.

=cut

sub fetch
{
    my ($self) = @_;
    if ($self->{_TRACE}) { print STDERR "BindDBI::fetch('".join("','",@_).")\n"; }

    if (!defined $self->{_STH})
    {
        return $self->dbError("BindDBI::fetch - no SQL prepared\n");
    }

    return $self->{_STH}->fetch();
}

################################################################################
=pod

=head1 finish( )

This method wraps and executes the Perl DBI::finish method.

=cut

sub finish
{
    my ($self) = @_;
    if ($self->{_TRACE}) { print STDERR "BindDBI::finish('".join("','",@_).")\n"; }

    if (!defined $self->{_STH})
    {
        return $self->dbError("BindDBI::finish - no SQL prepared\n");
    }

    $self->{_STH}->finish();
    $self->{_STH}    = undef;
    $self->{_SQL}    = undef;
    $self->{_BIND}   = undef;
}

################################################################################
=pod

=head1 commit( )

This method wraps and executes the Perl DBI::commit method.

=cut

sub commit
{
    my ($self) = @_;
    if ($self->{_TRACE}) { print STDERR "BindDBI::commit('".join("','",@_).")\n"; }

    $self->{_ERRNO} = 0;
    $self->{_ERRSTR}= 0;

    if (!defined $self->{_DBH})
    {
        $self->{_ERRNO} = -1;
        $self->{_ERRSTR} = "Not connected to a database";
        return $self->dbError("BindDBI::commit - Not connected to a database\n");
    }

    $self->{_DBH}->commit();
}

################################################################################
=pod

=head1 rollback( )

This method wraps and executes the Perl DBI::rollback method.

=cut

sub rollback
{
    my ($self) = @_;
    if ($self->{_TRACE}) { print STDERR "BindDBI::rollback('".join("','",@_).")\n"; }

    $self->{_ERRNO} = 0;
    $self->{_ERRSTR}= 0;

    if (!defined $self->{_DBH})
    {
        $self->{_ERRNO} = -1;
        $self->{_ERRSTR} = "Not connected to a database";
        return $self->dbError("BindDBI::rollback - Not connected to a database\n");
    }

    $self->{_DBH}->rollback();
}

################################################################################
=pod

=head1 disconnect( )

This method wraps and executes the Perl DBI::disconnect method.

=cut

sub disconnect
{
    my ($self) = @_;
    if ($self->{_TRACE}) { print STDERR "BindDBI::disconect('".join("','",@_).")\n"; }

    $self->{_ERRNO} = 0;
    $self->{_ERRSTR}= 0;

    if (!defined $self->{_DBH})
    {
        $self->{_ERRNO} = -1;
        $self->{_ERRSTR} = "Not connected to a database";
        return $self->dbError("BindDBI::disconnect - Not connected to a database\n");
    }

    $self->{_DBH}->disconnect();
    $self->{_DBH} = undef;
}

################################################################################
=pod

=head1 err( )

This method calls the DBI::err method to return the error code.

=cut

sub err
{
    return $DBI::err;
}

################################################################################
=pod

=head1 errstr( )

This method calls the DBI::errstr method to return the error code.

=cut

sub errstr
{
    return $DBI::errstr;
}

################################################################################
=pod

=head1 select_list(@columns)

This method returns a bound string to use as the list in a SELECT statement.

Arguments:

=over

=item * B<@columns> - An array of column names

=back

The string returned will be in the format of: 

    "$col[0];$col[0], $col[1];$col[1], ..."

However, for any column name that had its format registered via the col_type 
method the string returned will be modified in accordance with the registered
format.

=cut

sub select_list
{
   my ($self, @columns) = @_;
   if ($self->{_TRACE}) { print STDERR "BindDBI::select_list('".join("','",@_).")\n"; }

   my $retval = "";
   for my $column (@columns)
   {
       $column = uc($column);
       if (exists $self->{_COLTYPE}{$column}{SELECT})
       {
           $retval .= "$self->{_COLTYPE}{$column}{SELECT};$column, ";
       }
       else
       {
           $retval .= "$column;$column, ";
       }
   }
   $retval =~ s/, $//;

   return $retval;
}

################################################################################
=pod

=head1 select_list_alias($alias, @columns)

This method returns a bound string to use as the list in a SELECT statement.

Arguments:

=over

=item * B<$alias> - Table alias to used for column names

=item * B<@columns> - An array of column names

=back

The string returned will be in the format of: 

    "$alias.$col[0];$col[0], $alias.$col[1];$col[1], ..."

However, for any column name that had its format registered via the col_type 
method the string returned will be modified in accordance with the registered
format.

=cut

sub select_list_alias
{
   my ($self, $alias, @columns) = @_;
   if ($self->{_TRACE}) { print STDERR "BindDBI::select_list_alias('".join("','",@_).")\n"; }

   my $retval = "";
   for my $column (@columns)
   {
       $column = uc($column);
       if (exists $self->{_COLTYPE}{$column}{ALIAS})
       {
           (my $coltyp = $self->{_COLTYPE}{$column}{ALIAS}) =~ s/_ALIAS_/$alias/;
           $retval .= "$coltyp;$column, ";
       }
       else
       {
           $retval .= "$alias.$column;$column, ";
       }
   }
   $retval =~ s/, $//;

   return $retval;
}


################################################################################
=pod

=head1 where_list(@columns)

This method returns a bound string to use as a WHERE clause

Arguments:

=over

=item * B<@columns> - An array of column names

=back

The string returned will be in the format of: 

    "$col[0] = :$col[0] and $col[1] = :$col[1] and ..."

However, for any column name that had its format registered via the col_type 
method the string returned will be modified in accordance with the registered
format.

=cut

sub where_list
{
   my ($self, @columns) = @_;
   if ($self->{_TRACE}) { print STDERR "BindDBI::where_list('".join("','",@_).")\n"; }

   my $retval = "";
   for my $column (@columns)
   {
       $column = uc($column);
       if (exists $self->{_COLTYPE}{$column}{WHERE})
       {
           $retval .= "and $column = $self->{_COLTYPE}{$column}{WHERE} ";
       }
       else
       {
           $retval .= "and $column = :$column ";
       }
   }
   $retval =~ s/^and //;

   return $retval;
}

################################################################################
=pod

=head1 where_list_alias($alias, @columns)

This method returns a bound string to use as a WHERE clause.

Arguments:

=over

=item * B<$alias> - Table alias to used for column names

=item * B<@columns> - An array of column names

=back

The string returned will be in the format of: 

    "$alias.$col[0] = :$col[0] and $alias.$col[1] = :$col[1] and ..."

However, for any column name that had its format registered via the col_type 
method the string returned will be modified in accordance with the registered
format.

=cut

sub where_list_alias
{
   my ($self, $alias, @columns) = @_;
   if ($self->{_TRACE}) { print STDERR "BindDBI::where_list_alias('".join("','",@_).")\n"; }

   my $retval = "";
   for my $column (@columns)
   {
       $column = uc($column);
       if (exists $self->{_COLTYPE}{$column}{WHERE})
       {
           $retval .= "and $alias.$column = $self->{_COLTYPE}{$column}{WHERE} ";
       }
       else
       {
           $retval .= "and $alias.$column = :$column ";
       }
   }
   $retval =~ s/^and //;

   return $retval;
}

################################################################################
=pod

=head1 values_list(@columns)

This method returns a bound string to use as the list in values clause of an 
INSERT statement.

Arguments:

=over

=item * B<@columns> - An array of column names

=back

The string returned will be in the format of: 

    ":$col[0], :$col[1], ..."

However, for any column name that had its format registered via the col_type 
method the string returned will be modified in accordance with the registered
format.

=cut

sub values_list
{
   my ($self, @columns) = @_;
   if ($self->{_TRACE}) { print STDERR "BindDBI::values_list('".join("','",@_).")\n"; }

   my $retval = "";
   for my $column (@columns)
   {
       $column = uc($column);
       if (exists $self->{_COLTYPE}{$column}{SELECT})
       {
           $retval .= $self->{_COLTYPE}{$column}{INSERT}.", ";
       }
       else
       {
           $retval .= ":$column, ";
       }
   }
   $retval =~ s/, $//;

   return $retval;
}

################################################################################
=pod

=head1 update_list(@columns)

This method returns a bound string to use as the list in UPDATE statement.

Arguments:

=over

=item * B<@columns> - An array of column names

=back

The string returned will be in the format of: 

    "$col[0] = :$col[0], $col[1] = :$col[1], ..."

However, for any column name that had its format registered via the col_type 
method the string returned will be modified in accordance with the registered
format.

=cut

sub update_list
{
   my ($self, @columns) = @_;
   if ($self->{_TRACE}) { print STDERR "BindDBI::update_list('".join("','",@_).")\n"; }

   my $retval = "";
   for my $column (@columns)
   {
       $column = uc($column);
       if (exists $self->{_COLTYPE}{$column}{SELECT})
       {
           $retval .= "$column = " . $self->{_COLTYPE}{$column}{UPDATE}.", ";
       }
       else
       {
           $retval .= "$column = :$column, ";
       }
   }
   $retval =~ s/, $//;

   return $retval;
}


################################################################################
=pod

=head1 record($table, @columns)

This method returns a record hash of the column names passed.

Arguments:

=over

=item * B<$table> - Optional table name or alias to use with the column names

=item * B<@columns> - An array of column names

=back

The record hash returned is in one of the following two forms:

    1) $table eq "":   "column" => ""

    2) $table ne "":   "table.column" => ""


=cut

sub record
{
   my ($self, $table, @columns) = @_;
   if ($self->{_TRACE}) { print STDERR "BindDBI::record('".join("','",@_).")\n"; }

   if (($table ne "") && ($table !~ /\.$/)) { $table .= "."; }
   $table = uc($table);

   my %record = ();
   for my $column (@columns)
   {
       $column = uc($column);
       $record{$table.$column} = "";
   }

   return %record;
}
################################################################################
=pod

=head1 binding(%record)

This method returns a bound hash useable with the prepare method.

Arguments:

=over

=item * B<%record> - A record hash

=back

The record hash, %record, should be in format returned by the record method:

    COLUMN => ""

=cut

sub binding
{
    my ($self) = @_;
    if ($self->{_TRACE}) { print STDERR "BindDBI::binding('".join("','",@_).")\n"; }

    my %bind = ();

    my $idx  = 1; # Got skip $self;
    while ($idx < $#_)
    {
        my $column = $_[$idx++];
        $bind{$column} = \$_[$idx++];
    }

    return %bind
}

################################################################################
=pod

=head1 col_type(%typing)

This method registers data types that are naturally handled by DBI and Oracle 
for special handling with the BindDBI::*_list methods.

Arguments:

=over

=item * B<%typing> - Hash of extened datatype definitions

=back

The typing hash (%type) has a column name as its key and a the datatype
definition string.

Currently defined datatype definitions are:

=over 4

=item B<"DATE({fmt})"> - Use Oracle to_date() format, {fmt}.

=item B<"SYSDATE({fmt})"> - Same as DATE() format, but uses SYSDATE for inserts

=item B<"SINCE({yyyymmddhh24miss})"> - Returns seconds since date in
'yyymmddhh24miss' format.  Adds value to past to that date when inserting or
updating.

=back

Example:

    $db->col_type(CREATION_DATE     => "DATE(yyyymmddhh24miss)");
    $db->col_type(SYS_CREATION_DATE => "SYSDATE(yyyymmddhh24miss)");

=cut

sub col_type
{
   my ($self, %typing) = @_;
   if ($self->{_TRACE}) { print STDERR "BindDBI::col_type('".join("','",@_).")'\n"; }

   for my $column (keys %typing)
   {
       my $fmt = $typing{$column};
       if ($fmt != /^\w+\(.*\)$/)
       {
            return $self->dbError("?BindDBI::col_type - Format '$fmt' for column '$column'"
                    . " is not in the correct format of '{type}({args})'.\n");
       }
       my ($type,$args) = split(/\(/,$fmt);
       $args =~ s/\)//;
       $args = sqlSafe($self, $args);
       if (uc($type) eq "DATE")
       {
           $self->{_COLTYPE}{$column}{SELECT} = "to_char($column, '$args')";
           $self->{_COLTYPE}{$column}{INSERT} = "to_date(:$column, '$args')";
           $self->{_COLTYPE}{$column}{UPDATE} = "to_date(:$column, '$args')";
           $self->{_COLTYPE}{$column}{WHERE}  = "to_date(:$column, '$args')";
           $self->{_COLTYPE}{$column}{ALIAS}  = "to_char(_ALIAS_.$column, '$args')";
       }
       elsif (uc($type) eq "SINCE")
       {
           my $base = "to_date('$args','yyyymmddhh24miss')";
           my $secs = 24 * 60 * 60;
           $self->{_COLTYPE}{$column}{SELECT} = "floor(($column - $base) * $secs)";
           $self->{_COLTYPE}{$column}{INSERT} = "($base + (:$column / $secs))";
           $self->{_COLTYPE}{$column}{UPDATE} = "($base + (:$column / $secs))";
           $self->{_COLTYPE}{$column}{WHERE}  = "($base + (:$column / $secs))";
           $self->{_COLTYPE}{$column}{ALIAS}  = "floor((_ALIAS_.$column - $base) * $secs)";
       }
       elsif (uc($type) eq "SYSDATE")
       {
           $self->{_COLTYPE}{$column}{SELECT} = "to_char($column, '$args')";
           $self->{_COLTYPE}{$column}{INSERT} = "SYSDATE";
           $self->{_COLTYPE}{$column}{UPDATE} = "SYSDATE";
           $self->{_COLTYPE}{$column}{WHERE}  = "to_date(:$column, '$args')";
           $self->{_COLTYPE}{$column}{ALIAS}  = "to_char(_ALIAS_.$column, '$args')";
       }
       else
       {
            return $self->dbError("?BindDBI::col_type - Format '$fmt' for column '$column'"
                    . " contains an unknown datatype '$type'.\n");
       }
   }

   return;
}

################################################################################
=pod

=head1 sqlSafe($value)

This method returned an SQL safe string where backslashes and single quotes
are escaped.

Arguments:

=over

=item * B<$value> - String to escape

=back

=cut

sub sqlSafe
{
   my ($self, $value) = @_;
   if ($self->{_TRACE}) { print STDERR "BindDBI::sqlSafe('".join("','",@_).")\n"; }

   if ($value =~ /^\d+$/) { return $value; }

   $value =~ s/\\/\\\\/g;
   $value =~ s/'/\\'/g;

   return $value;
}

################################################################################
=pod

=head1 err_handler(\&routine)

This method resgisters an error handling routine to be called whenever BindDBI
or DBI encounters and error.

=over

=item * B<\&routine> - Error handler routine name

=back

The default error handler is 'die'.

=cut

sub err_handler
{
    my ($self, $routine) = @_;
    if ($self->{_TRACE}) { print STDERR "BindDBI::err_handler('".join("','",@_).")\n"; }

    $self->{_ERRHANDLER} = $routine;
}

################################################################################
sub dbError
{
    my ($self, $message) = @_;

    # If Oracle provided error information, use it
    if ($DBI::err != 0)
    {
        $self->{_ERRNO}  = $DBI::err;
        $self->{_ERRSTR} = $DBI::errstr;
    }
    # If not, use the message passed as the error text
    else
    {
        $self->{_ERRNO}  = -1;
        $self->{_ERRSTR} = $message;
    }

    $self->{_ERRHANDLER}($self->{_SQLID}, $message);

    return undef;
}

################################################################################
sub chkError
{
    my ($self) = @_;

    if ($self->{_ERRNO} == 0) { return "OK"; }

    return $self->{_ERRNO} . " - " . $self->{_ERRSTR};
}

################################################################################
sub BindDBIdefErrHandler
{
    die join(": ",@_)."\n";
}

################################################################################
sub traceOn
{
    my ($self,$lvl) = @_;
    $self->{_TRACE}  = 1;

    if (defined $lvl && ($lvl > 0))
    {
        $self->{_DBH}->trace($lvl);
    }
    print STDERR "BindDBI::TraceOn()\n";
}

################################################################################
sub traceOff
{
    my ($self)      = @_;
    $self->{_TRACE} = 0;
    $self->{_DBH}->trace(0);
    print STDERR "BindDBI::TraceOff()\n";
}

1
__END__

=head1 DIAGNOSTICS

    -- to do --

=head1 DEPENDENCIES

    use DBI;
    use DBI qw(:sql_types);

=head1 AUTHOR

    Michael Stemle
    Amdocs Champaign
    mstemle@amdocs.com
