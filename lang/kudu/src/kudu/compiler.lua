require"kudu.core"
require"kudu.grammar"
require"gaia.util"
require"sys"
require"sys.sock"

local Scope = { }
Scope.__index = Scope
Scope.new = function(outer, tag)
   local self = {
      entries = { };
      outer   = outer;
      tag     = tag or 'block';
   }
   return setmetatable(self, Scope)
end
Scope.define = function(self, name, info)
   local found = self:lookup(name)
   if found and found.const then
      return nil, "redefined const value:"..name
   end
   info = info or { }
   info.name = name
   self.entries[name] = info
   return info
end
Scope.lookup = function(self, name)
   if self.entries[name] then
      return self.entries[name], self
   elseif self.outer then
      return self.outer:lookup(name)
   end
end

local function lookup_class_member(scope, name)
   local cur = scope
   local got
   while cur do
      if cur.entries[name] and cur.tag == 'class' then
         got = cur.entries[name]
         break
      end
      cur = cur.outer
   end
   return got, cur
end

local Compiler = { }
Compiler.IDGEN = 9
Compiler.__index = Compiler
Compiler.new = function()
   return setmetatable({ }, Compiler)
end
Compiler.compile = function(self, script)
   self.source = script.source
   local root = kudu.grammar.match(script.source)
   print("AST:", root)
   self:enter_scope"global"
   for k,v in pairs(kudu.core.global) do
      self.scope:define(k, { modifier = 'global' })
   end
   root.name = script.name
   self.file = script.name

   local code = self:get('global', root)
   self:leave_scope()
   return code
end
Compiler.error = function(self, mesg)
   error(mesg.." on line: "..tostring(self.code.line))
end
Compiler.emit = function(self, ...)
   for i=1, select('#', ...) do
      local frag = select(i, ...)
      if frag == nil then break end
      local line = tostring(self.line or 1)
      self.code[#self.code + 1] = '\n--[['..self.file..':'..line..']] '..frag
   end
end
Compiler.gen = function(self, node)
   return self:get(node.tag, node)
end
Compiler.get = function(self, name, node, ...)
   if type(node) == "table" then
      local func = self.handlers[name]
      if func then
         local _1, _2 = func(self, node, ...)
         self:sync(node)
         return _1, _2
      end
      error("no handler for: "..tostring(name))
   else
      error("invalid node: "..tostring(node))
   end
end
Compiler.enter_scope = function(self, tag)
   self.scope = Scope.new(self.scope, tag)
   if tag == 'global' then
      self.scope.static = setmetatable({ }, { __index = kudu.core.global })
      self.scope.public = self.scope.static
   elseif tag == 'package' then
      self.scope.static = setmetatable({ }, { __index = self.scope.outer.static })
      self.scope.public = { }
   elseif tag == 'class' or tag == 'object' then
      self.scope.static = setmetatable({ }, { __index = self.scope.outer.static })
   end
end
Compiler.leave_scope = function(self)
   local scope = self.scope
   self.scope = self.scope.outer
   return scope
end
Compiler.enter_block = function(self)
   self.code = { outer = self.code, guard = self.code and self.code.guard }
end
Compiler.leave_block = function(self)
   local code = self.code
   self.code = self.code.outer
   print(table.concat(code, ' '))
   return table.concat(code, ' ')
end
Compiler.sync = function(self, node)
   if type(node) == 'table' and node.locn then
      self.line = node.locn.line
   end
end
Compiler.genid = function(self, prefix)
   Compiler.IDGEN = Compiler.IDGEN + 1
   return "__"..(prefix and prefix..'_' or '')..Compiler.IDGEN..'__'
end
Compiler.make_info = function(self, node, type)
   local info = {
      modifier = node.modifier or "lexical",
      attribute = node.attribute,
      type = type
   }
   if node.alloc == 'const' then
      info.const = true
   end
   local guard = node.guard
   if guard then
      if guard[1].tag == "ident" then
         info.guard = guard[1][1]
      elseif guard[1].tag == 'table_literal' then
         local like = self:genid"like"
         self:emit("local "..guard..'='..self:get('like_literal', { tag = 'like_literal', guard }))
         info.guard = like
      else
         error('NYI: info - '..tostring(guard))
      end
   end
   return info
end
Compiler.make_guard = function(self, node)
   local guard
   if node.guard then
      if node.guard[1].tag == 'ident' then
         guard = node.guard[1][1]
      elseif node.guard[1].tag == 'table_literal' then
         guard = self:genid"like"
         self:emit("local "..guard..'='..self:get('like_literal', { tag = 'like_literal'; node.guard[1] }))
      else
         error('NYI: info - '..tostring(node.guard[1]))
      end
   end
   return guard
end

Compiler.serialize = function(self, desc)
   if type(desc) ~= 'table' then return tostring(desc) end

   if desc.type == 'code' then
      return 'function('..table.concat(desc.params, ',')..') '..desc.code..' end'
   end

   if desc.type == 'name' then
      return tostring(desc.name)
   end

   if desc.type == 'table' then
      local buf = { }
      buf[#buf + 1] = '{'
      for k,v in pairs(desc.__elems__) do
         if k.type == 'name' then
            k = string.format('%q', k.name)
         end
         if v.type == 'function' then
            v = v.body
         end
         buf[#buf + 1] = '['..self:serialize(k)..']='..self:serialize(v)..';'
      end
      buf[#buf + 1] = '}'
      local grd = { }
      if desc.__guard__ then
         buf[#buf + 1] = ',{'
         for k,v in pairs(desc.__guard__) do
            if k.type == 'name' then
               k = string.format('%q', k.name)
            end
            buf[#buf + 1] = '['..self:serialize(k)..']='..self:serialize(v)..';'
         end
         buf[#buf + 1] = '}'
      end
      return '__table__('..table.concat(buf,'')..')'
   end

   if desc.type == 'array' then
      local buf = { }
      buf[#buf + 1] = '{["#size"]='..tostring(desc.count)..','
      for i=0, desc.count - 1 do
         buf[#buf + 1] = '['..tostring(i)..']='..self:serialize(desc.__elems__[i])..';'
      end
      buf[#buf + 1] = '}'
      local grd = { }
      if desc.__guard__ then
         buf[#buf + 1] = ',{'
         for k,v in pairs(desc.__guard__) do
            if k.type == 'name' then
               k = string.format('%q', k.name)
            end
            buf[#buf + 1] = '['..self:serialize(k)..']='..self:serialize(v)..';'
         end
         buf[#buf + 1] = '}'
      end
      return '__array__('..table.concat(buf,'')..')'
   end

   if desc.type == 'tuple' then
      local buf = { }
      for i=1, desc.count do
         buf[#buf + 1] = self:serialize(desc.elems[i])
      end
      return '__tuple__('..table.concat(buf, ',')..')'
   end

   if desc.type == 'string' then
      local val = desc.value
      if val:sub(1,1) == "'" then
         val = string.format('(%q)', val:sub(2,-2))
      else
         val = string.format('(%s)', val)
      end
      return val
   end

   if desc.type == 'number' or desc.type == 'boolean' or desc.type == 'nil' then
      return '('..tostring(desc.value)..')'
   end

   local buf = { }
   for k,v in pairs(desc) do
      if type(k) == 'string' then
         k = string.format('%q', k)
      end
      if type(k) == 'table' and k.type == 'name' then
         k = string.format('%q', k.name)
      end
      buf[#buf + 1] = '['..self:serialize(k)..']='
      if type(v) == 'string' then
         buf[#buf + 1] = string.format('%q', v)
      elseif type(v) == 'table' then
         buf[#buf + 1] = self:serialize(v)
      else
         buf[#buf + 1] = tostring(v)
         --error("bad field in descriptor: "..tostring(v))
      end
      buf[#buf + 1] = ';'
   end

   return "{"..table.concat(buf, '').."}"
end

Compiler.is_valid_lhs = function(self, node)
   local o = node[1].oper
   return o == '.' or o == '[' or o == '::' or o == '::['
      or (node[1].tag == "ident" and node[1][1] ~= 'this')
end

Compiler.ASSOPS = {
   ["="] = '=';
   ["+="] = "+";
   ["-="] = "-";
   ["*="] = "*";
   ["/="] = "/";
   ["**="] = "^";
   ["%="] = "%";
   ["~="] = "..";
   ["||="] = "or";
   ["&&="] = "and";
}
Compiler.BASSOPS = {
   ["&="] = "__band__";
   ["|="] = "__bor__";
   ["^="] = "__bxor__";
}
Compiler.handlers = {
   ['global'] = function(self, root)
      self:enter_block()
      self:emit"require'kudu.core'.init();"

      for i=1, #root do
         local node = root[i]
         if node.tag == 'var_decl' and node.modifier == 'static' then
            self.scope:define(name, { modifier = 'static' })
         elseif node.tag == 'func_decl' then
            if node.attribute ~= "" then
               self:error("function attributes not allowed outside of a class")
            end
            if node.modifier == 'static' then
               self.scope:define(node[1][1], { modifier = node.modifier })
            end
         elseif node.tag == 'rule_decl' then
            self.scope:define(node[1][1], { modifier = node.modifier, type = 'rule' })
         elseif node.tag == 'class_decl' then
            self.scope:define(node[1][1], { modifier = node.modifier })
         elseif node.tag == 'object_decl' then
            self.scope:define(node[1][1], { modifier = node.modifier })
         end
      end

      for i=1, #root do
         local expr = self:gen(root[i])
         if expr and expr ~= '' then self:emit(expr..';') end
      end

      local code = self:leave_block()
      return code
   end;

   ['import_stmt'] = function(self, node)
      local path = { }
      for i=1, #node do
         local iden = node[i]
         if type(iden) == 'string' then
            path[#path + 1] = iden
         else
            path[#path + 1] = iden[1]
         end
      end
      path = table.concat(path, ".")
      local pkg,sym = path:match"^(.-)%.([^.]+)$"
      local exports = kudu.core.require(pkg)
      if sym == "*" then
         for k,v in pairs(exports) do
            self:emit('local '..k..'='..pkg..'.'..k..';')
            self.scope:define(k, { modifier = "private" })
         end
      else
         if exports[sym] == nil then
            self:error(sym.." is not exported by "..pkg)
         end
         self:emit('local '..sym..'='..pkg..'.'..sym..';')
         self.scope:define(sym, { modifier = "private" })
      end
   end;

   ['slots_desc'] = function(self, node)
      local slot_list = { }
      local name_list = node[1]
      local expr_list = node[2]
      for i=1, #name_list do
         local iden = name_list[i]
         local expr = expr_list and expr_list[i] or nil

         local default = '(nil)'
         if expr then default = self:gen(expr) end

         local name = self:gen(iden)
         local info = self.scope:lookup(name)
         slot_list[#slot_list + 1] = {
            name     = name;
            guard    = { type = 'name', name = info.guard };
            default  = default;
            modifier = node.modifier;
         }
      end
      return slot_list
   end;

   ['method_desc'] = function(self, node)
      self:enter_scope"method"

      local name = node[1][1]
      local parm_node = node[2]
      local body_node = node[3]

      self:enter_block()

      local params = self:gen(parm_node)

      table.insert(params, 1, 'this')
      self.scope:define('this', { modifier = 'lexical' })

      self.code.guard = self:make_guard(node)
      for i=1, #body_node do
         local expr = self:gen(body_node[i])
         if expr then self:emit(expr..';') end
      end

      self:leave_scope()

      local code = self:leave_block()
      return {
         type      = 'method';
         name      = name;
         file      = self.file;
         body      = { type = 'code', code = code, params = params };
         params    = params;
         modifier  = node.modifier;
         attribute = node.attribute;
      }
   end;

   ['class_decl'] = function(self, node)
      self:enter_scope"class"
      local desc = self:get('class_desc', node, node[1], node[2], node[3])
      local code = desc.name..'=__class__('..self:serialize(desc)..')'
      self:emit(code..';')
      self:leave_scope()
   end;

   ['class_desc'] = function(self, node, iden, head, body)
      local name = iden[1]

      for i=1, #body do
         local node = body[i]
         if node.tag == 'var_decl' then
            local name_list, expr_list = node[1], node[2]
            for i=1, #name_list do
               local info = self:make_info(node)
               local iden = name_list[i]
               info.guard = self:make_guard(iden)
               self.scope:define(iden[1], info)
            end
         elseif node.tag == 'rule_decl' then
            self.scope:define(node[1][1], self:make_info(node,'rule'))
         elseif node.tag == 'func_decl' then
            self.scope:define(node[1][1], self:make_info(node))
         end
      end

      local base = 'nil'
      if head[1] and head[1][1] ~= "" then base = head[1][1][1] end

      self.scope:define("super", { modifier = "special" })

      local desc = {
         type    = 'class';
         slots   = { };
         methods = { };
         super   = { };
         traits  = { };
         rules   = { };
         name    = name or '<anon>';
      }

      if base ~= 'nil' then
         desc.parent = { type = 'name', name = base };
         self.scope.static['super'] = desc.super
      end

      for i=1, #body do
         local node = body[i]
         if node.tag == 'func_decl' then
            local meth = self:get('method_desc', node)
            desc.methods[#desc.methods + 1] = meth

         elseif node.tag == 'rule_decl' then
            local rule = self:get('rule_desc', node)
            desc.rules[rule.name] = rule

         elseif node.tag == 'var_decl' then
            local slots = self:get('slots_desc', node)
            for i=1, #slots do
               local slot = slots[i]
               desc.slots[slot.name] = slot
            end
         elseif node.tag == 'with_stmt' then
            desc.traits[#desc.traits + 1] = self:get('trait_desc', node[1])
         end
      end

      return desc
   end;

   ['trait_desc'] = function(self, node)
      local desc = { }
      local name = self:gen(node[1])
      local spec
      if node[2] then
         spec = self:get('table_desc', node[2])
      else
         spec = { __elems__ = { }, __guard__ = { } }
      end
      return {
         type   = 'trait';
         object = { type = 'name', name = name };
         spec   = spec;
      }
   end;

   ['object_decl'] = function(self, node)
      self:enter_scope"class"
      local desc = self:get('object_desc', node, node[1][1], node[2])
      local code = desc.name..'=__object__('..self:serialize(desc)..')'
      self:emit(code..';')
      self:leave_scope()
   end;

   ['object_desc'] = function(self, node, name, body)
      self:enter_scope"object"

      for i=1, #body do
         local node = body[i]
         if node.tag == 'var_decl' then
            local name_list, expr_list = node[1], node[2]
            for i=1, #name_list do
               local info = self:make_info(node)
               local iden = name_list[i]
               info.guard = self:make_guard(iden)
               self.scope:define(iden[1], info)
            end
         elseif node.tag == 'func_decl' then
            self.scope:define(node[1][1], self:make_info(node))
         elseif node.tag == 'rule_decl' then
            self.scope:define(node[1][1], self:make_info(node,'rule'))
         end
      end

      local desc = {
         type    = 'object';
         slots   = { };
         methods = { };
         traits  = { };
         rules   = { };
         name    = name or '<anon>';
      }
      for i=1, #body do
         local node = body[i]
         if node.tag == 'func_decl' then
            local meth = self:get('method_desc', node)
            desc.methods[#desc.methods + 1] = meth

         elseif node.tag == 'rule_decl' then
            local rule = self:get('rule_desc', node)
            desc.rules[rule.name] = rule

         elseif node.tag == 'var_decl' then
            local slots = self:get('slots_desc', node)
            for i=1, #slots do
               local slot = slots[i]
               desc.slots[slot.name] = slot
            end

         elseif node.tag == 'with_stmt' then
            desc.traits[#desc.traits + 1] = self:get('trait_desc', node[1])
         end
      end

      self:leave_scope()
      return desc
   end;

   ['like_desc'] = function(self, node)
      assert(node.tag == 'like_literal')
      return self:get('value_desc', node[1])
   end;

   ['rule_desc'] = function(self, node)
      local name, body
      if node.tag == 'rule_decl' then
         name = node[1][1]
         body = node[2]
      else
         name = self:genid"anon"
         body = node[1]
      end
      self:enter_scope"rule"
      self.scope.name = name
      local desc = { name = name, type = 'rule' }
      local code = self:get('rule_body', body)
      desc.body = { type = 'code', code = code, params = { 'this' } }
      self:leave_scope"rule"
      return desc
   end;

   ['rule_decl'] = function(self, node)
      return 'local '..node[1][1]..'=LPeg.P{'..self:gen(node[2])..'}'
   end;

   ['rule_body'] = function(self, node)
      local body = self:gen(node[1])
      return 'return '..body
   end;

   ['rule_seq'] = function(self, node)
      local buf = { }
      local pre = ''
      local i=1
      while i <= #node do
         if node[i] == '&' then
            pre = '#'
            i = i + 1
         elseif node[i] == '!' then
            i = i + 1
            pre = '-'
         else
            pre = ''
         end

         buf[#buf + 1] = pre..self:gen(node[i])
         i = i + 1
      end
      return table.concat(buf, '*')
   end;
   ['rule_alt'] = function(self, node)
      local a = self:gen(node[1])
      local b = self:gen(node[2])
      return a.."+"..b
   end;
   ['rule_rep'] = function(self, node)
      local rep = node.oper
      if rep == '*' then
         return self:gen(node[1])..'^0'
      elseif rep == '+' then
         return self:gen(node[1])..'^1'
      elseif rep == '?' then
         return self:gen(node[1])..'^-1'
      elseif rep == '^' then
         return self:gen(node[1])..'^'..self:gen(node[2])
      end
      error("NYI:"..tostring(node))
   end;
   ['rule_term'] = function(self, node)
      local str = self:get('string', node[1])
      return 'LPeg.P'..str
   end;
   ['rule_class'] = function(self, node)
      local buf = { }
      local neg = false
      for i=1, #node do
         if i==1 and node[i] == '^' then
            neg = true
         elseif type(node[i]) == 'table' then
            buf[#buf + 1] = self:gen(node[i])
         else
            buf[#buf + 1] = 'LPeg.P('..string.format('%q', node[i])..')'
         end
      end
      local pat = table.concat(buf, '+')
      if neg then
         return '(LPeg.P(1)-('..pat..'))'
      end
      return pat
   end;

   ['rule_ref'] = function(self, node)
      if node[1].tag == 'ident' then
         local name = node[1][1]
         local info, scope = self.scope:lookup(name)
         if info and info.type == 'rule' and scope == self.scope.outer then
            return 'LPeg.V('..string.format('%q', node[1][1])..')'
         end
      end
      return self:gen(node[1])
   end;

   ['rule_back_capt'] = function(self, node)
      return 'LPeg.Cb('..string.format('%q', node[1][1])..')'
   end;

   ['rule_any'] = function(self, node)
      return 'LPeg.P(1)'
   end;
   ['rule_range'] = function(self, node)
      return 'LPeg.R('..string.format('%q',node[1])..')'
   end;
   ['rule_group'] = function(self, node)
      local buf = { }
      for i=1, #node do
         buf[#buf + 1] = self:gen(node[i])
      end
      return '('..table.concat(buf)..')'
   end;
   ['rule_group_capt'] = function(self, node)
      if node.name then
         local name = node.name[1]
         return 'LPeg.Cg('..self:gen(node[1])..','..string.format('%q', name)..')'
      else
         return 'LPeg.Cg('..self:gen(node[1])..')'
      end
   end;
   ['rule_simple_capt'] = function(self, node)
      return 'LPeg.C('..self:gen(node[1])..')'
   end;
   ['rule_pos_capt'] = function(self, node)
      return 'LPeg.Cp()'
   end;
   ['rule_sub_capt'] = function(self, node)
      return 'LPeg.Cs('..self:gen(node[1])..')'
   end;
   ['rule_prod'] = function(self, node)
      local oper = node.oper
      local opnd
      if oper == '->' then
         if node[2].tag == 'table_literal' then
            return 'LPeg.Ct('..self:gen(node[1])..')'
         end
         return self:gen(node[1])..'/'..self:gen(node[2])
      elseif oper == '=>' then
         return 'LPeg.Cf('..self:gen(node[1])..','..self:gen(node[2])..')'
      end
   end;

   ['table_desc'] = function(self, node)
      local desc = { type = 'table', __elems__ = { } }
      for i=1, #node, 2 do
         local key, grd, val
         key = self:get('value_desc', node[i])
         val = self:get('value_desc', node[i + 1][1])
         if node[i].guard then
            grd = self:get('value_desc', node[i].guard)
            if not desc.__guard__ then
               desc.__guard__ = { }
            end
            desc.__guard__[key] = grd
         end
         desc.__elems__[key] = val
      end
      return desc
   end;

   ['array_desc'] = function(self, node)
      local desc = { type = 'array', __elems__ = { } }
      for i=1, #node do
         local key, grd, val
         key = i - 1
         val = self:get('value_desc', node[i][1])
         if node[i].guard then
            grd = self:get('value_desc', node[i].guard)
            if not desc.__guard__ then
               desc.__guard__ = { }
            end
            desc.__guard__[key] = grd
         end
         desc.__elems__[key] = val
      end
      desc.count = #node
      return desc
   end;

   ['tuple_desc'] = function(self, node)
      local desc = { type = 'tuple', elems = { } }
      for i=1, #node do
         local val = self:get('value_desc', node[i][1])
         desc.elems[i] = val
      end
      desc.count = #node
      return desc
   end;

   ['value_desc'] = function(self, node)
      if node.tag == 'nil' then
         return { type = 'nil', value = nil }
      elseif node.tag == 'false' then
         return { type = 'boolean', value = false }
      elseif node.tag == 'true' then
         return { type = 'boolean', value = true }
      elseif node.tag == 'number' then
         return { type = 'number', value = tonumber(node[1]) }
      elseif node.tag == 'string' then
         local str = node[1]
         if str:sub(1,1) == "'" then str = string.format('%q', str:sub(2,-2)) end
         return { type = 'string', value = str }
      elseif node.tag == 'ident' then
         return { type = 'name', name = node[1] }
      elseif node.tag == 'table_literal' then
         return self:get('table_desc', node)
      elseif node.tag == 'tuple_literal' then
         return self:get('tuple_desc', node)
      elseif node.tag == 'array_literal' then
         return self:get('array_desc', node)
      elseif node.tag == 'func_literal' then
         return self:get('function_desc', node, '<anon>', node[1], node[2])
      elseif node.tag == 'object_literal' then
         return self:get('object_desc', node, '<anon>', node[1], node[2])
      end
      return self:gen(node)
   end;

   ['function_desc'] = function(self, node, name, parm, body)
      self:enter_scope"function"
      self:enter_block()

      self.code.guard = self:make_guard(node)

      local params = self:gen(parm)
      for i=1, #body do
         local expr = self:gen(body[i])
         if expr then self:emit(expr..';') end
      end

      self:leave_scope()
      return {
         type   = 'function',
         file   = self.file,
         name   = name,
         params = params,
         guard  = self.code.guard,
         body   = {
            type   = 'code',
            code   = self:leave_block(),
            params = params,
         },
      }
   end;

   ['block'] = function(self, node)
      self:emit"do"
      self:enter_scope"block"
      for i=1, #node do
         self:emit(self:gen(node[i]..';'))
      end
      self:leave_scope()
      self:emit"end"
   end;

   ['ident'] = function(self, node)
      if node[1] == '__LINE__' and self.scope:lookup('__LINE__') == nil then
         return self.line
      end
      if node[1] == '__FILE__' and self.scope:lookup('__FILE__') == nil then
         return string.format('%q', self.file)
      end
      local found = self.scope:lookup(node[1])
      if not found then self:error(node[1].." is not defined") end
      return node[1]
   end;

   ['string'] = function(self, node)
      local str = node[1]
      if str:sub(1,1) == "'" then
         return string.format('(%q)', str:sub(2,-2))
      else
         return string.format('(%s)', str)
      end
   end;

   ['number'] = function(self, node)
      return '('..tostring(node[1])..')'
   end;

   ['nil'] = function(self, node)
      return '(nil)'
   end;

   ['true'] = function(self, node)
      return '(true)'
   end;

   ['false'] = function(self, node)
      return '(false)'
   end;

   ['this'] = function(self, node)
      return 'this'
   end;

   ['spread'] = function(self, node)
      local expr = self:gen(node[1])
      return '__spread__('..expr..')'
   end;

   ['range'] = function(self, node)
      local min, max = self:gen(node[1]), self:gen(node[2])
      return '__range__('..min..','..max..')'
   end;

   ['enum_stmt'] = function(self, node)
      local terms = { }
      local ident = node[1][1]
      for i=2, #node do
         terms[#terms + 1] = string.format('%q', node[i][1])
      end
      self:emit(ident..' = __enum__{'..table.concat(terms, ',')..'}')
      self.scope:define(ident, { modifier = 'static' })
   end;

   ['for_stmt'] = function(self, node)
      local iden = node[1][1]
      self:enter_scope"block"
      self.scope:define(iden, { modifier = "lexical" })
      local init = self:gen(node[2])
      local last = self:gen(node[3])
      local step
      if node[4] ~= "" then
         step = self:gen(node[4])
      else
         step = '1'
      end
      local vars = { init, last, step }
      self:emit("for "..iden..'='..table.concat(vars, ',')..' do local __break__ repeat')
      self:gen(node[5])
      self:emit"until true if __break__ then break end end"
      self:leave_scope()
   end;

   ['for_in_stmt'] = function(self, node)
      self:enter_scope"block"
      local vars = { }
      for i=1, #node[1] do
         self.scope:define(node[1][i][1], { modifier = "lexical" })
         vars[#vars + 1] = self:gen(node[1][i])
      end
      local expr = self:gen(node[2])
      self:emit("for "..table.concat(vars, ', ')..' in __each__('..expr[1]..') do local __break__ repeat')
      self:gen(node[3])
      self:emit"until true if __break__ then break end end"
      self:leave_scope()
   end;

   ['cond_block'] = function(self, node)
      self:enter_scope"block"
      self:enter_block()
      for i=1, #node do
         local expr = self:gen(node[i])
         if expr then self:emit(expr..';') end
      end
      self:emit(self:leave_block())
      self:leave_scope()
   end;

   ['expr'] = function(self, node)
      for i=1, #node do
         node[i].is_lhs = node.is_lhs
      end
      return self:gen(node[1])
   end;

   ['expr_noin'] = function(self, node)
      return self:get('expr', node)
   end;

   ['expr_base'] = function(self, node)
      return self:get('expr', node)
   end;

   ['list_expr'] = function(self, node)
      local list = { }
      local oper = node[1]
      for i=1, #oper do
         local item = oper[i]
         if item ~= "" then
            list[#list + 1] = self:gen(item)
         end
      end
      return list
   end;

   ['list_expr_noin'] = function(self, node)
      return self:get('list_expr', node)
   end;

   ['with_spec'] = function(self, node)
      return self:serialize(self:get('trait_desc', node))
   end;

   ['op_ternary'] = function(self, node)
      return self:gen(node.test)..' and '..self:gen(node[1])..' or '..self:gen(node[2])
   end;

   ['op_infix'] = function(self, node)
      local o = node.oper
      local a, b, q

      a = self:gen(node[1])
      if node[2].tag == 'ident' then
         b = node[2][1]
      else
         b = self:gen(node[2])
      end
      if o == "." or o == '::' then
         local is_private
         if a == 'this' then
            local found, scope = lookup_class_member(self.scope, b)
            if found then
               if found.modifier == "private" then
                  b = '#'..b
                  is_private = true
               end
            end
         end
         if not q then
            q = string.format('%q', b)
         end
         if node.is_lhs then
            if o == '::' then
               return { '__rawset__('..a..','..q..',%s)' }
            end
            return { a..'['..q..'] = %s' }
         else
            if node.is_call then
               local args = node.call_expr
               if a == 'super' then
                  table.insert(args, 1, 'this')
                  return 'super['..q..']'
               end
               if is_private then
                  if o ~= '::' then
                     table.insert(args, 1, 'this')
                  end
                  return a..'['..q..']'
               end
               if o == '::' then
                  return a..'.'..b
               end
               return a..':'..b
            end
            if o == '::' then
               return '__rawget__('..a..','..q..')'
            end
            return a..'['..q..']'
         end
      end

      a, b = self:gen(node[1]), self:gen(node[2])

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
      elseif o == "~"  then return '__cat__('..a..", "..b..')'

      -- bitwise ops
      elseif o == "|" then return "__bor__("..a..", "..b..")"
      elseif o == "&" then return "__band__("..a..", "..b..")"
      elseif o == "^" then return "__bxor__("..a..", "..b..")"
      elseif o == ">>" then return "__rshift__("..a..", "..b..")"
      elseif o == ">>>" then return "__arshift__("..a..", "..b..")"
      elseif o == "<<" then return "__lshift__("..a..", "..b..")"

      -- type and structural
      elseif o == 'instanceof' then return '__instanceof__('..a..', '..b..')'
      elseif o == 'in' then return '__has__('..b..', '..a..')'
      elseif o == 'is' then return '__isa__('..a..', '..b..')'
      elseif o == 'with' then return '__with__('..a..', '..b..')'

      else error("NYI: infix operator: "..o) end
   end;

   ['op_postcircumfix'] = function(self, node)
      local oper = node.oper
      local expr
      if node[2] ~= nil and node[2] ~= "" then
         expr = self:gen(node[2])
      else
         expr = { }
      end
      if oper == "(" then
         node[1].is_call = true
         node[1].call_expr = expr
         local base = self:gen(node[1])
         return base..'('..table.concat(expr, ',')..')'
      elseif oper == "[" or oper == '::[' then
         local base = self:gen(node[1])
         if node.is_lhs then
            if oper == '::[' then
               return { '__rawset__('..base..','..expr..',%s)' }
            end
            return { base..'['..expr..'] = %s' }
         elseif node.is_call and oper ~= '::[' then
            local args = node.call_expr
            table.insert(args, 1, base)
            table.insert(args, 2, expr)
            return '__send__'
         else
            if oper == '::[' then
               return '__rawget__('..base..','..expr..')'
            end
            return base..'['..expr..']'
         end
      end
      --error("NYI")
   end;

   ['op_prefix'] = function(self, node)
      local o = node.oper
      if o == "new" then
         local iden
         if node[1].tag == 'ident' then
            iden = self:gen(node[1])
         else -- postcircumfix
            iden = self:gen(node[1][1])
         end
         local expr = node[1][2]
         if expr then
            args = self:gen(expr)
         else
            args = { }
         end
         table.insert(args, 1, iden)
         return '__new__('..table.concat(args, ',')..')'
      end
      local a = self:gen(node[1])
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
      elseif o == 'typeof' then
         return '__typeof__('..a..')'
      end
   end;

   ['op_postfix'] = function(self, node)
      local o = node.oper
      local a = self:gen(node[1])
      if o == "++" then
         local temp = self:genid()
         self:emit("local "..temp..' = '..a)
         self:emit(a..' = '..a..' + 1')
         if node.is_rhs then
            return temp
         else
            return ''
         end
      elseif o == "--" then
         local temp = self:genid()
         self:emit("local "..temp..' = '..a)
         self:emit(a..' = '..a..' - 1')
         if node.is_rhs then
            return temp
         else
            return ''
         end
      end
   end;

   ['op_circumfix'] = function(self, node)
      local nops = { }
      for i=1, #node do
         nops[#nops + 1] = self:gen(node[1])
      end
      return '('..table.concat(nops, ' ')..')'
   end;

   ['late_bind'] = function(self, node)
      return self:get('expr', node[1])
   end;

   ['var_decl'] = function(self, node)
      local name_list, expr_list = node[1], node[2] or { }
      local lhs, rhs = { }, { }

      for i=1, #name_list do
         local iden = name_list[i]
         local expr = expr_list[i]
         local info = self:make_info(node)
         info.guard = self:make_guard(iden)
         self.scope:define(iden[1], info)

         lhs[#lhs + 1] = iden[1]

         if expr then
            rhs[i] = self:gen(expr)
            if type(rhs[i]) == 'table' then
               rhs[i] = string.format(rhs[i][1], rhs[i][2])
            end
         else
            if info.const then
               self:error("TypeError: constant declared without a value")
            end
         end
         if info.guard then
            rhs[i] = info.guard..'('..tostring(rhs[i])..')'
         end
      end

      return "local "..table.concat(lhs, ',')..(#rhs > 0 and '='..table.concat(rhs, ',') or '')
   end;

   ['bind_stmt'] = function(self, node)
      local oper, node = node.oper, node[1]
      local lhs_expr_list, rhs_expr_list = node[1], node[2]
      local lhs, rhs = { }, { }

      for i=1, #lhs_expr_list do
         local lhs_expr = lhs_expr_list[i]
         local rhs_expr = rhs_expr_list[i]

         lhs[#lhs + 1] = self:gen(lhs_expr)

         if rhs_expr then
            rhs[i] = self:gen(rhs_expr)
            if type(rhs[i]) == 'table' then
               rhs[i] = string.format(rhs[i][1], rhs[i][2])
            end
         end

         if lhs_expr[1].tag == 'ident' then
            local info = self.scope:lookup(lhs_expr[1][1])
            if info.guard then
               rhs[i] = info.guard..'('..tostring(rhs[i])..')'
            end
         end
      end
      if #rhs > 0 then
         return table.concat(lhs, ',')..'='..table.concat(rhs, ',')
      else
         return table.concat(lhs, ',')
      end
   end;

   ['binop_bind'] = function(self, node)
      node = node[1]
      local lhs_expr, rhs_expr = node[1], node[2]

      for i=1, #lhs_expr do
         lhs_expr[i].is_lhs = true
      end
      local a = self:gen(lhs_expr)
      local b = self:gen(rhs_expr)

      if lhs_expr[1].tag == 'ident' then
         local found, scope = self.scope:lookup(lhs_expr[1][1])
         if found.const then
            self:error("TypeError: attempt to modify '"..a.."' (a constant value)")
         end
         if found.guard then
            b = found.guard..'('..b..')'
         end
      end

      local o = node.oper
      if self.ASSOPS[o] then
         return a..'='..a..self.ASSOPS[o]..b
      elseif self.BASSOPS[o] then
         return a..'='..self.BASSOPS[o]..'('..a..', '..b..'))'
      end
   end;

   ['func_params'] = function(self, node)
      local list = { }
      for i=1,#node do
         if node[i].tag == "rest" then
            list[#list + 1] = "..."
            local name = node[i][1][1]
            local info = self:make_info(node[i][1])
            self.scope:define(name, info)
            self:emit('local '..name..'=__tuple__(...)')
            if info.guard then
               self:emit('for i,v in __each__('..name..') do')
               self:emit(name..'[i]='..info.guard..'('..name..'[i])')
               self:emit('end')
            end
            break
         end
         local name = node[i][1]
         local info = self:make_info(node[i])
         if info.guard then
            self:emit(name..'='..info.guard..'('..name..');')
         end
         self.scope:define(name, info)
         list[#list + 1] = name
      end
      return list
   end;

   ['short_lambda'] = function(self, node)
      self:enter_scope"function"
      self:enter_block()

      node[1].tag = 'func_params'
      local parm_list = self:gen(node[1])

      local guard = self:make_guard(node)
      local expr = self:gen(node[2])
      if expr then self:emit(expr) end

      self:leave_scope()
      local body = self:leave_block()
      if guard then
         body = 'return '..guard..'('..body..')'
      else
         body = 'return '..body
      end
      return 'function('..table.concat(parm_list, ', ')..') '..body..' end'
   end;

   ['func_literal'] = function(self, node)
      self:enter_scope"function"
      self:enter_block()

      self.code.guard = self:make_guard(node)

      local parm_list = self:gen(node[1])
      for i=1, #node[2] do
         local expr = self:gen(node[2][i])
         if expr then self:emit(expr) end
      end

      self:leave_scope()
      return 'function('..table.concat(parm_list, ', ')..') '..self:leave_block()..' end'
   end;

   ['func_decl'] = function(self, node)
      local name = node[1][1]

      self.scope:define(name, { modifier = node.modifier })
      self.code.guard = self:make_guard(node)

      self:enter_scope"function"
      self:enter_block()

      local parm_list = self:gen(node[2])
      for i=1, #node[3] do
         local expr = self:gen(node[3][i])
         if expr then self:emit(expr) end
      end

      self:leave_scope()
      local func = 'function '..name..'('..table.concat(parm_list, ', ')..') '..self:leave_block()..' end'
      if self.scope.tag == 'package' or self.scope.tag == 'global' then
         self:emit(func)
      else
         self:emit('local '..func)
      end
   end;

   ['expr_list'] = function(self, node)
      local list = { }
      for i=1, #node do
         list[#list + 1] = self:gen(node[i])
      end
      return list
   end;

   ['yield_stmt'] = function(self, node)
      local expr_list = node[1]
      local list = { }
      if expr_list then
         for i=1, #expr_list do
            list[#list + 1] = self:gen(expr_list[i])
         end
      end
      if self.code.guard then
         local guard = self.code.guard
         --table.insert(list, 1, guard)
         --return 'do return __coerce__('..table.concat(list, ',')..') end'
         return '__yield__('..guard..'('..table.concat(list, ',')..'))'
      end
      return '__yield__('..table.concat(list, ',')..')'
   end;

   ['return_stmt'] = function(self, node)
      local expr_list = node[1]
      local list = { }
      if expr_list then
         for i=1, #expr_list do
            list[#list + 1] = self:gen(expr_list[i])
         end
      end
      if self.code.guard then
         local guard = self.code.guard
         --table.insert(list, 1, guard)
         --return 'do return __coerce__('..table.concat(list, ',')..') end'
         return 'do return '..guard..'('..table.concat(list, ',')..') end'
      end
      return 'do return '..table.concat(list, ',')..' end'
   end;

   ['guard_expr'] = function(self, node)
      if node[1].tag == 'ident' then
         return self:gen(node[1])
      else
         if node[1].tag == 'table_literal' then
            return self:get('table', node[1])
         else
            return self:get('array', node[1])
         end
      end
   end;

   ['table_literal'] = function(self, node)
      return self:serialize(self:get('table_desc', node))
   end;

   ['tuple_literal'] = function(self, node)
      return self:serialize(self:get('tuple_desc', node))
   end;

   ['array_literal'] = function(self, node)
      return self:serialize(self:get('array_desc', node))
   end;

   ['object_literal'] = function(self, node)
      local name = 'object'
      local head = node[1]
      local body = node[2]
      local desc = self:get('object_desc', node, name, head, body)
      local object = '__object__('..self:serialize(desc)..')'
      --print(object)
      return object
   end;

   ['like_literal'] = function(self, node)
      local desc = self:get('like_desc', node)
      local like = '__like__('..self:serialize(desc)..')'
      return like
   end;

   ['regexp_literal'] = function(self, node)
      local args = { string.format('%q', node[1]) }
      if node[2] then
         args[#args + 1] = string.format('%q', node[2])
      end
      return '__pattern__('..table.concat(args, ',')..')'
   end;

   ['if_stmt'] = function(self, node)
      for i=1, #node, 2 do
         if i == #node and i % 2 == 1 then
            local cond_block = node[i]
            self:emit"else"
            self:gen(cond_block)
         else
            if i==1 then
               self:emit"if"
            else
               self:emit"elseif"
            end
            self:emit(self:gen(node[i])) -- expr
            self:emit"then"
            self:gen(node[i + 1])        -- block
         end
      end
      self:emit"end"
   end;

   ['while_stmt'] = function(self, node)
      self:emit("while "..self:gen(node[1]).." do local __break__ repeat")
      self:enter_scope"block"
      self:gen(node[2])
      self:leave_scope()
      self:emit"until true if __break__ then break end end"
   end;

   ['throw_stmt'] = function(self, node)
      return '__throw__('..self:gen(node[1])..')'
   end;

   ['try_catch'] = function(self, node)
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

      self:enter_scope"block"
      self:enter_block()
      self:gen(node[1])
      self:leave_scope()

      local try_func = 'function() '..self:leave_block()..' end'

      local catch_func = 'nil'
      if catch_node then
         self:enter_scope"block"
         self:enter_block()
         local parm_list = self:gen(catch_node[1])
         self:gen(catch_node[2])
         catch_func = 'function('..table.concat(parm_list, ', ')..') '..self:leave_block()..' end'
         self:leave_scope()
      end

      local finally_func = 'nil'
      if finally_node then
         self:enter_scope"block"
         self:enter_block()
         self:gen(finally_node[1])
         self:leave_scope()
         finally_func = 'function() '..self:leave_block()..' end'
      end

      self:emit"do"
      local temp = self:genid()
      self:emit("local "..temp.." = __try_catch__("..try_func..", "..catch_func..", "..finally_func..')')
      self:emit("if #"..temp.." > 0 then return __select__(1, __unpack__("..temp..")) end")
      self:emit"end"
   end;

   ['continue_stmt'] = function(self, node)
      return 'do break end'
   end;

   ['break_stmt'] = function(self, node)
      return 'do __break__ = true break end'
   end;

   ['package_decl'] = function(self, node)
      local path = { }
      for i=1, #node do
         local iden = node[i]
         path[#path + 1] = iden[1]
      end

      local curr = kudu.core.global
      for i=1, #path - 1 do
         local frag = path[i]
         local base = rawget(curr, frag)
         if not base then
            base = { }
            rawset(curr, frag, base)
         elseif type(curr) ~= "table" then
            error(string.format("name conflict for namespace '%s'", table.concat(path, '.')))
            break
         end
         curr = base
      end

      local name = path[#path]
      self:enter_scope"package"
      curr[name] = self.scope.public

      self:emit('__package__('..self:serialize({ path = path, name = name })..')')
   end;

   ['export_decl'] = function(self, node)
      local list = { }
      for i=1, #node do
         local iden = node[i]
         list[#list + 1] = iden[1]
      end
      return "__export__{"..table.concat(list, ', ').."}"
   end;
}

return Compiler
