#!/usr/bin/perl

use strict;
use warnings;
use Time::HiRes qw( usleep gettimeofday tv_interval);
use POSIX qw(mkfifo);

my $session = 'Halea';
my $user = 'Aoei';
my $user_lowercase = 'aoei';
my $t0 = [gettimeofday];
my $count = 0;
my $timeout = 0;
my @old_data;
my @tools;
my @weapons;
my @levelmap;
my @coords; # x, y Yo
my @first_room_features;

while (1)
{
	my $tonal;
	my $poly;
	my $teleport_control;
	my $marker;
	my $intelligence;
	my $context;
	my $slow_digestion;
	my $i;
	my $j;
	my @data;

	# get screen
	do
	{
		usleep 500000;
		#@old_data = @data
		#	if (@data);
		@data = get_screencopy ($session)
	}
#	while (!@data || diff_array (\@data, \@old_data));
	while (!@data);

	# start game
	if (grep { /Connection closed by foreign host/ } @data) {
		my $elapsed = get_elapsed ($t0);
		die "Spamfiltered ($count tries, time: $elapsed."
	}
	
	if (grep { /THE NOVEMBER NETHACK TOURNAMENT IS LIVE/ }  @data)
	{
		system ('screen', '-S', $session, '-X', 'stuff', 't');
	} elsif (grep { /^.?>>/ } @data) {
		system ('screen', '-S', $session, '-X', 'stuff', ' ');
	} elsif (grep { /Do you want to see the dungeon overview/ } @data) {
		system ('screen', '-S', $session, '-X', 'stuff', 'q');
	} elsif (grep { /Beware, there will be no return/ } @data) {
		system ('screen', '-S', $session, '-X', 'stuff', 'y');
#	elsif (grep { /\ba - a blessed \+1 quarterstaff\b/ } @data && grep { /\(end\)/ } @data)
	# perm_invent means we don't need to actually open inventory so it'll be there on the welcome screen
	# the welcome message remains on screen during quit steps, so process this case last
	} elsif (grep { /Hello ${user_lowercase}/ } @data) {
		# max scum one game per second otherwise dgl error turfs us out
		# tyrec/2020-10-29.08:51:59.ttyrec.gz already exists; do you wish to overwrite (y or n)? 
		if (grep { /\// } @data)
		{ goto OUT }
        elsif (grep { /\w - a .*wand/ })
        { goto OUT }
		# check for key items
		foreach my $line (@data) {
			if ($line =~ /$user the Evoker/) {
				$intelligence = $1
					if ($line =~ /\bSt:\d+ Dx:\d+ Co:\d+ In:(\d+) Wi:\d+ Ch:\d+\b/);
				last;
			}
			if ($line =~ /(tooled horn|harp|bugle|flute)/) {
				$tonal = $1;
			}
			if ($line =~ /teleport control/) {
				$teleport_control = 1;
			}
		}
		$poly = 1
			if (grep { /(?:ring of polymorph control|wand of polymorph)/ } @data);
		$marker = 1
			if (grep { /magic marker \(0:[6789]/ } @data);
		$slow_digestion = 1
			if (grep { /ring of slow digestion/ } @data);
		my $log_line = "scum$count; int: $intelligence, ";
		if ($tonal) {
			$log_line .= "got $tonal, ";
		} else {
			$log_line .= "no tonal, ";
		}
		if ($poly) {
			$log_line .= "got polyitem";
		} else {
			$log_line .= "no polyitem";
		}
		if ($marker && $teleport_control) {
			$log_line .= ", marker and TC!";
		} elsif ($marker) {
			$log_line .= ", marker!";
		} elsif ($teleport_control) {
			$log_line .= ", TC!";
		}
		print "$log_line\n";

		goto OUT
			if (    ($intelligence && $intelligence >= 17)
				 #&& $tonal
				 && $poly
				 && ($marker || $teleport_control));
		$count++;
		undef @levelmap;
		undef @coords;
		undef @first_room_features;
		undef @weapons;
		undef @tools;
		system ('screen', '-S', $session, '-X', 'stuff', "<");
	} elsif (grep { /gzip: .*\.ttyrec\.gz/ } @data) {
		# if this comes up something weird happened
		print "got weird gzip ttyrec question from server\n";
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

OUT:
my $elapsed = get_elapsed ($t0);
print "Success ($count tries, time: $elapsed).\n";
exit 0;

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

sub get_screencopy
{
	my ($fh, @screen_raw, @data_out, $i, $signal);
	my $session = shift;
	my $filename = "/tmp/$session.$$";
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

#	# post-processing - truncate tailing empty lines (previous solution removed all tempty lines which confused other things)
#	# blank screen causes hang so check for that too
#	chomp (@data);
#	$i = 0; $signal = 0;
#	while ($i < @data)
#	{ if ($data[$i]) { $signal = 1; $i = @data } $i++ }
#	return
#		unless $signal;
#	$i = -1;
#	while (!$data[$i]) { $i-- }
#	splice (@data, $i + 1);
	foreach my $line (@screen_raw) {
		$line =~ s/^\s*//; # strip preceeding whitespace
		$line =~ s/\s*$//; # strip tailing whitespace
		if (length($line) > 0) {
			push @data_out, $line;
			print STDERR "$line\n";
		}
	}
	return @data_out;
}

sub diff_array
{
	my ($arr_a, $arr_b) = (shift, shift);
	return 1
		if (@$arr_a != @$arr_b);
	my ($i);
	$i = 0;
	while ($i < @$arr_a)
	{
		if (!$arr_a->[$i] && !$arr_b->[$i])
		{
			$i++; next
		}
		elsif (!$arr_a->[$i] || !$arr_b->[$i])
		{
			return 1
		}
		elsif ($arr_a->[$i] ne $arr_b->[$i])
		{
			return 1
		}
		else
		{
			$i++
		}
	}
	return 0
}
