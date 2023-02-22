import std/re
import std/sugar
import std/deques
import std/strformat
import std/tables
from std/sequtils import zip
from math import sum, prod
from strutils import parseFloat, strip, startsWith, join

let primitives = ["+", "-", "*", "/", "==", "<", "do", "list", "define", "lambda", "macro", "eval", "while", "cond", "input", "parse", "print", "macro", "quote", "quasiquote", "unquote", "readfile", "len", "nth", "nthrest"]

type
    DataType = enum
        dt_nil, dt_string, dt_number, dt_primitive, dt_symbol, dt_lst, dt_lambda, dt_macro, dt_error

    # use "object variants" to store different types of data depending on the datatype the node represents
    # TODO: group objects? as seen in https://nim-lang.org/docs/manual.html#types-object-variants
    Node = ref object
        case dataType: DataType
        of dt_lst: list_var: seq[Node]
        of dt_number: number_var: float
        of dt_nil: nil_var: string # TODO change
        of dt_string: string_var: string
        of dt_primitive: primitive_var: string
        of dt_symbol: symbol_var: string
        of dt_lambda, dt_macro:
          argument_names: seq[string]
          code: Node
        of dt_error: error_var: string

    Environment = object
        t: Table[string, Node]
        has_parent_env: bool
        parent_env: ref Environment


proc new_num_node(num: float): Node =
    return Node(dataType: dt_number, number_var: num)

proc new_string_node(text: string): Node =
    return Node(dataType: dt_string, string_var: text)

proc new_symbol_node(symbol: string): Node =
    return Node(dataType: dt_symbol, symbol_var: symbol)

proc new_list_node(data: seq[Node]): Node =
    return Node(dataType: dt_lst, list_var: data)

proc new_nil_node(): Node =
    return Node(dataType: dt_nil)

proc new_error_node(error_message: string): Node =
    return Node(dataType: dt_error, error_var: error_message)


proc `==`(n1, n2: Node): bool =
    result = n1.dataType == n2.dataType
    if result:
        case n1.dataType
        of dt_number:
            result = n1.number_var == n2.number_var
        of dt_string:
            result = n1.string_var == n2.string_var
        of dt_symbol:
            result = n1.symbol_var == n2.symbol_var
        of dt_nil:
            result = true # nil == nil -> true
        of dt_lst:
            assert 1 == 0 # TODO
        else:
            assert 1 == 0 # TODO


proc to_string(self: Node): string =
    case self.dataType
    of dt_number:
        return fmt"{self.number_var}"
    of dt_string:
        return "\"" & fmt"{self.string_var}" & "\""
    of dt_symbol:
        return self.symbol_var
    of dt_nil:
        return "nil"
    of dt_error:
        return fmt"Error: {self.error_var}"
    of dt_lst:
        return "(" & join(block: collect(newSeq): (for n in self.list_var: to_string(n)), " ") & ")"
    else:
        return fmt"Error: printing for data of type {self.dataType} not implemented."


proc set(self: ref Environment, name: string, value: Node) =
    self.t[name] = value

proc get(self: ref Environment, name: string): Node =
    try:
        return self.t[name]
    except KeyError:
        if self.has_parent_env:
            return self.parent_env.get(name)
        else:
            return new_error_node(fmt"{name} not found in environment")

proc new_subenv(parent_env: ref Environment): ref Environment =
    var subenv: ref Environment
    new(subenv)
    subenv.has_parent_env = true
    subenv.parent_env = parent_env
    return subenv


proc isValidNumber(str: string): bool =
    try:
        var x = parseFloat(str)
        result = true
    except ValueError as e:
        result = false


proc getTokenType(token: string): DataType =
    if match(token, re("\".*\"")):
        result = dt_string
    elif isValidNumber(token):
        result = dt_number
    elif token == "nil":
        result = dt_nil
    elif token in primitives:
        result = dt_primitive
    else:
        result = dt_symbol


proc read_tokens(source_in: string): Deque[string] =
    var tokens = collect(newSeq):
        for token in findAll(source_in, re"""\s*([\()]|"(?:\\.|[^\\"])*"?|;.*|[^\s()";]*)\s*"""): strip(token)
    return tokens.toDeque()


proc genAbstractSyntaxTree(tokens: var Deque[string]): Node =
    # doAssert(len(tokens) >= 1)

    # TODO: remove comment tokens

    var token: string = tokens.popFirst()
    case token
    of "(":
        var n = Node(dataType: dt_lst)
        while tokens[0] != ")":
            n.list_var.add(genAbstractSyntaxTree(tokens))
        discard tokens.popFirst() # pop the trailing )
        return n
    of ")":
        raise newException(ValueError, "unexpected ')'")
    else:
        case getTokenType(token)
        of dt_number:
            var n = Node(dataType: dt_number)
            n.number_var = parseFloat(token)
            return n
        of dt_string:
            var n = Node(dataType: dt_string)
            n.string_var = token.substr(1, len(token) - 2) # remove leading and trailing quotes
            return n
        of dt_primitive:
            var n = Node(dataType: dt_primitive)
            n.primitive_var = token
            return n
        of dt_symbol:
            var n = Node(dataType: dt_symbol)
            n.symbol_var = token
            return n
        of dt_nil:
            var n = Node(dataType: dt_nil)
            return n
        else:
            assert (1 == 0) # TODO
            return new_error_node("yada")


proc read(source_in: string): Node =
    var tokens = read_tokens(source_in)
    return genAbstractSyntaxTree(tokens)


proc toJsonString(n: Node): string =
    var dataType = n.dataType
    case dataType
    of dt_lst:
        block:
            let tmp = collect(newSeq):
                for sub_node in n.list_var: "" & toJsonString(sub_node)
            result = """{"type": "list", "value": [""" & "\n" & tmp.join(",\n") & "\n]}"
    of dt_number:
        result = fmt"""{{"type": "number", "value": "{n.number_var}"}}"""
    of dt_string:
        result = fmt"""{{"type": "string", "value": "{n.string_var}"}}"""
    of dt_primitive:
        result = fmt"""{{"type": "primitive", "value": "{n.primitive_var}"}}"""
    of dt_symbol:
        result = fmt"""{{"type": "symbol", "value": "{n.symbol_var}"}}"""
    of dt_nil:
        result = fmt"""{{"type": "nil", "value": ""}}"""
    of dt_lambda:
        result = fmt"""{{"type": "lambda", "arguments": "[{join(n.argument_names, ",")}]", "code": {toJsonString(n.code)}}}""" # TODO: fix argument names
    of dt_macro:
        result = fmt"""{{"type": "macro", "arguments": "[{join(n.argument_names, ",")}]", "code": {toJsonString(n.code)}}}""" # TODO: fix argument names
    else:
        # TODO: add more cases
        result = "yada"


proc toPlantUmlString(n: Node): string =
    "@startjson\n" & toJsonString(n) & "\n@endjson"


proc eval_sum(nodes: seq[Node]): Node =
    return new_num_node(sum(block: collect(newSeq): (for n in nodes: n.number_var)))

proc eval_subtract(nodes: seq[Node]): Node =
    # TODO: what about more than 2 arguments?
    return new_num_node(nodes[0].number_var - nodes[1].number_var)

proc eval_product(nodes: seq[Node]): Node =
    return new_num_node(prod(block: collect(newSeq): (for n in nodes: n.number_var)))

proc eval_divide(nodes: seq[Node]): Node =
    # TODO: what about more than 2 arguments?
    return new_num_node(nodes[0].number_var / nodes[1].number_var)

proc eval_equals(nodes: seq[Node]): Node =
    # TODO: handle more cases
    assert len(nodes) == 2
    if nodes[0] == nodes[1]:
        return new_symbol_node("#t")
    else:
        return new_nil_node()

proc eval_lt(nodes: seq[Node]): Node =
    # TODO: error handling, should exactly be 2 arguments, and both numbers
    if nodes[0].number_var < nodes[1].number_var:
        return new_symbol_node("#t")
    else:
        return new_nil_node()

# TODO: eval_buildin_function?
proc eval(n: Node, env: ref Environment): Node


proc quasiquote_eval(n: Node, env: ref Environment): Node = 
    return new_list_node(block: collect(newSeq): 
        for sub_n in n.list_var:
            if sub_n.dataType == dt_lst:
                if sub_n.list_var[0].dataType == dt_primitive: # TODO: convert to try catch statement
                    if sub_n.list_var[0].primitive_var == "unquote":
                        eval(sub_n.list_var[1], env)
                    else:
                        quasiquote_eval(sub_n, env)
                else:
                     quasiquote_eval(sub_n, env)
            else:
                sub_n
     )


proc macro_quasiquote_expand(n: Node, env: ref Environment): Node = 
    return new_list_node(block: collect(newSeq): 
        for sub_n in n.list_var:
            if sub_n.dataType == dt_lst:
                if sub_n.list_var[0].dataType == dt_primitive: # TODO: convert to try catch statement
                    if sub_n.list_var[0].primitive_var == "unquote":
                        env.get(sub_n.list_var[1].symbol_var) # TODO: error handling, what if not defined
                    else:
                        macro_quasiquote_expand(sub_n, env)
                else:
                     macro_quasiquote_expand(sub_n, env)
            else:
                sub_n
     )


proc eval(n: Node, env: ref Environment): Node =
    var dataType = n.dataType
    var result_node: Node
    case dataType
    of dt_lst:
        var first_node_result = eval(n.list_var[0], env)
        var first_node_result_datatype = first_node_result.dataType # TODO: simplify?
        case first_node_result_datatype
        of dt_primitive:
            var primitive = first_node_result.primitive_var
            var nodes = n.list_var[1 .. ^1]
            case primitive:
            of "+":
                result_node = eval_sum(block: collect(newSeq): (for n in nodes: eval(n,  env)))
            of "-":
                result_node = eval_subtract(block: collect(newSeq): (for n in nodes: eval(n, env)))
            of "*":
                result_node = eval_product(block: collect(newSeq): (for n in nodes: eval(n, env)))
            of "/":
                result_node = eval_divide(block: collect(newSeq): (for n in nodes: eval(n, env)))
            of "==":
                result_node = eval_equals(block: collect(newSeq): (for n in nodes: eval(n, env)))
            of "<":
                result_node = eval_lt(block: collect(newSeq): (for n in nodes: eval(n, env)))
            of "do":
                # evaluate all arguments, and return the (evaluated) last one
                # TODO: pass previous environment through each cycle
                var tmp = collect(newSeq): (for n in nodes: eval(n, env))
                result_node = tmp[^1]
            of "list":
                result_node = new_list_node(block: collect(newSeq): (for n in nodes: eval(n, env)))
            of "define":
                # TODO: check that frist argument of define is a symbol name
                var tmp_n = eval(nodes[1], env)
                env.set(nodes[0].symbol_var, tmp_n)
                result_node = nodes[0]
            of "eval":
                # evaluate a list as code. first run eval on the first argument to get the (quoted) list,
                # and then perform eval on that returned list to evaluate the contents.
                var tmp_n = eval(nodes[0], env)
                result_node = eval(tmp_n, env)
            of "while":
                # (while cond expr)
                while true:
                    var tmp_n = eval(nodes[0], env)
                    if tmp_n.dataType != dt_nil:
                        tmp_n = eval(nodes[1], env) # TODO: discard result?
                    else:
                        break
                result_node = new_nil_node() # TODO: what to return?
            of "cond":
                # (cond (test1 expr1) (test2 expr2) ... (testn exprn)) evaluates tests from first
                # to last until test_i evaluates non-false and then returns expr_i
                result_node = new_nil_node()
                for i in 0 ..< len(nodes):
                    var tmp_n = eval(nodes[i].list_var[0], env)
                    if tmp_n.dataType != dt_nil:
                        result_node = eval(nodes[i].list_var[1], env)
                        break
            of "lambda":
                # (lambda (arg1 arg2 argn) code)
                result_node = Node(dataType: dt_lambda)
                result_node.argument_names = collect(newSeq): (for n in nodes[0].list_var: n.symbol_var)
                result_node.code = nodes[1]
            of "macro":
                # (macro (arg1 arg2 argn) code)
                result_node = Node(dataType: dt_macro)
                result_node.argument_names = collect(newSeq): (for n in nodes[0].list_var: n.symbol_var)
                result_node.code = nodes[1]
            of "input":
                # read from stdin
                result_node = new_string_node(readLine(stdin))
            of "parse":
                # eval argument and parse text into an AST
                result_node = read(eval(nodes[0], env).string_var)
            of "print":
                # eval argument and print text to the stdout
                result_node = eval(nodes[0], env)
                echo to_string(result_node)
            of "quote":
                # return the first argument without any evaluation
                result_node = nodes[0]
            of "quasiquote":
                result_node = quasiquote_eval(nodes[0], env) # TODO: check if correctly done
            of "readfile":
                let filename = eval(nodes[0], env).string_var
                result_node = new_string_node(readFile(filename))
            of "len":
                # (len lst): return number of items in list lst
                result_node = new_num_node(float(len(eval(nodes[0], env).list_var)))
            of "nth":
                # (nth n lst) return the n-th item in list lst
                try:
                    result_node = eval(nodes[1], env).list_var[int(eval(nodes[0], env).number_var)]
                except IndexDefect:
                    result_node = new_nil_node()
            of "nthrest":
                # (nthrest n list): return list[n+1:end]
                try:
                    result_node = new_list_node(eval(nodes[1], env).list_var[int(eval(nodes[0], env).number_var)+1 .. ^1])
                except IndexDefect:
                    result_node = new_nil_node()
            else:
                assert 1 == 0 # TODO
                result_node = nodes[0]
        of dt_lambda:
            var arguments = n.list_var[1 .. ^1]
            assert (len(arguments) == len(first_node_result.argument_names)) # todo: convert to generate error node
            # evaluate each argument, and write it with it's corresponding argument name to a new sub-environment
            var subenv = new_subenv(env)
            for (argument_name, argument) in zip(first_node_result.argument_names, arguments):
                var tmp_n = eval(argument, env) # TODO: evaluate in env or subenv?
                subenv.set(argument_name, tmp_n)
            result_node = eval(first_node_result.code, subenv)
        of dt_macro:
            var arguments = n.list_var[1 .. ^1]
            assert (len(arguments) == len(first_node_result.argument_names)) # todo: convert to generate error node
            # create a new scope, and bind the unevaluated arguments to the macro arguments
            var subenv = new_subenv(env)
            for (argument_name, argument) in zip(first_node_result.argument_names, arguments):
                subenv.set(argument_name, argument)
            # evaluate the macro code using the subenv to expand into a list of code to execute
            # echo toPlantUmlString(first_node_result.code)
            var tmp_n = macro_quasiquote_expand(first_node_result.code, subenv)
            # evaluate this expanded list as code in the "regular" environment
            result_node = eval(eval(tmp_n, env), env) # TODO: check
        else:
            result_node = new_error_node("First element in a list should be a closure, primitive, or macro after evaluation.")
    of dt_symbol:
        # result_node = env.get(n.symbol_var)
        result_node = eval(env.get(n.symbol_var), env) # TODO: workaround if element in environment is, for example, a list. is this correct way to handle this? seems to be issue when using macro's
    else:
        result_node = n
    return result_node


var env = new(Environment)
env.has_parent_env = false

let source_in: string = """
(do
 (eval (parse (readfile "stdlib.nlisp")))
 (while 1 (print (eval (parse (input)))))
)
"""

var ast = read(source_in)
#echo toPlantUmlString(ast)
#echo ""

let ast_result = eval(ast, env)

echo ""
echo toPlantUmlString(ast_result)