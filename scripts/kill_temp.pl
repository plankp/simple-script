#!/usr/bin/perl
use strict;
use warnings;

# instr-opcode => destination index
my %instrdst = (
    "mov" => 0,
    "add" => 0,
    "sub" => 0,
    "mul" => 0,
    "div" => 0,
    "mod" => 0,
    "rem" => 0,
    "call" => 0
);

my %replmap = ();
my $nextid = 0;
my $lasttmp = '';

while (<>) {
    chomp;
    s/^\s+|\s+$//g;

    # Skip comments (which start with ';')
    next if ($_ eq '') || /^;/;

    s/^([^ \t:]+)\s*(:?)\s*//;
    if ($2 ne '') {
        # It was a label:
        print "$1:\n";
        next;
    }

    my $op = $1;
    my @operands = split /\s*,\s*/;

    if ($op eq '.fn_start') {
        # Reset the internal state
        %replmap = ();
        $nextid = 0;
        $lasttmp = '';
    }

    my $slot = exists $instrdst{$op} ? $instrdst{$op} : -1;

    for my $i ($slot + 1 .. $#operands) {
        my $opr = $operands[$i];
        if ($opr =~ /^%/) {
            $operands[$i] = $replmap{$opr};
            $nextid-- if $opr eq $lasttmp;
        }
    }

    if ($slot >= 0) {
        my $dst = $operands[$slot];
        if ($dst =~ /^%/) {
            $lasttmp = $dst;
            my $name = '%' . $nextid++;

            $replmap{$dst} = $name;
            $operands[$slot] = $name;
        }
    }

    print "  $op ", (join ", ", @operands), "\n";
}
