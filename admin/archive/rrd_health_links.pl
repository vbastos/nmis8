#!/usr/bin/perl
#
#  Copyright (C) Opmantek Limited (www.opmantek.com)
#
#  ALL CODE MODIFICATIONS MUST BE SENT TO CODE@OPMANTEK.COM
#
#  This file is part of Network Management Information System ("NMIS").
#
#  NMIS is free software: you can redistribute it and/or modify
#  it under the terms of the GNU General Public License as published by
#  the Free Software Foundation, either version 3 of the License, or
#  (at your option) any later version.
#
#  NMIS is distributed in the hope that it will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#  GNU General Public License for more details.
#
#  You should have received a copy of the GNU General Public License
#  along with NMIS (most likely in a file named LICENSE).
#  If not, see <http://www.gnu.org/licenses/>
#
#  For further information on NMIS or for a license other than GPL please see
#  www.opmantek.com or email contact@opmantek.com
#
#  User group details:
#  http://support.opmantek.com/users/
#
# *****************************************************************************

# creates symlinks for health rrd files under generic pointing 
# to the correct rrd files, which should be useful for 
# nodes that are temporarily misidentified by update when node
# is down or goes down/up during the update

# obsolete as of nmis 8.5.0G, where Common-database.nmis 
# controls all rrd file locations. with that you can
# make the directory hierarchy as flat as you'd like.

use FindBin;
use lib "$FindBin::Bin/../lib";

use strict;
use Fcntl qw(:DEFAULT :flock);
use func;
use NMIS;
use NMIS::Timing;

my $t = NMIS::Timing->new();
print $t->elapTime(). " Begin\n";

# Variables for command line munging
my %arg = getArguements(@ARGV);

# Set debugging level.
my $debug = setDebug($arg{debug});

# load configuration table
my $C = loadConfTable(conf=>$arg{conf},debug=>$arg{debug});
print $t->markTime(). " Loading the Device List\n";
my $LNT = loadLocalNodeTable();

# check the nodes for health databases
print $t->markTime()." Checking nodes for health databases\n";
foreach my $node (sort keys %{$LNT}) 
{
		# Initialise a system object and load its node.
		my $S = Sys::->new; 
		$S->init(name=>$node, snmp=>'false'); 

		my $dbn = $S->getDBName(type=>"health");
		if ($dbn)
		{
				print "$node uses health db $dbn\n" if ($debug);

				# compute the generic variant
				my @path = split(m!/!,$dbn);
				# ...location.../database/health/...nodetype.../filename.rrd
				splice(@path,-2,1,"generic");
				my $newpath = join("/", @path);

				if (-f $dbn && !-f $newpath)
				{
						print $t->markTime(). 
								" symlinking $dbn for node $node\n";
						symlink($dbn,$newpath) or 
								print STDERR "\n\nERROR: cannot create symlink $newpath: $!\n\n";
				}
		}
};

print $t->markTime() . " all finished.\n";
exit 0;
