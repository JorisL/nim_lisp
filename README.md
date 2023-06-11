# Nim Lisp

A toy implementation of a lisp-like language written in Nim. This program is
based on my previous attempt at writing a
[lisp interpreter in LabVIEW](https://github.com/JorisL/labview_lisp), and was
written as a reason to get familiar with the Nim programming language and to
create an improved version of my previous Lisp interpreter.

One of my goals was for the language to be minimalistic, with only the bare
essential functions implemented in the compiled Nim program while other
functions and program structures implemented as functions or macros in the lisp
language itself (see `stdlib.nlisp`).

## Usage

First compile the program using `nim c nim_lisp.nim`

Then run the REPL using `.\nim_lisp`

## Examples

    (defun square (x) (* x x))
    square

    (define y (for x (range 10) (square x)))
    y

    y
    (0.0 1.0 4.0 9.0 16.0 25.0 36.0 49.0 64.0 81.0)

### Brainfuck interpreter

See `examples/bf/brainfuck.nlisp` for a proof-of-concept brainfuck interpreter
written in nim-lisp. By running this sript the functions to evalate a brainfuck
program are available.

    (run "examples/bf/brainfuck.nlisp")

    (eval_bf "++++++++++>++++++++++++++++++++++++++++++++++++++++++++++++++++.--.<." "")
    42
    nil

    (eval_bf (readfile "examples/bf/hello_world.bf") "")
    Hello World!
    nil

    (eval_bf (readfile "examples/bf/wc.bf") "Don't panic.")
    	0	2	12
    nil

For even more recursive fun it is even possible to run a brainfuck interpreter
in this brainfuck interpreter (in this lisp interpreter):

    (eval_bf (readfile "examples/bf/bf.bf") "++++++++++>++++++++++++++++++++++++++++++++++++++++++++++++++++.--.<.")
    42
    nil

Warning: this last example takes many hours to run.
