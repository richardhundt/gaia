module("gaia.codegen", package.seeall)

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
   if node.locn then
      if node.locn.line > LINE then
         buf[#buf + 1] = string.rep("\n", node.locn.line - LINE)
         LINE = node.locn.line
      end
   end
end

Id = class{ tag = "Id" }
Id.render = function(self, buf)
   self[1] = self[1]:gsub("[()]", "__")
   buf[#buf + 1] = self[1]
   line(self, buf)
end

Block = class{ tag = "Block" }
Block.render = function(self, buf)
   buf[#buf + 1] = "do"
   for i=1, #self do
      self[i]:render(buf)
   end
   buf[#buf + 1] = "end"
   line(self, buf)
end

Local = class{ tag = "Local" }
Local.render = function(self, buf)
   buf[#buf + 1] = "local"
   local lhs, rhs = self[1], self[2]
   for i=1, #lhs do
      lhs[i]:render(buf)
      if i ~= #lhs then buf[#buf + 1] = "," end
   end
   if rhs and #rhs > 0 then
      buf[#buf + 1] = "="
      for i=1, #rhs do
         rhs[i]:render(buf)
         if i ~= #rhs then buf[#buf + 1] = "," end
      end
   end
   line(self, buf)
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
   ["concat"] = "~";
}

local unaryops = {
   ["not"] = "not";
   ["unm"] = "-";
}

Op = class{ tag = "Op" }
Op.render = function(self, buf)
   if binops[self[1]] then
      self[2]:render(buf)
      buf[#buf + 1] = binops[self[1]]
      self[3]:render(buf)
   elseif unaryops[self[1]] then
      buf[#buf + 1] = unaryops[self[1]]
      self[2]:render(buf)
   end
   line(self, buf)
end

Call = class{ tag = "Call" }
Call.render = function(self, buf)
   line(self, buf)
   self[1]:render(buf)
   buf[#buf + 1] = "("
   for i=2, #self do
      self[i]:render(buf)
      if i ~= #self then buf[#buf + 1] = "," end
   end
   buf[#buf + 1] = ")"
end

Function = class{ tag = "Function" }
Function.render = function(self, buf)
   buf[#buf + 1] = "function"
   buf[#buf + 1] = "("
   for i=1, #self[1] do
      self[1][i]:render(buf)
      if i ~= #self[1] then buf[#buf + 1] = "," end
   end
   buf[#buf + 1] = ")"
   for i=1, #self[2] do
      self[2][i]:render(buf)
   end
   buf[#buf + 1] = "end"
   line(self, buf)
end

Nil = class{ tag = "Nil" }
Nil.render = function(self, buf)
   buf[#buf + 1] = "nil"
   line(self, buf)
end

True = class{ tag = "True"; true }
True.render = function(self, buf)
   buf[#buf + 1] = "true"
   line(self, buf)
end

False = class{ tag = "False"; false }
False.render = function(self, buf)
   buf[#buf + 1] = "false"
   line(self, buf)
end

Rest = class{ tag = "Rest" }
Rest.render = function(self, buf)
   buf[#buf + 1] = "..."
   line(self, buf)
end

String = class{ tag = "String" }
String.render = function(self, buf)
   buf[#buf + 1] = string.format("%q", self[1])
end

Number = class{ tag = "Number" }
Number.render = function(self, buf)
   buf[#buf + 1] = tostring(self[1])
   line(self, buf)
end

Ops = class{ tag = "Ops" }
Ops.render = function(self, buf)
   for i=1, #self do
      self[i]:render(buf)
   end
   line(self, buf)
end

Set = class{ tag = "Set" }
Set.render = function(self, buf)
   local lhs, rhs = self[1], self[2]
   for i=1, #lhs do
      lhs[i]:render(buf)
      if i ~= #lhs then buf[#buf + 1] = "," end
   end
   buf[#buf + 1] = "="
   for i=1, #rhs do
      rhs[i]:render(buf)
      if i ~= #rhs then buf[#buf + 1] = "," end
   end
   line(self, buf)
end

Table = class{ tag = "Table" }
Table.render = function(self, buf)
   buf[#buf + 1] = "{"
   for k,v in pairs(self) do
      if v.tag == "Pair" then
         v:render(buf)
      else
         buf[#buf + 1] = "["
         if type(k) == "string" then
            buf[#buf + 1] = string.format("%q", k)
         elseif type(k) == "table" then
            k:render(buf)
         else
            buf[#buf + 1] = k
         end
         buf[#buf + 1] = "]"
         buf[#buf + 1] = "="
         v:render(buf)
      end
      buf[#buf + 1] = ";"
   end
   buf[#buf + 1] = "}"
   line(self, buf)
end

Pair = class{ tag = "Pair" }
Pair.render = function(self, buf)
   buf[#buf + 1] = "["
   self[1]:render(buf)
   buf[#buf + 1] = "]"
   buf[#buf + 1] = "="
   self[2]:render(buf)
   line(self, buf)
end

Index = class{ tag = "Index" }
Index.render = function(self, buf)
   self[1]:render(buf)
   buf[#buf + 1] = "["
   self[2]:render(buf)
   buf[#buf + 1] = "]"
   line(self, buf)
end

Invoke = class{ tag = "Invoke" }
Invoke.render = function(self, buf)
   line(self, buf)
   self[1]:render(buf)
   buf[#buf + 1] = "["
   self[2]:render(buf)
   buf[#buf + 1] = "]"
   buf[#buf + 1] = "("
   self[1]:render(buf)
   if #self >= 3 then
      buf[#buf + 1] = ","
      for i=3, #self do
         self[i]:render(buf)
         if i ~= #self then buf[#buf + 1] = "," end
      end
   end
   buf[#buf + 1] = ")"
end

Return = class{ tag = "Return" }
Return.render = function(self, buf)
   buf[#buf + 1] = 'return'
   for i=1, #self do
      self[i]:render(buf)
   end
   line(self, buf)
end

If = class{ tag = "If" }
If.render = function(self, buf)
   buf[#buf + 1] = "if"
   for i=1, #self, 2 do
      if i == #self and i % 2 == 1 then
         buf[#buf + 1] = "else"
         self[i]:render(buf)
      else
         self[i]:render(buf)
         buf[#buf + 1] = "then"
         for i=1, #self[i + 1] do
            self[i + 1][i]:render(buf)
         end
      end
   end
   buf[#buf + 1] = "end"
   line(self, buf)
end

For = class{ tag = "For" }
For.render = function(self, buf)
   buf[#buf + 1] = "for"
   if not self[4] then self[4] = Number(1) end
   self[1]:render(buf)
   buf[#buf + 1] = "="
   self[2]:render(buf)
   buf[#buf + 1] = ","
   self[3]:render(buf)
   buf[#buf + 1] = ","
   self[4]:render(buf)
   buf[#buf + 1] = "do"
   for i=1, #self[5] do
      self[5][i]:render(buf)
   end
   buf[#buf + 1] = "end"
   line(self, buf)
end

ForIn = class{ tag = "ForIn" }
ForIn.render = function(self, buf)
   local vars = self[1]
   local exps = self[2]
   local body = self[3]
   buf[#buf + 1] = "for"
   for i=1, #vars do
      vars[i]:render(buf)
      if i ~= #vars then buf[#buf + 1] = "," end
   end
   buf[#buf + 1] = "in"
   for i=1, #exps do
      exps[i]:render(buf)
      if i ~= #exps then buf[#buf + 1] = "," end
   end
   buf[#buf + 1] = "do"
   for i=1, #body do
      body[i]:render(buf)
   end
   buf[#buf + 1] = "end"
   line(self, buf)
end

While = class{ tag = "While" }
While.render = function(self, buf)
   buf[#buf + 1] = "while"
   self[1]:render(buf)
   buf[#buf + 1] = "do"
   Block.render(self[2], buf)
   buf[#buf + 1] = "end"
   line(self, buf)
end

Chunk = class{ tag = "Chunk" }
Chunk.new = function(source)
   return setmetatable({ source = source }, Chunk)
end
Chunk.compile = function(self, block)
   local buf = { }
   line(self, buf)
   Block.render(block, buf)
   return table.concat(buf, ' ')
end

