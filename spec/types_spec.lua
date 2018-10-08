local types = require "pallene.types"

describe("Pallene types", function()

    it("pretty-prints types", function()
        assert.same("{ integer }", types.tostring(types.T.Array(types.T.Integer())))
    end)

    it("checks if a type is garbage collected", function()
        assert.truthy(types.is_gc(types.T.String()))
        assert.truthy(types.is_gc(types.T.Array(types.T.Integer())))
        assert.truthy(types.is_gc(types.T.Function({}, {})))
    end)

    it("compares identical functions", function()
        local f1 = types.T.Function({types.T.String(), types.T.Integer()}, {types.T.Boolean()})
        local f2 = types.T.Function({types.T.String(), types.T.Integer()}, {types.T.Boolean()})
        assert.truthy(types.equals(f1, f2))
    end)

    it("compares functions with different arguments", function()
        local f1 = types.T.Function({types.T.String(), types.T.Boolean()}, {types.T.Boolean()})
        local f2 = types.T.Function({types.T.Integer(), types.T.Integer()}, {types.T.Boolean()})
        assert.falsy(types.equals(f1, f2))
    end)

    it("compares functions with different returns", function()
        local f1 = types.T.Function({types.T.String(), types.T.Integer()}, {types.T.Boolean()})
        local f2 = types.T.Function({types.T.String(), types.T.Integer()}, {types.T.Integer()})
        assert.falsy(types.equals(f1, f2))
    end)

    it("compares functions of different input arity", function()
        local s = types.T.String()
        local f1 = types.T.Function({}, {s})
        local f2 = types.T.Function({s}, {s})
        local f3 = types.T.Function({s, s}, {s})
        assert.falsy(types.equals(f1, f2))
        assert.falsy(types.equals(f2, f1))
        assert.falsy(types.equals(f2, f3))
        assert.falsy(types.equals(f3, f2))
        assert.falsy(types.equals(f1, f3))
        assert.falsy(types.equals(f3, f1))
    end)

    it("compares functions of different output arity", function()
        local s = types.T.String()
        local f1 = types.T.Function({s}, {})
        local f2 = types.T.Function({s}, {s})
        local f3 = types.T.Function({s}, {s, s})
        assert.falsy(types.equals(f1, f2))
        assert.falsy(types.equals(f2, f1))
        assert.falsy(types.equals(f2, f3))
        assert.falsy(types.equals(f3, f2))
        assert.falsy(types.equals(f1, f3))
        assert.falsy(types.equals(f3, f1))
    end)

end)
