# $Id: ZOOM.pm,v 1.10 2005-10-31 15:10:49 mike Exp $

use strict;
use warnings;
use Net::Z3950::ZOOM;


package ZOOM;


# Member naming convention: hash-element names which begin with an
# underscore represent underlying ZOOM-C object descriptors; those
# which lack them represent Perl's ZOOM objects.  (The same convention
# is used in naming local variables where appropriate.)
#
# So, for example, the ZOOM::Connection class has an {_conn} element,
# which is a pointer to the ZOOM-C Connection object; but the
# ZOOM::ResultSet class has a {conn} element, which is a reference to
# the Perl-level Connection object by which it was created.  (It may
# be that we find we have no need for these references, but for now
# they are retained.)
#
# To get at the underlying ZOOM-C connection object of a result-set
# (if you ever needed to do such a thing, which you probably don't)
# you'd use $rs->{conn}->_conn().

# ----------------------------------------------------------------------------

# The "Error" package contains constants returned as error-codes.
package ZOOM::Error;
sub NONE { Net::Z3950::ZOOM::ERROR_NONE }
sub CONNECT { Net::Z3950::ZOOM::ERROR_CONNECT }
sub MEMORY { Net::Z3950::ZOOM::ERROR_MEMORY }
sub ENCODE { Net::Z3950::ZOOM::ERROR_ENCODE }
sub DECODE { Net::Z3950::ZOOM::ERROR_DECODE }
sub CONNECTION_LOST { Net::Z3950::ZOOM::ERROR_CONNECTION_LOST }
sub INIT { Net::Z3950::ZOOM::ERROR_INIT }
sub INTERNAL { Net::Z3950::ZOOM::ERROR_INTERNAL }
sub TIMEOUT { Net::Z3950::ZOOM::ERROR_TIMEOUT }
sub UNSUPPORTED_PROTOCOL { Net::Z3950::ZOOM::ERROR_UNSUPPORTED_PROTOCOL }
sub UNSUPPORTED_QUERY { Net::Z3950::ZOOM::ERROR_UNSUPPORTED_QUERY }
sub INVALID_QUERY { Net::Z3950::ZOOM::ERROR_INVALID_QUERY }
# The following are added specifically for this OO interface
sub CREATE_QUERY { 20001 }
sub QUERY_CQL { 20002 }
sub QUERY_PQF { 20003 }
sub SORTBY { 20004 }

# The "Event" package contains constants returned by last_event()
package ZOOM::Event;
sub NONE { Net::Z3950::ZOOM::EVENT_NONE }
sub CONNECT { Net::Z3950::ZOOM::EVENT_CONNECT }
sub SEND_DATA { Net::Z3950::ZOOM::EVENT_SEND_DATA }
sub RECV_DATA { Net::Z3950::ZOOM::EVENT_RECV_DATA }
sub TIMEOUT { Net::Z3950::ZOOM::EVENT_TIMEOUT }
sub UNKNOWN { Net::Z3950::ZOOM::EVENT_UNKNOWN }
sub SEND_APDU { Net::Z3950::ZOOM::EVENT_SEND_APDU }
sub RECV_APDU { Net::Z3950::ZOOM::EVENT_RECV_APDU }
sub RECV_RECORD { Net::Z3950::ZOOM::EVENT_RECV_RECORD }
sub RECV_SEARCH { Net::Z3950::ZOOM::EVENT_RECV_SEARCH }

# ----------------------------------------------------------------------------

package ZOOM;

sub diag_str {
    my($code) = @_;

    # Special cases for error specific to the OO layer
    if ($code == ZOOM::Error::CREATE_QUERY) {
	return "can't create query object";
    } elsif ($code == ZOOM::Error::QUERY_CQL) {
	return "can't set CQL query";
    } elsif ($code == ZOOM::Error::QUERY_PQF) {
	return "can't set prefix query";
    } elsif ($code == ZOOM::Error::SORTBY) {
	return "can't set sort-specification";
    }

    return Net::Z3950::ZOOM::diag_str($code);
}

### More of the ZOOM::Exception instantiations should use this
sub _oops {
    my($code, $addinfo) = @_;

    die new ZOOM::Exception($code, diag_str($code), $addinfo);
}

# ----------------------------------------------------------------------------

package ZOOM::Exception;

sub new {
    my $class = shift();
    my($code, $message, $addinfo) = @_;
    ### support diag-set, too

    return bless {
	code => $code,
	message => $message,
	addinfo => $addinfo,
    }, $class;
}

sub code {
    my $this = shift();
    return $this->{code};
}

sub message {
    my $this = shift();
    return $this->{message};
}

sub addinfo {
    my $this = shift();
    return $this->{addinfo};
}


# ----------------------------------------------------------------------------

package ZOOM::Options;

sub new {
    my $class = shift();
    my($p1, $p2) = @_;

    my $opts;
    if (@_ == 0) {
	$opts = Net::Z3950::ZOOM::options_create();
    } elsif (@_ == 1) {
	$opts = Net::Z3950::ZOOM::options_create_with_parent($p1->_opts());
    } elsif (@_ == 2) {
	$opts = Net::Z3950::ZOOM::options_create_with_parent2($p1->_opts(),
							      $p2->_opts());
    } else {
	die "can't make $class object with more than 2 parents";
    }

    return bless {
	_opts => $opts,
    }, $class;
}

sub _opts {
    my $this = shift();

    my $_opts = $this->{_opts};
    die "{_opts} undefined: has this Options block been destroy()ed?"
	if !defined $_opts;

    return $_opts;
}

sub option {
    my $this = shift();
    my($key, $value) = @_;

    my $oldval = Net::Z3950::ZOOM::options_get($this->_opts(), $key);
    Net::Z3950::ZOOM::options_set($this->_opts(), $key, $value)
	if defined $value;

    return $oldval;
}

sub option_binary {
    my $this = shift();
    my($key, $value) = @_;

    my $dummylen = 0;
    my $oldval = Net::Z3950::ZOOM::options_getl($this->_opts(),
						$key, $dummylen);
    Net::Z3950::ZOOM::options_setl($this->_opts(), $key,
				   $value, length($value))
	if defined $value;

    return $oldval;
}

# This is a bit stupid, since the scalar values that Perl returns from
# option() can be used as a boolean; but it's just possible that some
# applications will rely on ZOOM_options_get_bool()'s idiosyncratic
# interpretation of what constitutes truth.
#
sub bool {
    my $this = shift();
    my($key, $default) = @_;

    return Net::Z3950::ZOOM::options_get_bool($this->_opts(), $key, $default);
}

# .. and the next two are even more stupid
sub int {
    my $this = shift();
    my($key, $default) = @_;

    return Net::Z3950::ZOOM::options_get_int($this->_opts(), $key, $default);
}

sub set_int {
    my $this = shift();
    my($key, $value) = @_;

    Net::Z3950::ZOOM::options_set_int($this->_opts(), $key, $value);
}

#   ###	Feel guilty.  Feel very, very guilty.  I've not been able to
#	get the callback memory-management right in "ZOOM.xs", with
#	the result that the values of $function and $udata passed into
#	this function, which are on the stack, have sometimes been
#	freed by the time they're used by __ZOOM_option_callback(),
#	with hilarious results.  To avoid this, I copy the values into
#	module-scoped globals, and pass _those_ into the extension
#	function.  To avoid overwriting those globals by subsequent
#	calls, I keep all the old ones, pushed onto the @_function and
#	@_udata arrays, which means that THIS FUNCTION LEAKS MEMORY
#	LIKE IT'S GOING OUT OF FASHION.  Not nice.  One day, I should
#	fix this, but for now there's more important fish to fry.
#
my(@_function, @_udata);
sub set_callback {
    my $o1 = shift();
    my($function, $udata) = @_;

    push @_function, $function;
    push @_udata, $udata;
    Net::Z3950::ZOOM::options_set_callback($o1->_opts(),
					   $_function[-1], $_udata[-1]);
}

sub destroy {
    my $this = shift();

    Net::Z3950::ZOOM::options_destroy($this->_opts());
    $this->{_opts} = undef;
}


# ----------------------------------------------------------------------------

package ZOOM::Connection;

sub new {
    my $class = shift();
    my($host, $port) = @_;

    my $_conn = Net::Z3950::ZOOM::connection_new($host, $port);
    my($errcode, $errmsg, $addinfo) = (undef, "dummy", "dummy");
    $errcode = Net::Z3950::ZOOM::connection_error($_conn, $errmsg, $addinfo);
    die new ZOOM::Exception($errcode, $errmsg, $addinfo) if $errcode;

    return bless {
	host => $host,
	port => $port,
	_conn => $_conn,
    };
}

sub create {
    my $class = shift();
    my($options) = @_;

    my $_conn = Net::Z3950::ZOOM::connection_create($options->_opts());
    return bless {
	host => undef,
	port => undef,
	_conn => $_conn,
    };
}

# PRIVATE within this class
sub _conn {
    my $this = shift();

    my $_conn = $this->{_conn};
    die "{_conn} undefined: has this Connection been destroy()ed?"
	if !defined $_conn;

    return $_conn;
}

sub error_x {
    my $this = shift();

    my($errcode, $errmsg, $addinfo, $diagset) = (undef, "dummy", "dummy", "d");
    $errcode = Net::Z3950::ZOOM::connection_error_x($this->_conn(), $errmsg,
						    $addinfo, $diagset);
    return ($errcode, $errmsg, $addinfo, $diagset);
}

sub errcode {
    my $this = shift();
    return Net::Z3950::ZOOM::connection_errcode($this->_conn());
}

sub errmsg {
    my $this = shift();
    return Net::Z3950::ZOOM::connection_errmsg($this->_conn());
}

sub addinfo {
    my $this = shift();
    return Net::Z3950::ZOOM::connection_addinfo($this->_conn());
}

sub connect {
    my $this = shift();
    my($host, $port) = @_;

    Net::Z3950::ZOOM::connection_connect($this->_conn(), $host, $port);
    my($errcode, $errmsg, $addinfo) = (undef, "dummy", "dummy");
    $errcode = Net::Z3950::ZOOM::connection_error($this->_conn(),
						  $errmsg, $addinfo);
    die new ZOOM::Exception($errcode, $errmsg, $addinfo) if $errcode;
    # No return value
}

sub option {
    my $this = shift();
    my($key, $value) = @_;

    my $oldval = Net::Z3950::ZOOM::connection_option_get($this->_conn(), $key);
    Net::Z3950::ZOOM::connection_option_set($this->_conn(), $key, $value)
	if defined $value;

    return $oldval;
}

sub option_binary {
    my $this = shift();
    my($key, $value) = @_;

    my $dummylen = 0;
    my $oldval = Net::Z3950::ZOOM::connection_option_getl($this->_conn(),
							  $key, $dummylen);
    Net::Z3950::ZOOM::connection_option_setl($this->_conn(), $key,
					     $value, length($value))
	if defined $value;

    return $oldval;
}

sub search {
    my $this = shift();
    my($query) = @_;

    my $_rs = Net::Z3950::ZOOM::connection_search($this->_conn(),
						  $query->_query());
    my($errcode, $errmsg, $addinfo) = (undef, "dummy", "dummy");
    $errcode = Net::Z3950::ZOOM::connection_error($this->_conn(),
						  $errmsg, $addinfo);
    die new ZOOM::Exception($errcode, $errmsg, $addinfo) if $errcode;

    return _new ZOOM::ResultSet($this, $query, $_rs);
}

sub search_pqf {
    my $this = shift();
    my($pqf) = @_;

    my $_rs = Net::Z3950::ZOOM::connection_search_pqf($this->_conn(), $pqf);
    my($errcode, $errmsg, $addinfo) = (undef, "dummy", "dummy");
    $errcode = Net::Z3950::ZOOM::connection_error($this->_conn(),
						  $errmsg, $addinfo);
    die new ZOOM::Exception($errcode, $errmsg, $addinfo) if $errcode;

    return _new ZOOM::ResultSet($this, $pqf, $_rs);
}

sub destroy {
    my $this = shift();

    Net::Z3950::ZOOM::connection_destroy($this->_conn());
    $this->{_conn} = undef;
}


# ----------------------------------------------------------------------------

package ZOOM::Query;

sub new {
    my $class = shift();
    die "You can't create $class objects: it's a virtual base class";
}

sub _query {
    my $this = shift();

    my $_query = $this->{_query};
    die "{_query} undefined: has this Query been destroy()ed?"
	if !defined $_query;

    return $_query;
}

sub sortby {
    my $this = shift();
    my($sortby) = @_;

    Net::Z3950::ZOOM::query_sortby($this->_query(), $sortby) == 0
	or ZOOM::_oops(ZOOM::Error::SORTBY, $sortby);
}

sub destroy {
    my $this = shift();

    Net::Z3950::ZOOM::query_destroy($this->_query());
    $this->{_query} = undef;
}


package ZOOM::Query::CQL;
our @ISA = qw(ZOOM::Query);

sub new {
    my $class = shift();
    my($string) = @_;

    my $q = Net::Z3950::ZOOM::query_create()
	or ZOOM::_oops(ZOOM::Error::CREATE_QUERY);
    Net::Z3950::ZOOM::query_cql($q, $string) == 0
	or ZOOM::_oops(ZOOM::Error::QUERY_CQL, $string);

    return bless {
	_query => $q,
    }, $class;
}


package ZOOM::Query::PQF;
our @ISA = qw(ZOOM::Query);

sub new {
    my $class = shift();
    my($string) = @_;

    my $q = Net::Z3950::ZOOM::query_create()
	or ZOOM::_oops(ZOOM::Error::CREATE_QUERY);
    Net::Z3950::ZOOM::query_prefix($q, $string) == 0
	or ZOOM::_oops(ZOOM::Error::QUERY_PQF, $string);

    return bless {
	_query => $q,
    }, $class;
}


# ----------------------------------------------------------------------------

package ZOOM::ResultSet;

sub new {
    my $class = shift();
    die "You can't create $class objects directly";
}

# PRIVATE to ZOOM::Connection::search()
sub _new {
    my $class = shift();
    my($conn, $query, $_rs) = @_;

    return bless {
	conn => $conn,
	query => $query,	# This is not currently used, which is
				# just as well since it could be
				# either a string (when the RS is
				# created with search_pqf()) or a
				# ZOOM::Query object (when it's
				# created with search())
	_rs => $_rs,
    }, $class;
}

# PRIVATE within this class
sub _rs {
    my $this = shift();

    my $_rs = $this->{_rs};
    die "{_rs} undefined: has this ResultSet been destroy()ed?"
	if !defined $_rs;

    return $_rs;
}

sub size {
    my $this = shift();

    return Net::Z3950::ZOOM::resultset_size($this->_rs());
}

sub record {
    my $this = shift();
    my($which) = @_;

    my $_rec = Net::Z3950::ZOOM::resultset_record($this->_rs(), $which);
    ### Check for error -- but how?

    # For some reason, I have to use the explicit "->" syntax in order
    # to invoke the ZOOM::Record constructor here, even though I don't
    # have to do the same for _new ZOOM::ResultSet above.  Weird.
    return ZOOM::Record->_new($this, $which, $_rec);
}

sub destroy {
    my $this = shift();

    Net::Z3950::ZOOM::resultset_destroy($this->_rs());
    $this->{_rs} = undef;
}


# ----------------------------------------------------------------------------

package ZOOM::Record;

sub new {
    my $class = shift();
    die "You can't create $class objects directly";
}

# PRIVATE to ZOOM::ResultSet::record()
sub _new {
    my $class = shift();
    my($rs, $which, $_rec) = @_;

    return bless {
	rs => $rs,
	which => $which,
	_rec => $_rec,
    }, $class;
}

# PRIVATE within this class
sub _rec {
    my $this = shift();

    return $this->{_rec};
}

sub render {
    my $this = shift();

    my $len = 0;
    my $string = Net::Z3950::ZOOM::record_get($this->_rec(), "render", $len);
    # I don't think we need '$len' at all.  ### Probably the Perl-to-C
    # glue code should use the value of `len' as well as the opaque
    # data-pointer returned, to ensure that the SV contains all of the
    # returned data and does not stop at the first NUL character in
    # binary data.  Carefully check the ZOOM_record_get() documentation.
    return $string;
}

sub raw {
    my $this = shift();

    my $len = 0;
    my $string = Net::Z3950::ZOOM::record_get($this->_rec(), "raw", $len);
    # See comment about $len in render()
    return $string;
}


1;
