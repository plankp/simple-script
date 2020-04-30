package com.ymcmp.lang.sscr;

class RtValue {

    // Examples:
    //   10:  rep = 10,  isDst = false, isSrc = true
    //  foo:  rep = foo, isDst = true,  isSrc = is-declared?

    public final String rep;

    public final boolean isDst;
    public final boolean isSrc;
    public final boolean isLit;

    public RtValue(String rep, boolean isDst, boolean isSrc, boolean isLit) {
        this.rep = rep;
        this.isDst = isDst;
        this.isSrc = isSrc;
        this.isLit = isLit;
    }

    public static RtValue newLiteral(String rep) {
        return new RtValue(rep, false, true, true);
    }

    public static RtValue newTemporary(String rep) {
        return new RtValue(rep, false, true, false);
    }

    public static RtValue newVariable(String rep, boolean initialized) {
        return new RtValue(rep, true, initialized, false);
    }

    public void read() {
        if (!isSrc) {
            throw new RuntimeException("Illegal usage of non-rvalue " + rep);
        }
    }

    public void write() {
        if (!isDst) {
            throw new RuntimeException("Illegal usage of non-lvalue " + rep);
        }
    }
}