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

my $format = lc(shift || "nasm");

# Each argument is a line
sub emit_line {
    foreach my $line (@_) {
        if ($usebuf) {
            push @buffer, "$line";
        } else {
            print "$line\n";
        }
    }
}

# Each argument is a line of comment
sub emit_comment {
    foreach my $line (@_) {
        if ($format eq "nasm") {
            emit_line "; $line";
        } elsif ($format eq "gas") {
            emit_line "# $line";
        } else {
            die "Unsupported output format: $format\n";
        }
    }
}

# $_[0] = Width (8, 16, 32, 64)
# $_[1] = Data
sub emit_data {
    my $width = $_[0];
    my %map = ();

    if ($format eq "nasm") {
        %map = (8 => "db", 16 => "dw", 32 => "dd", 64 => "dq");
    } elsif ($format eq "gas") {
        %map = (8 => ".byte", 16 => ".word", 32 => ".long", 64 => ".quad");
    } else {
        die "Unsupported output format: $format\n";
    }

    die "Unsupported output width: $width\n" unless exists $map{$width};
    emit_line "  " . $map{$width} . " " . $_[1];
}

# $_[0] = Mnemonic
# Rest are operands (in dst src order)
sub emit_instr {
    my $mnemonic = shift @_;
    my $count = @_;
    if ($count == 2 and $format eq "gas") {
        # sub rbp, 10  ==>  sub 10, rbp
        my $tmp = $_[0];
        $_[0] = $_[1];
        $_[1] = $tmp;
    }
    emit_line "  $mnemonic " . (join ", ", @_);
}

# $_[0] = Register
sub wrap_reg {
    my $reg = $_[0];
    $format eq "gas" ? "\%$reg" : $reg;
}

# $_[0] = Immediate
sub wrap_imm {
    my $imm = $_[0];
    return $imm if $format eq "nasm";
    return "\$$imm" if $format eq "gas";

    die "Unsupported output format: $format\n";
}

# $_[0] = Base
# $_[1] = Offset
sub wrap_mem {
    my ($base, $offset) = @_;

    if ($format eq "nasm") {
        return "[$base]" if $offset == 0;
        return "[$base + $offset]" if $offset > 0;

        $offset = -$offset;
        return "[$base - $offset]";
    } elsif ($format eq "gas") {
        return "($base)" if $offset == 0;
        return "$offset($base)";
    } else {
        die "Unsupported output format: $format\n";
    }
}

# $_[0] = Base
sub wrap_rel {
    my $base = $_[0];
    return "[rel $base]" if $format eq "nasm";
    return "$base(\%rip)" if $format eq "gas";

    die "Unsupported output format: $format\n";
}

print emit_comment "Output format: $format assembler";

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

        emit_line "$lbl:";
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
            $varmap{$dst} = wrap_mem wrap_reg("rbp"), -$nextvar;
            emit_instr "mov", $varmap{$dst}, wrap_reg $regparams[$i];
        }

        my $offset = 8; # 8 (not 0) because we push rbp at prologue
        for my $i ($cnt .. $#operands) {
            $offset += 8;
            $varmap{$operands[$i]} = wrap_mem wrap_reg("rbp"), $offset;
        }
        next;
    }

    if ($op eq '.fn_end') {
        die 'Bad function start-end context' if !$usebuf;
        $usebuf = 0;

        # Align stack if needed
        $nextvar = $align * ceil($nextvar / $align) if $align;

        # Emit the prologue
        emit_instr "push", wrap_reg "rbp";
        emit_instr "sub", wrap_reg("rsp"), wrap_imm($nextvar) if $nextvar;

        # Spit out the buffer!
        for my $el (@buffer) {
            print "$el\n";
        }

        # Emit the epilogue
        if ($nextvar) {
            emit_instr "leave";
        } else {
            emit_instr "pop", wrap_reg "rbp";
        }
        emit_instr "ret";
        next;
    }

    my $slot = exists $instrdst{$op} ? $instrdst{$op} : -1;

    for my $i ($slot + 1 .. $#operands) {
        my $opr = $operands[$i];
        $operands[$i] = wrap_imm($opr) if $opr =~ /^\d/;
        $operands[$i] = $varmap{$opr} if exists $varmap{$opr};
        $operands[$i] = $lblmap{$opr} if exists $lblmap{$opr};

        if ($opr =~ /^::/) {
            # Drop the :: prefix
            $opr =~ s/^:://;
            $opr = wrap_rel $opr;
            $operands[$i] = $opr;
        }
    }

    if ($slot >= 0) {
        my $dst = $operands[$slot];
        if ($dst =~ /^::/) {
            # Drop the :: prefix
            $dst =~ s/^:://;
            $dst = wrap_reg $dst;
        } elsif ($op =~ /^br/) {
            $lblmap{$dst} = ".L" . $nextlbl++ unless exists $lblmap{$dst};
            $dst = $lblmap{$dst};
        } else {
            unless (exists $varmap{$dst}) {
                $nextvar += 8;
                $varmap{$dst} = wrap_mem wrap_reg("rbp"), -$nextvar;
            }
            $dst = $varmap{$dst};
        }

        $operands[$slot] = $dst;
    }

    # Convert these to real x86-64 instructions or nasm directives:
    if ($op eq ".emit") {
        emit_data 64, $operands[0];
    } elsif ($op eq "not") {
        emit_instr "xor", wrap_reg("rax"), wrap_reg("rax");
        emit_instr "mov", wrap_reg("rdx"), $operands[1];
        emit_instr "test", wrap_reg("rdx"), wrap_reg("rdx");
        emit_instr "sete", wrap_reg("al");
        emit_instr "mov", $operands[0], wrap_reg("rax");
    } elsif ($op eq "cmp") {
        emit_instr "xor", wrap_reg("rax"), wrap_reg("rax");
        emit_instr "mov", wrap_reg("rdx"), $operands[1];
        emit_instr "mov", wrap_reg("rcx"), wrap_imm(1);
        emit_instr "test", wrap_reg("rdx"), wrap_reg("rdx");
        emit_instr "setne", wrap_reg("al");
        emit_instr "neg", wrap_reg("rax");
        emit_instr "test", wrap_reg("rdx"), wrap_reg("rdx");
        emit_instr "cmovg", wrap_reg("rax"), wrap_reg("rcx");
        emit_instr "mov", $operands[0], wrap_reg("rax");
    } elsif ($op eq "ret") {
        emit_instr "mov", wrap_reg("rax"), $operands[0];
    } elsif ($op eq "mov") {
        # Add an explicit move because memory to memory move does not exist.
        emit_instr "mov", wrap_reg("rax"), $operands[1];
        emit_instr "mov", $operands[0], wrap_reg("rax");
    } elsif ($op eq "brz") {
        emit_instr "mov", wrap_reg("rax"), $operands[1];
        emit_instr "test", wrap_reg("rax"), wrap_reg("rax");
        emit_instr "jz", $operands[0];
    } elsif ($op eq "brnz") {
        emit_instr "mov", wrap_reg("rax"), $operands[1];
        emit_instr "test", wrap_reg("rax"), wrap_reg("rax");
        emit_instr "jnz", $operands[0];
    } elsif ($op eq "brlt") {
        emit_instr "mov", wrap_reg("rax"), $operands[1];
        emit_instr "cmp", wrap_reg("rax"), $operands[2];
        emit_instr "jl", $operands[0];
    } elsif ($op eq "brgt") {
        emit_instr "mov", wrap_reg("rax"), $operands[1];
        emit_instr "cmp", wrap_reg("rax"), $operands[2];
        emit_instr "jg", $operands[0];
    } elsif ($op eq "breq") {
        emit_instr "mov", wrap_reg("rax"), $operands[1];
        emit_instr "cmp", wrap_reg("rax"), $operands[2];
        emit_instr "je", $operands[0];
    } elsif ($op eq "brne") {
        emit_instr "mov", wrap_reg("rax"), $operands[1];
        emit_instr "cmp", wrap_reg("rax"), $operands[2];
        emit_instr "jne", $operands[0];
    } elsif ($op eq "brge") {
        emit_instr "mov", wrap_reg("rax"), $operands[1];
        emit_instr "cmp", wrap_reg("rax"), $operands[2];
        emit_instr "jge", $operands[0];
    } elsif ($op eq "brle") {
        emit_instr "mov", wrap_reg("rax"), $operands[1];
        emit_instr "cmp", wrap_reg("rax"), $operands[2];
        emit_instr "jle", $operands[0];
    } elsif ($op eq "br") {
        emit_instr "jmp", $operands[0];
    } elsif ($op eq "lt") {
        emit_instr "xor", wrap_reg("rax"), wrap_reg("rax");
        emit_instr "mov", wrap_reg("rdx"), $operands[1];
        emit_instr "cmp", wrap_reg("rdx"), $operands[2];
        emit_instr "setl", wrap_reg("al");
        emit_instr "mov", $operands[0], wrap_reg("rax");
    } elsif ($op eq "gt") {
        emit_instr "xor", wrap_reg("rax"), wrap_reg("rax");
        emit_instr "mov", wrap_reg("rdx"), $operands[1];
        emit_instr "cmp", wrap_reg("rdx"), $operands[2];
        emit_instr "setg", wrap_reg("al");
        emit_instr "mov", $operands[0], wrap_reg("rax");
    } elsif ($op eq "eq") {
        emit_instr "xor", wrap_reg("rax"), wrap_reg("rax");
        emit_instr "mov", wrap_reg("rdx"), $operands[1];
        emit_instr "cmp", wrap_reg("rdx"), $operands[2];
        emit_instr "sete", wrap_reg("al");
        emit_instr "mov", $operands[0], wrap_reg("rax");
    } elsif ($op eq "ne") {
        emit_instr "xor", wrap_reg("rax"), wrap_reg("rax");
        emit_instr "mov", wrap_reg("rdx"), $operands[1];
        emit_instr "cmp", wrap_reg("rdx"), $operands[2];
        emit_instr "setne", wrap_reg("al");
        emit_instr "mov", $operands[0], wrap_reg("rax");
    } elsif ($op eq "le" or $op eq "ge") {
        emit_instr "xor", wrap_reg("rax"), wrap_reg("rax");
        emit_instr "mov", wrap_reg("rdx"), $operands[1];
        emit_instr "cmp", wrap_reg("rdx"), $operands[2];
        emit_instr "set$op", wrap_reg("al");
        emit_instr "mov", $operands[0], wrap_reg("rax");
    } elsif ($op eq "add" or $op eq "sub") {
        emit_instr "mov", wrap_reg("rax"), $operands[1];
        emit_instr "$op", wrap_reg("rax"), $operands[2];
        emit_instr "mov", $operands[0], wrap_reg("rax");
    } elsif ($op eq "mul") {
        emit_instr "mov", wrap_reg("rax"), $operands[1];
        emit_instr "imul", wrap_reg("rax"), $operands[2];
        emit_instr "mov", $operands[0], wrap_reg("rax");
    } elsif ($op eq "div" or $op eq "rem") {
        emit_instr "mov", wrap_reg("rax"), $operands[1];
        emit_instr "cqo";
        emit_instr "idiv", $operands[2];
        emit_instr "mov", $operands[0], wrap_reg($op eq "div" ? "rax" : "rdx");
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

        emit_instr "mov", wrap_reg("r8"), $operands[1];
        emit_instr "mov", wrap_reg("rcx"), $operands[2];
        emit_instr "mov", wrap_reg("rax"), wrap_reg("r8");
        emit_instr "cqo";
        emit_instr "idiv", wrap_reg("rcx");
        emit_instr "test", wrap_reg("rdx"), wrap_reg("rdx");
        emit_instr "je", $site;
        emit_instr "test", wrap_reg("r8"), wrap_reg("r8");
        emit_instr "setle", wrap_reg("al");
        emit_instr "test", wrap_reg("rcx"), wrap_reg("rcx");
        emit_instr "setg", wrap_reg("r8b");
        emit_instr "cmp", wrap_reg("al"), wrap_reg("r8b");
        emit_instr "cmove", wrap_reg("rdx"), wrap_reg("rcx");
        emit_line "$site:";
        emit_instr "mov", $operands[0], wrap_reg("rdx");
    } elsif ($op eq 'call') {
        my $dst = shift @operands;
        my $site = shift @operands;

        # Arguments are processed from right to left (SysV style).
        my $i = $#operands;
        my $restore = 0;
        for (; $i >= scalar @regparams; --$i) {
            $restore += 8;
            emit_instr "push", $operands[$i];
        }
        for (; $i >= 0; --$i) {
            emit_instr "mov", wrap_reg($regparams[$i]), $operands[$i];
        }

        # Stack needs to be aligned before a call
        $align = 16;
        emit_instr "lea", wrap_reg("rax"), $site;
        emit_instr "call", wrap_reg("rax");
        emit_instr "add", wrap_reg("rsp"), wrap_imm($restore) if $restore;

        # Return value is passed through rax
        emit_instr "mov", $dst, wrap_reg("rax");
    } else {
        emit_comment "Warning: Unkown $op @operands";
    }
}
