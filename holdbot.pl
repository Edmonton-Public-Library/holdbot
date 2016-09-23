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
#          0.4.02 - Clean up variable declarations and trailing "'" on selhold selection. 
#          0.4.01 - Check for availability of yesterday. 
#          0.4.00 - Add fix to change INACTIVE holds to have available flag 'Y' to 'N'. 
#          0.3.02 - Fixed bug that failed to lower case titles before output. 
#          0.3.01 - Added -aN to not move holds that are available. 
#          0.3 - Add search-able URL to title. 
#          0.2.01 - Testing move holds. 
#          0.2 - Re-factored out excessive processing in favour of cancelling and moving holds. 
#          0.1_05 - Add -a to audit the DISCARD location before doing -l. 
#          0.1_04 - Add -l Last Copy hold cancellation. 
#          0.1_03 - Update messaging in usage. 
#          0.1_02 - Adding -m, check for hold type. 
#          0.1_01 - Adding -m, change dates of holds back to original. 
#          0.1 - Script framework and documentation set up. 
#          0.0 - Dev. 
# Dependencies: 
# cancelholds.pl 
# pipe.pl        - To clean and trim extra fields at various locations.
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
chomp( my $TEMP_DIR    = `getpathname tmp` );
chomp( my $TIME        = `date +%H%M%S` );
chomp( my $DATE        = `date +%Y%m%d` );
chomp( my $TODAY       = `date +%Y%m%d` );
my @CLEAN_UP_FILE_LIST = (); # List of file names that will be deleted at the end of the script if ! '-t'.
chomp( my $BINCUSTOM   = `getpathname bincustom` );
my $PIPE               = "$BINCUSTOM/pipe.pl";
my $VERSION            = qq{0.4.02};

# Removes all the temp files created during running of the script.
# param:  List of all the file names to clean up.
# return: <none>
sub clean_up
{
	foreach my $file ( @CLEAN_UP_FILE_LIST )
	{
		if ( $opt{'t'} )
		{
			printf STDERR "preserving file '%s' for review.\n", $file;
		}
		else
		{
			if ( -e $file )
			{
				unlink $file;
			}
		}
	}
}

# Writes data to a temp file and returns the name of the file with path.
# param:  unique name of temp file, like master_list, or 'hold_keys'.
# param:  data to write to file.
# return: name of the file that contains the list.
sub create_tmp_file( $$ )
{
	my $name    = shift;
	my $results = shift;
	my $sequence= sprintf "%02d", scalar @CLEAN_UP_FILE_LIST;
	my $master_file = "$TEMP_DIR/$name.$sequence.$DATE.$TIME";
	# Return just the file name if there are no results to report.
	return $master_file if ( ! $results );
	open FH, ">$master_file" or die "*** error opening '$master_file', $!\n";
	print FH $results;
	close FH;
	# Add it to the list of files to clean if required at the end.
	push @CLEAN_UP_FILE_LIST, $master_file;
	return $master_file;
}

#
# Message about this program and how to use it.
#
sub usage()
{
    print STDERR << "EOF";

	usage:  [cat catkeys.file | $0 [-cmsUx] | $0 -A]
Holdbot's job is to manage holds in a way that will produce output suitable for consumption of other scripts.

Holdbot can move holds from one title to another if given appropriate input of pipe separated catalogue keys on STDIN,
one pair per line in the format 'C_KEY_SRC|C_KEY_DEST|'.

The script can also cancel all holds on a title. The titles are identified by the catalog key supplied, one
per line, on STDIN.

In all cases the keys are tested before the operations take place.

 -A: Fix availability flag for INACTIVE holds. Can be run without fixing, see '-U' below.
 -c: Cancel tile and copy holds on title based on catalogue keys from STDIN. When this switch is used, and the
     holds are cancelled, the HOLD-er's user ID and title are output to STDOUT in pipe-delimited fashion.
 -m: Move holds from one title to another. Accepts input on STDIN in the form of 'TCN_SOURCE|TCN_DESTINATION|'
     preserving the holds from title SOURCE in order.
 -s: Add EPL search-able URL for title.
 -t: Preserve temporary files in $TEMP_DIR.
 -U: Actually do the work, don't just go through the motions. Without -U the script just prints the user ids and titles.
 -x: This (help) message.

example: 
 $0 -x
 echo "a1004031|LSC2740719" | $0 -m
 cat catalog.keys | $0 -c
 $0 -AUt
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
	printf STDERR "***'%s' heres the hold date!\n", $holdDate;
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
	`echo "$src" | selcatalog -iF -oC | selhold -iC -j"ACTIVE" -a'N' -oKNUtp >  tmp_holds.lst 2>/dev/null`;
	`echo "$dst" | selcatalog -iF -oC | selhold -iC -j"ACTIVE" -a'N' -oKNUtp >> tmp_holds.lst 2>/dev/null`;
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
	return if ( ! $opt{'U'} );
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
		chomp $original_hold_date;
		# Ensure we have an actual date
		if ( ! defined $original_hold_date or $original_hold_date eq '' or $original_hold_date !~ m/^\d{8}/ )
		{
			printf STDERR "*** error could find date in: '%s'\n", $original_hold_date;
			exit 0;
		}
		if ( ! set_hold_date( $user, $new_item, $original_hold_date ) )
		{
			printf STDERR "*** error: '%s'\n", $original_hold_line;
			printf STDERR "*** error: placed date unset for customer: '%s'; item: '%s'\n", $user, $item;
			exit 0;
		}
	}
	close ITEMS;
	close USERS;
	close ORDERED;
}

# Cancel holds on the title.
# param:  Catalogue key.
# return: Count of the number of holds cancelled on a title.
sub cancel_holds_on_title( $ )
{
	my $catKey  = shift;
	# Output the title for the customer for email content.
	my $title = `echo "$catKey" | selcatalog -iC -ot 2>/dev/null`;
	chomp $title;
	my $search = '';
	if ( $opt{'s'} )
	{
		# We need the title for the book not the rest of the string.
		# Titles usually have a '/' or ';' in them, we take just the text before this, which is the title
		# itself. Once we have done that we change the title to URL safe format.
		$search = `echo "$title" | $BINCUSTOM/opacsearchlink.pl` if ( -f "$BINCUSTOM/opacsearchlink.pl" );
	}
	# This should look like "[user bar code]|[title]|[search URL]", and be written in an output for mailerbot.
	my $results = `echo "$catKey" | selhold -iC -j"ACTIVE" -oIUt 2>/dev/null | selitem -iI -oSB 2>/dev/null | seluser -iU -oBS 2>/dev/null`;
	create_tmp_file( "holdbot_cancel_holds_on_title_selection", $results );
	# creates: '21221012345678|T|31221087033671  |' for the one hold on a many item-ed title, so many lines.
	my @lines = split '\n', $results;
	my $count = scalar( @lines );
	if ( ! $count )
	{
		printf STDERR "== no holds on title %s ($catKey)\n", $title;
		return 0;
	}
	printf STDERR "== cancelling holds on title %s ($catKey)\n", $title;
	while ( @lines )
	{
		my $line = shift @lines;
		chomp $line;
		my ( $userId, $holdType, $itemId ) = split '\|', $line;
		next if ( ! defined $userId or ! defined $holdType or ! defined $itemId );
		next if ( $userId eq '' or $holdType eq ''  or $itemId  eq '' );
		if ( $opt{'s'} )
		{
			printf "%s|%s|%s", $userId, $title, $search;
		}
		else
		{
			# This should look like "[user bar code]|[title]|", and be written in an output for mailerbot.
			printf "%s|%s", $userId, $title;
		}
		if ( $opt{'U'} )
		{
			printf STDERR "   user ID: %14s, item: %14s of type '%s'\n", $userId, $itemId, $holdType;
			if ( $holdType eq 'C' )
			{
				`echo "$itemId" | cancelholds.pl -B"$userId" -U`;
			}
			else # Title level hold $holdType eq 'T'
			{
				`echo "$itemId" | cancelholds.pl -B"$userId" -Ut`;
			}
		}
	}
	return $count;
}

# Tests if argument is a catalogue key on the ILS.
# param:  catalogue key.
# return: 1 if the argument tested to be a valid catalogue key on the ILS and false otherwise.
sub is_cat_key( $ )
{
	my $testKey = shift;
	my $result  = `echo "$testKey" | selcatalog -iC 2>/dev/null`;
	return 1 if ( defined $result and $result ne '' );
	return 0;
}

# Takes a line as argument splits the source and destination and tests each for cat-key'ed-ness.
# param:  string like "789657|203334|"
sub test_TCN_pairs( $ )
{
	my $testLine = shift;
	my @tcns = split '\|', $testLine;
	if ( defined $tcns[0] and $tcns[0] ne '' )
	{
		if ( defined $tcns[1] and $tcns[1] ne '' )
		{
			my $testKey = $tcns[0];
			my $result = `echo "$testKey" | selcatalog -iF 2>/dev/null`;
			if ( defined $result and $result ne '' )
			{
				$testKey = $tcns[1];
				$result = `echo "$testKey" | selcatalog -iF 2>/dev/null`;
				return 1 if ( defined $result and $result ne '' );
			}
		}
	}
	return 0;
}

# Selects INACTIVE but available holds then switches the Availability flag to 'N'.
# param: <none>
# return: count of records fixed.
sub fix_inactive_available_holds()
{
	my $results = `selhold -aY -jINACTIVE -6"<$TODAY" 2>/dev/null`;
	my $inactiveAvailableHoldKeys = create_tmp_file( "holdbot", $results );
	if ( $opt{'U'} )
	{
		`cat "$inactiveAvailableHoldKeys" | edithold -a'N'`;
	}
	$results = `cat "$inactiveAvailableHoldKeys" | wc -l | "$PIPE" -tc0`;
	return $results;
}

# Kicks off the setting of various switches.
# param:  
# return: 
sub init
{
	my $opt_string = 'AcmtUsx';
	getopts( "$opt_string", \%opt ) or usage();
	usage() if ( $opt{'x'} );
	if ( $opt{'A'} )
	{
		printf STDERR "Fixed: %d INACTIVE but available holds.\n", fix_inactive_available_holds();
		clean_up();
		exit 0;
	}
}

init();
# Can take input from STDIN, but each function handles it in a different way.
while (<>)
{
	# Move holds.
	if ( $opt{'m'} )
	{
		my $tcn_pair = $_;
		chomp $tcn_pair;
		if ( ! test_TCN_pairs( $tcn_pair ) )
		{
			printf STDERR "%14s one or both of the TCNs are not valid.\n", $tcn_pair;
			next;
		}
		move_holds( $tcn_pair );
	}
	if ( $opt{'c'} )
	{
		my $key = $_;
		chomp $key;
		if ( ! is_cat_key( $key ) )
		{
			printf STDERR "%14s is a not a valid catalogue key.\n", $key;
			next;
		}
		cancel_holds_on_title( $key );
	}
}
clean_up();
# EOF
