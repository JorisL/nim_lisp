import std/re
import std/sugar
import std/deques
import std/strformat
import std/tables
from std/sequtils import zip
from math import sum, prod
from strutils import parseFloat, strip, startsWith, join

let primitives = ["+", "-", "*", "/", "=", "<", "do", "list", "define", "lambda", "eval", "while", "cond"]


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
        of dt_lambda:
          argument_names: seq[string]
          code: Node
        of dt_macro: macro_var: string
        of dt_error: error_var: string
    
    Environment = ref object
        t: Table[string, Node]
        has_parent: bool
        parent_environment: Environment

# TODO: convert dataflow-style environment passing into a global stack-based environment

var base_env = new(Environment)


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
    elif token in primitives:
        result = dt_primitive
    else:
        result = dt_symbol


#let source_in: string = "(do (define foo 6) (* foo 7))"
#let source_in: string = "((lambda (x) (* x x)) 5)"
let source_in: string = "(do (define x 42) ((lambda (x) (* x x)) 5) x)"


proc read_tokens(source_in: string): Deque[string] =
    var tokens = collect(newSeq):
        for token in findAll(source_in, re"""\s*([\()]|"(?:\\.|[^\\"])*"?|;.*|[^\s()";]*)\s*"""): strip(token)
    return tokens.toDeque()

var tokens = read_tokens(source_in)


proc new_num_node(num: float): Node =
    return Node(dataType: dt_number, number_var: num)

proc new_symbol_node(symbol: string): Node =
    return Node(dataType: dt_symbol, symbol_var: symbol)

proc new_list_node(data: seq[Node]): Node =
    return Node(dataType: dt_lst, list_var: data)

proc new_nil_node(): Node =
    return Node(dataType: dt_nil)

proc new_error_node(error_message: string): Node =
    return Node(dataType: dt_error, error_var: error_message)


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
        else:
            assert (1 == 0) # TODO
            return new_error_node("yada")


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
    else:
        # TODO: add more cases
        result = "yada"


proc toPlantUmlString(n: Node): string =
    "@startjson\n" & toJsonString(n) & "\n@endjson"


var ast = genAbstractSyntaxTree(tokens)

echo toPlantUmlString(ast)


#proc eval(n: Node, env: Environment): (Node, Environment)

proc subenv_create(parent_env: Environment): Environment =
    return Environment(has_parent: true, parent_environment: parent_env)

proc subenv_delete(subenv: Environment): Environment =
    assert subenv.has_parent
    return subenv.parent_environment

proc env_write(env: Environment, symbol_name: string, value: Node): Environment =
    result = env
    result.t[symbol_name] = value

# TODO: use string instead of symbol_node?
proc env_read(env: Environment, symbol_name: string): Node =
    # TODO: also try reading from parent environment
    try:
        return env.t[symbol_name]
    except KeyError:
        if env.has_parent:
            return env_read(env.parent_environment, symbol_name)
        else:
            return new_error_node(fmt"{symbol_name} not found in environment.")

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

#proc eval_equals(nodes: seq[Node]): Node =
#    # TODO: handle more cases
#    if (nodes[0].dataType == nodes[1].dataType) and (nodes[0].str == nodes[1].str) and nodes[0].num == nodes[1].num:
#        return new_symbol_node("#t")
#    else:
#        return new_nil_node()

proc eval_lt(nodes: seq[Node]): Node =
    # TODO: error handling, should exactly be 2 arguments, and both numbers
    if nodes[0].number_var < nodes[1].number_var:
        return new_symbol_node("#t")
    else:
        return new_nil_node()

# TODO: eval_buildin_function?


proc eval(n: Node, env: Environment): (Node, Environment) =
    var env = env # TODO: clean up, only define where env is modified?
    var dataType = n.dataType
    var result_node: Node
    case dataType
    of dt_lst:
        var (first_node_result, env) = eval(n.list_var[0], env)
        var first_node_result_datatype = first_node_result.dataType # TODO: simplify?
        case first_node_result_datatype
        of dt_primitive:
            var primitive = first_node_result.primitive_var
            var nodes = n.list_var[1 .. ^1]
            case primitive:
            of "+":
                result_node = eval_sum(block: collect(newSeq): (for n in nodes: eval(n,  env)[0]))
            of "-":
                result_node = eval_subtract(block: collect(newSeq): (for n in nodes: eval(n, env)[0]))
            of "*":
                result_node = eval_product(block: collect(newSeq): (for n in nodes: eval(n, env)[0]))
            of "/":
                result_node = eval_divide(block: collect(newSeq): (for n in nodes: eval(n, env)[0]))
#            of "=":
#                result_node = eval_equals(block: collect(newSeq): (for n in nodes: eval(n, env)[0]))
            of "<":
                result_node = eval_lt(block: collect(newSeq): (for n in nodes: eval(n, env)[0]))
            of "do":
                # evaluate all arguments, and return the (evaluated) last one
                # TODO: pass previous environment through each cycle
                var tmp = collect(newSeq): (for n in nodes: eval(n, env))
                result_node = tmp[^1][0]
            of "list":
                result_node = new_list_node(block: collect(newSeq): (for n in nodes: eval(n, env)[0]))
            of "define":
                # TODO: check that frist argument of define is a symbol name
                var (tmp_n, env) = eval(nodes[1], env)
                env = env_write(env, nodes[0].symbol_var, tmp_n)
                result_node = nodes[0]
            of "eval":
                # evaluate a list as code. first run eval on the first argument to get the (quoted) list,
                # and then perform eval on that returned list to evaluate the contents.
                var (tmp_n, env) = eval(nodes[0], env)
                (result_node, env) = eval(tmp_n, env)
            of "while":
                # (while cond expr)
                while true:
                    var (tmp_n, env) = eval(nodes[0], env)
                    if tmp_n.dataType != dt_nil:
                        (tmp_n, env) = eval(nodes[1], env) # TODO: discard result?
                    else:
                        break
                result_node = new_nil_node() # TODO: what to return?
            of "cond":
                # (cond (test1 expr1) (test2 expr2) ... (testn exprn)) evaluates tests from first
                # to last until test_i evaluates non-false and then returns expr_i
                result_node = new_nil_node()
                for i in 0 ..< len(nodes):
                    var (tmp_n, env) = eval(nodes[i].list_var[0], env)
                    if tmp_n.dataType != dt_nil:
                        (result_node, env) = eval(nodes[i].list_var[1], env)
                        break
            of "lambda":
                # (lambda (arg1 arg2 argn) code)
                result_node = Node(dataType: dt_lambda)
                result_node.argument_names = collect(newSeq): (for n in nodes[0].list_var: n.symbol_var)
                result_node.code = nodes[1]
            else:
                result_node = nodes[0]
        of dt_symbol:
            result_node = first_node_result # TODO
        of dt_lambda:
            var arguments = n.list_var[1 .. ^1]
            assert (len(arguments) == len(first_node_result.argument_names)) # todo: convert to generate error node
            # evaluate each argument, and write it with it's corresponding argument name to a new sub-environment
            
            for (argument_name, argument) in zip(first_node_result.argument_names, arguments):
                var (tmp_n, env) = eval(argument, env)
                env = env_write(env, argument_name, tmp_n)

            (result_node, env) = eval(first_node_result.code, subenv_create(env))
            env = subenv_delete(env)
        of dt_macro:
            result_node = first_node_result # TODO
        else:
            result_node = new_error_node("First element in a list should be a closure, primitive, or symbol after evaluation.")
    of dt_symbol:
        result_node = env_read(env, n.symbol_var)
    else:
        result_node = n
    return(result_node, env)



echo ""
let (ast_result, env_result) = eval(ast, base_env)
echo toPlantUmlString(ast_result)