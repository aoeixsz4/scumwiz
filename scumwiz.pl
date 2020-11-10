#!/usr/bin/perl

use strict;
use warnings;
use List::MoreUtils qw(uniq any none);
use Time::HiRes qw(usleep gettimeofday tv_interval);
use POSIX qw(mkfifo);

# use environment-defined TMPDIR, if it exists
# the default of /tmp should be fairly cross-platform tho
my $tmp_dir = $ENV{TMPDIR} // '/tmp';

# define a usage text thingy here
my $run_as = $0;
my $usage_text = <<EOF;
Joanna aka aoei's super cool startscum script for NetHack wizards.
 (C) 2020 Joanna Doyle - treat as if licensed under MIT.
There is no warranty for this software, nor do I accept any responsibility
for your splats. Current version is designed specifically for TNNT.

Before running the script, you need to be logged in to hardfought
in the active window of a screen session, and in the TNNT submenu.
The size of the screen window / terminal window needs to be fairly large,
so that all starting inventory items fit on a single page - 40x150 is what I use.
Your rcfile must include certain options, required by the script,
many of these are set in order to cut down on unnecessary prompts etc:
	
	# these first two lines are absolutely necessary
	OPTIONS=!legacy,scores:!t !a !o,!tombstone,disclose:-i -a -v -g -c -o
	OPTIONS=windowtype:curses,perm_invent
	# the combo doesn't *have* to be Wiz-Elf-Fem-Cha, just needs to be set
	OPTIONS=role:wizard,race:elf,gender:female,align:chaotic
	# not 100% whether these are all required, but add just to be sure
	OPTIONS=!cmdassist,!help,!verbose,suppress_alert:3.4.3,!splash_screen
	# it's also assumed you have autopickup enabled and / in types
	# (or an autopickup exception that will pick up unidentified wands)
	
	 (the exact combo doesn't necessarily have to be Wiz-Elf-Fem-Cha,
	  but it absolutely has to be defined in the rcfile for the script to work)

	Usage:
	\$ $run_as [-h|-help] [-user=<dgl_login>] [-session=<screen_id>]
				[-<target>...] [no<target>...] [+<target>...]

	-h/-help	- print this text and quit

	-session=	- define the name of the relevant screen session
					(defaults to 'default').

	-<target>	- add a hard scumming target,
					(defaults are 'int', 'tonal' and 'poly')
					a hit requires all hard targets to be found.

	no<target>	- remove one of the default hard targets.

	+<target>	- add a soft scumming target - if any soft targets
					are set, a hit is only called if at least one
					of the defined soft targets is found.
	
NB: all hard and soft targets are ignored if a random wand is found.
Possible <target>s to scum for include: 'int' (meaning >=17), 'tonal',
	'poly' (either polywand or polycontrol), 'tc' (teleport control),
	'digging' (start with a digging wand), 'foodless' (slow digestion),
	'marker' (start with a marker).
EOF

# take two array refs, first is an exclusion list
# second is the arrray to be filtered
# return a list only containing values that 
# don't appear in the exclusion set, strings
# have to match exactly to be excluded
sub negate_filter {
    my ($exclusion_spec, $input_array) = @_;
    my @filtered_list = ();

    foreach my $list_item (@$input_array) {
        if (none { $_ eq $list_item } @$exclusion_spec) {
            push @filtered_list, $list_item;
        }
    }
    return @filtered_list;
}

# return true if the second array ref contains
# all the elements of the first as a subset of it
# this bit is used to test whether the set of
# goodies provided by the current game includes
# the set of hard scum targets
sub is_subset {
    my ($possible_subset, $search_space) = @_;

    # we can do a neat trick with the negate_filter,
    # $search_space becomes our exclusion_spec, with
    # $possible_subset as the input array -
    # if negate_filter returns an empty array,
    # we return true
    if (negate_filter ($search_space, $possible_subset) == 0) {
        return 1;
    } else {
        return 0;
    }
}

# count how many items in the first array
# appear in the second one, we can also use negate_filter
# here and take the difference in array length as hit count,
# however that seems odd and counter intuitive,
# will simply do the simple thing
sub count_hits {
    my ($test_set, $search_space) = @_;
    my $count = 0;

    foreach my $test_item (@$test_set) {
        if (any { $_ eq $test_item } @$search_space) {
            $count++;
        }
    }
    return $count;
}

sub get_elapsed
{
	my $t0 = shift;
	my ($days, $hours, $minutes, $seconds);
	my $elapsed = tv_interval ($t0);
	my @unit;

	$seconds = int ($elapsed);
	if ($seconds > 60)
	{
		$minutes = int ($seconds / 60);
		$seconds -= $minutes * 60;
		unshift @unit, "$seconds s";
		unshift @unit, "$minutes m"
	}
	else
	{
		unshift @unit, "$seconds s"
	}
	if ($minutes && $minutes > 60)
	{
		$hours = int ($minutes / 60);
		$minutes -= $hours * 60;
		unshift @unit, "$hours h"
	}
	if ($hours && $hours > 24)
	{
		$days = int ($hours / 24);
		$hours -= $days * 24;
		unshift @unit, "$days d"
	}

	return join ' ', @unit
}

# returns a line by line dump from the active
# window of the screen session we're interested in,
# with a bit of processing to trim excess whitespace etc.
sub get_screencopy
{
	my ($fh, @screen_raw, @data_out, $i, $signal);
	my $session = shift;
	my $filename = "${tmp_dir}/${session}.$$";
	mkfifo ($filename, 0700)
		or die "Couldn't make named pipe";
	my $pid = fork;
	if ($pid)
	{
		open ($fh, '<', $filename)
			or die "Open failed: $!\n";
		@screen_raw = <$fh>;
		close $fh;
		unlink $filename;
		wait;
#		print "returned: $?, ", $? >> 8, " from child $pid\n"
	}
	else
	{
		exec ('screen', '-S', $session, '-X', 'hardcopy', $filename)
	}
	close $fh;
	unlink $filename;

	foreach my $line (@screen_raw) {
		$line =~ s/^\s*//; # strip preceeding whitespace
		$line =~ s/\s*$//; # strip tailing whitespace
		if (length($line) > 0) {
			push @data_out, $line;
            #print STDERR "$line\n";
		}
	}
	return @data_out;
}

## i think this subroutine isn't currently in actual use
#sub diff_array
#{
#	my ($arr_a, $arr_b) = (shift, shift);
#	return 1
#		if (@$arr_a != @$arr_b);
#	my ($i);
#	$i = 0;
#	while ($i < @$arr_a)
#	{
#		if (!$arr_a->[$i] && !$arr_b->[$i])
#		{
#			$i++; next
#		}
#		elsif (!$arr_a->[$i] || !$arr_b->[$i])
#		{
#			return 1
#		}
#		elsif ($arr_a->[$i] ne $arr_b->[$i])
#		{
#			return 1
#		}
#		else
#		{
#			$i++
#		}
#	}
#	return 0
#}

my $session = 'default';

# add option to pass additional args,
# default scum behaviour would be a fairly oldskool setup
#   - int >= 17
#   - EITHER poly wand or ring of control (poly ring sucks)
#   - tonal necessary
# i may change these defaults to something else like
#  digging + teleport control, or digging + polyitem
#  tonal + hungerless casting is a bit overrated
#
# but, various flags passed to the script could change this
#   "notonal"  - remove requirement to start with tonal
#   "nopoly"   - don't scum for a polyitem necessarily
#   "noint"    - remove minimum int requirement of 17
#
#   flags beginning with - are hard scumming requirements,
#   tho if the prefix is missing, -flag behaviour is assumed
#   "-marker"   - scum for a marker
#   "-foodless" - scum for ring of slow digestion
#   "-digging"  - scum for starting digging wand
#   "-tc"       - scum for teleport control
#   
#   the same flags, if marked with +, are "soft-scum",
#   i.e. they don't all have to hit, but if any one of them
#   does, the script stops
#
# most options are superceded if a wand is found in the first room,
# since its worth checking whether it's a wand of wishing
#
# screen session can be set with -session=bar

my @scum_keys = ('tonal', 'poly', 'marker', 'foodless', 'digging', 'tc', 'int');
my @hard_scum = ('poly', 'tonal', 'int');
my @soft_scum = ();
my @non_scum = (); # anything added to this list will result in them being removed from 
foreach my $flag (@ARGV) {
	if ($flag =~ m/^-h(elp)?$/) {
		# print usage text and exit
		print STDERR $usage_text;
		exit 0;
	} elsif ($flag =~ m/^-session=([\w-]+)$/) {
		$session = $1;
	} elsif ($flag =~ m/^(no|\+|-|.*?)(\w+)$/) {
        my ($flag_type, $item) = ($1, $2);
        if (any { $_ eq $item } @scum_keys) {
            if ($flag_type eq 'no') {
                push @non_scum, $item;
            } elsif ($flag_type eq '+') {
                push @soft_scum, $item;
            } elsif ($flag_type eq '-' || $flag_type eq '') {
                push @hard_scum, $item;
            } else {
                print STDERR "unrecognised prefix $flag_type (argument $flag)\n";
            }
        } else {
            print STDERR "unrecognised option $item (argument $flag)\n";
        }
    } else {
        print STDERR "unexpected argument format: '$flag'\n";
    }
}
# do some cleaning up to make sure the lists @hard_scum, @soft_scum and @non_scum
# are free from duplicates, then ensure any item found in @non_scum is not
# present in hard scum. items in @hard_scum should also supercede any in @soft_scum
@hard_scum = uniq @hard_scum;
@soft_scum = uniq @soft_scum;
@non_scum = uniq @non_scum;
@hard_scum = negate_filter (\@non_scum, \@hard_scum);
@soft_scum = negate_filter (\@hard_scum, \@soft_scum);
# a single item in @soft_scum will behave effectively like a hard scum

# for testing this bit out now just print the lists and exit
#print STDERR "non-scum list: " . join (", ", @non_scum) . "\n";
#print STDERR "hard-scum list: " . join (", ", @hard_scum) . "\n";
#print STDERR "soft-scum list: " . join (", ", @soft_scum) . "\n";
#exit 0;

my $t0 = [gettimeofday];
my $count = 0;
my $timeout = 0;
my @old_data;

while (1)
{
    my %scum = ();
	my @data;

	# get screen
	do
	{
		# this sleep is important for two reasons
		# one: if it's shorter than the latency, the script will
		# respond to prompts twice (this behaviour could be changed,
		# but the current behaviour is much simpler to program)
		# two: a bug in dgl on the hardfought servers does not deal
		# gracefully if a dumplog already exists for the current
		# unix timestamp, which will kill our session
		# so scumming is effectively capped at one game per second
        usleep 500000;

		@data = get_screencopy ($session)
	}
	while (!@data);

	# start game
	if (grep { m/\bConnection closed by foreign host\b/ } @data) {
		my $elapsed = get_elapsed ($t0);
		die "Spamfiltered ($count tries, time: $elapsed."
	}
	
	# the logic for dealing with start-game and quit prompts
	# is a bit hacky and may be highly dependent on player rcfile!
	# windowtype curses is a must, and the terminal should be large
	# enough to fit the entire inventory (perm_invent must be true)
	# on a single page
	if (grep { m/\bTHE NOVEMBER NETHACK TOURNAMENT IS LIVE\b/ }  @data)
	{
		# hit t to start game
		system ('screen', '-S', $session, '-X', 'stuff', 't');

	} elsif (grep { m/\bGoodbye \w+ the \w+\.\.\./ } @data) {
		# space works for both these exit prompts
		system ('screen', '-S', $session, '-X', 'stuff', ' ');

	} elsif (grep { m/\bBeware, there will be no return\b/ } @data) {
		# this prompt i think is standard after trying to exit dl1 by <
		system ('screen', '-S', $session, '-X', 'stuff', 'y');
		# ths is typically followed by a >> prompt which for some reason
		# struggles to match, so just sleep briefly then send a space
		usleep 200000;
		system ('screen', '-S', $session, '-X', 'stuff', ' ');
	
	# perm_invent means we don't need to actually open inventory so it'll be there on the welcome screen
	# the welcome message remains on screen during quit steps, so process this case last
	} elsif (grep { m/\bHello \w+, welcome to\b/ } @data) {
		# max scum one game per second otherwise dgl error turfs us out
		# tyrec/2020-10-29.08:51:59.ttyrec.gz already exists; do you wish to overwrite (y or n)? 
		# check for key items
		foreach my $line (@data) {
			if ($line =~ m/\bSt:\d+ Dx:\d+ Co:\d+ In:(\d+) Wi:\d+ Ch:\d+\b/) {
				$scum{int} = $1 if $1 >= 17;
			}

            # autopickup gems results in a false positive for room_wand,
            # so filter that text
            $line =~ s/\bGems\/Stones\b//;
			if ($line =~ m/(\/|\b\w - a .*wand)/) {
                print STDERR "room_wand triggered by $1\n";
                $scum{room_wand} = 1;
            }
			
			# inventory lines are mutually exclusive
			if ($line =~ m/\b(tooled horn|harp|bugle|flute)\b/) {
				$scum{tonal} = $1;
			}
			elsif ($line =~ m/\bteleport control\b/) {
				$scum{tc} = 1;
			}
            elsif ($line =~ m/\b(ring of polymorph control|wand of polymorph)\b/) {
                $scum{poly} = $1;
            }
            elsif ($line =~ m/\bmagic marker \(0:[6789]/) {
                $scum{marker} = 1;
            }
            elsif ($line =~ m/\bring of slow digestion\b/) {
                $scum{foodless} = 1;
            }
            elsif ($line =~ m/\bwand of digging\b/) {
                $scum{digging} = 1;
            }
		}
		
        # declare a hit regardless of other targets if there's a random wand, either
		# visible on the map or obtained by autopickup on the staircase on t:1
        last if $scum{room_wand};

		# make an array of what we hit on this game, tbh actual hash was
		# only required for some verbose logging code that has been removed for now
        my @scum_keys = keys %scum;

		# verbose debuggy crap
        #print STDERR "scum keys this round: " . join (", ", @scum_keys) . "\n";
        if (is_subset (\@hard_scum, \@scum_keys)) {
            #print STDERR "hits all hard scum reqs\n";
        }
        if (scalar (@soft_scum) == 0) {
            #print STDERR "no soft scum requirements in place\n";
        } else {
            #print STDERR "soft scum hits total: " . count_hits (\@soft_scum, \@scum_keys) . "\n";
        }

		# the actual check for whether all hard targets are met,
		# and (if there are any), at least one soft target was found
        last if (is_subset (\@hard_scum, \@scum_keys)
                 && (scalar (@soft_scum) == 0 
                     || (count_hits (\@soft_scum, \@scum_keys) >= 1))
                );
        
		$count++;
		system ('screen', '-S', $session, '-X', 'stuff', "<");
	} elsif (grep { m/gzip: .*\.ttyrec\.gz/ } @data) {
		# if this comes up something weird happened
		print STDERR "got weird gzip ttyrec question from server\n";
		exit(1);
	} else {
		$timeout++;
		if ($timeout > 15 * 5)
		{
			my $elapsed = get_elapsed ($t0);
			print @data;
			die "Timed out ($count tries, time: $elapsed)\n"
		}
	}
}

my $elapsed = get_elapsed ($t0);
print STDERR "Success ($count tries, time: $elapsed).\n";
exit 0;
