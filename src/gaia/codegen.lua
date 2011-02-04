module("gaia.codegen", package.seeall)

local IDGEN = 9
local function genid()
   IDGEN = IDGEN + 1
   return '_'..IDGEN
end

local function class(class)
   class.__index = class
   setmetatable(class, {
      __call = function(_, self)
         if type(self) ~= "table" then self = { self } end
         return setmetatable(self, class)
      end;
   })
   return class
end
local LINE = 1
local function line(node, buf)
   if node.line and node.line > LINE then
      buf[#buf + 1] = string.rep("\n", node.line - LINE)
      LINE = node.line
   end
end

local VARS = 0
local function alloc()
   VARS = VARS +  1
   return '_'..VARS
end
local function free()
   VARS = VARS - 1
end

local function temp()
   local var = alloc()
   free()
   return var
end

Id = class{ tag = "Id" }
Id.render = function(self)
   return self[1]:gsub('[()]', '__')
end

Block = class{ tag = "Block" }
Block.render = function(self)
   local buf = { }
   buf[#buf + 1] = "do"
   for i=1, #self do
      buf[#buf + 1] = self[i]:render()
   end
   buf[#buf + 1] = "end"
   return table.concat(buf, ' ')
end

local binops = {
   ["eq"] = "==";
   ["ne"] = "~=";
   ["ge"] = ">=";
   ["le"] = "<=";
   ["lt"] = "<";
   ["gt"] = ">";
   ["add"] = "+";
   ["sub"] = "-";
   ["mul"] = "*";
   ["div"] = "/";
   ["mod"] = "%";
   ["pow"] = "^";
   ["and"] = "and";
   ["or"] = "or";
   ["concat"] = "..";
}

local unaryops = {
   ["not"] = "not";
   ["unm"] = "-";
   ["len"] = "#";
}

Op = class{ tag = "Op" }
Op.render = function(self)
   local buf = { }
   if binops[self[1]] then
      buf[#buf + 1] = self[2]:render()
      buf[#buf + 1] = binops[self[1]]
      buf[#buf + 1] = self[3]:render()
   elseif unaryops[self[1]] then
      buf[#buf + 1] = unaryops[self[1]]
      buf[#buf + 1] = self[2]:render()
   end
   return table.concat(buf, ' ')
end

Function = class{ tag = "Function" }
Function.render = function(self)
   local buf = { }
   line(self, buf)
   buf[#buf + 1] = "function"
   buf[#buf + 1] = "("
   for i=1, #self[1] do
      buf[#buf + 1] = self[1][i]:render()
      if i ~= #self[1] then buf[#buf + 1] = "," end
   end
   buf[#buf + 1] = ")"
   for i=1, #self[2] do
      buf[#buf + 1] = self[2][i]:render()
   end
   buf[#buf + 1] = "end"
   return table.concat(buf, ' ')
end

Nil = class{ tag = "Nil" }
Nil.render = function(self)
   return 'nil'
end

True = class{ tag = "True"; true }
True.render = function(self)
   return 'true'
end

False = class{ tag = "False"; false }
False.render = function(self)
   return 'false'
end

Rest = class{ tag = "Rest" }
Rest.render = function(self)
   return '...'
end

String = class{ tag = "String" }
String.render = function(self)
   return string.format('%q', self[1])
end

Number = class{ tag = "Number" }
Number.render = function(self, buf)
   return tostring(self[1])
end

Ops = class{ tag = "Ops" }
Ops.render = function(self, buf)
   local buf = { }
   for i=1, #self do
      buf[#buf + 1] = self[i]:render()
   end
   return table.concat(buf, ' ')
end

Set = class{ tag = "Set" }
Set.render = function(self)
   local buf = { }
   local lhs, rhs = self[1], self[2]
   for i=1, #lhs do
      buf[#buf + 1] = lhs[i]:render(buf)
      if i ~= #lhs then buf[#buf + 1] = "," end
   end
   buf[#buf + 1] = "="
   for i=1, #rhs do
      buf[#buf + 1] = rhs[i]:render()
      if i ~= #rhs then buf[#buf + 1] = "," end
   end
   return table.concat(buf, ' ')
end

Table = class{ tag = "Table" }
Table.render = function(self)
   local buf = { }
   buf[#buf + 1] = "{"
   for k,v in pairs(self) do
      if v.tag == "Pair" then
         buf[#buf + 1] = v:render()
      else
         buf[#buf + 1] = "["
         if type(k) == "string" then
            buf[#buf + 1] = string.format("%q", k)
         elseif type(k) == "table" then
            buf[buf + 1] = k:render()
         else
            buf[#buf + 1] = k
         end
         buf[#buf + 1] = "]"
         buf[#buf + 1] = "="
         buf[#buf + 1] = v:render()
      end
      buf[#buf + 1] = ";"
   end
   buf[#buf + 1] = "}"
   return table.concat(buf, ' ')
end

Pair = class{ tag = "Pair" }
Pair.render = function(self)
   return "["..self[1]:render().."] = "..self[2]:render()
end

local function is_scalar(node)
   return
      node.tag == "True"   or
      node.tag == "False"  or
      node.tag == "Nil"    or
      node.tag == "String" or
      node.tag == "Number" or
      node.tag == "Function"
end

Index = class{ tag = "Index" }
Index.render = function(self)
   local buf = { }
   if is_scalar(self[1]) then
      buf[#buf + 1] = "("
   end
   buf[#buf + 1] = self[1]:render()
   if is_scalar(self[1]) then
      buf[#buf + 1] = ")"
   end
   local key
   if type(self[2]) == 'string' then
      key = string.format('%q', self[2])
   else
      key = self[2]:render()
   end
   buf[#buf + 1] = "["..key.."]"
   return table.concat(buf, ' ')
end

Local = class{ tag = "Local" }
Local.render = function(self)
   local buf = { }
   local lhs, rhs = self[1], self[2]
   buf[#buf + 1] = 'local'
   local vars = { }
   for i=1, #lhs do
      vars[#vars + 1] = lhs[i]:render()
   end
   buf[#buf + 1] = table.concat(vars, ', ')
   if rhs then
      local vals = { }
      for i=1, #rhs do
         vals[#vals + 1] = rhs[i]:render(buf)
      end
      buf[#buf + 1] = table.concat(vars, ',')..'='..table.concat(vals, ',')
   end
   return table.concat(buf, ' ')
end

Call = class{ tag = "Call" }
Call.render = function(self)
   local buf = { }
   buf[#buf + 1] = self[1]:render(buf)
   buf[#buf + 1] = "("
   for i=2, #self do
      buf[#buf + 1] = self[i]:render()
      if i ~= #self then buf[#buf + 1] = "," end
   end
   buf[#buf + 1] = ")"
   return table.concat(buf, ' ')
end

Invoke = class{ tag = "Invoke" }
Invoke.render = function(self, code)
   local buf = { }
   local this
   local meth
   if type(self[2]) == 'string' then
      meth = string.format('%q', self[2])
   else
      meth = self[2]:render()
   end
   local args = { }
   if #self >= 3 then
      for i=3, #self do
         args[#args + 1] = self[i]:render()
      end
   end
   if self[1].tag == 'Invoke' then
      local call = self[1]:render(code)
      this = temp()
      code[#code + 1] = 'local '..this..' = '..call
   else
      this = self[1]:render()
   end

   table.insert(args, 1, this)
   args = table.concat(args, ', ')

   return this..'['..meth..']('..args..')'
end

Return = class{ tag = "Return" }
Return.render = function(self)
   local buf = { }
   buf[#buf + 1] = 'return'
   for i=1, #self do
      buf[#buf + 1] = self[i]:render()
   end
   return table.concat(buf, ' ')
end

If = class{ tag = "If" }
If.render = function(self)
   local buf = { }
   for i=1, #self, 2 do
      if i == #self and i % 2 == 1 then
         buf[#buf + 1] = "else"
         buf[#buf + 1] = self[i]:render()
      else
         if i==1 then
            buf[#buf + 1] = "if"
         else
            buf[#buf + 1] = "elseif"
         end
         buf[#buf + 1] = self[i]:render()
         buf[#buf + 1] = "then"
         for i=1, #self[i + 1] do
            buf[#buf + 1] = self[i + 1][i]:render()
         end
      end
   end
   buf[#buf + 1] = "end"
   return table.concat(buf, ' ')
end

For = class{ tag = "For" }
For.render = function(self)
   local buf = { }
   buf[#buf + 1] = "for"
   if not self[4] then self[4] = Number(1) end
   buf[#buf + 1] = self[1]:render()
   buf[#buf + 1] = "="
   buf[#buf + 1] = self[2]:render()
   buf[#buf + 1] = ","
   buf[#buf + 1] = self[3]:render()
   buf[#buf + 1] = ","
   buf[#buf + 1] = self[4]:render()
   buf[#buf + 1] = "do"
   for i=1, #self[5] do
      buf[#buf + 1] = self[5][i]:render()
   end
   buf[#buf + 1] = "end"
   return table.concat(buf, ' ')
end

ForIn = class{ tag = "ForIn" }
ForIn.render = function(self)
   local vars = self[1]
   local exps = self[2]
   local body = self[3]
   buf[#buf + 1] = "for"
   for i=1, #vars do
      buf[#buf + 1] = vars[i]:render()
      if i ~= #vars then buf[#buf + 1] = "," end
   end
   buf[#buf + 1] = "in"
   for i=1, #exps do
      buf[#buf + 1] = exps[i]:render()
      if i ~= #exps then buf[#buf + 1] = "," end
   end
   buf[#buf + 1] = "do"
   for i=1, #body do
      buf[#buf + 1] = body[i]:render()
   end
   buf[#buf + 1] = "end"
   return table.concat(buf, ' ')
end

While = class{ tag = "While" }
While.render = function(self)
   local buf = { }
   buf[#buf + 1] = "while"
   self[1]:render(buf)
   buf[#buf + 1] = "do"
   buf[#buf + 1] = Block.render(self[2])
   buf[#buf + 1] = "end"
   return table.concat(buf, ' ')
end

Repeat = class{ tag = "Repeat" }
Repeat.render = function(self)
   return "repeat "..Block.render(self[1]).." until "..self[2]:render()
end

Bracket = class{ tag = "Bracket" }
Bracket.render = function(self)
   return "("..self[1]:render()..")"
end

Chunk = class{ tag = "Chunk" }
Chunk.new = function()
   return setmetatable({ }, Chunk)
end
Chunk.compile = function(self, block)
   return Block.render(block)
end

