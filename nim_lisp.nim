import std/re
import std/sugar
import std/deques
import std/strformat
from strutils import parseFloat, strip, startsWith, join

let primitives = ["+", "-"]


type
    DataType = enum
        dt_nil, dt_string, dt_number, dt_primitive, dt_symbol, dt_lst, dt_function, dt_macro, dt_error

    Node = ref object
        dataType: DataType
        lst: seq[Node]
        num: float
        str: string


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
    else:
        # TODO: add more cases
        result = "yada"


proc toPlantUmlString(n: Node): string =
    "@startjson\n" & toJsonString(n) & "\n@endjson"


var ast = genAbstractSyntaxTree(tokens)

echo repr(ast)

echo ""
echo ""

echo toPlantUmlString(ast)