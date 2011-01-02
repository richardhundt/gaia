require"kudu.grammar"
require"gaia.codegen"
require"gaia.util"

module("kudu.compiler", package.seeall)

local gen = gaia.codegen

local Chunk, Block, Op, Ops = gen.Chunk, gen.Block, gen.Op, gen.Ops
local Number, String = gen.Number, gen.String
local True, False, Nil = gen.True, gen.False, gen.Nil
local Set, Local, Id = gen.Set, gen.Local, gen.Id
local Function, Call, Invoke = gen.Function, gen.Call, gen.Invoke
local Return, Label, Goto = gen.Return, gen.Label, gen.Goto
local Table, Index, Pair = gen.Table, gen.Index, gen.Pair
local If, For, ForIn, While = gen.If, gen.For, gen.ForIn, gen.While
local Rest = gen.Rest

Scope = { }
Scope.__index = Scope
Scope.new = function(outer, context)
   local self = {
      names   = { };
      outer   = outer;
      context = context;
   }
   return setmetatable(self, Scope)
end
Scope.lookup = function(self, name)
   if self.names[name] then
      return self.names[name]
   elseif self.outer then
      return self.outer:lookup(name)
   else
      self.context:error(tostring(name).." is not defined")
   end
end
Scope.define = function(self, name, info)
   self.names[name] = info or true
end

local def = { }

Context = { }
Context.__index = Context
Context.new = function()
   local self = { }
   return setmetatable(self, Context)
end
Context.error = function(self, mesg)
   error(mesg.." on line: "..tostring(self.line))
end
Context.enter_scope = function(self)
   self.scope = Scope.new(self.scope, self)
end
Context.leave_scope = function(self)
   self.scope = self.scope.outer
end
Context.compile = function(self, source, fname, opts)
   self.stack = { }
   self.state = { }
   self.scope = Scope.new(nil, self)

   self.scope:define("Number")
   self.scope:define("String")
   self.scope:define("Boolean")
   self.scope:define("Function")

   self.scope:define("print")
   self.scope:define("magic")

   self.input = kudu.grammar.match(source)
   if opts and opts.dump_ast then
      print("AST:", self.input)
   end

   self.chunk = Chunk.new(fname or source)
   self.scope:define("this")
   local bitops = Ops{ }
   self.nroot = {
      Ops{
         Call{ Id"require", String"kudu.runtime" };
         Call{ Index{ Id"kudu", String"load" } };
         Local{ { Id"this" }; Index{ Id"kudu", String"null" } };
         self:process(self.input);
         Call{ Id"(init)" };
         Return{ Id"__package__" };
      }
   }

   if opts and opts.dump_ost then
      print("OST:", gaia.util.dump(self.nroot))
   end
   self.baked = self.chunk:compile(self.nroot)
   return self.baked
end
Context.process = function(self, node)
   if type(node) == "table" then
      local func = def[node.tag]
      if func then
         if node.locn then
            self.line = node.locn.line
         end
         local nost = func(self, node)
         nost.line = self.line
         return nost
      end
      error("no handler for node: "..tostring(node.tag))
   else
      error("invalid node: "..tostring(node))
   end
end

Context.get = function(self, rule, node)
   if rule ~= node.tag then
      error("CompileError: expected <"..rule.."> but got <"..node.tag..">")
   end
   local func = def[rule]
   if node.locn then
      self.line = node.locn.line
   end
   local nost = func(self, node)
   nost.line = self.line
   return nost
end

local IDGEN = 0
Context.genid = function()
   IDGEN = IDGEN + 1
   return "(GEN_"..tostring(IDGEN)..")"
end

function def:block(node)
   local block = Block { }
   local outer = self.block
   self.block = block
   for i=1, #node do
      local stmt = self:process(node[i])
      block[#block + 1] = stmt
   end
   self.block = outer
   return block
end
function def:ident(node)
   local name = node[1]
   if not node.is_lhs then
      -- XXX - hack! for the sake of making imports work
      -- this really needs to do the file loading and parsing
      -- here and not at runtime... alternatively make another pass somewhere?
      --self.scope:lookup(name)
   end
   return Id(name)
end
function def:string(node)
   return String(node[1])
end
function def:number(node)
   return Number(tonumber(node[1]))
end
def['true'] = function(self, node)
   return True
end
def['false'] = function(self, node)
   return False
end
def['null'] = function(self, node)
   return Id'(null)'
end
function def:rest(node)
   return Rest{ }
end
function def:range(node)
   local min = self:process(node[1])
   local max = self:process(node[2])
   return Call{ Id"(range)", min, max }
end
function def:for_stmt(node)
   self:enter_scope()
   self.scope:define(node[1][1])
   local iden = self:process(node[1])
   local init = self:process(node[2])
   local last = self:process(node[3])
   local step
   if node[4] ~= "" then
      step = self:process(node[4])
   else
      step = Number(1)
   end
   local body = self:process(node[5])
   self:leave_scope()
   return For{ iden, init, last, step, body }
end
function def:for_in_stmt(node)
   self:enter_scope()
   local vars = { }
   for i=1, #node[1] do
      self.scope:define(node[1][i][1])
      vars[#vars + 1] = self:process(node[1][i])
   end
   local expr = self:process(node[2])
   local iter
   if #vars == 1 then
      iter = { Invoke{ expr[1], String"getValueIterator" } }
   else
      iter = { Invoke{ expr[1], String"getKeyValueIterator" } }
   end
   local body = self:process(node[3])
   self:leave_scope()
   return ForIn{ vars, iter, body }
end
function def:expr_lost(node)
   local nops = Ops{ }
   for i=1, #node do
      local expr = node[i]
      nops[#nops + 1] = self:get('expr', expr)
   end
   return nops
end
function def:cond_block(node)
   local block = Ops{ }
   local outer = self.block
   self.block = block
   for i=1, #node do
      block[#block + 1] = self:process(node[i])
   end
   self.block = outer
   return block
end
function def:expr(node)
   return self:process(node[1])
end
function def:expr_noin(node)
   return def.expr(self, node)
end
function def:expr_base(node)
   return def.expr(self, node)
end
function def:list_expr(node)
   local list = { }
   local oper = node[1]
   for i=1, #oper do
      local item = oper[i]
      if item ~= "" then
         list[#list + 1] = self:process(item)
      end
   end
   return list
end
function def:list_expr_noin(node)
   return def.list_expr(self, node)
end

local assops = {
   ["="] = true;
   ["+="] = "add";
   ["-="] = "sub";
   ["*="] = "mul";
   ["/="] = "div";
   ["**="] = "pow";
   ["%="] = "mod";
   ["~="] = "concat";
}
local bassops = {
   ["&="] = "(band)";
   ["|="] = "(bor)";
   ["^="] = "(bxor)";
}

function def:op_infix(node)
   local o = node.oper
   local a, b
   a = self:process(node[1])
   if o == "." then
      if node[2].tag == "ident" then
         b = String(node[2][1])
      else
         b = self:process(node[2])
      end
      if node.is_lhs then
         return { a, String"__set_member", b }
      else
         return Invoke{ a, String"__get_member", b }
      end
   end
   if o == "::" then
      if node[2].tag == "ident" then
         b = String(node[2][1])
      else
         b = self:process(node[2])
      end
      return Index{ a, b }
   end
   b = self:process(node[2])
   node[1].ost = a
   node[2].ost = b
   if     o == "||" then return Op{ "or", a, b }
   elseif o == "&&" then return Op{ "and", a, b }
   elseif o == "==" then return Op{ "eq", a, b }
   elseif o == "!=" then return Op{ "ne", a, b }
   elseif o == ">=" then return Op{ "ge", a, b }
   elseif o == "<=" then return Op{ "le", a, b }
   elseif o == ">"  then return Op{ "gt", a, b }
   elseif o == "<"  then return Op{ "lt", a, b }
   elseif o == "+"  then return Op{ "add", a, b }
   elseif o == "-"  then return Op{ "sub", a, b }
   elseif o == "*"  then return Op{ "mul", a, b }
   elseif o == "/"  then return Op{ "div", a, b }
   elseif o == "%"  then return Op{ "mod", a, b }
   elseif o == "**" then return Op{ "pow", a, b }
   elseif o == "~"  then return Op{ "concat", a, b }

   -- bitwise ops
   elseif o == "|" then
      return Call{ Id"(bor)", a, b }
   elseif o == "&" then
      return Call{ Id"(band)", a, b }
   elseif o == "^" then
      return Call{ Id"(bxor)", a, b }
   elseif o == ">>" then
      return Call{ Id"(rshift)", a, b }
   elseif o == ">>>" then
      return Call{ Id"(arshift)", a, b }
   elseif o == "<<" then
      return Call{ Id"(lshift)", a, b }

   -- simple and arithmetic assignment ops
   elseif assops[o] then
      if o == "=" then
         if a.tag == "Index" or node[1].tag == 'ident' then
            return Set{ { a }, { b } }
         else
            return Invoke{ a[1], a[2], a[3], b }
         end
         --return Set{ { a }, { b } }
      end
      local expr = Op{ assops[o], a, b }
      if a.tag == "Index" or node[1].tag == 'ident' then
         return Set{ { a }, { expr } }
      else
         return Invoke{ a[1], a[2], a[3], b }
      end
      --return Set{ { a }, { expr } }

   -- bitwise assignment ops
   elseif bassops[o] then
      local expr = Call{ Id(bassops[o]), a, b }
      return Set{ { a }, { expr } }
   else
      error("invalid infix operator: "..o)
   end
end
function def:op_prefix(node)
   local o = node.oper
   local a = self:process(node[1])
   if o == "!" then
      return Op{ "not", a }
   elseif o == "-" then
      return Op{ "unm", a }
   elseif o == "#" then
      return Op{ "len", a }
   elseif o == "~" then
      return Call{ Id"(bnot)", a }
   elseif o == "++" then
      return Set{ { a }, { Op{ "add", a, Number(1) } } }
   elseif o == "--" then
      return Set{ { a }, { Op{ "sub", a, Number(1) } } }
   elseif o == "new" then
      return Call{ Id"(alloc)", a }
   end
end
function def:op_postfix(node)
   local o = node.oper
   local a = self:process(node[1])
   if o == "++" then
      local temp = self:genid()
      return Ops{
         Local{ { Id(temp) }, { a } };
         Set{ { a }, { Op{ "add", a, Number(1) } } };
         Id(temp);
      }
   elseif o == "--" then
      local temp = self:genid()
      return Ops{
         Local{ { Id(temp) }, { a } };
         Set{ { a }, { Op{ "sub", a, Number(1) } } };
         Id(temp);
      }
   end
end
function def:op_circumfix(node)
   local nops = Ops{ }
   for i=1, #node do
      nops[#nops + 1] = self:process(node[1])
   end
   return nops
end
function def:op_postcircumfix(node)
   local oper = node.oper
   local expr
   if oper == "{" then
      self:enter_scope()

      local body  = node[2]
      local outer = self.block
      local nops  = Ops{ }
      self.block  = nops

      for i=1,#body do
         nops[#nops + 1] = self:process(body[i])
      end

      self.block = outer

      self:leave_scope()
      expr = { Function{ { Id"(self)", Rest{ } }, nops } }
   else
      expr = node[2]
      if expr ~= "" then
         expr = self:process(node[2])
      else
         expr = { }
      end
   end
   if oper == "(" or oper == "{" then
      if node[1].oper == "." then
         local meth_name = node[1][2][1]
         local this = self:process(node[1][1])
         local meth = String(meth_name)
         if node[1][1][1] == "super" then
            return Call{ Index{ this, meth }, Id"this", unpack(expr) }
         end
         return Invoke{ this, meth, unpack(expr) }
      elseif node[1].oper == "::" then
         local meth
         if node[1][2].tag == "ident" then
            local meth_name = node[1][2][1]
            meth = String(meth_name)
         else
            -- late binding base::[expr]()
            meth = self:process(node[1][2])
         end
         local this = self:process(node[1][1])
         return Call{ Index{ this, meth }, unpack(expr) }
      elseif node[1].oper == "new" then
         local base = self:process(node[1])
         for i=1, #expr do
            base[#base + 1] = expr[i]
         end
         return base
      elseif node[1].oper == "[" then
         local this = self:process(node[1][1])
         local meth = self:process(node[1][2])
         if node[1][1][1] == "super" then
            return Call{ Index{ this, meth }, Id"this", unpack(expr) }
         end
         return Invoke{ this, meth, unpack(expr) }
      else
         local iden = node[1]
         local args = { }
         if node[2] ~= "" then
            if node[2].tag == "block" then
               --args[#args + 1] = Rest{ }
            else
               args = node[2][1]
            end
         end
         if oper ~= "{" then
            --XXX fixme for blocks
            if iden.tag == 'ident' then
               local info = self.scope:lookup(iden[1])
            elseif iden.tag == 'op_postcircumfix' then
               -- XXX: if RHS expression, check return type from foo.bar()()
            end
         end

         local base = self:process(node[1])
         local call = Call{ base, Id"this", unpack(expr) }

         return call
      end
   elseif oper == "[" then
      local base = self:process(node[1])
      if node.is_lhs then
         return { base, String"__set_index", expr }
      else
         return Invoke{ base, String"__get_index", expr }
      end
   end
end
function def:late_bind(node)
   return def.expr(self, node[1])
end
function def:var_decl(node)
   local name_list, expr_list = node[1], node[2] or { }
   local lhs, rhs = { }, { }

   for i=1, #name_list do
      local iden = name_list[i] -- typed_ident
      local expr = expr_list[i] -- expr or ...

      local name = iden[1]
      lhs[i] = Id(name)

      self.scope:define(name)

      if expr then
         rhs[i] = self:process(expr)
      elseif i <= #expr_list then
         rhs[i] = Id"(null)"
      end
   end

   return Local{ lhs, rhs }
end
function def:bind_stmt(node)
   local op_infix_node = node[1]
   local lhs_expr_list = op_infix_node[1]
   local rhs_expr_list = op_infix_node[2]
   local nops = Ops{ }
   for i=1, #lhs_expr_list do
      local lhs_expr = lhs_expr_list[i]
      local rhs_expr = rhs_expr_list[i]
      local lhs_oper = lhs_expr[1].oper
      if not(lhs_oper == '.' or lhs_oper == '[' or lhs_oper == '::' or lhs_expr[1].tag == "ident") then
         self:error('invalid left hand side in assignment')
      end
      lhs_expr[1].is_lhs = true
      -- XXX: unhack this by moving the op_infix logic which relates to binding in here
      nops[#nops + 1] = self:get('op_infix', {
         tag = 'op_infix', oper = op_infix_node.oper, lhs_expr[1], rhs_expr and rhs_expr[1] or ''
      })
   end
   return nops
end
function def:func_decl(node)
   self:enter_scope()
   local iden = node[1]
   local name = iden[1]
   local parm_list = self:process(node[2])

   -- function body
   local body = node[3]
   local nops = def.func_init(self)
   local outer = self.block
   self.block = nops
   for i=1,#body do
      nops[#nops + 1] = self:process(body[i])
   end
   self.block = outer

   self:leave_scope()
   self.scope:define(name)

   local func = Function{ parm_list, nops }
   --[[
   outer[#outer + 1] = Call{
      Id"(register_function)", String(name), func
   }
   --]]

   local set = Set{ { Id(name) }, { func } }
   --[[
   outer[#outer + 1] = Call{
      Id"(register_function)", String(name), Id(name)
   }
   --]]
   return set
end
function def:func_params(node)
   local list = { Id"(self)" }
   for i=1,#node do
      if node[i].tag == "rest" then
         list[#list + 1] = Rest{ }
         break
      end
      local iden = node[i]
      local name = iden[1]

      self.scope:define(name)
      list[#list + 1] = Id(name)
   end
   return list
end
function def:func_literal(node)
   self:enter_scope()

   local parm_list = self:process(node[1])

   local body = node[2]
   local nops = def.func_init(self)
   local outer = self.block
   self.block = nops
   for i=1,#body do
      nops[#nops + 1] = self:process(body[i])
   end
   self.block = outer

   self:leave_scope()

   return Function{ parm_list, nops }
end
function def:return_stmt(node)
   local expr_list = node[1]
   local list = { }
   for i=1, #expr_list do
      local expr = self:process(expr_list[i])
      list[#list + 1] = expr
   end
   return Return(list)
end
function def:func_init()
   local init = Ops{
      -- trigger an upvalue
      Local{ { Id"this" }, { Id"this" } };
      If{
         -- override if (self) is passed
         Op{ "ne", Id"(self)", Nil() };
         { Set{ { Id"this" }, { Id"(self)" } } }
      }
   }
   return init
end
function def:table_literal(node)
   local table = Table{ }
   for i=1, #node, 2 do
      local k
      if type(node[i]) == "string" then
         k = String(node[i])
      else
         k = self:process(node[i])
      end
      local v = self:process(node[i + 1])
      table[#table + 1] = Pair{ k, v }
   end
   return Call{ Id"(table)", table }
end
function def:array_literal(node)
   local table = Table{ }
   for i=1, #node do
      local v = self:process(node[i])
      table[#table + 1] = v
   end
   return Call{ Id"(array)", table }
end
function def:class_decl(node)
   local iden = node[1]
   local name = iden[1]
   local head = node[2]
   local body = node[3]
   local nops = Ops{
      Set{ { Id(name) }, { Call{ Id"(class_create)", String(name) } } };
   }

   self.scope:define(name)

   local from = head[1]
   local with = head[2]

   if from ~= nil and from[1] ~= "" then
      local base = Id(from[1][1])
      nops[#nops + 1] = Call{ Id"(class_extend)", Id(name), base }
   end

   if with ~= nil then
      for i=1, #with do
         local role = Id(with[i][1])
         nops[#nops + 1] = Call{ Id"(class_mixin)", Id(name), role }
      end
   end

   self:enter_scope()

   for i=1, #body do
      local member = body[i]
      if member.tag == "func_decl" then
         -- remove the identifier so that we can pretend this is
         -- a function literal for kudu.class.add_method(class, name, func)
         local ident = table.remove(member, 1)
         self.scope:define("super")
         nops[#nops + 1] = Call{
            Id"(class_add_meth)",
            Id(name), String(ident[1]), def.func_literal(self, member)
         }
      elseif member.tag == "var_decl" then
         --kudu.class.add_attrib(class, name, type_info)
         local name_list = member[1]
         local expr_list = member[2]
         for i=1, #name_list do
            local ident = name_list[i]
            local default = Id"(null)"
            if expr_list and expr_list[i] then
               default = self:process(expr_list[i])
            end
            nops[#nops + 1] = Call{
               Id"(class_add_attr)", Id(name), String(ident[1]), default
            }
         end
      end
   end

   self:leave_scope()
   return nops
end
function def:role_decl(node)
   local iden = node[1]
   local name = iden[1]
   local head = node[2]
   local body = node[3]
   local nops = Ops{
      Set{ { Id(name) }, { Call{ Id"(role_create)", String(name) } } };
   }

   self.scope:define(name)

   local with = head[1]

   if with ~= nil then
      for i=1, #with do
         local role = Id(with[i][1])
         nops[#nops + 1] = Call{ Id"(role_mixin)", Id(name), role }
      end
   end

   self:enter_scope()

   for i=1, #body do
      local member = body[i]
      if member.tag == "func_decl" then
         -- remove the identifier so that we can pretend this is
         -- a function literal for kudu.role.add_method(role, name, func)
         local ident = table.remove(member, 1)
         nops[#nops + 1] = Call{
            Id"(role_add_meth)",
            Id(name), String(ident[1]), def.func_literal(self, member)
         }
      elseif member.tag == "var_decl" then
         --kudu.role.add_attrib(role, name, type_info)
         local name_list = member[1]
         local expr_list = member[2]
         for i=1, #name_list do
            local ident = name_list[i]
            local default = Id"(null)"
            if expr_list and expr_list[i] then
               default = self:process(expr_list[i])
            end
            nops[#nops + 1] = Call{
               Id"(role_add_attr)", Id(name), String(ident[1]), default
            }
         end
      end
   end

   self:leave_scope()
   return nops
end
function def:if_stmt(node)
   local opnode = If{ }
   for i=1, #node, 2 do
      if i == #node and i % 2 == 1 then
         local cond_block = node[i]
         opnode[#opnode + 1] = self:process(cond_block)
      else
         local expr_node  = node[i]
         local cond_block = node[i+1]

         local expr  = self:process(expr_node)
         local block = self:process(cond_block)

         opnode[#opnode + 1] = expr
         opnode[#opnode + 1] = block
      end
   end
   return opnode
end
function def:while_stmt(node)
   local expr_node, cond_block = node[1], node[2]

   local outer = self.loop
   self.loop = { top = gaia.util.genid(), bot = gaia.util.genid() }

   local while_ops = While{ self:process(expr_node), self:process(cond_block) }

   while_ops.loop_top = self.loop.top
   while_ops.loop_bot = self.loop.bot

   self.loop = outer

   return while_ops
end
function def:throw_stmt(node)
   local expr = node[1]
   return Call{ Id'(throw)', self:process(expr) }
end
function def:try_catch(node)
   local catch_node, finally_node

   if node[2] then
      if node[2].tag == 'catch_block' then
         catch_node = node[2]
         if node[3] and node[3].tag == 'finally_block' then
            finally_node = node[3]
         end
      elseif node[2].tag == 'finally_block' then
         finally_node = node[2]
      end
   end

   self:enter_scope()

   local body  = node[1]
   local outer = self.block
   local nops  = Ops{ }
   self.block  = nops

   for i=1,#body do
      nops[#nops + 1] = self:process(body[i])
   end

   self.block = outer
   self:leave_scope()

   local try_func = Function{ { }, nops }

   local catch_func = Nil
   if catch_node then
      local nops = Ops{ }
      self:enter_scope()
      self.block = nops

      local parm = catch_node[1]
      local body = catch_node[2]

      local parm_list = self:process(parm)
      table.remove(parm_list, 1)

      for i=1, #body do
         nops[#nops + 1] = self:process(body[i])
      end

      self.block = outer
      self:leave_scope()

      catch_func = Function{ parm_list, nops }
   end

   local finally_func = Nil
   if finally_node then
      local nops = Ops{ }
      self:enter_scope()
      self.block = nops

      local body = finally_node[1]

      for i=1, #body do
         nops[#nops + 1] = self:process(body[i])
      end

      self.block = outer
      self:leave_scope()

      finally_func = Function{ { }, nops }
   end

   return Block {
      Local{ { Id"(try_retval)" }, { Call{ Id'(try_catch)', try_func, catch_func, finally_func } } };
      If{
         Op{ 'gt', Op{ 'len', Id"(try_retval)" }, Number(0) },
         {
            Return{ Call{ Id"(select)", Number(1), Call{ Id"(unpack)", Id"(try_retval)" } } }
         }
      }
   }
end

function def:continue_stmt(node)
   return Goto(self.loop.top)
end
function def:break_stmt(node)
   return Goto(self.loop.bot)
end

function def:package_decl(node)
   local path = { }
   for i=1, #node do
      local iden = node[i]
      path[#path + 1] = iden[1]
   end
   return Call{ Id"(package_create)", String(table.concat(path, ".")) };
end

function def:import_stmt(node)
   local path = { }
   for i=1, #node do
      local iden = node[i]
      path[#path + 1] = iden[1]
   end
   return Call{ Id"(package_import)", String(table.concat(path, ".")) };
end

function def:export_decl(node)
   local list = { }
   for i=1, #node do
      local iden = node[i]
      list[#list + 1] = iden[1]
   end
   return Call{ Id"(package_export)", table2ost(list) };
end

function kpairs(t)
   return next, t, #t > 0 and #t or nil;
end

function osttype(v)
   if v == nil then
      return Nil()
   elseif type(v) == "string" then
      return String(v)
   elseif type(v) == "number" then
      return Number(v)
   elseif type(v) == "boolean" then
      if v == true then return True() end
      return False()
   elseif type(v) == "table" then
      if v.tag and v.compile then
         return v
      end
      return table2ost(v)
   end
end

function table2ost(t)
   local ost = Table{ }
   for i,v in ipairs(t) do
      ost[#ost + 1] = osttype(v)
   end
   for k,v in kpairs(t) do
      ost[#ost + 1] = Pair{ osttype(k), osttype(v) }
   end
   return ost
end

function compile(prog, name, opts)
   local cctx = Context.new()
   local bake = cctx:compile(prog, '='..name, opts)
   local file = io.open("a.out", "wb")
   file:write(bake)
   file:close()
   return bake
end

