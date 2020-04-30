#!/usr/bin/perl
use strict;
use warnings;
use POSIX qw/ceil/;

# instr-opcode => destination index
my %instrdst = (
    # destination is a variable
    "mov" => 0,
    "add" => 0,
    "sub" => 0,
    "mul" => 0,
    "div" => 0,
    "mod" => 0,
    "rem" => 0,
    "call" => 0,

    # destination is a label
    "br" => 0,
    "brz" => 0,
    "brnz" => 0,
    "brgt" => 0,
    "brge" => 0,
    "brlt" => 0,
    "brle" => 0,
);

# Registers used to pass function arguments from 1st arg to last arg
my @regparams = (
    "rdi", "rsi", "rdx", "rcx", "r8", "r9"
);

my $usebuf = 0;
my @buffer = ();

my $align = 0;
my %varmap = ();
my $nextvar = 0;

my %lblmap = ();
my $nextlbl = 0;

while (<>) {
    chomp;
    s/^\s+|\s+$//g;

    # Skip comments (which start with ';')
    next if ($_ eq '') || /^;/;

    s/^([^ \t:]+)\s*(:?)\s*//;
    if ($2 ne '') {
        # It was a label:
        my $lbl = $1;
        if ($lbl =~ /^#/) {
            $lblmap{$lbl} = ".L" . $nextlbl++ unless exists $lblmap{$lbl};
            $lbl = $lblmap{$lbl};
        }

        if ($usebuf) {
            push @buffer, "$lbl:";
        } else {
            print "$lbl:\n";
        }
        next;
    }

    my $op = $1;
    my @operands = split /\s*,\s*/;

    if ($op eq '.fn_start') {
        die 'Bad function start-end context' if $usebuf;
        $usebuf = 1;

        @buffer = ();
        $align = 0;
        %varmap = ();
        $nextvar = 0;
        %lblmap = ();
        $nextlbl = 0;

        my $cnt = @operands;
        $cnt = scalar @regparams if $cnt > scalar @regparams;
        for my $i (0 .. $cnt - 1) {
            my $dst = $operands[$i];
            $nextvar += 8;
            $varmap{$dst} = "qword [rbp - $nextvar]";
            push @buffer, "  mov $varmap{$dst}, $regparams[$i]";
        }

        my $offset = 8; # 8 (not 0) because we push rbp at prologue
        for my $i ($cnt .. $#operands) {
            $offset += 8;
            $varmap{$operands[$i]} = "qword [rbp + $offset]";
        }
        next;
    }

    if ($op eq '.fn_end') {
        die 'Bad function start-end context' if !$usebuf;
        $usebuf = 0;

        # Align stack if needed
        $nextvar = $align * ceil($nextvar / $align) if $align;

        # Emit the prologue
        print "  push rbp\n";
        print "  sub rsp, $nextvar\n" if $nextvar;

        # Spit out the buffer!
        for my $el (@buffer) {
            print "$el\n";
        }

        # Emit the epilogue
        if ($nextvar) {
            print "  leave\n";
        } else {
            print "  pop rbp\n";
        }
        print "  ret\n";
        next;
    }

    my $slot = exists $instrdst{$op} ? $instrdst{$op} : -1;

    for my $i ($slot + 1 .. $#operands) {
        my $opr = $operands[$i];
        $operands[$i] = $varmap{$opr} if exists $varmap{$opr};
        $operands[$i] = $lblmap{$opr} if exists $lblmap{$opr};

        if ($opr =~ /^::/) {
            # Drop the :: prefix
            $opr =~ s/^:://;
            $opr = "qword [rel $opr]";
            $operands[$i] = $opr;
        }
    }

    if ($slot >= 0) {
        my $dst = $operands[$slot];
        if ($dst =~ /^::/) {
            # Drop the :: prefix
            $dst =~ s/^:://;
            $dst = "qword [rel $dst]";
        } elsif ($op =~ /^br/) {
            $lblmap{$dst} = ".L" . $nextlbl++ unless exists $lblmap{$dst};
            $dst = $lblmap{$dst};
        } else {
            unless (exists $varmap{$dst}) {
                $nextvar += 8;
                $varmap{$dst} = "qword [rbp - $nextvar]";
            }
            $dst = $varmap{$dst};
        }

        $operands[$slot] = $dst;
    }

    # Convert these to real x86-64 instructions or nasm directives:
    if ($op eq ".emit") {
        $op = "dq";
    } elsif ($op eq "not") {
        push @buffer, "  xor rax, rax";
        push @buffer, "  mov rdx, $operands[1]";
        push @buffer, "  test rdx, rdx";
        push @buffer, "  sete al";
        $op = "mov";
        @operands = ($operands[0], "rax");
    } elsif ($op eq "cmp") {
        push @buffer, "  xor rax, rax";
        push @buffer, "  mov rdx, $operands[1]";
        push @buffer, "  mov rcx, 1";
        push @buffer, "  test rdx, rdx";
        push @buffer, "  setne al";
        push @buffer, "  neg rax";
        push @buffer, "  test rdx, rdx";
        push @buffer, "  cmovg rax, rcx";
        $op = "mov";
        @operands = ($operands[0], "rax");
    } elsif ($op eq "ret") {
        $op = "mov";
        @operands = ("rax", $operands[0]);
    } elsif ($op eq "mov") {
        # Add an explicit move because memory to memory move does not exist.
        push @buffer, "  mov rax, $operands[1]";
        $operands[1] = "rax";
    } elsif ($op eq "brz") {
        push @buffer, "  mov rax, $operands[1]";
        push @buffer, "  test rax, rax";
        $op = "jz";
        @operands = ($operands[0]);
    } elsif ($op eq "brnz") {
        push @buffer, "  mov rax, $operands[1]";
        push @buffer, "  test rax, rax";
        $op = "jnz";
        @operands = ($operands[0]);
    } elsif ($op eq "brlt") {
        push @buffer, "  mov rax, $operands[1]";
        push @buffer, "  cmp rax, $operands[2]";
        $op = "jl";
        @operands = ($operands[0]);
    } elsif ($op eq "brgt") {
        push @buffer, "  mov rax, $operands[1]";
        push @buffer, "  cmp rax, $operands[2]";
        $op = "jg";
        @operands = ($operands[0]);
    } elsif ($op eq "breq") {
        push @buffer, "  mov rax, $operands[1]";
        push @buffer, "  cmp rax, $operands[2]";
        $op = "je";
        @operands = ($operands[0]);
    } elsif ($op eq "brne") {
        push @buffer, "  mov rax, $operands[1]";
        push @buffer, "  cmp rax, $operands[2]";
        $op = "jne";
        @operands = ($operands[0]);
    } elsif ($op eq "brge") {
        push @buffer, "  mov rax, $operands[1]";
        push @buffer, "  cmp rax, $operands[2]";
        $op = "jge";
        @operands = ($operands[0]);
    } elsif ($op eq "brle") {
        push @buffer, "  mov rax, $operands[1]";
        push @buffer, "  cmp rax, $operands[2]";
        $op = "jle";
        @operands = ($operands[0]);
    } elsif ($op eq "br") {
        $op = "jmp";
    } elsif ($op eq "lt") {
        push @buffer, "  xor rax, rax";
        push @buffer, "  mov rdx, $operands[1]";
        push @buffer, "  cmp rdx, $operands[2]";
        push @buffer, "  setl al";
        $op = "mov";
        @operands = ($operands[0], "rax");
    } elsif ($op eq "gt") {
        push @buffer, "  xor rax, rax";
        push @buffer, "  mov rdx, $operands[1]";
        push @buffer, "  cmp rdx, $operands[2]";
        push @buffer, "  setg al";
        $op = "mov";
        @operands = ($operands[0], "rax");
    } elsif ($op eq "eq") {
        push @buffer, "  xor rax, rax";
        push @buffer, "  mov rdx, $operands[1]";
        push @buffer, "  cmp rdx, $operands[2]";
        push @buffer, "  sete al";
        $op = "mov";
        @operands = ($operands[0], "rax");
    } elsif ($op eq "ne") {
        push @buffer, "  xor rax, rax";
        push @buffer, "  mov rdx, $operands[1]";
        push @buffer, "  cmp rdx, $operands[2]";
        push @buffer, "  setne al";
        $op = "mov";
        @operands = ($operands[0], "rax");
    } elsif ($op eq "le" or $op eq "ge") {
        push @buffer, "  xor rax, rax";
        push @buffer, "  mov rdx, $operands[1]";
        push @buffer, "  cmp rdx, $operands[2]";
        push @buffer, "  set$op al";
        $op = "mov";
        @operands = ($operands[0], "rax");
    } elsif ($op eq "add" or $op eq "sub") {
        push @buffer, "  mov rax, $operands[1]";
        push @buffer, "  $op rax, $operands[2]";
        $op = "mov";
        @operands = ($operands[0], "rax");
    } elsif ($op eq "mul") {
        push @buffer, "  mov rax, $operands[1]";
        push @buffer, "  imul rax, $operands[2]";
        $op = "mov";
        @operands = ($operands[0], "rax");
    } elsif ($op eq "div" or $op eq "rem") {
        push @buffer, "  mov rax, $operands[1]";
        push @buffer, "  cqo";
        push @buffer, "  idiv $operands[2]";
        $op = "mov";
        @operands = ($operands[0], $op eq "div" ? "rax" : "rdx");
    } elsif ($op eq "mod") {
        # Pseudo code: (Also maybe we should generate this at IR level?)
        # let num = *operand[1]
        # let div = *operand[2]
        # let m = num `rem` div
        # if m == 0 OR num `same-sign` div
        #   *operand[0] = m
        # else
        #   *operand[0] = m + div

        my $site = ".L" . $nextlbl++;

        push @buffer, "  mov r8, $operands[1]";
        push @buffer, "  mov rcx, $operands[2]";
        push @buffer, "  mov rax, r8";
        push @buffer, "  cqo";
        push @buffer, "  idiv rcx";
        push @buffer, "  test rdx, rdx";
        push @buffer, "  je $site";
        push @buffer, "  test r8, r8";
        push @buffer, "  setle al";
        push @buffer, "  test rcx, rcx";
        push @buffer, "  setg r8b";
        push @buffer, "  cmp al, r8b";
        push @buffer, "  cmove rdx, rcx";
        push @buffer, "$site:";
        $op = "mov";
        @operands = ($operands[0], "rdx");
    } elsif ($op eq 'call') {
        my $dst = shift @operands;
        my $site = shift @operands;

        # Arguments are processed from right to left (SysV style).
        my $i = $#operands;
        my $restore = 0;
        for (; $i >= scalar @regparams; --$i) {
            $restore += 8;
            push @buffer, "  push $operands[$i]";
        }
        for (; $i >= 0; --$i) {
            push @buffer, "  mov $regparams[$i], $operands[$i]";
        }

        # Stack needs to be aligned before a call
        $align = 16;
        push @buffer, "  call $site";
        push @buffer, "  add rsp, $restore" if $restore;

        # Return value is passed through rax
        $op = "mov";
        @operands = ($dst, "rax");
    }

    if ($usebuf) {
        push @buffer, "  $op " . (join ", ", @operands);
    } else {
        print "  $op ", (join ", ", @operands), "\n";
    }
}
