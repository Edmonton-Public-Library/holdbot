=== Wed Jun 10 11:00:07 MDT 2015 ===

Project Notes
-------------

Instructions for Running:
./holdbot

Product Description:
Perl script written by Andrew Nisbet for Edmonton Public Library, and is distributable by the enclosed license.
Holdbot's job is to manage cancelling holds, and notify the owners of those holds, under special conditions.

== Conditions of hold cancelling ==
# ONORDER cancellation. This occurs when a item that is on order and accepting holds, is no longer available.
# Last copy discard. When the last copy of a title is about to be discarded, all the holds should be cancelled.
# Orphaned volume level hold, can occur because of a bug in Symphony that doesn't allow volume level holds.
  Once an item is checked in at a branch (under floating rules), if there are no other items under that call
  number, the sequence number doesn't get updated, and the hold table gets updated to contain the first item
  on the title. In some cases all customers have had their holds moved to volume 'n' of a title.
# Duplicate record load. TBD.
# Fix holds that show available 'Y' but status of INACTIVE.

Holdbot's role is to assess each of these situations as discrete tasks and cancel the holds on the title and
possibly moving holds to another title if possible.(?)


Repository Information:
This product is under version control using Git.

Dependencies:
[Pipe.pl](https://github.com/anisbet/pipe)

Known Issues:
Moving holds is experimental.
