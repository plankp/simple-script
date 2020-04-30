# Simple script

> It's like we went ***back in the day*** when everything is register sized...

This is a very simple language:
1. This is not dynamic type, it's everything-is-a-(64-bit because I use a mac)-integer.
2. The only optimization that happens is killing temporary variables (not even constant folding)
                         
Syntax is inspired by Algol 68 (I did *not* add the `fi`s and the `od`s)          

There are two (and a half?) parts to this:
1. The compiler, you need jdk 8+. This will convert the source code into IR.
2. The IR converter, you need perl5. This will convert the IR into x86-64 NASM code (SysV calling convention).
3. NASM if you want to assemble the code emitted by the IR converter.

How to run this?

Once you build the compiler (`./gradlew build`) and extract the zipped stuff (`./build/distributions/`),
let's say you want to compile `./sample/test.expr`, then you'd do:

```
./build/distributions/simple-script/bin/simple-script ./sample/test.expr | ./scripts/kill_temp.pl | ./scripts/assembler.pl
```

and it will spit the assembler code out!

***DISCLAIMER: The code generated is absolutely terrible***