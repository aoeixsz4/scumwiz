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
		usleep 200000;
#		@old_data = @data
#			if (@data);
		@data = get_screencopy ($session)
	}
#	while (!@data || diff_array (\@data, \@old_data));
	while (!@data);

	# start game
	if (grep { /Connection closed by foreign host/ } @data)
	{
		my $elapsed = get_elapsed ($t0);
		die "Spamfiltered ($count tries, time: $elapsed."
	}
	
	if (grep { /\bLogged in as: ${user_lowercase}\b/ }  @data)
	{
		system ('screen', '-S', $session, '-X', 'stuff', 'ay ')
	}
#	elsif (grep { /\ba - a blessed \+1 quarterstaff\b/ } @data && grep { /\(end\)/ } @data)
	elsif (grep { /\(end\)/ } @data)
	{
		# check for key items
		$intelligence = $1
			if ($data[-2] =~ /\bSt:\d+ Dx:\d+ Co:\d+ In:(\d+) Wi:\d+ Ch:\d+\b/);
		$tonal = $1
			if (grep { /\b(tooled horn|harp|bugle|flute)\b/ } @data);
		$poly = 1
			if (grep { /\b(?:ring of polymorph control|wand of polymorph)\b/ } @data);
		$marker = 1
			if (grep { /\bmagic marker \(0:[6789]/ } @data);
		$slow_digestion = 1
			if (grep { /\bring of slow digestion\b/ } @data);
		goto OUT
			if (    ($intelligence && $intelligence >= 17)
				 && $tonal
				 && $poly
				 && $marker);

		$count++;
		undef @levelmap;
		undef @coords;
		undef @first_room_features;
		undef @weapons;
		undef @tools;
		system ('screen', '-S', $session, '-X', 'stuff', '^[<yq')
	}
	elsif ($data[-2] && $data[-2] =~ /^${user} the \w+\s+St:\d+ Dx:\d+ Co:\d+ In:\d+ Wi:\d+ Ch:\d+\s+\w+$/
				&& $data[-1] =~ /^Dlvl:1 ?.* T:1$/)
	{
#		if (grep { /\{/ } @data)
#		{ goto OUT }
		if (grep { /\// } @data)
		{ goto OUT }
		if ($data[0] && $data[0] =~ /^(\(|\))\s+.*\((.*)\)$/)
		{ push @tools, $2 if ($1 eq '(');
		  push @weapons, $2 if ($1 eq ')');
		  print "Got a $2\n"; }
		if (grep { /lamp|pick-axe|marker/ } @tools)
		{ goto OUT }
		if (grep { /broad pick/ } @weapons)
		{ goto OUT }
		if (@first_room_features)
		{ my $cmd = ';'; my $obj = shift @first_room_features; my ($dx, $dy);
			$dx = $obj->[0] - $coords[0]; $dy = $obj->[1] - $coords[1];
			while ($dx && $dy)
			{ if ($dx < 0 && $dy < 0) { $cmd .= 'y'; $dx++; $dy++ }
			  if ($dx > 0 && $dy < 0) { $cmd .= 'u'; $dx--; $dy++ }
			  if ($dx > 0 && $dy > 0) { $cmd .= 'n'; $dx--; $dy-- }
			  if ($dx < 0 && $dy > 0) { $cmd .= 'b'; $dx++; $dy-- }
			}
			while ($dx || $dy)
			{ if ($dx < 0) { $cmd .= 'h'; $dx++ }
			  if ($dx > 0) { $cmd .= 'l'; $dx-- }
			  if ($dy < 0) { $cmd .= 'k'; $dy++ }
			  if ($dy > 0) { $cmd .= 'j'; $dy-- }
			}
			$cmd .= '.'; system ('screen', '-S', $session, '-X', 'stuff', $cmd);
			print "farlook\n";
		}
		elsif (@levelmap && @coords && !@first_room_features)
		{	system ('screen', '-S', $session, '-X', 'stuff', '  i')   }
		else
		{
			$i = 0;
			while ($i < 20 && $i + 2 < @data)
			{
				push @levelmap, [ split (//, substr ($data[$i+2], 0, 80)) ];
				$i++
			}
			$i = 0;
			while ($i < @levelmap)
			{
				$j = 0;
				while (@{ $levelmap[$i] } && $j < @{ $levelmap[$i] } && $j < 80)
				{
					@coords = ($j, $i)
						if ($levelmap[$i]->[$j] eq '@');
					push @first_room_features, [ $j, $i ]
						if ($levelmap[$i]->[$j] eq '('
							|| $levelmap[$i]->[$j] eq ')'); 
					$j++
				}
				$i++
			}
		}
	}
	elsif ($data[0] && $data[0] =~ /^NetHack, Copyright 1985-2003/
			|| $data[0] =~ /^Beware, there will be no return! Still climb? [yn] (n) y/
			|| $data[0] =~ /^Goodbye ${user} the Wizard\.\.\./)
	{
		system ('screen', '-S', $session, '-X', 'stuff', ' ')
	}
	else
	{
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
	my ($fh, @data, $i, $signal);
	my $session = shift;
	my $filename = "/tmp/$session.$$";
	mkfifo ($filename, 0700)
		or die "Couldn't make named pipe";
	my $pid = fork;
	if ($pid)
	{
		open ($fh, '<', $filename)
			or die "Open failed: $!\n";
		@data = <$fh>;
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

	# post-processing - truncate tailing empty lines (previous solution removed all tempty lines which confused other things)
	# blank screen causes hang so check for that too
	chomp (@data);
	$i = 0; $signal = 0;
	while ($i < @data)
	{ if ($data[$i]) { $signal = 1; $i = @data } $i++ }
	return
		unless $signal;
	$i = -1;
	while (!$data[$i]) { $i-- }
	splice (@data, $i + 1);
	return @data
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
