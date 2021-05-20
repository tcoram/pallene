local driver = require 'pallene.driver'
local util = require 'pallene.util'

local function run_checker(code)
    -- "__test__.pln" does not exist on disk. The name is only used for error messages.
    local module, errs = driver.compile_internal("__test__.pln", code, "checker")
    return module, table.concat(errs, "\n")
end

local function assert_error(code, expected_err)
    local module, errs = run_checker(code)
    assert.falsy(module)
    assert.match(expected_err, errs, 1, true)
end

describe("Scope analysis: ", function()

    it("forbids variables from being used before they are defined", function()
        assert_error([[
            local m: module = {}
            function fn(): nil
                x = 17
                local x = 18
            end

            return m
        ]],
            "Function must be 'local' or module function")
    end)

    it("forbids type variables from being used before they are defined", function()
        assert_error([[
            local m: module = {}

            function m.fn(p: Point): integer
                return p.x
            end

            record Point
                x: integer
                y: integer
            end

            return m
        ]],
            "type 'Point' is not declared")
    end)

    it("do-end limits variable scope", function()
        assert_error([[
            local m: module = {}
            function m.fn(): nil
                do
                    local x = 17
                end
                x = 18
            end

            return m
        ]],
            "variable 'x' is not declared")
    end)

    it("forbids multiple toplevel declarations with the same name for exported functions", function()
        assert_error([[
            local m: module = {}
            function m.f() end
            function m.f() end

            return m
        ]],
            "duplicate module field 'f', previous one at line 2")
    end)

    it("forbids multiple toplevel declarations with the same name for exported function and variable", function()
        assert_error([[
            local m: module = {}
            function m.f() end
            m.f = 1
            return m
        ]],
            "duplicate module field 'f', previous one at line 2")
    end)

    it("ensure toplevel variables are not in scope in their initializers", function()
        assert_error([[
            local m: module = {}
            local a, b = 1, a
            return m
        ]],
            "variable 'a' is not declared")
    end)

    it("ensure toplevel variables are not in scope in their initializers", function()
        assert_error([[
            local m: module = {}
            local a = a
            return m
        ]],
            "variable 'a' is not declared")
    end)

    it("ensure variables are not in scope in their initializers", function()
        assert_error([[
            local m: module = {}
            local function f()
                local a, b = 1, a
            end

            return m
        ]],
            "variable 'a' is not declared")
    end)

    it("ensure variables are not in scope in their initializers", function()
        assert_error([[
            local m: module = {}
            local function f()
                local a = a
            end

            return m
        ]],
            "variable 'a' is not declared")
    end)

    it("forbids typealias to non-existent type", function()
        assert_error([[
            typealias point = foo

            local m: module = {}
            return m
        ]],
            "type 'foo' is not declared")
    end)

    it("forbids recursive typealias", function()
        assert_error([[
            typealias point = {point}

            local m: module = {}
            return m
        ]],
            "type 'point' is not declared")
    end)

    it("forbids typealias to non-type name", function()
        assert_error([[
            local m: module = {}
            typealias point = x
            local x: integer = 0
            return m
        ]],
            "type 'x' is not declared")
    end)
end)

describe("Pallene type checker", function()

    it('catches incompatible function type assignments', function()
        assert_error([[
            local m: module = {}
            function m.f(a: integer, b: float): float
                return 3.14
            end

            function m.test(g: () -> integer)
                g = m.f
            end
        ]],
        "expected function type () -> (integer) but found function type (integer, float) -> (float) in assignment")
    end)

    it("detects when a non-type is used in a type variable", function()
        assert_error([[
            local m: module = {}
            function m.fn()
                local foo: integer = 10
                local bar: foo = 11
            end

            return m
        ]],
            "'foo' is not a type")
    end)

    it("detects when a non-type is used in a type variable", function()
        assert_error([[
            local m: module = {}
            function m.fn()
                local bar: m = 11
            end

            return m
        ]],
            "'m' is not a type")
    end)

    it("detects when a non-value is used in a value variable", function()
        assert_error([[
            record Point
                x: integer
                y: integer
            end

            local m: module = {}
            function m.fn()
                local bar: integer = Point
            end

            return m
        ]],
            "'Point' isn't a value")
    end)

    it("catches table type with repeated fields", function()
        assert_error([[
            local m: module = {}
            function m.fn(t: {x: float, x: integer}) end
            return m
        ]],
            "duplicate field 'x' in table")
    end)

    it("allows tables with fields with more than LUAI_MAXSHORTLEN chars", function()
        local field = string.rep('a', 41)
        local module, _ = run_checker([[
            local m: module = {}
            function m.f(t: {]].. field ..[[: float}) end
            return m
        ]])
        assert.truthy(module)
    end)

    it("catches array expression in indexing is not an array", function()
        assert_error([[
            local m: module = {}
            function m.fn(x: integer)
                x[1] = 2
            end
            return m
        ]],
            "expected array but found integer in array indexing")
    end)

    it("catches wrong use of length operator", function()
        assert_error([[
            local m: module = {}
            function m.fn(x: integer): integer
                return #x
            end

            return m
        ]],
            "trying to take the length")
    end)

    it("catches wrong use of unary minus", function()
        assert_error([[
            local m: module = {}
            function m.fn(x: boolean): boolean
                return -x
            end

            return m
        ]],
            "trying to negate a")
    end)

    it("catches wrong use of bitwise not", function()
        assert_error([[
            local m: module = {}
            function m.fn(x: boolean): boolean
                return ~x
            end

            return m
        ]],
            "trying to bitwise negate a")
    end)

    it("catches wrong use of boolean not", function()
        assert_error([[
            local m: module = {}
            function m.fn(): boolean
                return not nil
            end

            return m
        ]],
            "expression passed to 'not' operator has type nil")
    end)

    it("catches mismatching types in locals", function()
        assert_error([[
            local m: module = {}
            function m.fn()
                local i: integer = 1
                local s: string = "foo"
                s = i
            end

            return m
        ]],
            "expected string but found integer in assignment")
    end)

    it("requires a type annotation for an uninitialized variable", function()
        assert_error([[
            local m: module = {}
            function m.fn(): integer
                local x
                x = 10
                return x
            end
            return m
        ]], "uninitialized variable 'x' needs a type annotation")
    end)

    it("catches mismatching types in arguments", function()
        assert_error([[
            local m: module = {}
            function m.fn(i: integer, s: string): integer
                s = i
            end
            return m
        ]],
            "expected string but found integer in assignment")
    end)

    it("forbids empty array (without type annotation)", function()
        assert_error([[
            local m: module = {}
            function m.fn()
                local xs = {}
            end
            return m
        ]],
            "missing type hint for initializer")
    end)

    it("forbids non-empty array (without type annotation)", function()
        assert_error([[
            local m: module = {}
            function m.fn()
                local xs = {10, 20, 30}
            end
            return m
        ]],
            "missing type hint for initializer")
    end)

    it("forbids array initializers with a table part", function()
        assert_error([[
            local m: module = {}
            function m.fn()
                local xs: {integer} = {10, 20, 30, x=17}
            end
            return m
        ]],
            "named field 'x' in array initializer")
    end)

    it("forbids wrong type in array initializer", function()
        assert_error([[
            local m: module = {}
            function m.fn()
                local xs: {integer} = {10, "hello"}
            end
            return m
        ]],
            "expected integer but found string in array initializer")
    end)

    it("type checks the iterator function in for-in loops", function()
        assert_error([[
            local m: module = {}
            function m.fn()
                for k, v in 5, 1, 2 do
                    local a = k + v
                end
            end
            return m
        ]],
        "expected function type (any, any) -> (any, any) but found integer in loop iterator")

        assert_error([[
            local m: module = {}

            function m.foo(a: integer, b: integer): integer
                return a * b
            end

            function m.fn()
                for k, v in m.foo, 1, 2 do
                    local a = k + v
                end
            end
        ]], "expected 1 variable(s) in for loop but found 2")
    end)

    it("type checks the state and control values of for-in loops", function()
        assert_error([[
            local m: module = {}
            function m.foo(): (integer, integer)
                return 1, 2
            end

            function m.iter(a: any, b: any): (any, any)
                return 1, 2
            end

            function m.fn()
                for k, v in m.iter, m.foo() do
                    local a = k + v
                end
            end
            return m
        ]],
        "expected any but found integer in loop state value")

        assert_error([[
            local m: module = {}
            function m.iter(a: any, b: any): (any, any)
                return 1, 2
            end

            function m.fn()
                for k, v in m.iter do
                    k = v
                end
            end
            return m
        ]], "missing state variable in for-in loop")

        assert_error([[
            local m: module = {}
            function m.iter(a: any, b: any): (any, any)
                return 1, 2
            end

            function m.x_ipairs(): ((any, any) -> (any, any), integer)
                return m.iter, 4
            end

            function m.fn()
                for k, v in m.x_ipairs() do
                    k = v
                end
            end
            return m
        ]], "missing control variable in for-in loop")
    end)

    it("checks loops with ipairs.", function()
        assert_error([[
            local m: module = {}
            function m.fn()
                for i: integer in ipairs() do
                    local x = i
                end
            end
            return m
        ]], "function expects 1 argument(s) but received 0")

        assert_error([[
            local m: module = {}
            function m.fn()
                for i, x in ipairs({1, 2}, {3, 4}) do
                    local k = i
                end
            end
            return m
        ]], "function expects 1 argument(s) but received 2")

        assert_error([[
            local m: module = {}
            function m.fn()
                for i, x, z in ipairs({1, 2}) do
                    local k = z
                end
            end
            return m
        ]], "expected 2 variable(s) in for loop but found 3")

        assert_error([[
            local m: module = {}
            function m.fn()
                for i in ipairs({1, 2}) do
                    local k = z
                end
            end
            return m
        ]], "expected 2 variable(s) in for loop but found 1")
    end)


    describe("table/record initalizer", function()
        local function assert_init_error(typ, code, err)
            typ = typ and (": " .. typ) or ""
            assert_error([[
                local m: module = {}
                record Point x: float; y:float end

                function m.f(): float
                    local p ]].. typ ..[[ = ]].. code ..[[
                end
                return m
            ]], err)
        end

        it("forbids creation without type annotation", function()
            assert_init_error(nil, [[ { x = 10.0, y = 20.0 } ]],
                "missing type hint for initializer")
        end)

        for _, typ in ipairs({"{ x: float, y: float }", "Point"}) do

            it("forbids wrong type in initializer", function()
                assert_init_error(typ, [[ { x = 10.0, y = "hello" } ]],
                    "expected float but found string in table initializer")
            end)

            it("forbids wrong field name in initializer", function()
                assert_init_error(typ, [[ { x = 10.0, y = 20.0, z = 30.0 } ]],
                    "invalid field 'z' in table initializer for " .. typ)
            end)

            it("forbids array part in initializer", function()
                assert_init_error(typ, [[ { x = 10.0, y = 20.0, 30.0 } ]],
                    "table initializer has array part")
            end)

            it("forbids initializing a field twice", function()
                assert_init_error(typ, [[ { x = 10.0, x = 11.0, y = 20.0 } ]],
                    "duplicate field 'x' in table initializer")
            end)

            it("forbids missing fields in initializer", function()
                assert_init_error(typ, [[ { y = 1.0 } ]],
                    "required field 'x' is missing")
            end)
        end
    end)

    it("forbids type hints that are not array, tables, or records", function()
        assert_error([[
            local m: module = {}
            function m.fn()
                local p: string = { 10, 20, 30 }
            end
            return m
        ]],
            "type hint for initializer is not an array, table, or record type")
    end)

    it("requires while statement conditions to be boolean", function()
        assert_error([[
            local m: module = {}
            function m.fn(x:integer): integer
                while x do
                    return 10
                end
                return 20
            end
            return m
        ]],
            "expression passed to while loop condition has type integer")
    end)

    it("requires repeat statement conditions to be boolean", function()
        assert_error([[
            local m: module = {}
            function m.fn(x:integer): integer
                repeat
                    return 10
                until x
                return 20
            end
            return m
        ]],
            "expression passed to repeat-until loop condition has type integer")
    end)

    it("requires if statement conditions to be boolean", function()
        assert_error([[
            local m: module = {}
            function m.fn(x:integer): integer
                if x then
                    return 10
                else
                    return 20
                end
            end
            return m
        ]],
            "expression passed to if statement condition has type integer")
    end)

    it("ensures numeric 'for' variable has number type", function()
        assert_error([[
            local m: module = {}
            function m.fn(x: integer, s: string): integer
                for i: string = "hello", 10, 2 do
                    x = x + i
                end
                return x
            end
            return m
        ]],
            "expected integer or float but found string in for-loop control variable 'i'")
    end)

    it("catches 'for' errors in the start expression", function()
        assert_error([[
            local m: module = {}
            function m.fn(x: integer, s: string): integer
                for i:integer = s, 10, 2 do
                    x = x + i
                end
                return x
            end
            return m
        ]],
            "expected integer but found string in numeric for-loop initializer")
    end)

    it("catches 'for' errors in the limit expression", function()
        assert_error([[
            local m: module = {}
            function m.fn(x: integer, s: string): integer
                for i = 1, s, 2 do
                    x = x + i
                end
                return x
            end
            return m
        ]],
            "expected integer but found string in numeric for-loop limit")
    end)

    it("catches 'for' errors in the step expression", function()
        assert_error([[
            local m: module = {}
            function m.fn(x: integer, s: string): integer
                for i = 1, 10, s do
                    x = x + i
                end
                return x
            end
            return m
        ]],
            "expected integer but found string in numeric for-loop step")
    end)

    it("detects too many return values", function()
        assert_error([[
            local m: module = {}
            function m.f(): ()
                return 1
            end
            return m
        ]],
            "returning 1 value(s) but function expects 0")
    end)

    it("detects too few return values", function()
        assert_error([[
            local m: module = {}
            function m.f(): integer
                return
            end
            return m
        ]],
            "returning 0 value(s) but function expects 1")
    end)

    it("detects too many return values when returning a function call", function()
        assert_error([[
            local m: module = {}
            local function f(): (integer, integer)
                return 1, 2
            end

            function m.g(): integer
                return f()
            end
            return m
        ]],
            "returning 2 value(s) but function expects 1")
    end)

    it("detects when a function returns the wrong type", function()
        assert_error([[
            local m: module = {}
            function m.fn(): integer
                return "hello"
            end
            return m
        ]],
            "expected integer but found string in return statement")
    end)

    it("rejects void functions in expression contexts", function()
        assert_error([[
            local m: module = {}
            local function f(): ()
            end

            local function g(): integer
                return 1 + f()
            end
            return m
        ]],
            "void instead of a number")
    end)

    it("detects attempts to call non-functions", function()
        assert_error([[
            local m: module = {}
            function m.fn(): integer
                local i: integer = 0
                i()
            end
            return m
        ]],
            "attempting to call a integer value")
    end)

    it("detects wrong number of arguments to functions", function()
        assert_error([[
            local m: module = {}
            function m.f(x: integer, y: integer): integer
                return x + y
            end

            function m.g(): integer
                return m.f(1)
            end
            return m
        ]],
            "function expects 2 argument(s) but received 1")
    end)

    it("detects too few arguments when expanding a function", function()
        assert_error([[
            local m: module = {}
            function m.f(): (integer, integer)
                return 1, 2
            end

            function m.g(x:integer, y:integer, z:integer): integer
                return x + y
            end

            function m.test(): integer
                return m.g(m.f())
            end
            return m
        ]],
            "function expects 3 argument(s) but received 2")
    end)

    it("detects too many arguments when expanding a function", function()
        assert_error([[
            local m: module = {}
            function m.f(): (integer, integer)
                return 1, 2
            end

            function m.g(x:integer): integer
                return x
            end

            function m.test(): integer
                return m.g(m.f())
            end
            return m
        ]],
            "function expects 1 argument(s) but received 2")
    end)

    it("detects wrong types of arguments to functions", function()
        assert_error([[
            local m: module = {}
            function m.f(x: integer, y: integer): integer
                return x + y
            end

            function m.g(): integer
                return m.f(1.0, 2.0)
            end
            return m
        ]],
            "expected integer but found float in argument 1 of call to function")
    end)

    describe("concatenation", function()
        for _, typ in ipairs({"boolean", "nil", "{ integer }"}) do
            local err_msg = string.format(
                "cannot concatenate with %s value", typ)
            local test_program = util.render([[
                local m: module = {}
                function m.fn(x : $typ) : string
                    return "hello " .. x
                end
                return m
            ]], { typ = typ })

            it(err_msg, function()
                assert_error(test_program, err_msg)
            end)
        end
    end)


    local function optest(err_template, program_template, opts)
        local err_msg = util.render(err_template, opts)
        local test_program = util.render(program_template, opts)
        it(err_msg, function()
            assert_error(test_program, err_msg)
        end)
    end

    describe("equality:", function()
        local ops = { "==", "~=" }
        local typs = {
            "integer", "boolean", "float", "string", "{ integer }", "{ float }",
            "{ x: float }"
        }
        for _, op in ipairs(ops) do
            for _, t1 in ipairs(typs) do
                for _, t2 in ipairs(typs) do
                    if not (t1 == t2) and
                        not (t1 == "integer" and t2 == "float") and
                        not (t1 == "float" and t2 == "integer")
                    then
                        optest("cannot compare $t1 and $t2 using $op", [[
                            local m: module = {}
                            function m.fn(a: $t1, b: $t2): boolean
                                return a $op b
                             end
                            return m
                        ]], {
                            op = op, t1 = t1, t2 = t2
                        })
                    end
                end
            end
        end
    end)

    describe("and/or:", function()
        for _, op in ipairs({"and", "or"}) do
            for _, t in ipairs({"{ integer }", "integer", "string"}) do
                for _, test in ipairs({
                    { "left", t, "boolean" },
                    { "right", "boolean", t },
                }) do
                    local dir, t1, t2 = test[1], test[2], test[3]
                    optest(
       "$dir hand side of '$op' has type $t", [[
                        local m: module = {}
                        function m.fn(x: $t1, y: $t2) : boolean
                            return x $op y
                        end
                        return m
                    ]], { op = op, t = t, dir = dir, t1 = t1, t2=t2 })
                end
            end
        end
    end)

    describe("bitwise:", function()
        for _, op in ipairs({"|", "&", "<<", ">>"}) do
            for _, t in ipairs({"{ integer }", "boolean", "string"}) do
                for _, test in ipairs({
                    { "left", t, "integer" },
                    { "right", "integer", t },
                }) do
                    local dir, t1, t2 = test[1], test[2], test[3]
                    optest(
        "$dir hand side of bitwise expression is a $t instead of an integer", [[
                        local m: module = {}
                        function m.fn(a: $t1, b: $t2): integer
                            return a $op b
                        end
                        return m
                    ]], { op = op, t = t, dir = dir, t1 = t1, t2 = t2 })
                end
            end
        end
    end)

    describe("arithmetic:", function()
        for _, op in ipairs({"+", "-", "*", "//", "/", "^"}) do
            for _, t in ipairs({"{ integer }", "boolean", "string"}) do
                for _, test in ipairs({
                    { "left", t, "float" },
                    { "right", "float", t },
                }) do
                    local dir, t1, t2 = test[1], test[2], test[3]
                    optest(
        "$dir hand side of arithmetic expression is a $t instead of a number", [[
                        local m: module = {}
                        function m.fn(a: $t1, b: $t2) : float
                            return a $op b
                        end
                        return m
                    ]], { op = op, t = t, dir = dir, t1 = t1, t2 = t2} )
                end
            end
        end
    end)

    describe("dot", function()
        local function assert_dot_error(typ, code, err)
            assert_error([[
                record Point x: float; y:float end

                local m: module = {}
                function m.f(p: ]].. typ ..[[): float
                    ]].. code ..[[
                end
                return m
            ]], err)
        end

        it("doesn't typecheck read/write to non indexable type", function()
            local err = "trying to access a member of value of type 'string'"
            assert_dot_error("string", [[ ("t").x = 10 ]], err)
            assert_dot_error("string", [[ local x = ("t").x ]], err)
        end)

        for _, typ in ipairs({"{ x: float, y: float }", "Point"}) do
            it("doesn't typecheck read/write to non existent fields", function()
                local err = "field 'nope' not found in type '".. typ .."'"
                assert_dot_error(typ, [[ p.nope = 10 ]], err)
                assert_dot_error(typ, [[ return p.nope ]], err)
            end)

            it("doesn't typecheck read/write with invalid types", function()
                assert_dot_error(typ, [[ p.x = p ]],
                    "expected float but found ".. typ .." in assignment")
                assert_dot_error(typ, [[ local p: ]].. typ ..[[ = p.x ]],
                    "expected ".. typ .." but found float in declaration")
            end)
        end
    end)

    describe("casting:", function()
        local typs = {
            "boolean", "float", "integer", "nil", "string",
            "{ integer }", "{ float }", "{ x: float }",
        }
        for _, t1 in ipairs(typs) do
            for _, t2 in ipairs(typs) do
                if t1 ~= t2 then
                    optest("expected $t2 but found $t1 in cast expression", [[
                        local m: module = {}
                        function m.fn(a: $t1) : $t2
                            return a as $t2
                        end
                        return m
                    ]], { t1 = t1, t2 = t2 })
                end
            end
        end
    end)

    it("catches assignment to function", function ()
        assert_error([[
            local m: module = {}
            function m.f()
            end

            function m.g()
                m.f = m.g
            end
            return m
        ]],
        --"attempting to assign to toplevel constant function 'f'")
        "type error: Can't assign module field to 'function type () -> ()'")
    end)

    it("catches assignment to builtin (with correct type)", function ()
        assert_error([[
            local m: module = {}
            function m.f(x: string)
            end

            function m.g()
                io.write = m.f
            end
            return m
        ]],
        "attempting to assign to builtin function io.write")
    end)

    it("catches assignment to builtin (with wrong type)", function ()
        assert_error([[
            local m: module = {}
            function m.f(x: integer)
            end

            function m.g()
                io.write = m.f
            end
            return m
        ]],
        "attempting to assign to builtin function io.write")
    end)

    it("typechecks io.write (error)", function()
        assert_error([[
            local m: module = {}
            function m.f()
                io.write(17)
            end
            return m
        ]],
        "expected string but found integer in argument 1")
    end)

    it("checks assignment variables to modules", function()
        assert_error([[
            local m: module = {}
            function m.f()
                local x = io
            end
            return m
        ]],
        "cannot reference module name 'io' without dot notation")
    end)

    it("checks assignment of modules", function()
        assert_error([[
            local m: module = {}
            function m.f()
                io = 1
            end
            return m
        ]],
        "cannot reference module name 'io' without dot notation")
    end)
    it("check if module variable is not declared", function()
        assert_error([[
            local function f()
                local x = 2.5
            end
        ]],
        "type error: Program has no module variable")
    end)
    it("forbid declarion of two module variables", function()
        assert_error([[
            local m: module = {}
            local n: module = {}
            function m.f()
                local x = 2.5
            end
            return m
        ]],
        "type error: There can only be one module variable per program")
    end)
    it("forbid return of more than one variable", function()
        assert_error([[
            local m: module = {}
            local i: integer = 2
            function m.f()
                local x = 2.5
            end
            return m, n
        ]],
        "type error: returning 2 value(s) but function expects 1")
    end)
    it("forbid return of any variable of type other then module", function()
        assert_error([[
            local m: module = {}
            local i: integer = 2
            function m.f()
                local x = 2.5
            end
            return i
        ]],
        "type error: expected module but found integer in return statement")
    end)
    it("forbid assignment of Record as module field", function()
        assert_error([[
            record Point
                x: integer
                y: integer
            end
            local p: Point = {x = 12, y = 7}
            local m: module = {}
            m.p = p
            return m
        ]],
        "type error: Can't assign module field to 'Point'")
    end)
    it("forbid assignment of Array as module field", function()
        assert_error([[
            local arr: {integer} = {1, 2, 6, -10}
            local m: module = {}
            m.arr = arr
            return m
        ]],
        "type error: Can't assign module field to '{ integer }'")
    end)
    it("forbid assignment of any as module field", function()
        assert_error([[
            local a: any
            local m: module = {}
            m.a = a
            return m
        ]],
        "type error: Can't assign module field to 'any'")
    end)
    it("forbid empty program", function()
        assert_error([[]], "type error: Empty modules are not permitted")
    end)
end)
