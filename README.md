# scumwiz
Perl script for automated NetHack startscumming

Requirements: SSH, GNU Screen & Perl
Setup:
  before: set windowtype:curses in your nethack rcfile, and enable perm_invent
  also define race/role/gender/alignment in your rcfile - script assumes this is set
  edit the player name in scumwiz.pl to reflect your own login name
  start a named screen session (default session name in scumwiz.pl is Halea)
  connect to hardfought nh server via ssh within the named screen session
  log in to your account
  run ./scumwiz.pl in another terminal emulator

Scumwiz.pl will keep re-rolling wizards until some favourable parameters are arrived at,
current configuration is to stop if: int >= 16 && have_polyitem && (have_marker || have teleport_control)
script will also stop if a wand is seen in the first room - check for WoW manually
