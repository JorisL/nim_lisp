import std/re
import std/sugar
import std/deques
import std/strformat
import std/tables
import math
from strutils import parseFloat, strip, startsWith, join

let primitives = ["+", "-", "*", "/", "=", "<", "do", "list"]


type
    DataType = enum
        dt_nil, dt_string, dt_number, dt_primitive, dt_symbol, dt_lst, dt_function, dt_macro, dt_error

    Node = ref object
        dataType: DataType
        lst: seq[Node]
        num: float
        str: string
    
    Environment = ref object
        t: Table[string, Node]
        has_parent: bool
        parent_environment: Environment


proc env_write(env: Environment, symbol: string, value: Node): Environment =
    result = env
    result.t[symbol] = value

proc env_read(env: Environment, symbol: string): Node =
    # TODO: also try reading from parent environment
    result = env.t[symbol]


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


let source_in: string = readFile("test.nlisp")


proc read_tokens(source_in: string): Deque[string] =
    var tokens = collect(newSeq):
        for token in findAll(source_in, re"""\s*([\()]|"(?:\\.|[^\\"])*"?|;.*|[^\s()";]*)\s*"""): strip(token)
    return tokens.toDeque()

var tokens = read_tokens(source_in)


proc genAbstractSyntaxTree(tokens: var Deque[string]): Node =
    # doAssert(len(tokens) >= 1)
    var n = new(Node)

    # TODO: remove comment tokens

    var token: string = tokens.popFirst()
    case token
    of "(":
        n.dataType = dt_lst
        while tokens[0] != ")":
            n.lst.add(genAbstractSyntaxTree(tokens))
        discard tokens.popFirst() # pop the trailing )
        return n
    of ")":
        raise newException(ValueError, "unexpected ')'")
    else:
        n.dataType = getTokenType(token)
        case n.dataType
        of dt_number:
            n.num = parseFloat(token)
        of dt_string:
            n.str = token.substr(1, len(token) - 2) # remove leading and trailing quotes
        else:
            n.str = token
        return n


proc toJsonString(n: Node): string =
    var dataType = n.dataType
    case dataType
    of dt_lst:
        block:
            let tmp = collect(newSeq):
                for sub_node in n.lst: "" & toJsonString(sub_node)
            result = """{"type": "list", "value": [""" & "\n" & tmp.join(",\n") & "\n]}"
    of dt_number:
        result = fmt"""{{"type": "number", "value": "{n.num}"}}"""
    of dt_string:
        result = fmt"""{{"type": "string", "value": "{n.str}"}}"""
    of dt_primitive:
        result = fmt"""{{"type": "primitive", "value": "{n.str}"}}"""
    of dt_symbol:
        result = fmt"""{{"type": "symbol", "value": "{n.str}"}}"""
    of dt_nil:
        result = fmt"""{{"type": "nil", "value": ""}}"""
    else:
        # TODO: add more cases
        result = "yada"


proc toPlantUmlString(n: Node): string =
    "@startjson\n" & toJsonString(n) & "\n@endjson"


var ast = genAbstractSyntaxTree(tokens)

echo toPlantUmlString(ast)


proc eval(n: Node): Node

proc new_num_node(num: float): Node =
    result = new(Node)
    result.dataType = dt_number
    result.num = num

proc new_symbol_node(symbol: string): Node =
    result = new(Node)
    result.dataType = dt_symbol
    result.str = symbol

proc new_list_node(data: seq[Node]): Node =
    result = new(Node)
    result.dataType = dt_lst
    result.lst = data

proc new_nil_node(): Node =
    result = new(Node)
    result.dataType = dt_nil

proc new_error_node(error_message: string): Node =
    result = new(Node)
    result.dataType = dt_error
    result.str = error_message


proc eval_sum(nodes: seq[Node]): Node =
    new_num_node(sum(block: collect(newSeq): (for n in nodes: n.num)))

proc eval_subtract(nodes: seq[Node]): Node =
    # TODO: what about more than 2 arguments?
    new_num_node(nodes[0].num - nodes[1].num)

proc eval_product(nodes: seq[Node]): Node =
    new_num_node(prod(block: collect(newSeq): (for n in nodes: n.num)))

proc eval_divide(nodes: seq[Node]): Node =
    # TODO: what about more than 2 arguments?
    new_num_node(nodes[0].num / nodes[1].num)

proc eval_equals(nodes: seq[Node]): Node =
    # TODO: handle more cases
    if (nodes[0].dataType == nodes[1].dataType) and (nodes[0].str == nodes[1].str) and nodes[0].num == nodes[1].num:
        new_symbol_node("#t")
    else:
        new_nil_node()

proc eval_lt(nodes: seq[Node]): Node =
    # TODO: error handling, should exactly be 2 arguments, and both numbers
    if nodes[0].num < nodes[1].num:
        result = new_symbol_node("#t")
    else:
        result = new_nil_node()


proc eval_primitive(primitive: string, nodes: seq[Node]): Node =
    case primitive:
    of "+":
        result = eval_sum(block: collect(newSeq): (for n in nodes: eval(n)))
    of "-":
        result = eval_subtract(block: collect(newSeq): (for n in nodes: eval(n)))
    of "*":
        result = eval_product(block: collect(newSeq): (for n in nodes: eval(n)))
    of "/":
        result = eval_divide(block: collect(newSeq): (for n in nodes: eval(n)))
    of "=":
        result = eval_equals(block: collect(newSeq): (for n in nodes: eval(n)))
    of "<":
        result = eval_lt(block: collect(newSeq): (for n in nodes: eval(n)))
    of "do":
        # evaluate all arguments, and return the (evaluated) last one
        var tmp = collect(newSeq): (for n in nodes: eval(n))
        result = tmp[^1]
    of "list":
        result = new_list_node(block: collect(newSeq): (for n in nodes: eval(n)))
    else:
        result = nodes[0]


proc eval(n: Node): Node =
    var dataType = n.dataType
    case dataType
    of dt_lst:
        var first_node_result = eval(n.lst[0])
        var first_node_result_datatype = first_node_result.dataType
        case first_node_result_datatype
        of dt_function:
            result = first_node_result # TODO
        of dt_macro:
            result = first_node_result # TODO
        of dt_primitive:
            result = eval_primitive(first_node_result.str, n.lst[1 .. ^1])
        of dt_symbol:
            result = first_node_result # TODO
        else:
            result = first_node_result # TODO
    of dt_symbol:
        result = n
    else:
        result = n



echo ""
echo toPlantUmlString(eval(ast))