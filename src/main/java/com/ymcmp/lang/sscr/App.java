package com.ymcmp.lang.sscr;

import java.io.IOException;

import java.nio.file.Files;
import java.nio.file.Paths;

import org.antlr.v4.runtime.CharStreams;
import org.antlr.v4.runtime.CommonTokenStream;
import org.antlr.v4.runtime.tree.ParseTree;

public class App {

    public static void main(String[] args) throws IOException {
        if (args.length == 0) {
            System.out.println("Missing file!");
            return;
        }

        final GrammarLexer lexer = new GrammarLexer(CharStreams.fromFileName(args[0]));
        final CommonTokenStream tokens = new CommonTokenStream(lexer);
        final GrammarParser parser = new GrammarParser(tokens);
        final ParseTree tree = parser.file();

        new Validator().visit(tree);
    }
}
