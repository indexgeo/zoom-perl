# $Id: 2-ZOOM.t,v 1.2 2005-10-12 11:56:27 mike Exp $

# Before `make install' is performed this script should be runnable with
# `make test'. After `make install' it should work as `perl ZOOM.t'

#########################

# change 'tests => 1' to 'tests => last_test_to_print';

use strict;
use Test::More tests => 1;
BEGIN { use_ok('ZOOM') };

#########################

# Insert your test code below, the Test::More module is use()ed here so read
# its man page ( perldoc Test::More ) for help writing this test script.

my $host = "indexdata.com/gils";
$host = "localhost:3950";
my $port = 0;

my $conn = new ZOOM::Connection($host, $port);

my $syntax = "usmarc";
$conn->option(preferredRecordSyntax => $syntax);
my $val = $conn->option("preferredRecordSyntax");
die "set preferredRecordSyntax to '$syntax' but got '$val'"
    if $val ne $syntax;

my $query = '@attr 1=4 minerals';
my $rs = $conn->search_pqf($query);

my $n = $rs->size($rs);

for (my $i = 0; $i < $n; $i++) {
    my $rec = $rs->record($i);
    my $data = $rec->render();
    my $raw = $rec->raw();
}

$rs->destroy();
$conn->destroy();