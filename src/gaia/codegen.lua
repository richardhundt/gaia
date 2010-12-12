module("gaia.codegen", package.seeall)

require("pack")

local util  = require("gaia.util")
local bpack = string.pack
local pairs, ipairs, setmetatable, type = pairs, ipairs, setmetatable, type

local function lshift(num, ofs) return num * 2^ofs end
local function rshift(num, ofs) return math.floor(num / 2^ofs) end

local DEBUG = false
local const_tags = {
   Number = true,
   String = true,
   True   = true,
   False  = true
}
local function isconst(node)
   if type(node) ~= "table" then
      return false
   end
   return const_tags[node.tag]
end
local function isblock(node)
   return type(node) == "table" and node.tag == nil
end

MINSTACK = 2
MAXSTACK = 250

local SIZE_C  = 9
local SIZE_B  = 9
local SIZE_Bx = SIZE_C + SIZE_B
local SIZE_A  = 8

local SIZE_OP = 6

local POS_OP  = 0
local POS_A   = POS_OP + SIZE_OP
local POS_C   = POS_A + SIZE_A
local POS_B   = POS_C + SIZE_C
local POS_Bx  = POS_C

local MAXARG_Bx  = lshift(1, SIZE_Bx)-1
local MAXARG_sBx = rshift(MAXARG_Bx, 1)

local MAXARG_A = lshift(1, SIZE_A)-1
local MAXARG_B = lshift(1, SIZE_B)-1
local MAXARG_C = lshift(1, SIZE_C)-1

local NO_REG = MAXARG_A

local _OP = 2^POS_OP
local _A  = 2^POS_A
local _B  = 2^POS_B
local _C  = 2^POS_C
local _Bx = 2^POS_Bx

OP = {
   "MOVE", "LOADK", "LOADBOOL", "LOADNIL", "GETUPVAL", "GETGLOBAL",
   "GETTABLE", "SETGLOBAL", "SETUPVAL", "SETTABLE", "NEWTABLE",
   "SELF", "ADD", "SUB", "MUL", "DIV", "MOD", "POW", "UNM", "NOT",
   "LEN", "CONCAT", "JMP", "EQ", "LT", "LE", "TEST", "TESTSET",
   "CALL", "TAILCALL", "RETURN", "FORLOOP", "FORPREP", "TFORLOOP",
   "SETLIST", "CLOSE", "CLOSURE", "VARARG"
}
-- reverse index
for i,o in ipairs(OP) do OP[o] = i-1 end
local OP = OP
local OP_iABC  = 0
local OP_iABx  = 1
local OP_iAsBx = 2
local OP_MODES = {
   0, 1, 0, 0, 0, 1, 0, 1, 0, 0, 0, 0, 0,
   0, 0, 0, 0, 0, 0, 0, 0, 0, 2, 0, 0, 0,
   0, 0, 0, 0, 0, 2, 2, 0, 0, 0, 1, 0
}

-- identity for unpatched jumps
local PATCH = { }

-- const types
local TNIL = 0
local TBIT = 1
local TNUM = 3
local TSTR = 4
local TOBJ = 5

local BINOPS = {
   ["add"] = OP.ADD;
   ["sub"] = OP.SUB;
   ["mul"] = OP.MUL;
   ["mod"] = OP.MOD;
   ["div"] = OP.DIV;
   ["pow"] = OP.POW;
   ["and"] = OP.TESTSET;
   ["or"]  = OP.TESTSET;
   ["lt"]  = OP.LT;
   ["le"]  = OP.LE;
   ["eq"]  = OP.EQ;
   ["gt"]  = OP.LE;
   ["ge"]  = OP.LT;
   ["ne"]  = OP.EQ;
   ["concat"] = OP.CONCAT;
}
local CMPOPS = {
   ["lt"] = 0;
   ["le"] = 0;
   ["eq"] = 0;
   ["gt"] = 1;
   ["ge"] = 1;
   ["ne"] = 1;
}
local UNOPS = {
   ["unm"] = OP.UNM;
   ["len"] = OP.LEN;
   ["not"] = OP.NOT;
}

---------------------------------------------------------------------------
-- Chunk class
---------------------------------------------------------------------------
Chunk = { tag = "Chunk" }
Chunk.__index = Chunk
Chunk_meta = { }
Chunk_meta.__call = function(class, source)
   return class.new(source)
end
setmetatable(Chunk, Chunk_meta)
Chunk.new = function(source)
   local self = setmetatable({
      head = { };
      conf = { };
   }, Chunk)
   self:init(source)
   return self
end
Chunk.init = function(self, source)
   local byte = string.byte
   local samp = string.dump(function() end)

   self.conf.signature  = string.sub(samp, 1, 4)
   self.conf.version    = byte(samp, 5)
   self.conf.format     = byte(samp, 6)
   self.conf.endian     = byte(samp, 7)
   self.conf.int        = byte(samp, 8)
   self.conf.size_t     = byte(samp, 9)
   self.conf.word       = byte(samp, 10)
   self.conf.lua_Number = byte(samp, 11)
   self.conf.int_flag   = byte(samp, 12)

   self.root = Proto:new(nil, source)
   self.root.vararg = 2
   self.root.lndefn = 0
   self.root.lnlast = 0

   if self.conf.int < 4 then
      -- 16 bit system, so use an unsigned long
      self.packfmt = "=L"
   else
      self.packfmt = "=I"
   end

   self.head = string.sub(samp, 1, 12)
end
Chunk.compile = function(self, block)
   self.root[1] = block
   self.root:compile()
   return self.head .. self.root:bake()
end

---------------------------------------------------------------------------
-- Proto class
---------------------------------------------------------------------------
Proto = { }
Proto.__index = Proto
Proto.new = function(class, parent, source)
   local self = setmetatable({
      parent = parent;
      opcode = { };
      labels = { };
      bpatch = { };
      kcache = { };
      upvals = { };
      params = { };
      consts = { };
      protos = { };
      locals = { };
      lninfo = { };
      vstack = 0;
      vcount = MINSTACK;
      source = source;
      lndefn = 1;
      lnlast = 1;
      lncurr = 1;
      vararg = 0;
   }, class)

   return self
end
Proto.compile = function(self)
   if DEBUG then print(">>>[TOP]") end
   local body = self[1]
   for i=1,#body do
      local node = body[i]
      if node.compile then
         node:compile(self)
      else
         Block.compile(node, self)
      end
   end
   if DEBUG then print("<<<[END]") end
end
Proto.const = function(self, value)
   assert(value ~= nil, "const value cannot be nil")
   assert(type(value) ~= "table", "table cannot be a const")
   if self.kcache[value] then
      return self.kcache[value]
   end
   local const = Const:new(value)
   self.kcache[value] = const

   const.index = #self.consts
   self.consts[#self.consts + 1] = const

   return const
end
Proto.upval = function(self, name)
   if self.upvals[name] then
      return self.upvals[name]
   end
   local slot = #self.upvals
   self.upvals[name] = slot
   self.upvals[slot + 1] = name
   return slot
end
Proto.alloc = function(self, node)
   if node and node.alloc then
      return node.alloc
   end
   local index = self.vstack
   self.vstack = self.vstack + 1
   if self.vstack > self.vcount then
      self.vcount = self.vstack
   end
   if DEBUG then print("alloc: ", index) end
   return index
end
Proto.alloc_range = function(self, count)
   local base = self.vstack
   self.vstack = base + count
   if self.vstack > self.vcount then
      self.vcount = self.vstack
   end
   return base
end
Proto.free = function(self, vreg)
   if DEBUG then print("free - vreg: ", vreg, ", vstack: ", self.vstack) end
   if vreg == self.vstack - 1 then
      self.vstack = self.vstack - 1
   end
end
Proto.lexvar = function(self, name, index)
   local lvar
   if not self.locals[name] then
      lvar = LexVar{ name = name, index = index }
      self.locals[name] = lvar
      self.locals[#self.locals + 1] = name
   else
      lvar = self.locals[name]
      if index then
         lvar.index = index
         --[[
         self:free(index)
         error("lexvar: "..name.." already allocated to: "..lvar.index)
         --]]
      end
   end
   lvar:seen(self)
   return lvar.index
end
Proto.line = function(self, node)
   if node.line then
      local line = node.line
      self.lncurr = line
      if self.lnlast < line then
         self.lnlast = line
      end
   end
end
Proto.emit = function(self, o, a, b, c)
   a = a or 0
   b = b or 0
   local m = OP_MODES[o + 1]
   if m == OP_iABC then
      c = c or 0
      if DEBUG then print(string.format("emit_iABC %s %d %d %d", OP[o + 1], a, b, c)) end
      self:emit_ABC(o, a, b, c)
   elseif m == OP_iABx then
      if DEBUG then print(string.format("emit_ABx %s %d %d", OP[o + 1], a, b)) end
      self:emit_ABx(o, a, b)
   elseif m == OP_iAsBx then
      if DEBUG then print(string.format("emit_sABx %s %d %d", OP[o + 1], a, b)) end
      self:emit_AsBx(o, a, b)
   else
      error("unknown op mode "..tostring(m).." for: "..OP[o+1])
   end
   local lninfo = self.lninfo
   lninfo[#lninfo + 1] = self.lncurr
end

Proto.emit_ABC = function(self, o, a, b, c)
   local opcode = self.opcode
   opcode[#opcode + 1] = o*_OP + a*_A + b*_B + c*_C
end
Proto.emit_ABx = function(self, o, a, bc)
   local opcode = self.opcode
   opcode[#opcode + 1] = o*_OP + a*_A + bc*_Bx
end
Proto.emit_AsBx = function(self, o, a, bc)
   local opcode = self.opcode
   opcode[#opcode + 1] = o*_OP + a*_A + (MAXARG_sBx+bc)*_Bx
end

Proto.code = function(self, o, a, b, c)
   a = a or 0
   b = b or 0
   local m = OP_MODES[o + 1]
   if m == OP_iABC then
      c = c or 0
      return self:code_ABC(o, a, b, c)
   elseif m == OP_iABx then
      return self:code_ABx(o, a, b)
   elseif m == OP_iAsBx then
      return self:code_AsBx(o, a, b)
   else
      error("unknown op mode "..tostring(m).." for: "..OP[o+1])
   end
end

Proto.code_ABC = function(self, o, a, b, c)
   return o*_OP + a*_A + b*_B + c*_C
end
Proto.code_ABx = function(self, o, a, bc)
   return o*_OP + a*_A + bc*_Bx
end
Proto.code_AsBx = function(self, o, a, bc)
   return o*_OP + a*_A + (MAXARG_sBx+bc)*_Bx
end

Proto.bake = function(self)

   assert(self.vcount <= MAXSTACK, "function or expression too complex")

   -- bake header
   local source
   if self.source then
      source = bpack("a", self.source.."\0")
   else
      source = bpack("a", "")
   end

   -- mandatory final return
   self:emit(OP.RETURN, 0, 1, 0)

   local lndefn = bpack('=I', self.lndefn)
   local lnlast = bpack('=I', self.lnlast)
   local nupval = bpack('b', #self.upvals)
   local nparam = bpack('b', #self.params)
   local vararg = bpack('b', self.vararg)
   local vcount = bpack('b', self.vcount)
   local buffer = { source, lndefn, lnlast, nupval, nparam, vararg, vcount }

   -- bake opcode
   buffer[#buffer + 1] = bpack("=I", #self.opcode)
   for i,op in ipairs(self.opcode) do
      buffer[#buffer + 1] = bpack("=I", op)
   end

   -- bake consts
   buffer[#buffer + 1] = bpack("=I", #self.consts)
   for i,const in ipairs(self.consts) do
      buffer[#buffer + 1] = const:bake()
   end

   -- bake protos
   buffer[#buffer + 1] = bpack("=I", #self.protos)
   for i,proto in ipairs(self.protos) do
      buffer[#buffer + 1] = proto:bake()
   end

   -- bake lninfo
   buffer[#buffer + 1] = bpack("=I", #self.lninfo)
   for i,line in ipairs(self.lninfo) do
      buffer[#buffer + 1] = bpack("=I", line)
   end

   -- bake locals
   local vlist = { }
   for i,k in ipairs(self.locals) do
      if type(k) == "string" then
         local v = self.locals[k]
         vlist[#vlist + 1] = bpack("a=I=I", k.."\0", v.initpc, v.lastpc)
      end
   end
   buffer[#buffer + 1] = bpack("=I", #vlist)..table.concat(vlist, '')

   -- bake upvals
   buffer[#buffer + 1] = bpack("=I", #self.upvals)
   for i, name in ipairs(self.upvals) do
      buffer[#buffer + 1] = bpack("a", name.."\0")
   end

   return table.concat(buffer, '')
end

---------------------------------------------------------------------------
-- Const class
---------------------------------------------------------------------------
Const = { }
Const.__index = Const
Const.__tostring = function(self)
   if self[1] == TSTR then
      return string.format("%q", self[2])
   else
      return tostring(self[2])
   end
end
Const.new = function(class, value)
   if value == Nil then
      ctype = TNIL
   elseif type(value) == "boolean" then
      ctype = TBIT
   elseif type(value) == "number" then
      ctype = TNUM
   elseif type(value) == "string" then
      ctype = TSTR
   elseif type(value) == "table" then
      assert(value.tag == "Struct")
      ctype = TOBJ
   end
   return setmetatable({ ctype, value }, class)
end
Const.bake = function(self)
   local ctype, value = self[1], self[2]
   assert(type(value) ~= "table")
   if ctype == TNIL then
      return bpack('b', ctype)
   elseif ctype == TBIT then
      return bpack('bb', ctype, value and 1 or 0)
   elseif ctype == TNUM then
      return bpack('bn', ctype, value)
   elseif ctype == TSTR then
      -- size_t, "...\0"
      return bpack('ba', ctype, value.."\0")
   elseif ctype == TOBJ then
      return value[2]:bake()
   end
end

---------------------------------------------------------------------------
-- AST nodes
---------------------------------------------------------------------------
Nil = { tag = "Nil" }
Nil.__index = Nil
Nil_meta = { }
Nil_meta.__call = function(class, value)
   return setmetatable({ }, class)
end
setmetatable(Nil, Nil_meta)
Nil.compile = function(self, proto)
   local vreg = proto:alloc(self)
   proto:emit(OP.LOADNIL, vreg, vreg)
   return vreg
end

True = { tag = "True"; true }
True.__index = True
True_meta = { }
True_meta.__call = function(class, value)
   return setmetatable({ }, class)
end
setmetatable(True, True_meta)
True.compile = function(self, proto)
   local vreg = proto:alloc(self)
   proto:emit(OP.LOADK, vreg, proto:const(true).index)
   return vreg
end

False = { tag = "False"; false }
False.__index = False
False_meta = { }
False_meta.__call = function(class, value)
   return setmetatable({ }, class)
end
setmetatable(False, False_meta)
False.compile = function(self, proto)
   local vreg = proto:alloc(self)
   proto:emit(OP.LOADK, vreg, proto:const(false).index)
   return vreg
end

Rest = { tag = "Rest" }
Rest.__index = Rest
Rest_meta = { }
Rest_meta.__call = function(class, value)
   return setmetatable({ }, class)
end
setmetatable(Rest, Rest_meta)
Rest.compile = function(self, proto, want)
   if proto.vararg ~= 3 then
      error('cannot use "Rest" outside of a vararg function')
   end
   local base = proto:alloc(self)
   proto:emit(OP.VARARG, base, want or 1)
   return base
end

Number = { tag = "Number" }
Number.__index = Number
Number_meta = { }
Number_meta.__call = function(class, value)
   return setmetatable({ value }, class)
end
setmetatable(Number, Number_meta)
Number.compile = function(self, proto)
   local vreg = proto:alloc(self)
   proto:emit(OP.LOADK, vreg, proto:const(self[1]).index)
   return vreg
end

String = { tag = "String" }
String.__index = String
String_meta = { }
String_meta.__call = function(class, value)
   return setmetatable({ value }, class)
end
setmetatable(String, String_meta)
String.compile = function(self, proto)
   local vreg = proto:alloc(self)
   proto:emit(OP.LOADK, vreg, proto:const(self[1]).index)
   return vreg
end

Ops = { }
Ops.__index = Ops
Ops_meta = { }
Ops_meta.__call = function(class, self)
   return setmetatable(self, class)
end
setmetatable(Ops,  Ops_meta)
Ops.compile = function(self, proto)
   proto:line(self)
   local last
   for i=1, #self do
      last = self[i]:compile(proto)
   end
   return last
end

Block = { }
Block.__index = Block
Block_meta = { }
Block_meta.__call = function(class, self)
   return setmetatable(self, class)
end
setmetatable(Block,  Block_meta)
Block.compile = function(self, proto)
   local free = proto.vstack
   for i=1, #self do
      self[i]:compile(proto)
   end
   if proto.vstack ~= free then
      proto:emit(OP.CLOSE, free)
   end
   proto.vstack = free
end

LexVar = { tag = "LexVar" }
LexVar.__index = LexVar
LexVar_meta = { }
LexVar_meta.__call = function(class, self)
   return setmetatable(self, class)
end
setmetatable(LexVar, LexVar_meta)
LexVar.compile = function(self, proto)
   self:seen(proto)
   return self.index
end
LexVar.seen = function(self, proto)
   local currpc = #proto.opcode
   if not self.initpc then
      self.initpc = currpc
   end
   self.lastpc = currpc
   return self
end

VReg = { tag = "VReg" }
VReg.__index = VReg
VReg_meta = { }
VReg_meta.__call = function(class, self)
   return setmetatable(self, class)
end
setmetatable(VReg, VReg_meta)
VReg.compile = function(self, proto)
   return self[1]
end

Id = { tag = "Id" }
Id.__index = Id
Id_meta = { }
Id_meta.__call = function(class, name)
   return setmetatable({ name = name }, class)
end
setmetatable(Id, Id_meta)
Id.compile = function(self, proto)
   local ident = self.name
   if proto.locals[ident] then
      local index = proto:lexvar(ident)
      local alloc = self.alloc
      if alloc and alloc ~= index then
         proto:emit(OP.MOVE, alloc, index)
         index = alloc
      end
      return index
   elseif proto.upvals[ident] then
      local dest = proto:alloc(self)
      proto:emit(OP.GETUPVAL, dest, proto.upvals[ident])
      return dest
   else
      local nest, seen = { }
      local prev, curr = proto, proto.parent
      while curr do
         if curr.locals[ident] then
            seen = curr.locals[ident]
            break
         end
         nest[#nest + 1] = curr
         prev, curr = curr, curr.parent
      end
      local dest
      if seen then
         for i,curr in ipairs(nest) do
            curr:upval(ident)
         end
         local slot = proto:upval(ident)
         dest = proto:alloc(self)
         proto:emit(OP.GETUPVAL, dest, slot)
      else
         dest = proto:alloc(self)
         proto:emit(OP.GETGLOBAL, dest, proto:const(ident).index)
      end
      return dest
   end
end

Local = { tag = "Local" }
Local.__index = Local
Local_meta = { }
Local_meta.__call = function(class, self)
   return setmetatable(self, class)
end
setmetatable(Local, Local_meta)
Local.compile = function(self, proto)
   proto:line(self)
   local lhs, rhs = self[1], self[2] or { }
   local want = #lhs
   local rest, base
   local free = proto.vstack
   for i=1, #lhs do
      local a = lhs[i]
      local b = rhs[i]
      local vreg = free + i - 1
      if b then
         b.alloc = vreg
         if b.tag == "Rest" or b.tag == "Call" or b.tag == "Invoke" then
            if i == #rhs then
               b:compile(proto, want + 1)
               rest = true
            else
               b:compile(proto, 2)
            end
         else
            if not rest then
               if b.tag == "Index" then
                  b:compile(proto, want + 1)
               else
                  b:compile(proto, want + 1)
               end
            end
            want = want - 1
         end
      end
      proto:lexvar(a.name, vreg)
   end
   proto.vstack = free + #lhs
end

Label = { tag = "Label" }
Label.__index = Label
Label_meta = { }
Label_meta.__call = function(class, patch)
   return setmetatable({ patch }, class)
end
setmetatable(Label, Label_meta)
Label.compile = function(self, proto)
   local patch = proto.bpatch[self[1]]
   if patch then
      while #patch > 0 do
         local locn = table.remove(patch)
         local offs = #proto.opcode - locn
         proto:emit(OP.JMP, 0, offs)
         local code = table.remove(proto.opcode)
         local line = table.remove(proto.lninfo)
         proto.opcode[locn] = code
         proto.lninfo[locn] = line
      end
      proto.bpatch[self[1]] = nil
   end
   proto.labels[self[1]] = #proto.opcode
end

Goto = { tag = "Goto" }
Goto.__index = Goto
Goto_meta = { }
Goto_meta.__call = function(class, label)
   if label == nil then
      error("Goto nil label")
   end
   return setmetatable({ label }, class)
end
setmetatable(Goto, Goto_meta)
Goto.compile = function(self, proto)
   local label = proto.labels[self[1]]
   local ident = self[1]
   if label then
      -- backward jump
      local offs = (label - #proto.opcode) - 1
      proto:emit(OP.JMP, 0, offs)
   else
      -- forward jump
      proto:emit(OP.JMP, 0, 0, 0)
      if not proto.bpatch[ident] then
         proto.bpatch[ident] = { }
      end
      local patch = proto.bpatch[ident]
      patch[#patch + 1] = #proto.opcode
   end
end

Set = { tag = "Set" }
Set.__index = Set
Set_meta = { }
Set_meta.__call = function(class, self)
   return setmetatable(self, class)
end
setmetatable(Set, Set_meta)
Set.compile = function(self, proto)
   proto:line(self)
   local lhs, rhs = self[1], self[2]
   local free = proto.vstack
   local want = #lhs
   for i=1, #lhs do
      local a = lhs[i]
      local b = rhs[i] or Nil
      if not (b.tag == "Call" or b.tag == "Invoke" or b.tag == "Rest") then
         want = want - 1
      end
      if a.tag == "Id" then
         local name = a.name
         local vreg = b:compile(proto, want + 1)
         if proto.locals[name] then
            local dest = proto:lexvar(name)
            proto:emit(OP.MOVE, dest, vreg)
         elseif proto.upvals[name] then
            local uval = proto.upvals[name]
            proto:emit(OP.SETUPVAL, vreg, uval)
         else
            proto:emit(OP.SETGLOBAL, vreg, proto:const(name).index)
         end
      elseif a.tag == "Index" then
         local base = a[1]:compile(proto, want + 1)
         local expr
         if isconst(a[2]) then
            expr = proto:const(a[2][1]).index + 256
         else
            expr = a[2]:compile(proto)
         end
         local vreg
         if isconst(b) then
            vreg = proto:const(b[1]).index + 256
         else
            vreg = b:compile(proto, want + 1)
         end
         proto:emit(OP.SETTABLE, base, expr, vreg)
      else
         error("unknown dest tag:"..a.tag)
      end
   end
   proto.vstack = free
end

Op = { tag = "Op" }
Op.__index = Op
Op_meta = { }
Op_meta.__call = function(class, self)
   return setmetatable(self, class)
end
setmetatable(Op, Op_meta)
Op.compile = function(self, proto)
   local free = proto.vstack
   local o = self[1]
   local a, b, c
   if o == "and" or o == "or" then
      c = (o == "and") and 0 or 1
      b = self[2]:compile(proto, 2)
      proto.vstack = free
      a = proto:alloc(self)
      proto:emit(OP.TESTSET, a, b, c)
      proto:emit(OP.JMP, 0, 1)
      self[3].alloc = a
      b = self[3]:compile(proto, 2)
      if b ~= a then
         proto:emit(OP.MOVE, a, b)
      end
   elseif BINOPS[o] then
      if #self ~= 3 then
         error(string.format("2 operands expected for %q", o))
      end
      if CMPOPS[o] then
         local cmp = CMPOPS[o]
         if isconst(self[2]) then
            b = proto:const(self[2][1]).index + 256
         else
            b = self[2]:compile(proto, 2)
         end
         if isconst(self[3]) then
            c = proto:const(self[3][1]).index + 256
         else
            c = self[3]:compile(proto, 2)
         end
         proto.vstack = free
         a = proto:alloc(self)
         o = BINOPS[o]
         if self.if_stmt then
            proto:emit(o, cmp, b, c)
         else
            cmp = cmp == 1 and 0 or 1
            proto:emit(o, cmp, b, c)
            proto:emit(OP.JMP, 0, 1)
            proto:emit(OP.LOADBOOL, a, 0, 1)
            proto:emit(OP.LOADBOOL, a, 1, 0)
         end
      elseif o == "concat" then
         o = OP.CONCAT
         b = self[2]:compile(proto, 2)
         c = self[3]:compile(proto, 2)
         ---[[
         if b + 1 < c then
            local dest = proto:alloc()
            proto:emit(OP.MOVE, dest, b)
            b = dest
         end
         --]]
         if c < b then
            local dest = proto:alloc()
            proto:emit(OP.MOVE, dest, c)
            c = dest
         end
         proto.vstack = free
         a = proto:alloc(self)
         proto:emit(o, a, b, c)
      else
         if isconst(self[2]) then
            b = proto:const(self[2][1]).index + 256
         else
            b = self[2]:compile(proto, 2)
         end
         if isconst(self[3]) then
            c = proto:const(self[3][1]).index + 256
         else
            c = self[3]:compile(proto, 2)
         end
         proto.vstack = free
         a = proto:alloc(self)
         o = BINOPS[o]
         proto:emit(o, a, b, c)
      end
   elseif UNOPS[o] then
      if #self ~= 2 then
         error(string.format("1 operand expected for %q", o))
      end
      o = UNOPS[o]
      b = self[2]:compile(proto, 2)
      proto.vstack = free
      a = proto:alloc(self)
      proto:emit(o, a, b, c)
   else
      error(string.format("invalid operator %q", o))
   end
   return a
end

--[[ TODO
Concat = { tag = "Concat" }
Concat.__index = Concat
Concat_meta = { }
Concat_meta.__call = function(class, self)
   return setmetatable(self, class)
end
setmetatable(Concat, Concat_meta)
Concat.compile = function(self, proto)
   proto:line(self)
   local dest = proto:alloc()
   proto:emit(OP.CONCAT, dest, from, last)
   return dest
end
--]]

Table = { tag = "Table" }
Table.__index = Table
Table_meta = { }
Table_meta.__call = function(class, self)
   return setmetatable(self, class)
end
setmetatable(Table, Table_meta)
Table.compile = function(self, proto)
   proto:line(self)
   self.line = nil
   local dest = proto:alloc(self)
   local free = proto.vstack
   local arry, hash = { }, { }
   for _,node in pairs(self) do
      if type(node) == "table" then
         if node.tag == "Pair" then
            hash[#hash + 1] = node
         else
            arry[#arry + 1] = node
         end
      end
   end
   proto:emit(OP.NEWTABLE, dest, #arry, #hash)
   for i,pair in ipairs(hash) do
      local k, v = pair:compile(proto)
      proto:emit(OP.SETTABLE, dest, k, v)
   end
   if #arry > 0 then
      for i,item in ipairs(arry) do
         local vreg = item:compile(proto)
         -- TODO: fix this heuristic
         if vreg < dest then
            local temp = proto:alloc()
            proto:emit(OP.MOVE, temp, vreg)
            vreg = temp
         end
         arry[i] = i
      end
      -- TODO flush limit
      proto:emit(OP.SETLIST, dest, arry[#arry], arry[1])
   end
   proto.vstack = free
   return dest
end

Pair = { tag = "Pair" }
Pair.__index = Pair
Pair_meta = { }
Pair_meta.__call = function(class, self)
   return setmetatable(self, class)
end
setmetatable(Pair, Pair_meta)
Pair.compile = function(self, proto)
   local k, v = self[1], self[2]
   if isconst(k) then
      k = proto:const(k[1]).index + 256
   else
      k = k:compile(proto)
   end
   if isconst(v) then
      v = proto:const(v[1]).index + 256
   else
      v = v:compile(proto)
   end
   return k, v
end

Index = { tag = "Index" }
Index.__index = Index
Index_meta = { }
Index_meta.__call = function(class, self)
   return setmetatable(self, class)
end
setmetatable(Index, Index_meta)
Index.compile = function(self, proto, want)
   local base = self[1]:compile(proto, 2)
   local expr
   if isconst(self[2]) then
      expr = proto:const(self[2][1]).index + 256
   else
      expr = self[2]:compile(proto, 2)
      proto:free(expr)
   end
   if self[1].tag ~= "Id" or not proto.locals[self[1].name] then
      proto:free(base)
   end
   local dest = proto:alloc(self)
   proto:emit(OP.GETTABLE, dest, base, expr)
   return dest
end

Function = { tag = "Function" }
Function.__index = Function
Function_meta = { }
Function_meta.__call = function(class, self)
   return setmetatable(self, class)
end
setmetatable(Function, Function_meta)
Function.compile = function(self, outer)
   outer:line(self)
   local param = self[1]
   local block = self[2]

   local proto = Proto:new(outer)
   proto[1] = block
   for i,p in ipairs(param) do
      if p.tag == "Id" then
         local vreg = proto:lexvar(p.name, proto:alloc())
         proto.params[p.name] = vreg
         proto.params[#proto.params + 1] = p.name
      elseif p.tag == "Rest" then
         proto.vararg = 3
      else
         error("unknown param type: "..tostring(p.tag))
      end
   end

   local line
   if self.line then
      line = self.line
   elseif outer.lncurr > 0 then
      line = outer.lncurr
   end
   proto.lndefn = line
   proto.lnlast = line
   proto.lncurr = line

   proto:compile()

   local index = #outer.protos
   outer.protos[index + 1] = proto

   local dest = outer:alloc(self)
   outer:emit(OP.CLOSURE, dest, index)
   for i,name in ipairs(proto.upvals) do
      if outer.locals[name] then
         outer:emit(OP.MOVE, 0, outer:lexvar(name))
      else
         outer:emit(OP.GETUPVAL, 0, outer.upvals[name])
      end
   end

   return dest
end

Call = { tag = "Call" }
Call.__index = Call
Call_meta = { }
Call_meta.__call = function(class, self)
   return setmetatable(self, class)
end
setmetatable(Call, Call_meta)
Call.compile = function(self, proto, want, tail)
   proto:line(self)
   local base = self.alloc or proto:alloc_range(#self)
   self[1].alloc = base
   assert(self[1]:compile(proto, 2) == base, tostring(self[1].tag))
   local args = 1
   for i=2, #self do
      local item = self[i]
      local dest = base + i - 1
      if dest >= proto.vcount then
         proto.vcount = dest + 1
      end
      item.alloc = dest
      if i == #self and item.tag == "Call" then
         args = 0
         item[1].alloc = dest
         item[1]:compile(proto, 2)
         item[1] = VReg{ dest }
         item:compile(proto, 0)
      elseif i == #self and item.tag == "Rest" then
         args = 0
         item:compile(proto, 0)
      else
         item:compile(proto, 2)
         args = args + 1
      end
   end
   if not want then want = 1 end
   if tail then
      proto:emit(OP.TAILCALL, base, args, 0)
   else
      proto:emit(OP.CALL, base, args, want)
   end
   proto.vstack = base + want - 1
   return base
end

Invoke = { tag = "Invoke" }
Invoke.__index = Invoke
Invoke_meta = { }
Invoke_meta.__call = function(class, self)
   return setmetatable(self, class)
end
setmetatable(Invoke, Invoke_meta)
Invoke.compile = function(self, proto, want, tail)
   proto:line(self)

   local free = proto.vstack
   self[1].alloc = self.alloc

   local base = self[1]:compile(proto, 2)
   local expr
   if isconst(self[2]) then
      expr = proto:const(self[2][1]).index + 256
   else
      expr = self[2]:compile(proto, 2)
   end

   local dest = self.alloc or proto:alloc_range(2)
   local this = self.alloc and dest + 1 or proto:alloc()

   proto:emit(OP.SELF, dest, base, expr)
   local call = Call{ VReg{ dest }, VReg{ this } }
   call.alloc = dest

   for i=3, #self do
      call[#call + 1] = self[i]
   end

   call:compile(proto, want, tail)
   if not want then want = 1 end
   proto.vstack = free + want - 1
   return dest
end

Return = { tag = "Return" }
Return.__index = Return
Return_meta = { }
Return_meta.__call = function(class, self)
   return setmetatable(self, class)
end
setmetatable(Return, Return_meta)
Return.compile = function(self, proto)
   proto:line(self)
   local base = 0
   local list = { }
   local tail
   for i=1, #self do
      local item = self[i]
      if item.tag == "Call" or item.tag == "Invoke" or item.tag == "Rest" then
         if i == #self then
            -- keep stack and tailcall
            base = item:compile(proto, 0, true)
            tail = true
         else
            -- keep 1 return value
            item:compile(proto, 2)
         end
      else
         local dest = proto:alloc()
         item.alloc = dest
         item:compile(proto)
         list[#list + 1] = dest
      end
   end

   local rets = #list + 1
   if #list > 0 and not tail then
      base = list[1]
   elseif tail then
      rets = 0
   end
   proto:emit(OP.RETURN, base, rets)
   return base
end

If = { tag = "If" }
If.__index = If
If_meta = { }
If_meta.__call = function(class, self)
   return setmetatable(self, class)
end
setmetatable(If, If_meta)
If.compile = function(self, proto)
   proto:line(self)
   local free = proto.vstack
   local exit_label = util.genid()

   for i=1, #self, 2 do
      if i == #self and i % 2 == 1 then
         -- else
         local block = self[i]
         -- free the block registers
         proto.vstack = free
         for i, node in ipairs(block) do
            node:compile(proto)
         end
      else
         local expr, block = self[i], self[i + 1]
         local block_end = util.genid()
         block[#block + 1] = Goto(exit_label)
         block[#block + 1] = Label(block_end)

         expr.if_stmt = true
         local cond = expr:compile(proto)

         if expr.tag == "Op" then
            if not CMPOPS[expr[1]] then
               proto:emit(OP.TEST, cond, 0, 0)
            end
            Goto(block_end):compile(proto)
         else
            proto:emit(OP.TEST, cond, 0, 0)
            Goto(block_end):compile(proto)
         end

         proto.vstack = free
         for i, node in ipairs(block) do
            node:compile(proto)
         end
      end
   end

   -- reset the free register counter at the end now
   proto.vstack = free

   Label(exit_label):compile(proto)
end

For = { tag = "For" }
For.__index = For
For_meta = { }
For_meta.__call = function(class, self)
   return setmetatable(self, class)
end
setmetatable(For, For_meta)
For.compile = function(self, proto)
   proto:line(self)
   local free = proto.vstack
   local offs = 0
   local list = { "(for index)", "(for limit)", "(for step)" }
   if not self[4] then
      self[4] = Number(1)
   end
   for i=2, 4 do
      offs = offs + 1
      local name = list[offs]
      local dest
      if isconst(self[i]) then
         dest = proto:lexvar(name, proto:alloc())
         proto:emit(OP.LOADK, dest, proto:const(self[i][1]).index)
      else
         self[i].alloc = proto:alloc()
         dest = self[i]:compile(proto, 2)
      end
      list[offs] = dest
   end

   local forx = list[1]
   local iden = proto:lexvar(self[1].name, proto:alloc())

   proto.opcode[#proto.opcode + 1] = PATCH
   proto.lninfo[#proto.lninfo + 1] = proto.lncurr
   local here = #proto.opcode

   local body = self[5]
   local base = #proto.opcode
   Block.compile(body, proto)

   local back = base - #proto.opcode
   proto:emit(OP.FORLOOP, forx, back - 1)

   local over = #proto.opcode - here
   proto:emit(OP.FORPREP, forx, over - 1)

   local code = table.remove(proto.opcode)
   local line = table.remove(proto.lninfo)
   proto.opcode[here] = code
   proto.lninfo[here] = line

   proto.vstack = free
end

ForIn = { tag = "ForIn" }
ForIn.__index = ForIn
ForIn_meta = { }
ForIn_meta.__call = function(class, self)
   return setmetatable(self, class)
end
setmetatable(ForIn, ForIn_meta)
ForIn.compile = function(self, proto)
   proto:line(self)
   local free = proto.vstack
   local base = proto:alloc_range(3)
   local head = proto.vstack
   local vars = self[1]
   local exps = self[2]
   local body = self[3]

   local list = {"(for generator)","(for state)","(for control)"}

   for i=1, #list do
      local name = list[i]
      local vreg = base + i - 1
      if i <= #exps then
         local want = 4 - i
         exps[i].alloc = vreg
         exps[i]:compile(proto, want + 1)
      end
      list[i] = proto:lexvar(name, vreg)
   end

   proto.vstack = head
   for i=4, #exps do
      local vreg = proto:alloc()
      exps[i].alloc = vreg
      exps[i]:compile(proto)
      list[#list + 1] = vreg
   end
   for i=1, #vars do
      proto:lexvar(vars[i].name, proto:alloc())
   end

   local iter = list[1]

   proto.opcode[#proto.opcode + 1] = PATCH
   proto.lninfo[#proto.lninfo + 1] = proto.lncurr
   local here = #proto.opcode

   Block.compile(body, proto)
   proto:emit(OP.TFORLOOP, iter, 0, #vars)

   local over = #proto.opcode - here
   proto:emit(OP.JMP, 0, over - 1)
   -- TODO make these edits use proto:code(...)
   local code = table.remove(proto.opcode)
   local line = table.remove(proto.lninfo)
   proto.opcode[here] = code
   proto.lninfo[here] = line

   local back = here - #proto.opcode
   proto:emit(OP.JMP, 0, back - 1)

   proto.vstack = free
end

While = { tag = "While" }
While.__index = While
While_meta = { }
While_meta.__call = function(class, self)
   return setmetatable(self, class)
end
setmetatable(While, While_meta)
While.compile = function(self, proto)
   proto:line(self)
   local free = proto.vstack
   local expr, block = self[1], self[2]

   local loop_bot = self.loop_bot or util.genid()
   local loop_top = self.loop_top or util.genid()

   Label(loop_top):compile(proto)
   block[#block + 1] = Goto(loop_top)
   If{ expr, block, { Goto(loop_bot) } }:compile(proto)
   Label(loop_bot):compile(proto)

   proto.vstack = free
end


