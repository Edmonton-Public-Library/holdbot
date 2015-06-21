#!/usr/bin/perl -w
####################################################################################
#
# Perl source file for project holdbot
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
#          0.1_04 - Add -l Last Copy hold cancellation. 
#          0.1_03 - Update messaging in usage. 
#          0.1_02 - Adding -m, check for hold type. 
#          0.1_01 - Adding -m, change dates of holds back to original. 
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
my $VERSION      = qq{0.1_04};

# The report table produces this data. It gives an item key and status from discard audit
# as bit flags.
# Discard location (all)   = 0b00000001 1  = DISCARD
# Last Copy                = 0b00000010 2  = last copy
# Bills on copy            = 0b00000100 4  = item has bills
# On order                 = 0b00001000 8  = item has orders pending. Check to make sure this flag is NOT set.
# Serial Control (ignore)  = 0b00010000 16 = item is under serial control
# Academic record (ignore) = 0b00100000 32 = item is accountable
# Hold (Title)             = 0b01000000 64 = item has title level hold
# Hold (Copy)              = 0b10000000 128= item has copy level hold
my $DISCARD   = 0b00000001;
my $LAST_COPY = 0b00000010;
my $BILLS     = 0b00000100;
my $ORDERS    = 0b00001000;
my $SERIALS   = 0b00010000;
my $ACCT      = 0b00100000;
my $T_HOLDS   = 0b01000000;
my $C_HOLDS   = 0b10000000;
# 
# The last copy complete list looks like this:
# 999849|53|1|9|
# 999849|61|1|13|
# 999851|32|1|77|
# 999859|23|1|9|
# 999859|25|2|9|
# 999875|22|1|9|
# 999877|15|3|9|
# 999948|1|1|19|
# 999957|56|1|9|
# 999999|20|1|9|
#
my $DISCARD_AUDIT = qq{'cat /s/sirsi/Unicorn/EPLwork/cronjobscripts/Discards/DISCARD_COMP.lst'};

#
# Message about this program and how to use it.
#
sub usage()
{
    print STDERR << "EOF";

	usage: [echo "TCN_1|TCN_2|"] | $0 [-dlmovx]
Holdbot's job is to manage cancelling holds, and notify the owners of those holds, under special conditions.

== Conditions of hold cancelling ==
1 ONORDER cancellation. This occurs when a item that is on order and accepting holds, is no longer available.
  Identifies the cancelled orders, cancels the holds for customers, and sends notification.
2 Last copy discard. When the last copy of a title is about to be discarded, all the holds should be cancelled
  and the customers notified.
3 Orphaned volume level hold, can occur because of a bug in Symphony that doesn't allow volume level holds.
  Once an item is checked in at a branch (under floating rules), if there are no other items under that call
  number, the sequence number doesn't get updated, and the hold table gets updated to contain the first item
  on the title. In some cases all customers have had their holds moved to volume 'n' of a title.

Holdbot's role is to assess each of these situations as discrete tasks and cancel the holds on the title and
possibly moving holds to another title if possible. TBD

 -l: Process last copy holds. TBD.
 -m: Move holds from one title to another. Accepts input on STDIN in the form of 'TCN_SOURCE|TCN_DESTINATION|...'
     preserving the holds from title SOURCE in order. IN PROGRESS.
 -o: ** deprecated **, cancel, cancelled ONORDER holds. Use Notice for cancelled holds (holdcancelntc) report (in Circulation tab).
 -v: Process volume level holds AKA orphan holds.
 -x: This (help) message.

example: 
 $0 -x
 echo "a1004031|LSC2740719" | $0 -m
Version: $VERSION
EOF
    exit;
}

# Search holds on item id for the given user id, then sets the hold date placed to the argument date.
# param:  String user id.
# param:  String item id.
# param:  String holds date.
# return: 1 if the user was found in the list of holds and 0 otherwise.
sub set_hold_date( $$$ )
{
	my ( $userId, $itemId, $holdDate ) = @_;
	return 0 if ( ! defined $holdDate or $holdDate eq '' );
	chomp $holdDate;
	# We will do a selection on holds on the new item and grep the user id to get the hold key then set the date with edithold.
	my @holds = `echo "$userId" | seluser -iB 2>/dev/null | selhold -iU -j"ACTIVE" -oIK 2>/dev/null | selitem -iI -oBS 2>/dev/null | pipe.pl -t"c0"`;
	chomp @holds;
	return 0 if ( scalar @holds == 0 );
	my @matches = grep $itemId, @holds;
	printf STDERR "** Warning: customer '%s' has more than one hold on '%s'!\n", $userId, $itemId if ( scalar @matches > 1 );
	foreach my $match ( @matches )
	{
		my ( $id, $holdKey ) = split '\|', $match;
		return 0 if ( ! defined $holdKey or $holdKey eq '' );
		printf STDERR "=setting hold key '%s's placed date to '%s'\n", $holdKey, $holdDate;
		`echo "$holdKey" | edithold -p"$holdDate"`;
	}
	return 1;
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
	# holdKey   catkey sequence# userKey holdType date placed.
	# 23038226|1419753|1|433644|T|20150325|
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
	open ORDERED, "<tmp_holds_ordered.lst" or die "*** error reading 'tmp_holds_ordered.lst' $!\n";
	# Stitch the two pieces together, items and users.
	while (<ITEMS>)
	{
		my $item = $_; chomp $item;
		my $user = <USERS>; chomp $user;
		# Set the date hold placed back to original date.
		my $original_hold_line = <ORDERED>; chomp $original_hold_line;
		my $hold_type = `echo "$original_hold_line" | pipe.pl -o"c4"`;
		chomp $hold_type;
		# Don't process if this isn't a title level hold.
		if ( ! defined $hold_type or $hold_type !~ m/T/ )
		{
			printf STDERR "* refusing to move non-title level hold for '%14s'\n", $user;
			next;
		}
		printf STDERR "cancelling hold on item %14s for %14s\n", $item, $user;
		`echo "$item" | cancelholds.pl -B"$user" -tU`;
		printf STDERR " creating hold on item %14s for %14s\n", $new_item, $user;
		`echo "$new_item" | createholds.pl -B"$user" -tU`;
		# Now reset the original hold placed date from the original holds.
		# We want '23482547|1419753|1|1007114|T|<20150603>|'
		my $original_hold_date = `echo "$original_hold_line" | pipe.pl -o"c5"`;
		# Ensure we have an actual date
		if ( ! defined $original_hold_date or $original_hold_date eq '' or $original_hold_date !~ m/^\d{8}/ )
		{
			printf STDERR "*** error could find date in: '%s'\n", $original_hold_date;
			exit 0;
		}
		if ( ! set_hold_date( $user, $new_item, $original_hold_date ) )
		{
			printf STDERR "*** error: placed date unset for customer: '%s'; item: '%s'\n", $user, $item;
			exit 0;
		}
		exit 1; # testing just do one for now.
	}
	close ITEMS;
	close USERS;
	close ORDERED;
}

# Takes a flag encoded integer and tests if it encodes a last copy with a hold or not.
# param:  flag field.
# return: 1 if the param encoded a item with a hold and is a last copy and 0 otherwise. 
sub isLastCopyWithHold( $ )
{
	my $bitField = shift;
	### Last viable item with holds can be gathered through the discard report mechanism 
	# (or looking for titles with 1 visible call num with one item).
	# Read the entire list of discarded items. We are looking for those that match last copy,
	# title hold and copy hold.
	if (( $bitField & $LAST_COPY ) == $LAST_COPY ) 
	{
		if ((( $bitField & $T_HOLDS ) == $T_HOLDS ) or (( $bitField & $C_HOLDS ) == $C_HOLDS ) )
		{
			return 1;
		}
	}
	return 0;
}

# Kicks off the setting of various switches.
# param:  
# return: 
sub init
{
	my $opt_string = 'lmovx';
	getopts( "$opt_string", \%opt ) or usage();
	usage() if ( $opt{'x'} );
	if ( $opt{'l'} )
	{
		my $lines = `ssh sirsi\@eplapp.library.ualberta.ca '$DISCARD_AUDIT'`;
		my @data = split '\n', $lines;
		my $count = 0;
		while ( @data )
		{
			my $line = shift @data;
			chomp $line;
			my @fields = split '\|', $line;
			# Bit field is in the 4th element of the array.
			if ( @fields and isLastCopyWithHold( $fields[3] ) )
			{
				# TODO: Do something clever.
				$count++;
				printf "%s\n", join( '|', @fields );
			}
		}
		printf "%3d\n", $count;
		exit 1;
	}
	if ( $opt{'o'} )
	{
		### Cancelled on order items have ORD_CANCEL as an inactive reason. This should be done 
		# using the Notice for cancelled holds (holdcancelntc) report.
		print STDERR "*** Warning: -o cancelled on-order holds not implemented. See Notice for cancelled holds (holdcancelntc)\n";
		usage();
	}
	if ( $opt{'v'} )
	{
		### Find and move / cancel orphan volume holds.
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
