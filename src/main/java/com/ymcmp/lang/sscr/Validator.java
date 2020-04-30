package com.ymcmp.lang.sscr;

import java.util.HashSet;
import java.util.ArrayDeque;
import java.util.LinkedHashSet;
import java.util.stream.Collectors;

import org.antlr.v4.runtime.Token;
import org.antlr.v4.runtime.tree.ParseTree;

class Validator extends GrammarBaseVisitor<RtValue> {

    private int idTemporary = 0;
    private int idGenerated = 0;

    private final HashSet<String> locals = new HashSet<>();
    private final ArrayDeque<String> buffer = new ArrayDeque<>();

    @Override
    public RtValue visitTop(GrammarParser.TopContext ctx) {
        this.locals.clear();
        this.buffer.clear();
        this.idTemporary = 0;
        this.idGenerated = 0;

        this.visitChildren(ctx);

        String str;
        while ((str = this.buffer.poll()) != null) {
            System.out.println(str);
        }

        return null;
    }

    private String nextTemporary() {
        return "%" + (this.idTemporary++);
    }

    private String nextGenerated() {
        return "#" + (this.idGenerated++);
    }

    @Override
    public RtValue visitGlobal(GrammarParser.GlobalContext ctx) {
        final String name = ctx.name.getText();
        final RtValue ret = this.visit(ctx.e);
        if (ret == null || !ret.isLit || !this.buffer.isEmpty()) {
            throw new RuntimeException("Initializer for " + name + " is not a compile-time constant");
        }

        this.buffer.add(name + ":");
        this.buffer.add("  .emit " + ret.rep);
        return null;
    }

    @Override
    public RtValue visitFunc(GrammarParser.FuncContext ctx) {
        final LinkedHashSet<String> params = new LinkedHashSet<>();
        for (final Token param : ctx.args) {
            final String name = param.getText();
            if (!params.add(name)) {
                throw new RuntimeException("Duplicate parameter name for function: " + ctx.name.getText());
            }
        }
        this.locals.addAll(params);

        final RtValue ret = this.visit(ctx.body);
        if (ret == null) {
            // Dummy return value.
            this.buffer.add("  ret 0");
        } else {
            ret.read();
            this.buffer.add("  ret " + ret.rep);
        }
        this.buffer.add("  .fn_end");

        // Add header (the function label and clearing locals to 0)
        this.locals.removeAll(params);
        for (final String local : this.locals) {
            this.buffer.push("  mov " + local + ", 0");
        }
        this.buffer.push(params.stream().collect(Collectors.joining(", ", "  .fn_start ", "")));
        this.buffer.push(ctx.name.getText() + ":");
        return null;
    }

    @Override
    public RtValue visitAtomNested(GrammarParser.AtomNestedContext ctx) {
        return this.visit(ctx.e);
    }

    @Override
    public RtValue visitAtomTrue(GrammarParser.AtomTrueContext ctx) {
        return RtValue.newLiteral(ctx.getText());
    }

    @Override
    public RtValue visitAtomFalse(GrammarParser.AtomFalseContext ctx) {
        return RtValue.newLiteral(ctx.getText());
    }

    @Override
    public RtValue visitAtomNumber(GrammarParser.AtomNumberContext ctx) {
        return RtValue.newLiteral(ctx.getText());
    }

    @Override
    public RtValue visitAtomIdentifier(GrammarParser.AtomIdentifierContext ctx) {
        final String text = ctx.name.getText();
        if (ctx.ext == null) {
            // Local variable
            return RtValue.newVariable(text, this.locals.contains(text));
        } else {
            return RtValue.newVariable(ctx.getText(), true);
        }
    }

    @Override
    public RtValue visitExpr(GrammarParser.ExprContext ctx) {
        // Note: (t) := 10; is valid, so at this point, the subexpression does
        // not need to be a valid rvalue!
        return this.visit(ctx.e);
    }

    @Override
    public RtValue visitExpr1(GrammarParser.Expr1Context ctx) {
        final RtValue base = this.visit(ctx.e);
        if (ctx.op == null) {
            return base;
        }

        final String op = ctx.op.getText();
        final String opc;
        switch (op) {
            case "!":
                opc = "not";
                break;
            case "+":
                opc = "mov";
                break;
            case "-":
                opc = "neg";
                break;
            default:
                throw new AssertionError("UNREACHABLE: " + op);
        }

        final String tmp = this.nextTemporary();
        base.read();
        this.buffer.add("  " + opc + ' ' + tmp + ", " + base.rep);
        return RtValue.newTemporary(tmp);
    }

    @Override
    public RtValue visitExpr2(GrammarParser.Expr2Context ctx) {
        final int limit = ctx.getChildCount();

        RtValue lhs = this.visit(ctx.lhs);
        if (limit == 1) {
            return lhs;
        }

        for (int i = 1; i < limit; i += 2) {
            final String op = ctx.getChild(i).getText();
            final RtValue rhs = this.visit(ctx.getChild(i + 1));

            final String opc;
            switch (op) {
                case "*":
                    opc = "mul";
                    break;
                case "/":
                    opc = "div";
                    break;
                case "\\mod":
                    opc = "mod";
                    break;
                case "\\rem":
                    opc = "rem";
                    break;
                default:
                    throw new AssertionError("UNREACHABLE: " + op);
            }

            final String tmp = this.nextTemporary();
            lhs.read();
            rhs.read();
            this.buffer.add("  " + opc + ' ' + tmp + ", " + lhs.rep + ", " + rhs.rep);
            lhs = RtValue.newTemporary(tmp);
        }

        return lhs;
    }

    @Override
    public RtValue visitExpr3(GrammarParser.Expr3Context ctx) {
        final int limit = ctx.getChildCount();

        RtValue lhs = this.visit(ctx.lhs);
        if (limit == 1) {
            return lhs;
        }

        for (int i = 1; i < limit; i += 2) {
            final String op = ctx.getChild(i).getText();
            final RtValue rhs = this.visit(ctx.getChild(i + 1));

            final String opc;
            switch (op) {
                case "+":
                    opc = "add";
                    break;
                case "-":
                    opc = "sub";
                    break;
                default:
                    throw new AssertionError("UNREACHABLE: " + op);
            }

            final String tmp = this.nextTemporary();
            lhs.read();
            rhs.read();
            this.buffer.add("  " + opc + ' ' + tmp + ", " + lhs.rep + ", " + rhs.rep);
            lhs = RtValue.newTemporary(tmp);
        }

        return lhs;
    }

    @Override
    public RtValue visitExpr4(GrammarParser.Expr4Context ctx) {
        final RtValue lhs = this.visit(ctx.lhs);
        if (ctx.op == null) {
            return lhs;
        }

        final RtValue rhs = this.visit(ctx.rhs);
        final String op = ctx.op.getText();
        switch (op) {
            case "<>":
                final String tmp = this.nextTemporary();
                lhs.read();
                rhs.read();
                this.buffer.add("  cmp " + tmp + ", " + lhs.rep + ", " + rhs.rep);
                return RtValue.newTemporary(tmp);
            default:
                throw new AssertionError("UNREACHABLE: " + op);
        }
    }

    @Override
    public RtValue visitExpr5(GrammarParser.Expr5Context ctx) {
        final RtValue lhs = this.visit(ctx.lhs);
        if (ctx.op == null) {
            return lhs;
        }

        final RtValue rhs = this.visit(ctx.rhs);
        final String op = ctx.op.getText();

        final String opc;
        switch (op) {
            case "<":
                opc = "lt";
                break;
            case ">":
                opc = "gt";
                break;
            case "<=":
                opc = "le";
                break;
            case ">=":
                opc = "ge";
                break;
            default:
                throw new AssertionError("UNREACHABLE: " + op);
        }

        final String tmp = this.nextTemporary();
        lhs.read();
        rhs.read();
        this.buffer.add("  " + opc + ' ' + tmp + ", " + lhs.rep + ", " + rhs.rep);
        return RtValue.newTemporary(tmp);
    }

    @Override
    public RtValue visitExpr6(GrammarParser.Expr6Context ctx) {
        final RtValue lhs = this.visit(ctx.lhs);
        if (ctx.op == null) {
            return lhs;
        }

        final RtValue rhs = this.visit(ctx.rhs);
        final String op = ctx.op.getText();

        final String opc;
        switch (op) {
            case "==":
                opc = "eq";
                break;
            case "!=":
                opc = "ne";
                break;
            default:
                throw new AssertionError("UNREACHABLE: " + op);
        }

        final String tmp = this.nextTemporary();
        lhs.read();
        rhs.read();
        this.buffer.add("  " + opc + ' ' + tmp + ", " + lhs.rep + ", " + rhs.rep);
        return RtValue.newTemporary(tmp);
    }

    @Override
    public RtValue visitExpr7Set(GrammarParser.Expr7SetContext ctx) {
        final RtValue dst = this.visit(ctx.dst);
        final RtValue src = this.visit(ctx.src);

        final String op = ctx.op.getText();

        final String opc;
        switch (op) {
            case ":=":
                // Note: if dst is not a valid source, then that means we are
                // creating a new local variable!
                src.read();
                dst.write();
                this.buffer.add("  mov " + dst.rep + ", " + src.rep);
                if (!dst.isSrc && !this.locals.add(dst.rep)) {
                    throw new RuntimeException("Illegal redefinition of " + dst.rep);
                }
                return RtValue.newTemporary(dst.rep);
            case "+=":
                opc = "add";
                break;
            case "-=":
                opc = "sub";
                break;
            case "*=":
                opc = "mul";
                break;
            case "/=":
                opc = "div";
                break;
            default:
                throw new AssertionError("UNREACHABLE: " + op);
        }

        dst.read();
        src.read();
        dst.write();
        this.buffer.add("  " + opc + ' ' + dst.rep + ", " + dst.rep + ", " + src.rep);
        return RtValue.newTemporary(dst.rep);
    }

    @Override
    public RtValue visitExpr7Ternary(GrammarParser.Expr7TernaryContext ctx) {
        final String outValue = this.nextGenerated();
        final String lblFalse = this.nextGenerated();
        final String lblMerge = this.nextGenerated();

        final RtValue cond = this.visit(ctx.cond);
        cond.read();
        this.buffer.add("  brz " + lblFalse + ", " + cond.rep);

        final RtValue onTrue = this.visit(ctx.vtrue);
        onTrue.read();
        this.buffer.add("  mov " + outValue + ", " + onTrue.rep);
        this.buffer.add("  br " + lblMerge);

        this.buffer.add(lblFalse + ':');
        final RtValue onFalse = this.visit(ctx.vfalse);
        onFalse.read();
        this.buffer.add("  mov " + outValue + ", " + onFalse.rep);

        this.buffer.add(lblMerge + ':');

        return RtValue.newTemporary(outValue);
    }

    @Override
    public RtValue visitExpr7Atom(GrammarParser.Expr7AtomContext ctx) {
        return this.visit(ctx.e);
    }

    @Override
    public RtValue visitExpr8CallNoArgs(GrammarParser.Expr8CallNoArgsContext ctx) {
        final String outValue = this.nextTemporary();

        final RtValue site = this.visit(ctx.site);
        site.read();
        this.buffer.add("  call " + outValue + ", " + site.rep);

        return RtValue.newTemporary(outValue);
    }

    @Override
    public RtValue visitExpr8Call(GrammarParser.Expr8CallContext ctx) {
        final StringBuilder args = new StringBuilder();
        for (ParseTree arg : ctx.head) {
            final RtValue v = this.visit(arg);
            v.read();
            args.append(", ").append(v.rep);
        }
        final RtValue last = this.visit(ctx.last);
        last.read();
        args.append(", ").append(last.rep);

        final String outValue = this.nextTemporary();
        final RtValue site = this.visit(ctx.site);
        site.read();
        this.buffer.add("  call " + outValue + ", " + site.rep + args);

        return RtValue.newTemporary(outValue);
    }

    @Override
    public RtValue visitExpr8Atom(GrammarParser.Expr8AtomContext ctx) {
        return this.visit(ctx.e);
    }

    @Override
    public RtValue visitStmtBlock(GrammarParser.StmtBlockContext ctx) {
        RtValue acc = null;
        for (ParseTree stmt : ctx.body) {
            acc = this.visit(stmt);
        }
        return acc;
    }

    @Override
    public RtValue visitStmtIfElse(GrammarParser.StmtIfElseContext ctx) {
        final String lblMerge = this.nextGenerated();
        if (ctx.onfalse == null) {
            final RtValue test = this.visit(ctx.test);
            test.read();
            this.buffer.add("  brz " + lblMerge + ", " + test.rep);
            this.visit(ctx.ontrue);
        } else {
            final String lblFalse = this.nextGenerated();

            final RtValue test = this.visit(ctx.test);
            test.read();
            this.buffer.add("  brz " + lblFalse + ", " + test.rep);

            this.visit(ctx.ontrue);
            this.buffer.add("  br " + lblMerge);

            this.buffer.add(lblFalse + ":");
            this.visit(ctx.onfalse);
        }

        this.buffer.add(lblMerge + ":");

        return null;
    }

    @Override
    public RtValue visitStmtWhileDo(GrammarParser.StmtWhileDoContext ctx) {
        final String lblStart = this.nextGenerated();
        final String lblEnd = this.nextGenerated();

        this.buffer.add(lblStart + ":");
        final RtValue test = this.visit(ctx.test);
        test.read();
        this.buffer.add("  brz " + lblEnd + ", " + test.rep);

        this.visit(ctx.body);
        this.buffer.add("  br " + lblStart);

        this.buffer.add(lblEnd + ":");

        return null;
    }

    @Override
    public RtValue visitStmtLoop(GrammarParser.StmtLoopContext ctx) {
        final String lblStart = this.nextGenerated();
        final String lblEnd = this.nextGenerated();

        if (ctx.name == null && ctx.from == null && ctx.by == null && ctx.to == null) {
            // This is a infinite loop.
            // Note: we still emit a lblEnd in case we add break and stuff in
            // the future.

            this.buffer.add(lblStart + ":");
            this.visit(ctx.body);
            this.buffer.add("  br " + lblStart);
            this.buffer.add(lblEnd + ":");
            return null;
        }

        final String loopvar;
        if (ctx.name == null) {
            loopvar = this.nextGenerated();
        } else {
            // Make sure we have this variable somewhere
            loopvar = ctx.name.getText();
            this.locals.add(loopvar);
        }

        if (ctx.from == null) {
            this.buffer.add("  mov " + loopvar + ", 1");
        } else {
            final RtValue low = this.visit(ctx.from);
            low.read();
            this.buffer.add("  mov " + loopvar + ", " + low.rep);
        }

        final String loopinc;
        if (ctx.by == null) {
            loopinc = "1";
        } else {
            loopinc = this.nextGenerated();
            final RtValue inc = this.visit(ctx.by);
            inc.read();
            this.buffer.add("  mov " + loopinc + ", " + inc.rep);
        }

        final String loopend;
        if (ctx.to != null) {
            loopend = this.nextGenerated();
            final RtValue end = this.visit(ctx.to);
            end.read();
            this.buffer.add("  mov " + loopend + ", " + end.rep);
        } else {
            loopend = null;
        }

        this.buffer.add(lblStart + ":");
        if (ctx.to != null) {
            this.buffer.add("  brgt " + lblEnd + ", " + loopvar + ", " + loopend);
        }

        this.visit(ctx.body);

        this.buffer.add("  add " + loopvar + ", " + loopvar + ", " + loopinc);
        this.buffer.add("  br " + lblStart);

        this.buffer.add(lblEnd + ":");
        return null;
    }

    @Override
    public RtValue visitStmtExpr(GrammarParser.StmtExprContext ctx) {
        // Important: all top-level expressions must be a valid source
        // (even if it's value is discarded and never used!)
        final RtValue base = this.visit(ctx.e);
        base.read();
        return base;
    }
}
