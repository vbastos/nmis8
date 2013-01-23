#!/usr/bin/perl
#
## $Id: rrddraw.pl,v 8.10 2012/08/24 05:35:22 keiths Exp $
#
#  Copyright 1999-2011 Opmantek Limited (www.opmantek.com)
#  
#  ALL CODE MODIFICATIONS MUST BE SENT TO CODE@OPMANTEK.COM
#  
#  This file is part of Network Management Information System (“NMIS”).
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
# Auto configure to the <nmis-base>/lib
use FindBin;
use lib "$FindBin::Bin/../lib";

use NMIS::uselib;
use lib "$NMIS::uselib::rrdtool_lib";
#
#****** Shouldn't be anything else to customise below here *******************

require 5;

use strict;
use RRDs 1.4004;
use func;
#use rrdfunc;
use Sys;
use NMIS;
use Data::Dumper;

use CGI qw(:standard);

use vars qw($q $Q $C $AU);

$q = new CGI; # This processes all parameters passed via GET and POST
$Q = $q->Vars;

if (!($C = loadConfTable(conf=>$Q->{conf},debug=>$Q->{debug}))) { exit 1; };
$C->{auth_require} = 0; # bypass auth

# NMIS Authentication module
use Auth;

# variables used for the security mods
use vars qw($headeropts); $headeropts = {type=>'text/html',expires=>'now'};
$AU = Auth->new(conf => $C, forward_url=>$Q->{forward_url});  # Auth::new will reap init values from NMIS::config

if ($AU->Require) {
	exit 0 unless $AU->loginout(type=>$Q->{auth_type},username=>$Q->{auth_username},
					password=>$Q->{auth_password},headeropts=>$headeropts) ;
}

# check for remote request
if ($Q->{server} ne "") { exit if requestServer(headeropts=>$headeropts); }

#======================================================================

# select function
if ($Q->{act} eq 'draw_graph_view') {	rrdDraw();
} else { notfound(); }

exit;

sub notfound {
	logMsg("rrddraw; Command unknown act=$Q->{act}");
}

#============================================================================

sub error {
	print header($headeropts);
	print start_html();
	print "Network: ERROR on getting graph<br>\n";
	print "Request not found\n";
	print end_html;
}

#============================================================================

sub rrdDraw {
	my %args = @_;

	# Break the query up for the names
	my $type = $Q->{obj};
	my $nodename = $Q->{node};
	my $debug = $Q->{debug};
	my $grp = $Q->{group};
	my $graphtype = $Q->{graphtype};
	my $graphlength = $Q->{graphlength};
	my $graphstart = $Q->{graphstart};
	my $width = $Q->{width};
	my $height = $Q->{height};
	my $start = $Q->{start};
	my $end = $Q->{end};
	my $intf = $Q->{intf};
	my $item = $Q->{item};
	my $filename = $Q->{filename};

	my $S = Sys::->new; # get system object
	$S->init(name=>$nodename,snmp=>'false');
	my $NI = $S->ndinfo;
	my $IF = $S->ifinfo;

	### 2012-02-06 keiths, handling default graph length
	# default is hours!
	my $graphlength = $C->{graph_amount};
	if ( $C->{graph_unit} eq "days" ) {
		$graphlength = $C->{graph_amount} * 24;
	}

	if ( $start eq "" or $start == 0) {
		$start = time() - ($graphlength*3600);
	}
	if ( $end eq "" or $end == 0) {
		$end = time();
	}

	my $ERROR;
	my $graphret;
	my $xs;
	my $ys;
	my @options;
	my @opt;
	my $db;

	if ($graphtype eq 'metrics') {
		$item = $Q->{group};
		$intf = "";
	}


	if ($graphtype =~ /cbqos/) {
		@opt = graphCBQoS(sys=>$S,graphtype=>$graphtype,intf=>$intf,item=>$item,start=>$start,end=>$end,width=>$width,height=>$height);
	} elsif ($graphtype eq "calls") {
		@opt = graphCalls(sys=>$S,graphtype=>$graphtype,intf=>$intf,item=>$item,start=>$start,end=>$end,width=>$width,height=>$height);
	} else {

		if (!($db = $S->getDBName(graphtype=>$graphtype,index=>$intf,item=>$item)) ) { # get database name from node info
			error();
			return 0;
		}

		my $graph;
		if (!($graph = loadTable(dir=>'models',name=>"Graph-$graphtype"))) {
			logMsg("ERROR reading Graph-$graphtype");
			error();
			return 0;
		}

		my $title = 'standard';
		my $vlabel = 'standard';
		my $size = 'standard';
		my $ttl;
		my $lbl;

		$title = 'short' if $width <= 400 and $graph->{title}{short} ne "";

		$vlabel = 'short' if $width <= 400 and $graph->{vlabel}{short} ne "";

		$vlabel = 'split' if $C->{graph_split} eq "true" and $graph->{vlabel}{split} ne "";

		$size = 'small' if $width <= 400 and $graph->{option}{small} ne "";

		if (($ttl = $graph->{title}{$title}) eq "") {
			logMsg("no title->$title found in Graph-$graphtype");
		}
		if (($lbl = $graph->{vlabel}{$vlabel}) eq "") {
			logMsg("no vlabel->$vlabel found in Graph-$graphtype");
		}

		@opt = (
		"--title", $ttl,
		"--vertical-label", $lbl,
		"--start", $start,
		"--end", $end,
		"--width", $width,
		"--height", $height,
		"--imgformat", "PNG",
		"--interlace"
		);
		# add option rules
		foreach my $str (@{$graph->{option}{$size}}) {
			push @opt, $str;
		}
	}

	# define length of graph
	my $l;
	if (($end - $start) < 3600) {
		$l = int(($end - $start) / 60) . " minutes";
	} elsif (($end - $start) < (3600*48)) {
		$l = int(($end - $start) / (3600)) . " hours";
	} else {
		$l = int(($end - $start) / (3600*24)) . " days";
	}

	{
		# scalars must be global
		no strict;
		if ($intf ne "") {
			$indx = $intf;
			$ifDescr = $IF->{$intf}{ifDescr};
			$ifSpeed = $IF->{$intf}{ifSpeed};
			if ($ifSpeed eq "auto" ) {
				$ifSpeed = 10000000;
			}
			$speed = convertIfSpeed($ifSpeed);
		}
		$node = $NI->{system}{name};
		$datestamp_start = returnDateStamp($start);
		$datestamp_end = returnDateStamp($end);
		$datestamp = returnDateStamp(time);
		$database = $db;
		$group = $grp;
		$itm = $item;
		$length = $l;
		$split = $C->{graph_split} eq 'true' ? -1 : 1 ;
		$GLINE = $C->{graph_split} eq 'true' ? "AREA" : "LINE1" ;
		$weight = 0.983;
	
		foreach my $str (@opt) {
			$str =~ s{\$(\w+)}{if(defined${$1}){${$1};}else{"ERROR, no variable \'\$$1\' ";}}egx;
			if ($str =~ /ERROR/) {
				logMsg("ERROR in expanding variables, $str");
				return;
			}
			push @options,$str;
		}
	}

	# Do the graph!
	### 2012-01-30 keiths, deprecating the need for Win32 support and Image::Resize.  But leaving there for PersistentPerl (to be sure).
	# This works around a bug in RRDTool which doesn't like writing to STDOUT on Win32!
	# Also PersistentPerl needs this workaround
	if ( $^O eq "MSWin32" ) { # or (eval {require PersistentPerl} && PersistentPerl->i_am_perperl) ) {
		my $buff;
		my $random = int(rand(1000)) + 25;
		my $tmpimg = "$C->{'<nmis_var>'}/rrdDraw-$random.png";
	
		print "Content-type: image/png\n\n";
		($graphret,$xs,$ys) = RRDs::graph($tmpimg, @options);
		if ( -f $tmpimg ) {
	
			### 2012-01-30 keiths, deprecating the need for Win32 support and Image::Resize.
			#use Image::Resize;
			#my $image = Image::Resize->new("$tmpimg");
			#my $gd = $image->resize(120,120);
	
			#open(FH, ">$tmpimg");
			#print FH $gd->png();
			#close(FH);
	
			open(IMG,"$tmpimg") or logMsg("$NI->{system}{name}, ERROR: problem with $tmpimg; $!");
			binmode(IMG);
			binmode(STDOUT);
			while (read(IMG, $buff, 8 * 2**10)) {
				print STDOUT $buff;
			}
			close(IMG);
			unlink($tmpimg) or logMsg("$NI->{system}{name}, Can't delete $tmpimg: $!");
		}
	} else {
		# buffer stdout to avoid Apache timing out on the header tag while waiting for the PNG image stream from RRDs
		select((select(STDOUT), $| = 1)[0]);
		print "Content-type: image/png\n\n";
		if( $filename eq "" ) {
			($graphret,$xs,$ys) = RRDs::graph('-', @options);
		}
		else {
			($graphret,$xs,$ys) = RRDs::graph($filename, @options);
		}
		select((select(STDOUT), $| = 0)[0]);			# unbuffer stdout


		if ($ERROR = RRDs::error) {
			logMsg("$db Graphing Error for $graphtype: $ERROR");
	
		} else {
			#return "GIF Size: ${xs}x${ys}\n";
			#print "Graph Return:\n",(join "\n", @$graphret),"\n\n";
		}
	}

#=====
	### Cologne and Stephane CBQoS Support
	sub graphCBQoS {
		my %args = @_;
		my $S = $args{sys};
		my $NI = $S->ndinfo;
		my $IF = $S->ifinfo;
		my $graphtype = $args{graphtype};
		my $intf = $args{intf};
		my $item = $args{item};
		my $start = $args{start};
		my $end = $args{end};
		my $width = $args{width};
		my $height = $args{height};

		my $database;
		my @opt;
		my $title;

		my ($CBQosNames,$CBQosValues) = loadCBQoS(sys=>$S,graphtype=>$graphtype,index=>$intf);

		if ( $item eq "" ) {
			# display all class-maps in one graph
			my $i;
			my $avgppr;
			my $maxppr;
			my $avgdbr;
			my $maxdbr;
			my $direction = ($graphtype eq "cbqos-in") ? "input" : "output" ;
			my $ifDescr = shortInterface($IF->{$intf}{ifDescr});
			my $vlabel = "Avg Bits per Second";
			if ( $width < 400 ) { 
				$title = "$NI->{name} $ifDescr $direction - $CBQosNames->[0]";
				$vlabel = "Avg bps";
			} else { 
				$title = "$NI->{name} $ifDescr $direction - CBQoS from ".'$datestamp_start to $datestamp_end';
			}
			@opt = (
				"--title", $title,
				"--vertical-label",$vlabel,
				"--start", "$start",
				"--end", "$end",
				"--width", "$width",
				"--height", "$height",
				"--imgformat", "PNG",
				"--interlace"
			);
			# calculate the sum (avg and max) of all Classmaps for PrePolicy and Drop
			$avgppr = "CDEF:avgPrePolicyBitrate=0";
			$maxppr = "CDEF:maxPrePolicyBitrate=0";
			$avgdbr = "CDEF:avgDropBitrate=0";
			$maxdbr = "CDEF:maxDropBitrate=0";
			foreach my $i (1..$#$CBQosNames) {
				$database = $S->getDBName(graphtype=>$graphtype,index=>${intf},item=>$CBQosNames->[$i]);
				my $alias = $CBQosNames->[$i];
				$alias =~ s/\-\-/\//g;
				my $color = $CBQosValues->{"$intf$CBQosNames->[$i]"}{'Color'};
				push(@opt,"DEF:avgPPB$i=$database:PrePolicyByte:AVERAGE");
				push(@opt,"DEF:maxPPB$i=$database:PrePolicyByte:MAX");
				push(@opt,"DEF:avgDB$i=$database:DropByte:AVERAGE");
				push(@opt,"DEF:maxDB$i=$database:DropByte:MAX");
				push(@opt,"CDEF:avgPPR$i=avgPPB$i,8,*");
				push(@opt,"CDEF:maxPPR$i=maxPPB$i,8,*");
				push(@opt,"CDEF:avgDBR$i=avgDB$i,8,*");
				push(@opt,"CDEF:maxDBR$i=maxDB$i,8,*");
				push(@opt,"LINE1:avgPPR$i#$color:$alias");
				#push(@opt,"LINE1:avgPPR$i#$color:$CBQosNames->[$i]");
				$avgppr = $avgppr.",avgPPR$i,+";
				$maxppr = $maxppr.",maxPPR$i,+";
				$avgdbr = $avgdbr.",avgDBR$i,+";
				$maxdbr = $maxdbr.",maxDBR$i,+";
			}
			push(@opt,$avgppr);
			push(@opt,$maxppr);
			push(@opt,$avgdbr);
			push(@opt,$maxdbr);

			if ($width > 400) {
				push(@opt,"COMMENT:\\l");
				push(@opt,"GPRINT:avgPrePolicyBitrate:AVERAGE:Avg PrePolicyBitrate %1.0lf bps");
				push(@opt,"GPRINT:maxPrePolicyBitrate:MAX:Max PrePolicyBitrate %1.0lf bps\\l");
				push(@opt,"GPRINT:avgDropBitrate:AVERAGE:Avg DropBitrate %1.0lf bps");
				push(@opt,"GPRINT:maxDropBitrate:MAX:Max DropBitrate %1.0lf bps");
			}

			# reset $database so any errors reference the correct class-map
	##		$database = getRRDFileName(type => $graph, node => $node, group => $group, nodeType => $NMIS::systemTable{nodeType}, extName => $IF->{$intf}{ifDescr}, item => $CBQosNames[0]);

		} else {
			# display the selected class-map (push button)
			my $speed = &convertIfSpeed($$CBQosValues{"$intf$item"}{'CfgRate'});
			my $direction = ($graphtype eq "cbqos-in") ? "input" : "output" ;
			$database = $S->getDBName(graphtype=>$graphtype,index=>$intf,item=>$item);
			my $color = $CBQosValues->{"$intf$item"}{'Color'};
			my $ifDescr = shortInterface($IF->{$intf}{ifDescr});
			$title = "$ifDescr $direction - $item from ".'$datestamp_start to $datestamp_end';
			@opt = (
				"--title", "$title",
				"--vertical-label", 'Avg Bits per Second',
				"--start", "$start",
				"--end", "$end",
				"--width", "$width",
				"--height", "$height",
				"--imgformat", "PNG",
				"--interlace",
				"DEF:PrePolicyByte=$database:PrePolicyByte:AVERAGE", 
				"DEF:maxPrePolicyByte=$database:PrePolicyByte:MAX", 
				"DEF:DropByte=$database:DropByte:AVERAGE", 
				"DEF:maxDropByte=$database:DropByte:MAX", 
				"DEF:PrePolicyPkt=$database:PrePolicyPkt:AVERAGE", 
				"DEF:DropPkt=$database:DropPkt:AVERAGE", 
				"DEF:NoBufDropPkt=$database:NoBufDropPkt:AVERAGE", 
				"CDEF:PrePolicyBitrate=PrePolicyByte,8,*",
				"CDEF:maxPrePolicyBitrate=maxPrePolicyByte,8,*",
				"CDEF:DropBitrate=DropByte,8,*",
				"LINE1:PrePolicyBitrate#$color:PrePolicyBitrate",
				"LINE1:DropBitrate#ff0000:DropBitrate\\l"
			);
			if ($width > 400) {
				push(@opt,"GPRINT:PrePolicyBitrate:AVERAGE:Avg PrePolicyBitrate %1.0lf bps");
				push(@opt,"GPRINT:maxPrePolicyBitrate:MAX:Max PrePolicyBitrate %1.0lf bps");
				push(@opt,"GPRINT:PrePolicyByte:AVERAGE:Avg Bytes transfered %1.0lf");
				push(@opt,"GPRINT:PrePolicyPkt:AVERAGE:Avg Packets transfered %1.0lf\\l");
				push(@opt,"GPRINT:DropByte:AVERAGE:Avg Bytes dropped %1.0lf");
				push(@opt,"GPRINT:maxDropByte:MAX:Max Bytes dropped %1.0lf");
				push(@opt,"GPRINT:DropPkt:AVERAGE:Avg Packets dropped %1.0lf");
				push(@opt,"GPRINT:NoBufDropPkt:AVERAGE:Avg Packets No buffer dropped %1.0lf");
			}
			push(@opt,"COMMENT:$$CBQosValues{\"$intf$item\"}{'CfgType'} $speed");
		}
		return @opt;
	}

	### Mike McHenry 2005
	sub graphCalls {
		my %args = @_;
		my $S = $args{sys};
		my $NI = $S->ndinfo;
		my $IF = $S->ifinfo;
		my $graphtype = $args{graphtype};
		my $intf = $args{intf};
		my $start = $args{start};
		my $end = $args{end};
		my $width = $args{width};
		my $height = $args{height};

		my $database;
		my @opt;
		my $title;

		my $device = ($intf eq "") ? "total" : $IF->{$intf}{ifDescr};
		if ( $width < 400 ) { $title = "$NI->{name} Calls ".'$length'; }
		else { $title = "$NI->{name} - $device - ".'$length from $datestamp_start to $datestamp_end'; }

		# display Calls summarized or only one port
		@opt = (
			"--title", $title,
			"--vertical-label","Call Stats",
			"--start", "$start",
			"--end", "$end",
			"--width", "$width",
			"--height", "$height",
			"--imgformat", "PNG",
			"--interlace"
		);

		my $CallCount = "CDEF:CallCount=0";
		my $AvailableCallCount = "CDEF:AvailableCallCount=0";
		my $totalIdle = "CDEF:totalIdle=0";
		my $totalUnknown = "CDEF:totalUnknown=0";
		my $totalAnalog = "CDEF:totalAnalog=0";
		my $totalDigital = "CDEF:totalDigital=0";
		my $totalV110 = "CDEF:totalV110=0";
		my $totalV120 = "CDEF:totalV120=0";
		my $totalVoice = "CDEF:totalVoice=0";

		foreach my $i (keys %{$NI->{database}{calls}}) {
			next unless $intf eq "" or $intf eq $i;
			$database = $NI->{database}{calls}{$i};

			push(@opt,"DEF:CallCount$i=$database:CallCount:MAX");
			push(@opt,"DEF:AvailableCallCount$i=$database:AvailableCallCount:MAX");
			push(@opt,"DEF:totalIdle$i=$database:totalIdle:MAX");
			push(@opt,"DEF:totalUnknown$i=$database:totalUnknown:MAX");
			push(@opt,"DEF:totalAnalog$i=$database:totalAnalog:MAX");
			push(@opt,"DEF:totalDigital$i=$database:totalDigital:MAX");
			push(@opt,"DEF:totalV110$i=$database:totalV110:MAX");
			push(@opt,"DEF:totalV120$i=$database:totalV120:MAX");
			push(@opt,"DEF:totalVoice$i=$database:totalVoice:MAX");

			$CallCount .= ",CallCount$i,+";
			$AvailableCallCount .= ",AvailableCallCount$i,+";
			$totalIdle .= ",totalIdle$i,+";
			$totalUnknown .= ",totalUnknown$i,+";
			$totalAnalog .= ",totalAnalog$i,+";
			$totalDigital .= ",totalDigital$i,+";
			$totalV110 .= ",totalV110$i,+";
			$totalV120 .= ",totalV120$i,+";
			$totalVoice .= ",totalVoice$i,+";
			if ($intf ne "") { last; }
		}

		push(@opt,$CallCount);
		push(@opt,$AvailableCallCount);
		push(@opt,$totalIdle);
		push(@opt,$totalUnknown);
		push(@opt,$totalAnalog);
		push(@opt,$totalDigital);
		push(@opt,$totalV110);
		push(@opt,$totalV120);
		push(@opt,$totalVoice);

		push(@opt,"LINE1:AvailableCallCount#FFFF00:AvailableCallCount");
		push(@opt,"LINE2:totalIdle#000000:totalIdle");
		push(@opt,"LINE2:totalUnknown#FF0000:totalUnknown");
		push(@opt,"LINE2:totalAnalog#00FFFF:totalAnalog");
		push(@opt,"LINE2:totalDigital#0000FF:totalDigital");
		push(@opt,"LINE2:totalV110#FF0080:totalV110");
		push(@opt,"LINE2:totalV120#800080:totalV120");
		push(@opt,"LINE2:totalVoice#00FF00:totalVoice");
		push(@opt,"COMMENT:\\l");
		push(@opt,"GPRINT:AvailableCallCount:MAX:Available Call Count %1.2lf");
		push(@opt,"GPRINT:CallCount:MAX:Total Call Count %1.0lf");

		# reset $database so any errors gives information
###		$database = getRRDFileName(graphtype => $graphtype, node => $node, group => $group, nodeType => $NMIS::systemTable{nodeType}, extName => "dummy");
		return @opt;
	}

} # end graph

###
### Load the CBQoS values in array
###
sub loadCBQoS {
	my %args = @_;
	my $S = $args{sys};
	my $NI = $S->ndinfo;
	my $CB = $S->cbinfo;
	my $M = $S->mdl;
	my $node = $NI->{name};
	my $index = $args{index};
	my $graphtype = $args{graphtype};

	my $PMName;
	my @CMNames;
	my %CBQosValues;
	my @CBQosNames;

	# define line color of the graph
	my @colors = ("888888","00CC00","0000CC","CC00CC","FFCC00","00CCCC",
				"444444","440000","004400","000044","BBBB00","BB00BB","00BBBB",
				"888800","880088","008888","444400","440044","004444");

	my $direction = $graphtype eq "cbqos-in" ? "in" : "out" ;

	$PMName = $CB->{$index}{$direction}{PolicyMap}{Name};

	foreach my $k (keys %{$CB->{$index}{$direction}{ClassMap}}) {
		my $CMName = $CB->{$index}{$direction}{ClassMap}{$k}{Name};
		push @CMNames , $CMName if $CMName ne "";

		$CBQosValues{$index.$CMName}{'CfgType'} = $CB->{$index}{$direction}{ClassMap}{$k}{'BW'}{'Descr'};
		$CBQosValues{$index.$CMName}{'CfgRate'} = $CB->{$index}{$direction}{ClassMap}{$k}{'BW'}{'Value'};
	}

	# order the buttons of the classmap names for the Web page
	@CMNames = sort {uc($a) cmp uc($b)} @CMNames;

	my @qNames;
	my @confNames = split(',', $M->{node}{cbqos}{order_CM_buttons});
	foreach my $Name (@confNames) {
		for (my $i=0; $i<=$#CMNames; $i++) {
			if ($Name eq $CMNames[$i] ) {
				push @qNames, $CMNames[$i] ; # move entry
				splice (@CMNames,$i,1);
				last;
			}
		}
	}

	@CBQosNames = ($PMName,@qNames,@CMNames); #policy name, classmap names sorted, classmap names unsorted
	if ($#CBQosNames) { 
		# colors of the graph in the same order
		for my $i (1..$#CBQosNames) {
			if ($i < $#colors ) {
				$CBQosValues{"${index}$CBQosNames[$i]"}{'Color'} = $colors[$i-1];
			} else {
				$CBQosValues{"${index}$CBQosNames[$i]"}{'Color'} = "000000";
			}
		}
	}
	return \(@CBQosNames,%CBQosValues);
} # end loadCBQos

sub id { 
	my $x = 10 *shift;
	return '_'.sprintf("%02X", $x);	
}	