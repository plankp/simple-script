grammar Grammar;

@header {
    package com.ymcmp.lang.sscr;
}

// Keywords are case insensitive:
fragment A: [Aa];
fragment B: [Bb];
fragment C: [Cc];
fragment D: [Dd];
fragment E: [Ee];
fragment F: [Ff];
fragment G: [Gg];
fragment H: [Hh];
fragment I: [Ii];
fragment J: [Jj];
fragment K: [Kk];
fragment L: [Ll];
fragment M: [Mm];
fragment N: [Nn];
fragment O: [Oo];
fragment P: [Pp];
fragment Q: [Qq];
fragment R: [Rr];
fragment S: [Ss];
fragment T: [Tt];
fragment U: [Uu];
fragment V: [Vv];
fragment W: [Ww];
fragment X: [Xx];
fragment Y: [Yy];
fragment Z: [Zz];

TRUE: '\\' T R U E;
FALSE: '\\' F A L S E;
IF: '\\' I F;
THEN: '\\' T H E N;
ELSE: '\\' E L S E;
WHILE: '\\' W H I L E;
DO: '\\' D O;
FOR: '\\' F O R;
FROM: '\\' F R O M;
BY: '\\' B Y;
TO: '\\' T O;
MOD: '\\' M O D;
REM: '\\' R E M;

SCOPE: '::';
SET: ':=';
SET_ADD: '+=';
SET_SUB: '-=';
SET_MUL: '*=';
SET_DIV: '/=';
COMPARE: '<>';
COMMA: ',';
SEMI: ';';
NE: '==';
EQ: '!=';
LE: '<=';
GE: '>=';
LT: '<';
GT: '>';
NOT: '!';
ADD: '+';
SUB: '-';
MUL: '*';
DIV: '/';
LPAREN: '(';
RPAREN: ')';
LCURL: '{';
RCURL: '}';

NUMBER:
    [1-9][0-9]*
    | '0' X [a-fA-F0-9]+
    | '0' D [0-9]+
    | '0' C [0-7]+
    | '0' B [01]+
    | '0';

IDENTIFIER: [$_a-zA-Z][$_a-zA-Z0-9]*;

COMMENT: '#' ~[\r\n]* -> skip;
WS: [ \t\r\n] -> skip;

file: top*;

top: (global | func) SEMI;
global: name = IDENTIFIER SET e = expr;
func:
    name = IDENTIFIER args += IDENTIFIER (
        COMMA args += IDENTIFIER
    )* SET body = stmt
    | name = IDENTIFIER LPAREN RPAREN SET body = stmt;

atom:
    LPAREN e = expr RPAREN           # atomNested
    | TRUE                           # atomTrue
    | FALSE                          # atomFalse
    | NUMBER                         # atomNumber
    | ext = SCOPE? name = IDENTIFIER # atomIdentifier;
expr1: op = (NOT | ADD | SUB)? e = atom;
expr2: lhs = expr1 ((MUL | DIV | MOD | REM) expr1)*;
expr3: lhs = expr2 ((ADD | SUB) expr2)*;
expr4: lhs = expr3 (op = COMPARE rhs = expr3)?;
expr5: lhs = expr4 (op = (LT | LE | GE | GT) rhs = expr4)?;
expr6: lhs = expr5 (op = (EQ | NE) rhs = expr5)?;
expr7:
    dst = expr6 op = (
        SET
        | SET_ADD
        | SET_SUB
        | SET_MUL
        | SET_DIV
    ) src = expr7                                      # expr7Set
    | vtrue = expr6 IF cond = expr ELSE vfalse = expr7 # expr7Ternary
    | e = expr6                                        # expr7Atom;
expr8:
    site = expr8 LPAREN RPAREN                                        # expr8CallNoArgs
    | <assoc = right> site = expr8 (head += expr COMMA)* last = expr8 # expr8Call
    | e = expr7                                                       # expr8Atom;
expr: e = expr8;

stmt:
    LCURL (body += stmt SEMI)* body += stmt? SEMI? RCURL       # stmtBlock
    | IF test = expr THEN ontrue = stmt (ELSE onfalse = stmt)? # stmtIfElse
    | WHILE test = expr DO body = stmt                         # stmtWhileDo
    | (FOR name = IDENTIFIER)? (FROM from = expr)? (BY by = expr)? (
        TO to = expr
    )? DO body = stmt # stmtLoop
    | e = expr        # stmtExpr;