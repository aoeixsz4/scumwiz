#!/usr/bin/perl

use strict;
use warnings;
use List::MoreUtils qw(uniq any none);
use Time::HiRes qw(usleep gettimeofday tv_interval);
use POSIX qw(mkfifo);
use Data::Dump qw(dd);

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

	foreach my $line (@screen_raw)
	{
		$line =~ s/^\s*//; # strip preceeding whitespace
		$line =~ s/\s*$//; # strip tailing whitespace
		if (length($line) > 0)
		{
			push @data_out, $line;
            #print STDERR "$line\n";
		}
	}
	return @data_out;
}

sub get_statusline
{
	my $data = shift;
	my %statusline;

	# this iterates over all the *pairs* of lines,
	# hence the $i < length - 1
	for (my $i = 0; $i < (@$data - 1); $i++)
	{
		my $top_line = $data->[$i];
		my $bottom_line = $data->[$i+1];

		# first do a simpler test to skip any wrong lines, also trim junk
		# before and after actual statusline text
		if ($top_line
			=~ m/\[?
					(\w+) \x20 the \x20 (\w+)
				(?: \s*? \])?
				\x20*
					( (?: \x20 [A-Z] [a-z]
						: \d+ (?: \/(?: \d+ | \*\*) )?
						){6} )
				\s+
					(\w+)/x
			)
		{
			my ($name,				# this is typically the server username
				$title,				# role title at xlvl, or polyform e.g. Minotaur
				$abilities_line,		# this should essentially be St:xx Dx:xx Co:xx In:xx Wi:xx Ch:xx 
				$align
			) = ($1, $2, $3, $4);

			$statusline{name}  = $name;
			$statusline{title} = $title;
			$statusline{align} = $align;
			
			# the ability score bit needs some additional processing
			my @ability_keys = ('St', 'Dx', 'Co', 'In', 'Wi', 'Ch');
			foreach my $ability (split(/\s+/, $abilities_line))
			{
				if ($ability =~ m/^([A-Z][a-z]) : (\S+)$/x)
				{
					my ($stat, $value) = ($1, $2);
					if ($value =~ m/^\d+$/
						&& any { $_ eq $stat } @ability_keys)
					{
						$statusline{$stat} = int($value);
					}
					# St:18/whatever special case
					elsif ($value =~ m/^18\/ (\d+ | \*{2})$/x
							&& $stat eq 'St')
					{
						$statusline{St} = 18;
						if ($1 eq '**')
						{
							$statusline{St_percentile} = 100;
						}
						else
						{
							$statusline{St_percentile} = int($1);
						}
					}
				}
			}
		}
		# I'd forgotten the design plan for this - if one of the lines
		# fails, we have to try the next pair in the list of lines
		else
		{
			next;
		}

		##dd(%statusline);

		if ($bottom_line
			=~ s/^.*?
				(
					\S+ : \S+ (?:\s+ \S+ : \S+){6,7}
				).*?$/$1/x
			)
		{
			my @status_keys = ('Dlvl', 'Zm', 'HP', 'Pw', 'AC', 'Xp', 'HD', 'T', 'S');
			foreach my $status_field (split(/\s+/, $bottom_line))
			{
				if ($status_field =~ m/^(\S+):(\S+)$/)
				{
					my ($key, $value) = ($1, $2);

					# convert '$' to 'Zm' for the hash table
					$value =~ s/^\$$/Zm/;

					# normally HP and Pw are shown as cur(max)
					if ($value =~ m/^(\d+)\((\d+)\)$/
						&& $key eq 'HP' || $key eq 'Pw')
					{
						my ($current, $max) = ($1, $2);
						$statusline{"${key}_current"} = int($current);
						$statusline{"${key}_max"} = int($max);
					}

					# Xp can sometimes have exp points attached
					elsif ($value =~ m/^(\d+)\/(\d+)$/
						&& $key eq 'Xp')
					{
						my ($level, $points) = ($1, $2);
						$statusline{"${key}_level"} = int($level);
						$statusline{"${key}_points"} = int($points);
					}

					# AC is the only one that can be a negative value
					elsif ($value =~ m/^-(\d+)$/
							&& $key eq 'AC')
					{
						$statusline{AC} = -int($1);
					}

					# this is the general behaviour,
					# Dlvl, Zm, HD, T and S are normal integer fields
					elsif ($value =~ m/^\d+$/
							&& any { $_ eq $key } @status_keys)
					{
						$statusline{$key} = int($value);
					}
				}
				## consider including a debug output on else?
			}
			## hear we should have found and succesfully processed a
			## statusline in the hash %statusline
			##dd(%statusline);
			return \%statusline;
		}
		else
		{
			next;
		}
	}

	## if we fall out of the loop without finding success,
	## then we have to return undef
	return undef;
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
        if (any { $_ eq $item } @scum_keys)
		{
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

my $active_turn = 0;			# this will track the current turn-count
my $scumwiz_active = 1;			# if set to undef, scumwiz.pl will only watch, until the user dies or quits
my $t0 = [gettimeofday];

my @old_data;

while (1)
{
    my %scum = ();
	my @data;

	my $count = 0;		# thi is now a timeout for quitting a scum and re-rolling, i.e. give the user
	my $timeout = 0;	# a half chance of spotting something they like in inventory and overriding
						# what was requested - once the game is quit it'll go back to autoscum anyway
								

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

	if (grep { m/\bConnection closed by foreign host\b/ } @data)
	{
		my $elapsed = get_elapsed ($t0);
		die "Spamfiltered ($count tries, time: $elapsed.";
	}

	# wanna do this update independently each time, *if* we get an open
	# nethack with a visible status line
	my $nh_status = get_statusline(\@data);
	if ($nh_status && $nh_status->{T})
	{
		$active_turn = $nh_status->{T};

		# if the current game-turn shows as anything above 1,
		# disable automatic scumming for now
		if ($active_turn > 1)
		{
			$scumwiz_active = 0;
		}
	}
	
	# the logic for dealing with start-game and quit prompts
	# is a bit hacky and may be highly dependent on player rcfile!
	# windowtype curses is a must, and the terminal should be large
	# enough to fit the entire inventory (perm_invent must be true)
	# on a single page
	if ($scumwiz_active && $active_turn <= 1 
			&& grep { m/\bTHE NOVEMBER NETHACK TOURNAMENT IS LIVE\b/ } @data)
	{
		# hit t to start game
		system ('screen', '-S', $session, '-X', 'stuff', 't');
		
		# reset timer/counter so user has a little more time to
		# (potentially) see something they want and pause scumming
		$count = 0;
	}
	
	# oh no, it's game over! (could be quit, death, perhaps even ascension?)
	# the saved temp values don't persist with this ḱind of grep over an array
	if (grep { m/\bGoodbye \w+ the \w+\.\.\./ } @data)
	{
		foreach my $line (@data)
		{
			if ($line =~ m/\bGoodbye (\w+) the (\w+)\.\.\./)
			{
				my ($name, $title) = ($1, $2);
				if ($title =~ m/Demigod(?:dess)?/)
				{
					print STDERR "$name ascended!\n";
				}
			}
		}

		# space works for both these exit prompts
		if ($scumwiz_active)
		{
			system ('screen', '-S', $session, '-X', 'stuff', ' ');
		}
		else
		{
			$scumwiz_active = 1;			
		}
		$active_turn = 0;	# there is no game currently, as we just quit
	}

	# if there has been user intervention, don't confirm this prompt
	elsif ($scumwiz_active && grep { m/\bBeware, there will be no return\b/ } @data)
	{
		# this prompt i think is standard after trying to exit dl1 by <
		system ('screen', '-S', $session, '-X', 'stuff', 'y');
		# ths is typically followed by a >> prompt which for some reason
		# struggles to match, so just sleep briefly then send a space
		usleep 200000;
		system ('screen', '-S', $session, '-X', 'stuff', ' ');
	}
	
	# perm_invent means we don't need to actually open inventory so it'll be there on the welcome screen
	# the welcome message remains on screen during quit steps, so process this case last
	# this case should apply when we've just started a game - if we've been idle but are still following
	# an active game, we need another case that just looks for some statusline stuff...
	elsif ($scumwiz_active && grep { m/\bHello \w+, welcome to\b/ } @data)
	{
		# some information is already got for us from the call to 
		# get_statusline, above, i.e. $nh_status->{In}
		if ($nh_status && $nh_status->{In} && $nh_status->{In} => 17)
		{
			$scum{int} = $nh_status->{In}
		}

		# max scum one game per second otherwise dgl error turfs us out
		# tyrec/2020-10-29.08:51:59.ttyrec.gz already exists; do you wish to overwrite (y or n)? 
		# check for key items
		foreach my $line (@data)
		{
			# autopickup gems results in a false positive for room_wand,
            # so filter that text
            $line =~ s/\bGems\/Stones\b//;
			if ($line =~ m/(\/|\b\w - a .*wand)/)
			{
                print STDERR "room_wand triggered by $1\n";
                $scum{room_wand} = 1;
            }
			
			# inventory lines are mutually exclusive
			if ($line =~ m/\b(tooled horn|harp|bugle|flute)\b/)
			{
				$scum{tonal} = $1;
			}
			elsif ($line =~ m/\bteleport control\b/)
			{
				$scum{tc} = 1;
			}
            elsif ($line =~ m/\b(ring of polymorph control|wand of polymorph)\b/)
			{
                $scum{poly} = $1;
            }
            elsif ($line =~ m/\bmagic marker \(0:[6789]/)
			{
                $scum{marker} = 1;
            }
            elsif ($line =~ m/\bring of slow digestion\b/)
			{
                $scum{foodless} = 1;
            }
            elsif ($line =~ m/\bwand of digging\b/)
			{
                $scum{digging} = 1;
            }
		}
		
        # declare a hit regardless of other targets if there's a random wand, either
		# visible on the map or obtained by autopickup on the staircase on t:1
        if ($scum{room_wand})
		{
			$scumwiz_active = 0;
			next;
		}

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
        if (is_subset (\@hard_scum, \@scum_keys)
                 && (scalar (@soft_scum) == 0 
                     || (count_hits (\@soft_scum, \@scum_keys) >= 1)))
		{
			$scumwiz_active = 0;
			next;
		}
		else
		{
        	$count++;
			if ($count >= 3)
			{
				system ('screen', '-S', $session, '-X', 'stuff', "<");
			}		
		}
	}
	elsif (grep { m/gzip: .*\.ttyrec\.gz/ } @data)
	{
		# if this comes up something weird happened
		print STDERR "got weird gzip ttyrec question from server\n";
		exit(1);
	}
	#else		- idk what to use this for
	#	$timeout++;
	#	if ($timeout > 15 * 5)
	#	{
	#		my $elapsed = get_elapsed ($t0);
	#		print @data;
	#		die "Timed out ($count tries, time: $elapsed)\n"
	#	}
	#}
}