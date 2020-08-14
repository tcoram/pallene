-- Copyright (c) 2020, The Pallene Developers
-- Pallene is licensed under the MIT license.
-- Please refer to the LICENSE and AUTHORS files for details
-- SPDX-License-Identifier: MIT

local util = require "pallene.util"

--
-- This file implements a Pallene to Lua translator.
--
-- The Pallene compiler is divided into two logical ends:
-- * The frontend which parses Pallene source code to generate AST and performs semantic analysis.
-- * The backend which generates C source code.
--
-- Both these ends are decoupled, this provides us with the flexibility to integrate another backend
-- that generates Lua. The users can run the compiler with `--emit-lua` trigger the translator to
-- generate plain Lua instead of C.
--
-- The generation of Lua is performed by a different backend (implemented here). It accepts input
-- string and the AST generated by the parser. The generator then walks over the AST to replacing
-- type annotations with white space. Interestingly spaces, newlines, comments and pretty much
-- everything else other than type annotations are retained in the translated code. Thus, the
-- formatting in the original input is preserved, which means the error messages always point to
-- the same location in both Pallene and Lua code.
--
-- Since shadowing top-level components is a syntax error in Pallene, the translator can generate
-- all the forward references at the beginning of the module. This design allows us to not worry
-- about finding empty lines, lines with comments, and so on to correctly translate mutually recursive
-- function groups.
--

local translator = {}

local Translator = util.Class()

function Translator:init(input)
    self.input = input -- string
    self.last_index = 1 -- integer
    self.partials = {} -- list of strings
    self.exports = {} -- list of strings
    return self
end

function Translator:add_previous(stop_index)
    assert(self.last_index <= stop_index + 1)
    local partial = self.input:sub(self.last_index, stop_index)
    table.insert(self.partials, partial)
    self.last_index = stop_index + 1
end

function Translator:erase_region(start_index, stop_index)
    assert(self.last_index <= start_index)
    assert(start_index <= stop_index + 1)
    self:add_previous(start_index - 1)

    local region = self.input:sub(start_index, stop_index)
    local start_pos = region:find("[\n\r][ \t]*$")
    if start_pos then
        local first_region = region:sub(1, start_pos)
        local first_partial = first_region:gsub("[^\n\r]", "")
        local last_partial = region:sub(start_pos + 1)

        table.insert(self.partials, first_partial)
        table.insert(self.partials, last_partial)
    else
        local partial = region:gsub("[^\n\r]", "")
        table.insert(self.partials, partial)
    end

    if self.input:sub(stop_index + 1, stop_index + 1) == "=" then
        table.insert(self.partials, " ")
    end

    self.last_index = stop_index + 1
end

function Translator:add_exports()
    if #self.exports > 0 then
        table.insert(self.partials, "\nreturn {\n")
        for _, export in ipairs(self.exports) do
            local pair = string.format("    %s = %s,\n", export, export)
            table.insert(self.partials, pair)
        end
        table.insert(self.partials, "}\n")
    end
end

function Translator:add_forward_declarations(prog_ast)
    table.insert(self.partials, "local string_ = string;")

    local names = {}
    for _, node in ipairs(prog_ast.tls) do
        -- Build the exports and forward declaration table.
        if node._tag == "ast.Toplevel.Var" then
            if node.visibility == "export" then
                for _, decl in ipairs(node.decls) do
                    table.insert(self.exports, decl.name)
                end
            end

            for _, decl in ipairs(node.decls) do
                table.insert(names, decl.name)
            end
        elseif node._tag == "ast.Toplevel.Func" then
            local name = node.decl.name
            table.insert(names, name)

            if node.visibility == "export" then
                table.insert(self.exports, name)
            end
        end
    end

    if #names > 0 then
        table.insert(self.partials, "local ")
        table.insert(self.partials, table.concat(names, ", "))
        table.insert(self.partials, ";")
    end
end

function translator.translate(input, prog_ast)
    local instance = Translator.new(input)
    instance:add_forward_declarations(prog_ast)

    -- Erase all type regions, while preserving comments
    -- As a sanity check, assert that the comment regions are either inside or outside the type
    -- regions, not crossing the boundaries.
    local j = 1
    local comments = prog_ast.comment_regions
    for _, region in ipairs(prog_ast.type_regions) do
        local start_index = region[1]
        local end_index   = region[2]

        -- Skip over the comments before the current region.
        while j <= #comments and comments[j][2] < start_index do
            j = j + 1
        end

        -- Preserve the comments inside the current region
        while j <= #comments and comments[j][2] <= end_index do
            assert(start_index < comments[j][1])
            instance:erase_region(start_index, comments[j][1] - 1)
            start_index = comments[j][2] + 1
            j = j + 1
        end

        -- Ensure that the next comment is outside the current region
        if j <= #comments then
            assert(end_index < comments[j][1])
        end

        instance:erase_region(start_index, end_index)
    end

    -- Whatever characters that were not included in the partials should be added.
    instance:add_previous(#input)
    instance:add_exports()

    return table.concat(instance.partials)
end

return translator
