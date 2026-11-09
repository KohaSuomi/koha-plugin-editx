#!/usr/bin/perl
use strict;
use warnings;
use Test::More tests => 4;
use Koha::Plugins;
use File::Temp qw(tempdir);
use File::Path qw(make_path);

use_ok('Koha::Plugin::Fi::KohaSuomi::Editx::Procurement::Logger');

# 1. Logger must not die when the log file cannot be opened, and must warn.
my $dir = tempdir(CLEANUP => 1);
make_path("$dir/sub");
# Make transaction.log an existing directory so open(... '>>') fails.
mkdir "$dir/transaction.log";

my @warnings;
local $SIG{__WARN__} = sub { push @warnings, $_[0] };

my $logger;
eval { $logger = Koha::Plugin::Fi::KohaSuomi::Editx::Procurement::Logger->new($dir); };
ok(!$@, 'Logger->new does not die when transaction.log cannot be opened');
ok(scalar @warnings > 0, 'Logger->new warns when transaction.log cannot be opened');

# 2. Logging must not die either.
@warnings = ();
eval { $logger->log('test message'); };
ok(!$@, 'log() does not die when the log file is unavailable');
