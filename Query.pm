# Package to interface with WordNet (wn) command line program
# written by Jason Rennie <jrennie@ai.mit.edu>, July 1999

# Run 'perldoc' on this file to produce documentation

# Copyright 1999 Jason Rennie <jrennie@ai.mit.edu>  All rights reserved.

# This module is free software; you can redistribute it and/or modify
# it under the same terms as Perl itself.

# $Id: Query.pm,v 1.2 1999/09/15 19:53:28 jrennie Exp $

package WordNet::Query;

use strict;
use Carp;
use FileHandle;
use Exporter;

##############################
# Environment/Initialization #
##############################

BEGIN {
  use vars qw($VERSION @ISA @EXPORT @EXPORT_OK);

  $VERSION = do { my @r=(q$Revision: 1.2 $=~/\d+/g); sprintf "%d."."%02d"x$#r,@r };
  
  # Function names to export
  @ISA = qw(Exporter);
  @EXPORT = qw();
  @EXPORT_OK = qw(hype_set level syns gloss hype hypo mero holo do_findtheinfo);
}

# non-exported package globals go here
use vars qw( $wn );

#############################
# Private Package Variables #
#############################

# WordNet "cache"
my $wn;

# Mapping of possible part of speech to single letter used by wordnet
my %pos_map = ('noun'      => 'n',
	       'n'         => 'n',
	       '1'         => 'n',
	       ''          => 'n',
	       'verb'      => 'v',
	       'v'         => 'v',
	       '2'         => 'v',
	       'adjective' => 'a',
	       'adj'       => 'a',
	       '3'         => 'a',
	       'adverb'    => 'r',
	       'adv'       => 'r',
	       '4'         => 'r');

# Print lots of extra stuff if verbosity turned on
my $verbose = 0;

###############
# Subroutines #
###############

# Some simple functions to make things easier
sub min { my $cur_min = $_[0]; foreach my $thing (@_) { if ($thing < $cur_min) { $cur_min = $thing; } } return $cur_min; }
sub max { my $cur_max = $_[0]; foreach my $thing (@_) { if ($thing > $cur_max) { $cur_max = $thing; } } return $cur_max; }
# Convert list of strings to lower case
sub lower { foreach my $string (@_) { $string =~ tr/A-Z/a-z/; } return @_; }


# Execute a -syns query to WordNet, cache results
# Use -g option to get glossary definition
sub parse_syns
  {
    my ($word, $pos) = @_;
    my $fh;
    my $num_senses = 0; # number of senses of queried word
    
    print STDERR "parse_syns ($word)\n" if ($verbose);

    my $sense;
    # Need to modify this to work for other parts of speech
    if ($word =~ s/\#(\d+)$//)
      {	
	$sense = $1;
	$fh = new FileHandle "wn \"$word\" -synsn -g -s -n$sense |";
	print STDERR "wn \"$word\" -synsn -g -s -n$sense\n" if ($verbose);
	die "Not able to execute wn: $!\n" if (!defined ($fh));
      } 
    else
      {
	$fh = new FileHandle "wn \"$word\" -synsn -g -s |";
	print STDERR "wn \"$word\" -synsn -g -s\n" if ($verbose);
	die "Not able to execute wn: $!\n" if (!defined ($fh));
      }
    
    my $this_word;
    my $this_pos;
    while (defined ($_ = <$fh>))
      {
	my $sense_no;
	if (m,^Synonyms/Hypernyms \(Ordered by Frequency\) of (\S+) (\S+),)
	  {
	    $this_pos = $1;
	    $this_word = $2;
	    # Convert underscores to spaces in $this_word
	    $this_word =~ s/\_/ /g;
	  }
	elsif (m,^Sense (\d+),)
	  {
	    $sense_no = $1;
	    $num_senses++ if ($this_word =~ m/^$word$/);
	    $_ = <$fh>;
	    # Split into words and definition
	    m/^([^\(]+)\((.+)\)+$/;
	    my $syns = $1;
	    $wn->{"$this_word\#$sense_no"}->{"gloss"} = $2;
	    print STDERR "Add $this_word\#$sense_no =(gloss)=> $2\n" if ($verbose);
	    # Get rid of trailing junk
	    $syns =~ s/(\s|\-)*$//;
	    my @synlist = lower (split (", ", $syns));
	    # Convert list to a hash
	    my %synhash;
	    foreach my $syn (@synlist) {$synhash{$syn} = 1;}
	    $wn->{"$this_word\#$sense_no"}->{"syns"} = \%synhash;
	    print STDERR "Add $this_word\#$sense_no =(syns)=> ", join (", ", keys (%synhash)), "\n" if ($verbose);
	    # Capture hypernyms
	    while (defined ($_ = <$fh>))
	      {
		# End this word sense if we don't see an arrow =>
		last if $_ !~ m/\=\>/;
		# Split into words and definition
		m/\=\>\s([^\(]+)\((.+)\)+$/;
		my $syns = $1;
		my $gloss = $2;
		$syns =~ s/(\s|\-)*$//;
		my @synlist = lower (split (", ", $syns));
		# Convert list to a hash
		my %synhash;
		foreach my $syn (@synlist) {$synhash{$syn} = 1;}
		# Cache info
		$wn->{$synlist[0]}->{"syns"} = \%synhash;
		print STDERR "Add $synlist[0] =(syns)=> ", join (", ", keys (%synhash)), "\n" if ($verbose);
		$wn->{$synlist[0]}->{"gloss"} = $2;
		print STDERR "Add $synlist[0] =(gloss)=> $gloss\n" if ($verbose);
		$wn->{"$this_word\#$sense_no"}->{"hype"}->{$synlist[0]} = 1;
		print STDERR "Add $this_word\#$sense_no =(hype)=> $synlist[0]\n" if ($verbose);
	      }
	  }
      }
    # Use '-1' to identify words without meronyms (leaf nodes)
    $wn->{"$word\#$sense"}->{"syns"} = -1
      if (!defined($wn->{"$word\#$sense"}->{"syns"}));
    undef $fh;
    return $num_senses;
  }	  


# Return Definition
# Input is word-sense in form of "word#S" where S is the sense number
sub gloss
  {
    my ($word, $pos) = @_;

    ($word) = lower ($word);
    print STDERR "gloss ($word)\n" if ($verbose);

    return () if ($wn->{$word}->{"gloss"} == -1);

    my $senses = &parse_syns ($word, $pos)
      if (!defined ($wn->{$word}->{"gloss"}));

    # return a ref to an array of senses if no sense was specified
    if ($word !~ m/\#\d+$/)
      {
	my @sensearray;
	for (my $i=1; $i <= $senses; $i++)
	  {
	    push @sensearray, ($wn->{"$word\#$i"}->{"gloss"})
	      if ($wn->{"$word\#$i"}->{"gloss"});
	  }
	return \@sensearray;
      }
    return $wn->{$word}->{"gloss"};
  }


# Return reference to array of Synonyms
# Input is word-sense in form of "word#S" where S is the sense number
sub syns
  {
    my ($word, $pos) = @_;

    ($word) = lower ($word);
    print STDERR "syns ($word)\n" if ($verbose);

    return () if ($wn->{$word}->{"syns"} == -1);

    my $senses = &parse_syns ($word, $pos)
      if (!defined ($wn->{$word}->{"syns"}));

    # return an array of senses if no sense was specified
    if ($word !~ m/\#\d+$/)
      {
	my @sensearray;
	for (my $i=1; $i <= $senses; $i++)
	  {
	    my @words = keys (%{$wn->{"$word\#$i"}->{"syns"}});
	    push @sensearray, \@words if (@words);
	  }
	return @sensearray;
      }
    return () if (!defined ($wn->{$word}->{"syns"}));
    return (keys (%{$wn->{$word}->{"syns"}}));
  }


# Execute a -hype query to WordNet, cache results
sub parse_hype
  {
    my ($word, $pos) = @_;
    my $fh;
    my $num_senses = 0;
    
    print STDERR "parse_hype ($word)\n" if ($verbose);

    my $sense;
    # Need to modify this to work for other parts of speech
    if ($word =~ s/\#(\d+)$//)
      {	
	$sense = $1;
	$fh = new FileHandle "wn \"$word\" -hypen -s -n$sense |";
	die "Not able to execute wn: $!\n" if (!defined ($fh));
      } 
    else
      {
	$fh = new FileHandle "wn \"$word\" -hypen -s |";
	die "Not able to execute wn: $!\n" if (!defined ($fh));
      }
    
    my $this_word;
    my $this_pos;
    while (defined ($_ = <$fh>))
      {
	my $sense_no;
	if (m,^Synonyms/Hypernyms \(Ordered by Frequency\) of (\S+) (\S+),)
	  {
	    $this_pos = $1;
	    $this_word = $2;
	    # Convert underscores to spaces in $this_word
	    $this_word =~ s/\_/ /g;
	  }
	elsif (m,^Sense (\d+),)
	  {
	    my %depth_map;  # last words found at each depth
	    $sense_no = $1;
	    $num_senses++ if ($this_word =~ m/^$word$/);
	    $_ = <$fh>;
	    chop $_;
	    # Store synset of this word
	    my @synlist = lower (split (", ", $_));
	    # Convert list to a hash
	    my %synhash;
	    foreach my $syn (@synlist) {$synhash{$syn} = 1;}
	    $wn->{"$this_word\#$sense_no"}->{"syns"} = \%synhash;
	    print STDERR "Add $this_word\#$sense_no =(syns)=> ", join (", ", keys (%synhash)), "\n" if ($verbose);

	    $depth_map{0} = "$this_word\#$sense_no";
	    my $max_depth = 0;
	    # Capture hypernyms
	    while (defined ($_ = <$fh>))
	      {
		chop $_;
		# End this word sense if we don't see an arrow =>
		last if $_ !~ s/^(\s+)\=\>\s*//;
		my $depth = length ($1);
		$max_depth = $depth if ($depth > $max_depth);
		# Use '-1' to identify words without hypernyms (root nodes)
		if ($depth < $max_depth) {
		  $wn->{$depth_map{$max_depth}}->{"hype"} = -1;
		  $wn->{$depth_map{$max_depth}}->{"level"} = 1;
	        }
		# Gather synset
		my @synlist = lower (split (", ", $_));
		# Convert list to a hash
		my %synhash;
		foreach my $syn (@synlist) {$synhash{$syn} = 1;}
		# Cache info
		$depth_map{$depth} = $synlist[0];
		$wn->{$synlist[0]}->{"syns"} = \%synhash;
		print STDERR "Add $synlist[0] =(syns)=> ", join (", ", keys (%synhash)), "\n" if ($verbose);
		# Find the most recent parent
		for (my $i = $depth-1; $i >=0 ; $i--)
		  {
		    if ($depth_map{$i})
		      {	
			print STDERR "Add $depth_map{$i} =(hype)=> $synlist[0]\n" if ($verbose);
			$wn->{$depth_map{$i}}->{"hype"}->{$synlist[0]} = 1;
			last;
		      }
		  }
	      }
	    # Use '-1' to identify words without hypernyms (root nodes)
	    $wn->{$depth_map{$max_depth}}->{"hype"} = -1;
	    $wn->{$depth_map{$max_depth}}->{"level"} = 1;
	  }
      }
    # Use '-1' to identify words without meronyms (leaf nodes)
    $wn->{"$word\#$sense"}->{"hype"} = -1
      if (!defined($wn->{"$word\#$sense"}->{"hype"}));
    undef $fh;
    return $num_senses;
  }	  


# Return set of all hypernyms that are not more than $max_length levels above
# the word and no higher than $top_level (where '1' is the level where root
# hypernyms reside
sub hype_set
{
  my ($word, $pos, $max_length, $top_level) = @_;

  ($word) = lower ($word);
  print STDERR "hype_set ($word, $pos, $max_length, $top_level)\n"
      if ($verbose);

  my $start_level = level ($word);
  return () if (!defined ($start_level));
  my @queue = ($word);
  my %rtn;
  while (my $this = shift @queue)
    {
      my $this_level = level ($this);
      push @queue, hype ($this);
      if ($start_level - $this_level <= $max_length
	  and $this_level >= $top_level)
        {
	  # If this word is within range, add it to the return set
	  $rtn{$this} = 1;
	}
    }
  return keys %rtn;
}


# Return length (+1) of shortest path to a root hypernym
# Input is word-sense in form of "word#S" where S is the sense number
sub level
{
    my ($word, $pos) = @_;

    ($word) = lower ($word);
    print STDERR "level ($word)\n" if ($verbose);

    return undef if (defined $wn->{$word}->{"level"} and
		     $wn->{$word}->{"level"} == -1);

    # Return the level if it is cached
    return $wn->{$word}->{"level"} if (defined $wn->{$word}->{"level"});

    # Get hypernym information if we haven't already grabbed it from WordNet
    my $senses = &parse_hype ($word, $pos)
      if (!defined ($wn->{$word}->{"hype"}));

    my @hypernyms = hype ($word, $pos);
    my @levels;
    foreach my $hypernym (@hypernyms)
      {
	my $level = level ($hypernym, $pos);
	push @levels, $level if (defined $level);
      }
    # Return undefined value if the word doesn't exist
    return undef if (!@levels);
    # Cache and return "level" value
    $wn->{$word}->{"level"} = min (@levels) + 1;
}


# Return Hypernym
# Input is word-sense in form of "word#S" where S is the sense number
sub hype
  {
    my ($word, $pos) = @_;
    
    ($word) = lower ($word);
    print STDERR "hype ($word)\n" if ($verbose);

    return () if ($wn->{$word}->{"hype"} == -1);

    my $senses = &parse_hype ($word, $pos)
      if (!defined ($wn->{$word}->{"hype"}));

    # return a ref to an array of senses if no sense was specified
    if ($word !~ m/\#\d+$/)
      {
	my @sensearray;
	for (my $i=1; $i <= $senses; $i++)
	  {
	    my @words = keys (%{$wn->{"$word\#$i"}->{"hype"}});
	    push @sensearray, \@words if (@words);
	  }
	return \@sensearray;
      }
    # Return empty list if the word has no hypernyms
    return () if ($wn->{$word}->{"hype"} == -1);
    return (keys (%{$wn->{$word}->{"hype"}}));
  }


# Execute a -hype query to WordNet, cache results
sub parse_hypo
  {
    my ($word, $pos) = @_;
    my $fh;
    my $num_senses = 0; # number of senses of queried word

    print STDERR "parse_hypo ($word)\n" if ($verbose);
    my $sense;

    # Need to modify this to work for other parts of speech
    if ($word =~ s/\#(\d+)$//)
      {	
	$sense = $1;
	$fh = new FileHandle "wn \"$word\" -hypon -s -n$sense |";
	die "Not able to execute wn: $!\n" if (!defined ($fh));
      } 
    else
      {
	$fh = new FileHandle "wn \"$word\" -hypon -s |";
	die "Not able to execute wn: $!\n" if (!defined ($fh));
      }
    
    my $this_word;
    my $this_pos;
    while (defined ($_ = <$fh>))
      {
	my $sense_no;
	if (m,^Hyponyms of (\S+) (\S+),)
	  {
	    $this_pos = $1;
	    $this_word = $2;
	    # Convert underscores to spaces in $this_word
	    $this_word =~ s/\_/ /g;
	  }
	elsif (m,^Sense (\d+),)
	  {
	    $sense_no = $1;
	    $num_senses++ if ($this_word =~ m/^$word$/);
	    $_ = <$fh>;
	    chop $_;
	    # Store synset of this word
	    my @synlist = lower (split (", ", $_));
	    # Convert list to a hash
	    my %synhash;
	    foreach my $syn (@synlist) {$synhash{$syn} = 1;}
	    $wn->{"$this_word\#$sense_no"}->{"syns"} = \%synhash;
	    print STDERR "Add $this_word\#$sense_no =(syns)=> ", join (", ", keys (%synhash)), "\n" if ($verbose);

	    # Capture hyponyms
	    while (defined ($_ = <$fh>))
	      {
		chop $_;
		# End this word sense if we don't see an arrow =>
		last if $_ !~ s/\s+\=\>\s*//;
		# Gather synset
		my @synlist = lower (split (", ", $_));
		# Convert list to a hash
		my %synhash;
		foreach my $syn (@synlist) {$synhash{$syn} = 1;}
		# Cache info
		$wn->{$synlist[0]}->{"syns"} = \%synhash;
		print STDERR "Add $synlist[0] =(syns)=> ", join (", ", keys (%synhash)), "\n" if ($verbose);

		$wn->{"$this_word\#$sense_no"}->{"hypo"}->{$synlist[0]} = 1;
		print STDERR "Add $this_word\#$sense_no =(hypo)=> $synlist[0]\n" if ($verbose);
	      }
	    # Use '-1' to identify words without hyponyms (leaf nodes)
	    $wn->{"$this_word\#$sense_no"}->{"hypo"} = -1
	      if (!defined($wn->{"$this_word\#$sense_no"}->{"hypo"}));
	  }
      }
    # Use '-1' to identify words without hyponyms (leaf nodes)
    $wn->{"$word\#$sense"}->{"hypo"} = -1
      if (!defined($wn->{"$word\#$sense"}->{"hypo"}));
    undef $fh;
    return $num_senses;
  }	  


# Return reference to array of Hyponyms
# Input is word-sense in form of "word#S" where S is the sense number
sub hypo
  {
    my ($word, $pos) = @_;
    
    ($word) = lower ($word);
    print STDERR "hypo ($word)\n" if ($verbose);

    return () if ($wn->{$word}->{"hypo"} == -1);

    my $senses = &parse_hypo ($word, $pos)
      if (!defined ($wn->{$word}->{"hypo"}));
    
    # return a ref to an array of senses if no sense was specified
    if ($word !~ m/\#\d+$/)
      {
	my @sensearray;
	for (my $i=1; $i <= $senses; $i++)
	  {
	    my @words = keys (%{$wn->{"$word\#$i"}->{"hypo"}});
	    push @sensearray, \@words if (@words);
	  }
	return \@sensearray;
      }
    # Return empty list if the word has no hyponyms
    return () if ($wn->{$word}->{"hypo"} == -1);
    return (keys (%{$wn->{$word}->{"hypo"}}));
  }


# Execute a -hype query to WordNet, cache results
sub parse_mero
  {
    my ($word, $pos) = @_;
    my $fh;
    my $num_senses = 0; # number of senses of queried word

    print STDERR "parse_mero ($word)\n" if ($verbose);
    my $sense;

    # Need to modify this to work for other parts of speech
    if ($word =~ s/\#(\d+)$//)
      {	
	$sense = $1;
	$fh = new FileHandle "wn \"$word\" -meron -s -n$sense |";
	die "Not able to execute wn: $!\n" if (!defined ($fh));
      } 
    else
      {
	$fh = new FileHandle "wn \"$word\" -meron -s |";
	die "Not able to execute wn: $!\n" if (!defined ($fh));
      }
    
    my $this_word;
    my $this_pos;
    while (defined ($_ = <$fh>))
      {
	my $sense_no;
	if (m,^Meronyms of (\S+) (\S+),)
	  {
	    $this_pos = $1;
	    $this_word = $2;
	    # Convert underscores to spaces in $this_word
	    $this_word =~ s/\_/ /g;
	  }
	elsif (m,^Sense (\d+),)
	  {
	    $sense_no = $1;
	    $num_senses++ if ($this_word =~ m/^$word$/);
	    $_ = <$fh>;
	    chop $_;
	    # Store synset of this word
	    my @synlist = lower (split (", ", $_));
	    # Convert list to a hash
	    my %synhash;
	    foreach my $syn (@synlist) {$synhash{$syn} = 1;}
	    $wn->{"$this_word\#$sense_no"}->{"syns"} = \%synhash;
	    print STDERR "Add $this_word\#$sense_no =(syns)=> ", join (", ", keys (%synhash)), "\n" if ($verbose);

	    # Capture meronyms
	    while (defined ($_ = <$fh>))
	      {
		chop $_;
		# End this word sense if we don't see an arrow =>
		last if $_ !~ s/\s+([^\:]+):\s*//;
		# Gather synset
		my @synlist = lower (split (", ", $_));
		# Convert list to a hash
		my %synhash;
		foreach my $syn (@synlist) {$synhash{$syn} = 1;}
		# Cache info
		$wn->{$synlist[0]}->{"syns"} = \%synhash;
		print STDERR "Add $synlist[0] =(syns)=> ", join (", ", keys (%synhash)), "\n" if ($verbose);

		$wn->{"$this_word\#$sense_no"}->{"mero"}->{$synlist[0]} = 1;
		print STDERR "Add $this_word\#$sense_no =(mero)=> $synlist[0]\n" if ($verbose);
	      }
	    # Use '-1' to identify words without meronyms (leaf nodes)
	    $wn->{"$this_word\#$sense_no"}->{"mero"} = -1
	      if (!defined($wn->{"$this_word\#$sense_no"}->{"mero"}));
	  }
      }
    # Use '-1' to identify words without meronyms (leaf nodes)
    $wn->{"$word\#$sense"}->{"mero"} = -1
      if (!defined($wn->{"$word\#$sense"}->{"mero"}));
    undef $fh;
    return $num_senses;
  }	  


# Return reference to array of Meronyms
# Input is word-sense in form of "word#S" where S is the sense number
sub mero
  {
    my ($word, $pos) = @_;
    
    ($word) = lower ($word);
    print STDERR "mero ($word)\n" if ($verbose);

    return () if ($wn->{$word}->{"mero"} == -1);

    my $senses = &parse_mero ($word, $pos)
      if (!defined ($wn->{$word}->{"mero"}));
    
    # return a ref to an array of senses if no sense was specified
    if ($word !~ m/\#\d+$/)
      {
	my @sensearray;
	for (my $i=1; $i <= $senses; $i++)
	  {
	    my @words = keys (%{$wn->{"$word\#$i"}->{"mero"}});
	    push @sensearray, \@words if (@words);
	  }
	return \@sensearray;
      }
    # Return empty list if the word has no meronyms
    return () if ($wn->{$word}->{"mero"} == -1);
    return (keys (%{$wn->{$word}->{"mero"}}));
  }


# Execute a -hype query to WordNet, cache results
sub parse_holo
  {
    my ($word, $pos) = @_;
    my $fh;
    my $num_senses = 0; # number of senses of queried word

    print STDERR "parse_holo ($word)\n" if ($verbose);
    my $sense;

    # Need to modify this to work for other parts of speech
    if ($word =~ s/\#(\d+)$//)
      {	
	$sense = $1;
	$fh = new FileHandle "wn \"$word\" -holon -s -n$sense |";
	die "Not able to execute wn: $!\n" if (!defined ($fh));
      } 
    else
      {
	$fh = new FileHandle "wn \"$word\" -holon -s |";
	die "Not able to execute wn: $!\n" if (!defined ($fh));
      }
    
    my $this_word;
    my $this_pos;
    while (defined ($_ = <$fh>))
      {
	my $sense_no;
	if (m,^Holonyms of (\S+) (\S+),)
	  {
	    $this_pos = $1;
	    $this_word = $2;
	    # Convert underscores to spaces in $this_word
	    $this_word =~ s/\_/ /g;
	  }
	elsif (m,^Sense (\d+),)
	  {
	    $sense_no = $1;
	    $num_senses++ if ($this_word =~ m/^$word$/);
	    $_ = <$fh>;
	    chop $_;
	    # Store synset of this word
	    my @synlist = lower (split (", ", $_));
	    # Convert list to a hash
	    my %synhash;
	    foreach my $syn (@synlist) {$synhash{$syn} = 1;}
	    $wn->{"$this_word\#$sense_no"}->{"syns"} = \%synhash;
	    print STDERR "Add $this_word\#$sense_no =(syns)=> ", join (", ", keys (%synhash)), "\n" if ($verbose);

	    # Capture holonyms
	    while (defined ($_ = <$fh>))
	      {
		chop $_;
		# End this word sense if we don't see an arrow =>
		last if $_ !~ s/\s+([^\:]+):\s*//;
		# Gather synset
		my @synlist = lower (split (", ", $_));
		# Convert list to a hash
		my %synhash;
		foreach my $syn (@synlist) {$synhash{$syn} = 1;}
		# Cache info
		$wn->{$synlist[0]}->{"syns"} = \%synhash;
		print STDERR "Add $synlist[0] =(syns)=> ", join (", ", keys (%synhash)), "\n" if ($verbose);

		$wn->{"$this_word\#$sense_no"}->{"holo"}->{$synlist[0]} = 1;
		print STDERR "Add $this_word\#$sense_no =(holo)=> $synlist[0]\n" if ($verbose);
	      }
	    # Use '-1' to identify words without holonyms (root nodes)
	    $wn->{"$this_word\#$sense_no"}->{"holo"} = -1
	      if (!defined($wn->{"$this_word\#$sense_no"}->{"holo"}));
	  }
      }
    # Use '-1' to identify words without meronyms (leaf nodes)
    $wn->{"$word\#$sense"}->{"holo"} = -1
      if (!defined($wn->{"$word\#$sense"}->{"holo"}));
    undef $fh;
    return $num_senses;
  }	  


# Return reference to array of Holonyms
# Input is word-sense in form of "word#S" where S is the sense number
sub holo
  {
    my ($word, $pos) = @_;
    
    ($word) = lower ($word);
    print STDERR "holo ($word)\n" if ($verbose);

    return () if ($wn->{$word}->{"holo"} == -1);

    my $senses = &parse_holo ($word, $pos)
      if (!defined ($wn->{$word}->{"holo"}));
    
    # return a ref to an array of senses if no sense was specified
    if ($word !~ m/\#\d+$/)
      {
	my @sensearray;
	for (my $i=1; $i <= $senses; $i++)
	  {
	    my @words = keys (%{$wn->{"$word\#$i"}->{"holo"}});
	    push @sensearray, \@words if (@words);
	  }
	return \@sensearray;
      }
    # Return empty list if the word has no holonyms
    return () if ($wn->{$word}->{"holo"} == -1);
    return (keys (%{$wn->{$word}->{"holo"}}));
  }

END { undef $wn; } # module clean-up code here (global destructor)

# module must return true
1;
__END__

#################
# Documentation #
#################

=head1 NAME

WordNet::Query - perl interface for noun relations of WordNet

=head1 SYNOPSIS

use WordNet::Query;
  
print "Definition: ", &gloss ("car\#1"), "\n";
print "Synset: ", join (", ", &syns ("car\#1")), "\n";
print "Hypernyms: ", join (", ", &hype ("car\#1")), "\n";
my @hypes = &hype("car\#1");
print "Hype Synset: ", join (", ", &syns ($hypes[0])), "\n";
print "Hype-Hypernyms: ", join (", ", &hype ($hypes[0])), "\n";
print "Hyponyms: ", join (", ", &hypo ("car\#1")), "\n";
print "Meronyms: ", join (", ", &mero ("car\#1")), "\n";
print "Holonyms: ", join (", ", &holo ("roof\#2")), "\n";

my @sensearray = &syns ("car");

print "Num Senses: ", scalar @sensearray, "\n";
for (my $i=0; $i < scalar @sensearray; $i++)
  {
    print $i+1, ") ", join (", ", @{$sensearray[$i]}), "\n";
  }

=head1 DESCRIPTION

The WordNet::Query perl module uses the 'wn' command-line program to
give a more palatable interface to the WordNet system.  Before the
WordNet perl module can be used, the WordNet C code must be installed
on your system and the 'wn' executable must be located in a directory
that is part of your PATH variable.

When a query is performed, the module gathers data from 'wn', caches
it in memory and returns the requested information.  This mechanism
makes accessing WordNet information both efficient and more natural.
The WordNet module requires little effort to traverse the various
graphs of information that are available in the WordNet system.

=head1 USAGE

The WordNet::Query module includes six exported functions, each of
which operate in two different modes.  The functions are:

syns - Returns the synonym set of the provided word

gloss - Returns the glossary definition of the provided word

hype - Returns all hypernyms one level above the provided word

hypo - Returns all hyponyms one level below the provided word

mero - Returns all meronyms (part/member/substance of parents) of the provided word

holo - Returns all holonyms (part/member/substance of children) of the provided word

Each word accepts a single string that is the word to be queried.  In
the case that the exact sense of the word is known, that may be
provided in the string using the #S notation (where 'S' is the sense
number).  For example, 'car#1' refers to the first sense of the word
'car'.

The output of each of these function depends on the format of the
input and is probably best described by the examples provided in the
SYNOPSIS section (above).  Generally, if a specific sense is provided
(e.g. 'window#2'), then a list of strings is returned, one for each
found instance of the requested object.  In the case of the 'gloss'
function, a single item is returned (the single definition of that
word).  If no specific sense is provided, then an array of references
is returned.  Each reference will point to a list of strings,
corresponding to the list that would have been returned given a
specific sense query.  The array of referneces is ordered according to
sense number, with sense #1 coming first and the largest sense coming
last.  i.e. add one to the array index to get the sense number.

=head1 NOTES

Requires existence of WordNet command line program, 'wn'.  Currently
only allows WordNet queries on noun forms.

=head1 COPYRIGHT

Copyright 1999 Jason Rennie <jrennie@ai.mit.edu>  All rights reserved.

This module is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=head1 SEE ALSO

perl(1)

http://www.cogsci.princeton.edu/~wn/

http://www.ai.mit.edu/~jrennie/WordNet/

=head1 LOG

$Log: Query.pm,v $
Revision 1.2  1999/09/15 19:53:28  jrennie
add URL

Revision 1.1  1999/09/15 13:27:54  jrennie
new Query directory

Revision 1.3  1999/07/22 21:12:25  jrennie
add lower; lowercase everything; put all verbosity output on STDERR

Revision 1.2  1999/07/22 18:54:24  jrennie
add hype_set, level functions; have all parse_* functions return -1 if
nothing is found; have export functions return empty list or undef if
nothing is found

Revision 1.1  1999/07/21 20:08:51  jrennie
rename from WordNet.pm; modify initialization code to allow direct
access to findtheinfo function; in future, plan to rely soley on
findtheinfo (no more command-line 'wn' execution)

Revision 1.5  1999/07/20 16:17:09  jrennie
missing '>' in hash dereference

Revision 1.4  1999/07/19 14:19:53  jrennie
use CVS for versioning ($VERSION line taken from CPAN suggestion)

Revision 1.3  1999/07/19 14:09:19  jrennie
various fixes in parsing of 'wn' output -- particularly for special
cases ('wn' does not have the requested information)

Revision 1.2  1999/07/16 19:51:06  jrennie
deal with empty holo or mero wn output (different from other queries)

Revision 1.1.1.1  1999/07/16 18:27:02  jrennie
move WordNet to separate directory

Revision 1.9  1999/07/16 18:04:12  jrennie
bug fix---forgot to convert synlist to hash

Revision 1.8  1999/07/16 14:55:48  jrennie
various clean up to make "use strict" happy; do the right thing for
top and bottom of tree

Revision 1.7  1999/07/15 16:41:09  jrennie
updated documentation

Revision 1.6  1999/07/15 15:27:42  jrennie
allow arbitrary sense querying

Revision 1.5  1999/07/14 22:38:48  jrennie
complete rewrite; created separate function for each aspect of wordnet
(gloss, synset, hype, hypo, mero, holo); still need to allow for
querying w/o a specific sense

Revision 1.4  1999/07/13 15:28:22  jrennie
add example for ambiguous mode

Revision 1.3  1999/07/13 15:16:50  jrennie
Follow guidelines in perl FAQ

Revision 1.2  1999/07/13 13:48:09  jrennie
quote query words passed to wn

=cut

