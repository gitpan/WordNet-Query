# Before `make install' is performed this script should be runnable with
# `make test'. After `make install' it should work as `perl test.pl'

######################### We start with some black magic to print on failure.

# Change 1..1 below to 1..last_test_to_print .
# (It may become useful if the test is moved to ./t subdirectory.)

BEGIN { $| = 1; print "1..2\n"; }
END {print "not ok 1\n" unless $loaded;}
use WordNet::Query qw(syns);
$loaded = 1;
print "ok 1\n";

######################### End of black magic.

# Insert your test code below (better if it prints "ok 13"
# (correspondingly "not ok 13") depending on the success of chunk 13
# of the test code):

my @foo = syns ("food\#1");
print "ok 2\n" if ($foo[0] eq "food\#1");

#my $word="canary";
#print STDERR "Food: ", join (", ", @foo), "\n";
#my $rtn = do_findtheinfo ($word,1,29,0);
#print STDERR $rtn, "\n";
#if (do_findtheinfo ($word,1,29,0) =~ /canary/) { print "ok 2\n"; }
#    else { print "not ok 2\n"; }
#if (do_findtheinfo ($word,1,3,4) =~ /canary/) { print "ok 3\n"; }
#    else { print "not ok 3\n"; }

