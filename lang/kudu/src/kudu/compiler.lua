require"kudu.grammar"
require"gaia.codegen"
require"gaia.util"

module("kudu.compiler", package.seeall)

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

   self.input = kudu.grammar.match(source)
   if opts and opts.dump_ast then
      print("AST:", self.input)
   end

   self.code = { }
   function self:emit(...)
      for i=1, select('#', ...) do
         self.code[#self.code + 1] = select(i, ...)
      end
   end
   self.line = 1
   self:emit[[require"kudu.runtime"; kudu.load(); local this = nil]]
   self:process(self.input);
   self:emit"return __package__"

   return table.concat(self.code, ' ')
end
Context.process = function(self, node)
   if type(node) == "table" then
      local func = def[node.tag]
      if func then
         if node.locn then
            if node.tag ~= 'block' and node.locn.line > self.line then
               for i=self.line, node.locn.line - 1 do
                  self:emit("\n")
               end
               self.line = node.locn.line
            end
         end
         return func(self, node)
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
   return func(self, node)
end

local IDGEN = 9
Context.genid = function()
   IDGEN = IDGEN + 1
   return "__auto_"..IDGEN..'__'
end

function def:block(node)
   self:emit"do"
   for i=1, #node do
      self:emit(self:process(node[i]))
   end
   self:emit"end"
end
function def:ident(node)
   return node[1]
end
function def:string(node)
   local str = node[1]
   if str:sub(1,1) == "'" then
      return string.format('(%q)', str:sub(2,-2))
   else
      return string.format('(%s)', str)
   end
end
function def:number(node)
   return '('..tostring(node[1])..')'
end
def['nil'] = function(self, node)
   return '(nil)'
end
def['true'] = function(self, node)
   return '(true)'
end
def['false'] = function(self, node)
   return '(false)'
end
function def:rest(node)
   return '...'
end
function def:range(node)
   local min, max = self:process(node[1]), self:process(node[2])
   return '__range__('..min..','..max..')'
end
function def:enum_stmt(node)
   local terms = { }
   local ident = node[1][1]
   for i=2, #node do
      terms[#terms + 1] = string.format('%q', self:process(node[i]))
   end
   self:emit(ident..' = kudu.enum{'..table.concat(terms, ',')..'}')
end
function def:for_stmt(node)
   local iden = self:process(node[1])
   local init = self:process(node[2])
   local last = self:process(node[3])
   local step
   if node[4] ~= "" then
      step = self:process(node[4])
   else
      step = '1'
   end
   local vars = { init, last, step }
   self:emit("for "..iden..'='..table.concat(vars, ',')..' do local __break__ repeat')
   self:process(node[5])
   self:emit"until true if __break__ then break end end"
end
function def:for_in_stmt(node)
   local vars = { }
   for i=1, #node[1] do
      vars[#vars + 1] = self:process(node[1][i])
   end
   local expr = self:process(node[2])
   local iter = expr[1]..':__each()'
   local temp = self:genid()
   self:emit("do local "..temp.." = "..expr[1]..
      " if magic.type("..temp..") ~= 'function' then "..temp..' = '..iter..' end'
   )
   self:emit("for "..table.concat(vars, ', ')..' in '..temp..' do local __break__ repeat')
   self:process(node[3])
   self:emit"until true if __break__ then break end end end"
end
function def:cond_block(node)
   local body = { }
   local code = self.code
   self.code = body
   for i=1, #node do
      local expr = self:process(node[i])
      if expr then self:emit(expr) end
   end
   self.code = code
   self:emit(table.concat(body, ' '))
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
   ["="] = '=';
   ["+="] = "+";
   ["-="] = "-";
   ["*="] = "*";
   ["/="] = "/";
   ["**="] = "^";
   ["%="] = "%";
   ["~="] = "..";
}
local bassops = {
   ["&="] = "__band__";
   ["|="] = "__bor__";
   ["^="] = "__bxor__";
}

function def:op_infix(node)
   local o = node.oper
   local a, b
   a = self:process(node[1])
   if o == "." then
      if node[2].tag == "op_postcircumfix" then
         if node[2].oper == '(' then
            local ident = self:process(node[2][1])
            local parms = node[2][2]
            if parms == "" then
               parms = { }
            else
               parms = self:process(parms)
            end
            return a..':'..ident..'('..table.concat(parms, ', ')..')'
         elseif node[2].oper == '::[' then
            local ident = self:process(node[2][1])
            local expr  = self:process(node[2][2])
            if a == 'this' then
               return 'this['..string.format('%q', '!'..ident)..']['..expr..']'
            end
            return a..'.'..ident..'['..expr..']'
         end
      else
         b = self:process(node[2])
      end
      if a == 'this' then
         b = string.format('%q', '!'..b)
      else
         b = string.format('%q', b)
      end
      if node.is_lhs then
         return { a..'['..b..'] = %s' }
      end
      return a..'['..b..']'
   end
   if o == "::" then
      return a..'.'..self:process(node[2])
   end
   b = self:process(node[2])
   if     o == "||" then return a.." or "..b
   elseif o == "&&" then return a.." and "..b
   elseif o == "==" then return a.." == "..b
   elseif o == "!=" then return a.." ~= "..b
   elseif o == ">=" then return a.." >= "..b
   elseif o == "<=" then return a.." <= "..b
   elseif o == ">"  then return a.." > "..b
   elseif o == "<"  then return a.." < "..b
   elseif o == "+"  then return a.." + "..b
   elseif o == "-"  then return a.." - "..b
   elseif o == "*"  then return a.." * "..b
   elseif o == "/"  then return a.." / "..b
   elseif o == "%"  then return a.." % "..b
   elseif o == "**" then return a.." ^ "..b
   elseif o == "~"  then return "magic.tostring("..a..")..magic.tostring("..b..")"

   -- bitwise ops
   elseif o == "|" then
      return "__bor__("..a..", "..b..")"
   elseif o == "&" then
      return "__band__("..a..", "..b..")"
   elseif o == "^" then
      return "__bxor__("..a..", "..b..")"
   elseif o == ">>" then
      return "__rshift__("..a..", "..b..")"
   elseif o == ">>>" then
      return "__arshift__("..a..", "..b..")"
   elseif o == "<<" then
      return "__lshift__("..a..", "..b..")"
   elseif o == 'instanceof' then
      return '__instanceof__('..a..', '..b..')'
   else
      error("invalid infix operator: "..o)
   end
end
function def:op_prefix(node)
   local o = node.oper
   local a = self:process(node[1])
   if o == "!" then
      return 'not '..a
   elseif o == "-" then
      return '-'..a
   elseif o == "#" then
      return '#'..a
   elseif o == "~" then
      return '__bnot__('..a..')'
   elseif o == "++" then
      return a..' = '..a..' + 1'
   elseif o == "--" then
      return a..' = '..a..' - 1'
   elseif o == "new" then
      return { '__alloc__(%s)', a }
   elseif o == 'typeof' then
      return '__typeof__('..a..')'
   end
end
function def:op_postfix(node)
   local o = node.oper
   local a = self:process(node[1])
   if o == "++" then
      local temp = self:genid()
      self:emit("local "..temp..' = '..a)
      self:emit(a..' = '..a..' + 1')
      return temp
   elseif o == "--" then
      local temp = self:genid()
      self:emit("local "..temp..' = '..a)
      self:emit(a..' = '..a..' - 1')
      return temp
   end
end
function def:op_circumfix(node)
   local nops = { }
   for i=1, #node do
      nops[#nops + 1] = self:process(node[1])
   end
   return '('..table.concat(nops, ' ')..')'
end
function def:op_postcircumfix(node)
   local oper = node.oper
   local expr
   if node[2] ~= "" then
      expr = self:process(node[2])
   else
      expr = { }
   end
   if oper == "(" then
      if node[1].oper == "." then
         local meth = node[1][2][1]
         local this = self:process(node[1][1])
         if this == "super" then
            local args = { 'this', unpack(expr) }
            return this..'.'..meth..'('..table.concat(args, ', ')..')'
         elseif this == 'this' then
            local args = { 'this', unpack(expr) }
            meth = string.format('%q', '!'..meth)
            return 'this['..meth..']('..table.concat(args, ', ')..')'
         end
         return this..':'..meth..'('..table.concat(expr, ', ')..')'

      elseif node[1].oper == "::" then
         local this = self:process(node[1][1])
         local meth = node[1][2][1]
         return this..'.'..meth..'('..table.concat(expr, ', ')..')'

      elseif node[1].oper == "new" then
         local base = self:process(node[1])
         for i=1, #expr do
            base[#base + 1] = expr[i]
         end
         local tmpl = table.remove(base, 1)
         return string.format(tmpl, table.concat(base, ', '))

      elseif node[1].oper == ".[" then
         local this = self:process(node[1][1])
         local meth = self:process(node[1][2])
         local args
         if this == "super" then
            args = { this, meth, 'this', unpack(expr) }
         else
            args = { this, meth, 'nil', unpack(expr) }
         end
         return '__invoke_late__('..table.concat(args, ', ')..')'

      elseif node[1].oper == '::[' then
         local this = self:process(node[1][1])
         local meth = self:process(node[1][2])
         return this..'['..meth..']('..table.concat(expr, ', ')..')'

      else
         local iden = node[1]
         local args = { }
         if node[2] ~= "" then
            args = node[2][1]
         end

         local base = self:process(node[1])
         local args = { unpack(expr) }
         return base..'('..table.concat(args, ', ')..')'
      end

   elseif oper == "[" then
      local base = self:process(node[1])
      if node.is_lhs then
         return { base..':__set_index('..expr..', %s)' }
      else
         return base..':__get_index('..expr..')'
      end
   elseif oper == '::[' then
      local base = self:process(node[1])
      if node.is_lhs then
         return { base..'['..expr..'] = %s' }
      end
      return base..'['..expr..']'
   elseif oper == '.[' then
      error('NYI')
   end
end
function def:late_bind(node)
   return def.expr(self, node[1])
end
function def:var_decl(node)
   local name_list, expr_list = node[1], node[2] or { }
   local lhs, rhs = { }, { }

   for i=1, #name_list do
      local iden = name_list[i]
      local expr = expr_list[i]

      lhs[#lhs + 1] = iden[1]

      if expr then
         rhs[i] = self:process(expr)
         if type(rhs[i]) == 'table' then
            rhs[i] = string.format(rhs[i][1], rhs[i][2])
         end
      elseif i <= #expr_list then
         rhs[i] = 'nil'
      end
   end

   self:emit("local "..table.concat(lhs, ', ')..' = '..table.concat(rhs, ', '))
end
function def:bind_stmt(node)
   local op_infix_node = node[1]
   local lhs_expr_list = op_infix_node[1]
   local rhs_expr_list = op_infix_node[2]
   local lhs, rhs = { }, { }
   for i=1, #lhs_expr_list do
      local lhs_expr = lhs_expr_list[i]
      local rhs_expr = rhs_expr_list[i]
      local lhs_oper = lhs_expr[1].oper
      if not(
         lhs_oper == '.' or lhs_oper == '[' or
         lhs_oper == '.[' or lhs_oper == '::' or
         lhs_oper == '::[' or lhs_expr[1].tag == "ident"
      ) or lhs_expr[1].tag == 'ident' and lhs_expr[1][1] == 'this' then
         self:error('invalid left hand side in assignment')
      end
      for i=1, #lhs_expr do
         lhs_expr[i].is_lhs = true
      end
      local a = self:process(lhs_expr)
      local b = self:process(rhs_expr)
      if type(a) == 'table' then
         self:emit(string.format(a[1], b))
      else
         local o = op_infix_node.oper
         if assops[o] then
            if o == "=" then return a..' = '..b end
            return a..' = '..a..' '..assops[o]..' '..b
         elseif bassops[o] then
            return a..' = '..bassops[o]..'('..a..', '..b..')'
         end
      end
   end
end
function def:func_decl(node)
   local iden = node[1]
   local name = iden[1]
   local parm_list = self:process(node[2])

   -- function body
   local code = self.code
   local body = { }
   self.code = body
   for i=1, #node[3] do
      local expr = self:process(node[3][i])
      if expr then body[#body + 1] = expr end
   end
   self.code = code
   self:emit("function "..name.."("..table.concat(parm_list, ', ')..")")
   self:emit(table.concat(body, ' '))
   self:emit"end"
end
function def:func_params(node)
   local list = { }
   if self.in_class then
      list[#list + 1] = 'this'
   end
   for i=1,#node do
      if node[i].tag == "rest" then
         list[#list + 1] = "..."
         break
      end
      local iden = node[i]
      local name = iden[1]
      list[#list + 1] = name
   end
   return list
end
function def:short_lambda(node)
   node[1].tag = 'func_params'
   local parm_list = self:process(node[1])
   if self.in_class and parm_list[1] == 'this' then
      table.remove(parm_list, 1)
   end
   local body = { }
   local code = self.code
   self.code = body
   body[#body + 1] = 'return'
   local expr = self:process(node[2])
   if expr then
      body[#body + 1] = expr
   end
   self.code = code
   return 'function('..table.concat(parm_list, ', ')..') '..table.concat(body, ' ')..' end'
end
function def:func_literal(node)
   local parm_list = self:process(node[1])
   local body = { }
   local code = self.code
   self.code = body
   for i=1, #node[2] do
      local expr = self:process(node[2][i])
      if expr then
         body[#body + 1] = expr
      end
   end
   self.code = code
   return 'function('..table.concat(parm_list, ', ')..') '..table.concat(body, ' ')..' end'
end
function def:return_stmt(node)
   local expr_list = node[1]
   local list = { }
   for i=1, #expr_list do
      list[#list + 1] = self:process(expr_list[i])
   end
   return 'do return '..table.concat(list, ', ')..' end'
end
function def:table_literal(node)
   local buf = { }
   for i=1, #node, 2 do
      local k
      if type(node[i]) == "string" then
         k = string.format('%q', node[i])
      else
         k = self:process(node[i])
      end
      local v = self:process(node[i + 1])
      buf[#buf + 1] = '['..k..'] = '..v
   end
   return '__table__{'..table.concat(buf, ', ')..'}'
end
function def:array_literal(node)
   local buf = { }
   for i=1, #node do
      local v = self:process(node[i])
      buf[#buf + 1] = v
   end
   return '__array__{'..table.concat(buf, ', ')..'}'
end
function def:class_decl(node)
   local iden = node[1]
   local name = iden[1]
   local head = node[2]
   local body = node[3]
   local code = self.code

   local class_frame = { }
   self.in_class = true
   self.code = class_frame

   self:emit(name..' = '..string.format('__class_create__(%q)', name))

   self:emit"do"

   local from = head[1]
   local with = head[2]

   if from ~= nil and from[1] ~= "" then
      local base = from[1][1]
      self:emit("local super = __class_extend__("..name..", "..base..")")
   end

   if with ~= nil then
      for i=1, #with do
         local role = with[i][1]
         self:emit("__class_mixin__("..name..', '..role..')')
      end
   end

   local hoist = { }
   self:emit"local %s"
   local hoist_idx = #self.code

   for i=1, #body do
      local body_stmt = body[i]
      local member = body_stmt[1]
      if member.tag == "func_decl" then
         local ident = member[1]
         local fname = ident[1]
         if member.attribute == 'set' or member.attribute == 'get' then
            ident[1] = '__'..member.attribute..'_'..ident[1]
         end
         self:process(member)
         hoist[ident[1]] = 'nil'
         local args  = {
            name,
            string.format('%q', fname),
            ident[1],
            string.format('%q', body_stmt.modifier or ''),
            string.format('%q', member.attribute or ''),
         }
         self:emit('__class_add_meth__('..table.concat(args, ', ')..')')
      elseif member.tag == "var_decl" then
         local name_list = member[1]
         local expr_list = member[2]
         for i=1, #name_list do
            local ident = name_list[i]
            local default = 'nil'
            if expr_list and expr_list[i] then
               default = self:process(expr_list[i])
            end
            local args = {
               name,
               string.format('%q', ident[1]),
               default,
               string.format('%q', body_stmt.modifier or ''),
            }
            self:emit('__class_add_attr__('..table.concat(args, ', ')..')')
         end
      end
   end
   self:emit"end"

   local hoist_keys = { }
   local hoist_vals = { }
   for k,v in pairs(hoist) do
      hoist_keys[#hoist_keys + 1] = k
      hoist_vals[#hoist_vals + 1] = v
   end

   if #hoist_keys > 0 then
      local hoist_expr = self.code[hoist_idx]
      self.code[hoist_idx] = hoist_expr:format(
         table.concat(hoist_keys, ', ')..'='..table.concat(hoist_vals, ', ')
      )
   else
      self.code[hoist_idx] = ''
   end
   self.code = code
   self:emit(table.concat(class_frame, ' '))
   self.in_class = nil
end
function def:role_decl(node)
   local iden = node[1]
   local name = iden[1]
   local head = node[2]
   local body = node[3]
   local code = self.code

   local class_frame = { }
   self.in_class = true
   self.code = class_frame

   self:emit(name..' = '..string.format('__role_create__(%q)', name))

   self:emit"do"

   local with = head[1]

   if with ~= nil then
      for i=1, #with do
         local role = with[i][1]
         self:emit("__role_mixin__("..name..', '..role..')')
      end
   end

   local hoist = { }
   self:emit"local %s"
   local hoist_idx = #self.code

   for i=1, #body do
      local body_stmt = body[i]
      local member = body_stmt[1]
      if member.tag == "func_decl" then
         self:process(member)
         local ident = member[1]
         hoist[ident[1]] = 'nil'
         local args  = {
            name,
            string.format('%q', ident[1]),
            ident[1],
            string.format('%q', body_stmt.modifier or '')
         }
         self:emit('__role_add_meth__('..table.concat(args, ', ')..')')
      elseif member.tag == "var_decl" then
         local name_list = member[1]
         local expr_list = member[2]
         for i=1, #name_list do
            local ident = name_list[i]
            local default = 'nil'
            if expr_list and expr_list[i] then
               default = self:process(expr_list[i])
            end
            local args = {
               name,
               string.format('%q', ident[1]),
               default,
               string.format('%q', body_stmt.modifier or ''),
            }
            self:emit('__role_add_attr__('..table.concat(args, ', ')..')')
         end
      end
   end
   self:emit"end"

   local hoist_keys = { }
   local hoist_vals = { }
   for k,v in pairs(hoist) do
      hoist_keys[#hoist_keys + 1] = k
      hoist_vals[#hoist_vals + 1] = v
   end

   if #hoist_keys > 0 then
      local hoist_expr = self.code[hoist_idx]
      self.code[hoist_idx] = hoist_expr:format(
         table.concat(hoist_keys, ', ')..'='..table.concat(hoist_vals, ', ')
      )
   else
      self.code[hoist_idx] = ''
   end
   self.code = code
   self:emit(table.concat(class_frame, ' '))
   self.in_class = nil
end
function def:if_stmt(node)
   for i=1, #node, 2 do
      if i == #node and i % 2 == 1 then
         local cond_block = node[i]
         self:emit"else"
         self:process(cond_block)
      else
         if i==1 then
            self:emit"if"
         else
            self:emit"elseif"
         end
         self:emit(self:process(node[i])) -- expr
         self:emit"then"
         self:process(node[i + 1])        -- block
      end
   end
   self:emit"end"
end
function def:while_stmt(node)
   self:emit("while "..self:process(node[1]).." do local __break__ repeat")
   self:process(node[2])
   self:emit"until true if __break__ then break end end"
end
function def:throw_stmt(node)
   return '__throw__('..self:process(node[1])..')'
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

   local code = self.code

   local body = { }
   self.code = body
   self:process(node[1])
   self.code = code
   local try_func = 'function() '..table.concat(body, ' ')..' end'

   local catch_func = 'nil'
   if catch_node then
      local parm_list = self:process(catch_node[1])
      if self.in_class and parm_list[1] == 'this' then
         table.remove(parm_list, 1)
      end
      local body = { }
      self.code = body
      self:process(catch_node[2])
      self.code = code
      catch_func = 'function('..table.concat(parm_list, ', ')..') '..table.concat(body, ' ')..' end'
   end

   local finally_func = 'nil'
   if finally_node then
      local body = { }
      self.code = body
      self:process(finally_node[1])
      self.code = code
      finally_func = 'function() '..table.concat(body, ' ')..' end'
   end

   self:emit"do"
   local temp = self:genid()
   self:emit("local "..temp.." = __try_catch__("..try_func..", "..catch_func..", "..finally_func..')')
   self:emit("if #"..temp.." > 0 then return __select__(1, __unpack__("..temp..")) end")
   self:emit"end"
end

function def:continue_stmt(node)
   return 'do break end'
end
function def:break_stmt(node)
   return 'do __break__ = true break end'
end

function def:package_decl(node)
   local path = { }
   for i=1, #node do
      local iden = node[i]
      path[#path + 1] = iden[1]
   end
   return string.format('__package_create__(%q)', table.concat(path, '.'))
end

function def:import_stmt(node)
   local path = { }
   for i=1, #node do
      local iden = node[i]
      path[#path + 1] = iden[1]
   end
   return string.format('__package_import__(%q)', table.concat(path, "."))
end

function def:export_decl(node)
   local list = { }
   for i=1, #node do
      local iden = node[i]
      list[#list + 1] = iden[1]
   end
   return "__package_export__{"..table.concat(list, ', ').."}"
end

function compile(prog, name, opts)
   local cctx = Context.new()
   local bake = cctx:compile(prog, '='..name, opts)
   local file = io.open("a.out", "wb")
   file:write(bake)
   file:close()
   return bake
end

