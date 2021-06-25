# scumwiz
Perl script for automated NetHack startscumming


Requirements: SSH, GNU Screen & Perl incl. perl modules List::MoreUtils and Time::HiRes.
I really need to write a more detailed readme, but scumwiz.pl now has a fairly detailed
usage text if you run it with the flag -h or -help

This will explain how to run it, and some things you need to have set up in your rcfile


the above information about the helptext might not be accurate at all anymore

# note: scumwiz.pl scums for particular wizard starting inventory items
#       scumwiz-2.pl is a more involved autoscummer that searches for first-room wand of wishing

also i am mainly using scumwiz-2.pl for scumming on NAO currently. this script is pretty awful and,
to anybody who tries to use it, im really sorry that its so bad, but if you find me
on IRC (Libera network, nick: aoei), i might be able to help you out a bit

the script is quite sensitve to the setup of your rcfile, but if you use mine as a template,
the thing should work, and then you need only to do the following:
in one terminal or screen/tmux session run

```
$ screen -S nao
[inside screen]$ ssh nethack@nethack.alt.org
-- log in as your user
```

somewhere else run 
```
./scumwiz-2.pl -session=nao
```
but you will need to keep an eye on the screen session where the script is running, because the script
is not very robust: it will periodically break and requrie manual intervention to get started again
