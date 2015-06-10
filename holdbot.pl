#!/usr/bin/perl -w
####################################################################################
#
# Perl source file for project holdbot 
# Purpose:
# Method:
#
# Manages the process of assessing, cancelling, and notifying customers about holds.
#    Copyright (C) 2015  Andrew Nisbet
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
# 
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
# 
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston,
# MA 02110-1301, USA.
#
# Author:  Andrew Nisbet, Edmonton Public Library
# Created: Wed Jun 10 11:00:07 MDT 2015
# Rev: 
#          0.1 - Script framework and documentation set up. 
#          0.0 - Dev. 
# Dependencies: pipe.pl.
#
###################################################################################

use strict;
use warnings;
use vars qw/ %opt /;
use Getopt::Std;

# Environment setup required by cron to run script because its daemon runs
# without assuming any environment settings and we need to use sirsi's.
###############################################
# *** Edit these to suit your environment *** #
$ENV{'PATH'}  = qq{:/s/sirsi/Unicorn/Bincustom:/s/sirsi/Unicorn/Bin:/usr/bin:/usr/sbin};
$ENV{'UPATH'} = qq{/s/sirsi/Unicorn/Config/upath};
###############################################
my $VERSION    = qq{0.1};

#
# Message about this program and how to use it.
#
sub usage()
{
    print STDERR << "EOF";

	usage: $0 [-x]
Holdbot's job is to manage cancelling holds, and notify the owners of those holds, under special conditions.

== Conditions of hold cancelling ==
1 ONORDER cancellation. This occurs when a item that is on order and accepting holds, is no longer available.
2 Last copy discard. When the last copy of a title is about to be discarded, all the holds should be cancelled.
3 Orphaned volume level hold, can occur because of a bug in Symphony that doesn't allow volume level holds.
  Once an item is checked in at a branch (under floating rules), if there are no other items under that call
  number, the sequence number doesn't get updated, and the hold table gets updated to contain the first item
  on the title. In some cases all customers have had their holds moved to volume 'n' of a title.
4 Duplicate record load. TBD.

Holdbot's role is to assess each of these situations as discrete tasks and cancel the holds on the title and
possibly moving holds to another title if possible. TBD

 -d: Process duplicate record load holds. TBD.
 -l: Process last copy holds. TBD.
 -m: Move holds from one title to another. Accepts input on STDIN in the form of 'TCN_SOURCE|TCN_DESTINATION|...'
     preserving the holds from title SOURCE in order. IN PROGRESS.
 -o: Process orphan holds. TBD.
 -v: Process volume level holds. TBD.
 -x: This (help) message.

example: $0 -x
Version: $VERSION
EOF
    exit;
}

# Moves holds from one title to another.
# param:  String of pipe delimited 'src_TCN|dst_TCN|'
# return: <none>
sub move_holds( $ )
{
	my $line = shift;
	chomp $line;
	my ($src, $dst) = split '\|', $line;
	if ( ! defined $src or $src eq "" or ! defined $dst or $dst eq "" )
	{
		print STDERR "*** error: malformed input line. Expected 'src_TCN|dst_TCN|[...]' as input.\n";
		usage();
	}
	# 1) collect all information about the current state of holds on these two titles.
	# echo LSC2740719 | selcatalog -iF -oC | selhold -iC -j"ACTIVE" -oKNUtp >
	# holdKey   catkey sequence# userKey holdType date placed.
	# 23038226|1419753|1|433644|T|20150325|
	# 23470605|1419753|1|1050288|T|20150601|
	# 23482547|1419753|1|1007114|T|20150603|
	`echo "$src" | selcatalog -iF -oC | selhold -iC -j"ACTIVE" -oKNUtp >  tmp_holds.lst 2>/dev/null`;
	`echo "$dst" | selcatalog -iF -oC | selhold -iC -j"ACTIVE" -oKNUtp >> tmp_holds.lst 2>/dev/null`;
	# Order by date placed to interleave the holds from the other
	`cat tmp_holds.lst | pipe.pl -s"c5" -U >tmp_holds_ordered.lst`;
	# Cancel all holds on src, and create on dst, in order one-at-a-time.
	# To do that, lets get the item id and user id
	`cat tmp_holds_ordered.lst | selhold -iK -oI | selitem -iI -oB | pipe.pl -t"c0" >item_ids_ordered.lst`;
	# find all the user ids in order.
	`cat tmp_holds_ordered.lst | pipe.pl -o"c3" | seluser -iU -oB | pipe.pl -t"c0" >user_ids_ordered.lst`;
	# Find an ID of an item for the new hold.
	my $new_item = `echo "$dst" | selcatalog -iF -oC | selitem -iC -oB | pipe.pl -L"1" -t"c0"`;
	chomp $new_item;
	if ( ! defined $new_item or $new_item eq '' )
	{
		print STDERR "*** error: couldn't find an item ID associated with flex key '$dst'\n";
		exit 0;
	}
	open ITEMS, "<item_ids_ordered.lst" or die "*** error reading 'item_ids_ordered.lst' $!\n";
	open USERS, "<user_ids_ordered.lst" or die "*** error reading 'user_ids_ordered.lst' $!\n";
	# Stitch the two pieces together, items and users.
	while (<ITEMS>)
	{
		my $item = $_; chomp $item;
		my $user = <USERS>; chomp $user;
		printf "cancelling hold on item %14s for %14s\n", $item, $user;
		# `echo "$item" | cancelholds.pl -B"$user" -tU`;
		printf " creating hold on item %14s for %14s\n", $new_item, $user;
		# `echo "$new_item" | createholds.pl -B"$user" -tU`;
	}
	close ITEMS;
	close USERS;
}

# Kicks off the setting of various switches.
# param:  
# return: 
sub init
{
	my $opt_string = 'dlmovx';
	getopts( "$opt_string", \%opt ) or usage();
	usage() if ( $opt{'x'} );
	if ( $opt{'d'} )
	{
		### Duplicate order loads can be spotted by looking for duplicate 020, or 024
		# tags in titles, and are typically caused by bibload not matching on these tags
		# due to an indexing failure, and thus creating new records.
		print STDERR "*** Warning: -d duplicate title holds cancel not implemented yet.\n";
		usage();
	}
	if ( $opt{'l'} )
	{
		### Last viable item with holds can be gathered through the discard report mechanism 
		# (or looking for titles with 1 visible call num with one item).
		print STDERR "*** Warning: -l last viable copy holds cancel not implemented yet.\n";
		usage();
	}
	if ( $opt{'o'} )
	{
		### Cancelled on order items have a home location of CANC_ORDER.
		print STDERR "*** Warning: -o cancelled on-order holds cancel not implemented yet.\n";
		usage();
	}
	if ( $opt{'v'} )
	{
		print STDERR "*** Warning: -v volume (orphaned) holds cancel not implemented yet.\n";
		usage();
	}
}

init();
# Can take input from STDIN, but each function handles it in a different way.
while (<>)
{
	move_holds( $_ ) if ( $opt{'m'} );
}
# EOF
