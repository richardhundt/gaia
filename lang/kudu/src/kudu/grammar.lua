local lpeg   = require "lpeg"
local re     = require "re"
local util   = require "gaia.util"
local Parser = require "gaia.parser".Parser
lpeg.setmaxstack(500)

module("kudu.grammar", package.seeall)

local m = lpeg
local p = Parser.new()
local s = m.V"skip"
local stmt_sep = s * m.P";"^-1
local line_comment = m.P"//" * (1 - m.V"NL")^0 * m.V"NL"
local span_comment = m.P"/*" * ((m.V"NL" + 1) - m.P"*/")^0 * m.P"*/"
local comment = line_comment + span_comment
local idsafe =  -(m.V"alnum" + m.P"_")

p:skip { (comment + m.V"WS")^0 }

p:rule(1) {
   m.V"BOF" * s * m.V"chunk" * s * (m.V"EOF" + p:error"parse error")
}
p:rule"chunk" {
   m.V"block"
}
p:match"block" {
   (m.V"statement" * (stmt_sep * m.V"statement")^0)^-1
}
p:rule"statement" {
     m.V"func_decl"     * stmt_sep
   + m.V"var_decl"      * stmt_sep
   + m.V"chan_decl"     * stmt_sep
   + m.V"enum_stmt"     * stmt_sep
   + m.V"like_stmt"     * stmt_sep
   + m.V"if_stmt"       * stmt_sep
   + m.V"for_stmt"      * stmt_sep
   + m.V"for_in_stmt"   * stmt_sep
   + m.V"while_stmt"    * stmt_sep
   + m.V"return_stmt"   * stmt_sep
   + m.V"package_decl"  * stmt_sep
   + m.V"import_stmt"   * stmt_sep
   + m.V"export_stmt"   * stmt_sep
   + m.V"class_decl"    * stmt_sep
   + m.V"object_decl"   * stmt_sep
   + m.V"rule_decl"     * stmt_sep
   + m.V"bind_stmt"     * stmt_sep
   + m.V"binop_bind"    * stmt_sep
   + m.V"throw_stmt"    * stmt_sep
   + m.V"spawn_stmt"    * stmt_sep
   + m.V"try_catch"     * stmt_sep
   + m.V"break_stmt"    * stmt_sep
   + m.V"continue_stmt" * stmt_sep
   + m.V"expr_stmt"     * stmt_sep
}
p:token"word_char" {
   m.R"az" + m.R"AZ" + m.P"_" + m.R"09"
}
p:rule"keyword" {
   (
      m.P"var" + "function" + "class" + "is" + "with" + "new" + "object" + "spawn"
      + "nil" + "true" + "false" + "typeof" + "return" + "in" + "for" + "throw"
      + "enum" + "like" + "delete" + "private" + "public" + "protected" + "extends"
      + "break" + "continue" + "package" + "import" + "export" + "try" + "catch"
      + "finally" + "static" + "this" + "rule" + "if" + "else" + "chan"
   ) * idsafe
}

p:rule"guard" {
   m.P":" * s * m.Cg(m.V"guard_expr" + p:error"invalid guard expression")
}
p:rule"guard_term" {
   m.V"like_expr" + m.V"ident"
}
p:rule"like_expr" {
   m.P"like" * s * (m.V"table_literal" + m.V"array_literal")
}
p:match"like_literal" {
   m.V"like_expr"
}
p:rule"guarded_ident" {
   m.Cg(m.V"ident" * (s * m.V"guard")^-1) / function(id, g)
      id.guard = g
      return id
   end
}
p:match"ident" {
   (m.C((m.V"alpha" + "_") * (m.V"alnum" + "_")^0) - m.V"keyword")
}
p:token"hexadec" {
   m.P"-"^-1 * s * "0x" * m.V"xdigit"^1
}
p:token"decimal" {
   m.P"-"^-1 * s * m.V"digit"^1
   * (m.P"." * m.V"digit"^1)^-1
   * (m.S"eE" * m.P"-"^-1 * m.V"digit"^1)^-1
}
p:match"number" {
   m.V"hexadec" + m.V"decimal"
}
p:match"string" {
     m.C(m.P'"' * (m.P'\\\\' + m.P'\\"' + (1 -m.P'"'))^0 * m.P'"')
   + m.C(m.P"'" * (m.P"\\\\" + m.P"\\'" + (1 -m.P"'"))^0 * m.P"'")
}
p:rule"primary" {
     m.V"ident"
   + m.V"range"
   + m.V"number"
   + m.V"string"
   + m.V"nil"
   + m.V"spread"
   + m.V"true"
   + m.V"false"
   + m.V"this"
   + m.V"short_lambda"
   + m.V"array_literal"
   + m.V"table_literal"
   + m.V"tuple_literal"
   + m.V"object_literal"
   + m.V"func_literal"
   + m.V"chan_literal"
   + m.V"like_literal"
   + m.Cg(m.C"(" * s * m.V"expr" * s * p:expect")" / function(o, ...)
      return gaia.parser.ASTNode{ tag = 'op_circumfix', oper = o, ... }
   end)
}
p:rule"term" {
   m.Cf(m.Cg(m.V"primary") *
   m.Cg(s * m.V"tail_expr")^0, function(a, o, b, ...)
      if o == '.' or o == '::' or o == 'with' then
         return gaia.parser.ASTNode{ tag = 'op_infix', oper = o, a, b }
      else
         return gaia.parser.ASTNode{ tag = 'op_postcircumfix', oper = o, a, b, ... }
      end
   end)
}
p:rule"tail_expr" {
   m.C"[" * s * m.V"expr" * s * p:expect"]"
   + m.C"." * s * m.V"ident"
   + m.P"::" * s * m.P"[" * m.Cc"::[" * s * m.V"expr" * s * p:expect"]"
   + m.C"::" * s * m.V"ident"
   + m.C"with" * s * m.V"with_spec"
   + m.C"(" * s * m.V"expr_list"^-1 * s * p:expect")"
}
p:match"nil"    { m.P"nil"   }
p:match"true"   { m.P"true"  }
p:match"false"  { m.P"false" }
p:match"this"   { m.C"this"  }
p:match"rest"   { m.P"..." * m.V"guarded_ident" }
p:match"spread" { m.P"..." * m.V"expr" }

p:match"var_decl" {
   (m.Cg(m.C"public" + m.C"private" + m.C"static" + m.C"protected", "modifier") * s)^-1
   * m.Cg(m.C"var" + m.C"const", "alloc") * s
   * m.V"name_list" * (s * m.P"=" * s * m.V"expr_list")^-1
}
p:match"name_list" {
   m.V"guarded_ident" * (s * "," * s * m.V"guarded_ident")^0
}
p:match"expr_list" {
   (m.V"expr" * (s * "," * s * m.V"expr")^0)
}
p:rule"expr_stmt" {
   m.V"expr" / function(node)
      ---[[
      if node[1].oper == nil then
         local format = "Syntax Error: %s on line %s - %s"
         error(string.format(format, "bare term", node.locn.line, tostring(node)))
      end
      --]]
      return node
   end
}
p:match"enum_stmt" {
   m.P"enum" * idsafe * s * m.V"ident" * s * p:expect"{" *
   (s * m.V"ident" * s * ";")^1 * s *
   p:expect"}"
}
p:match"like_stmt" {
   m.P"like" * idsafe * s * m.V"ident" * s * m.V"like_expr"
}
p:match"for_stmt" {
   m.P"for" * idsafe * s
   * m.V"ident" * s * "=" * s * m.V"expr" * s
   * p:expect"," * s * m.V"expr" * (s * "," * s * m.V"expr" + m.C(true)) * s
   * m.V"cond_block"
}
p:match"for_in_stmt" {
   m.P"for" * idsafe * s
   * m.V"for_in_vars" * s
   * m.P"in" * idsafe * s * m.V"list_expr_noin" * s
   * m.V"cond_block"
}
p:match"for_in_vars" {
   m.V"ident" * (s * "," * s * m.V"ident")^0
}
p:match"while_stmt" {
   m.P"while" * idsafe * s
   * m.V"expr" * s
   * m.V"cond_block"
}
p:match"if_stmt" {
   m.P"if" * idsafe * s * m.V"expr" * s
   * m.V"cond_block" * s
   * (m.P"else" * idsafe * s * m.P"if" * idsafe * s
      * m.V"expr" * s
      * m.V"cond_block" * s)^0
   * (m.P"else" * idsafe * s * m.V"cond_block")^-1
}
p:match"spawn_stmt" {
   m.P"spawn" * idsafe * s * m.V"expr"
}
p:match"throw_stmt" {
   m.P"throw" * idsafe * s * m.V"expr"
}
p:match"try_catch" {
   m.P"try" * idsafe * s * m.V"cond_block" * (s * m.V"catch_block")^-1 * (s * m.V"finally_block")^-1
}
p:match"catch_block" {
   m.P"catch" * idsafe * s * p:expect"(" * s * m.V"func_params" * s * p:expect")" * s * m.V"cond_block"
}
p:match"finally_block" {
   m.P"finally" * idsafe * s * m.V"cond_block"
}
p:match"break_stmt" {
   m.P"break" * idsafe
}
p:match"continue_stmt" {
   m.P"continue" * idsafe
}
p:match"cond_block" {
   m.P"{" * s * (m.V"statement" * stmt_sep)^0 * s * p:expect"}"
   + m.V"statement" * stmt_sep
}
p:match"array_literal" {
   m.P"[" * s * m.V"items"^-1 * s * p:expect"]"
}
p:rule"items" {
   m.V"expr" * (s * "," * s * m.V"expr")^0 * (s * ",")^-1
}
p:match"tuple_literal" {
   m.P"(" * s * (
      m.V"expr" * (s * "," * s * m.V"expr")^1 * (s * ",")^-1
      + m.V"expr" * s * ","
      + m.P","
   ) * s * p:expect")"
}
p:match"table_literal" {
   m.P"{" * s * m.V"pairs"^-1 * s * p:expect"}"
}
p:rule"pairs" {
   m.V"pair" * (s * "," * s * m.V"pair")^0 * (s * ",")^-1
}
p:rule"pair" {
   (m.V"guarded_ident" + m.P"[" * s * m.V"expr" * s * p:expect"]") * s
   * p:expect"=" * s * m.V"expr"
}
p:match"short_lambda" {
   m.P"{" * s * m.V"name_list" * s * m.P"=>" * s * m.V"expr_stmt" * s * p:expect"}"
}
p:match"range" {
   m.V"number" * s * ".." * s * m.V"number"
}
p:match"func_decl" {
   (m.Cg(m.C"public" + m.C"private" + m.C"static", "modifier") * s)^-1
   * m.P"function" * s * (
      m.Cg((m.C"get" + m.C"set") * idsafe + m.P(true), "attribute")
   ) * s * (m.V"ident" + m.V"this") * s * m.V"func_common"
}
p:match"func_literal" {
   m.P"function" * s * m.V"func_common"
}
p:rule"func_common" {
   p:expect"(" * s
   * (m.V"func_params" * s + p:error"invalid parameter list")
   * p:expect")" * s * m.Cg(m.V"guard", "guard")^-1 * s
   * p:expect"{" * s * m.V"block" * s * p:expect"}"
}
p:match"func_params" {
   (((m.V"this" + m.V"guarded_ident") * (s * "," * s * m.V"guarded_ident")^0)^-1
   * (s * "," * s * m.V"rest")^-1) * (s * m.V"rest" * s)^-1
   + m.P(true)
}
p:match"chan_decl" {
   (m.Cg(m.C"public" + m.C"private" + m.C"static", "modifier") * s)^-1
   * m.P"chan" * idsafe * s * m.V"ident" * s
   * p:expect"(" * s * m.Cg(m.V"number" + m.Cc(nil), 'size') * s * p:expect")" * s
   * m.Cg(m.V"guard", "guard")^-1
}
p:match"chan_literal" {
   m.P"chan" * idsafe * s
   * p:expect"(" * s * m.Cg(m.V"number"^1 + m.Cc(nil), 'size') * s * p:expect")" * s
   * m.Cg(m.V"guard", "guard")^-1
}
p:match"return_stmt" {
   m.P"return" * idsafe * s * m.V"expr_list"^-1
}
p:match"class_decl" {
   (m.Cg(m.C"public" + m.C"private", "modifier") * s)^-1
   * m.P"class" * s * m.V"ident" * s
   * m.V"class_head" * s
   * p:expect"{" * s * m.V"class_body" * s * p:expect"}"
}
p:match"class_head" {
   m.V"class_extends"
}
p:match"class_body" {
   (m.V"class_body_stmt" * (stmt_sep * m.V"class_body_stmt")^0)^-1
}
p:rule"class_body_stmt" {
   m.V"var_decl"      * stmt_sep
   + m.V"func_decl"   * stmt_sep
   + m.V"chan_decl"   * stmt_sep
   + m.V"rule_decl"   * stmt_sep
   + m.V"with_stmt"   * stmt_sep
}
p:match"class_extends" {
   m.P"extends" * s * m.V"ident"
   + m.Cc""
}
p:match"with_stmt" {
   m.P"with" * s * m.V"with_spec"
}
p:match"with_spec" {
   m.V"ident" * s * m.V"table_literal"^-1
}
p:match"object_decl" {
   m.P"object" * s * m.V"ident" * s * p:expect"{" * s * m.V"class_body" * s * p:expect"}"
}
p:match"object_literal" {
   m.P"object" * s * p:expect"{" * s * m.V"class_body" * s * p:expect"}"
}
p:rule"member_term" {
   m.V"late_bind" + m.V"ident" + m.V"expr"
}
p:match"late_bind" {
   m.P"[" * s * m.V"expr" * s * p:expect"]"
}
p:match"bind_stmt" {
   m.Cf(
      m.Cg(m.V"expr_list") * s *m.Cg(m.C(m.P"=") * s * m.V"expr_list")
   , gaia.parser.OpInfix.handler)
}
p:match"binop_bind" {
   m.Cf(
      m.Cg(m.V"expr") * s *m.Cg(m.C(
         m.P"+=" + "-=" + "**=" + "/=" + "%=" + "||=" + "|=" + "&=" + "^=" + "~=" + "*="
      ) * s * m.V"expr")
   , gaia.parser.OpInfix.handler)
}
p:match"package_decl" {
   m.P"package" * s * m.V"ident" * (s * "." * s * m.V"ident")^0
}
p:match"import_stmt" {
   m.P"import" * s * m.V"ident" * (s * "." * s * m.V"ident")^0 * (s * "." * s * m.C"*")^-1
}
p:match"export_stmt" {
   m.P"export" * s * m.V"ident" * (s * "," * s * m.V"ident")^0
}

------------------------------------------------------------------------------
-- PEG rules
------------------------------------------------------------------------------
p:match"rule_decl" {
   m.P"rule" * s * m.V"ident" * s * m.P"{" * s * m.V"rule_body" * s * p:expect"}"
}
p:match"rule_body" {
   m.P"|"^-1 * s * m.V"rule_expr"
}
p:rule"rule_expr" {
  s * m.Cf(m.Cg(m.V"rule_seq") * m.Cg(s * "|" * s * m.V"rule_seq")^0, function(a, b)
      return gaia.parser.ASTNode{ tag = 'rule_alt', a, b }
  end)
}
p:match"rule_range" {
   m.Cs(m.P(1) * (m.P"-" / "") * (m.P(1) - "]"))
}
p:rule"rule_item" {
   m.V"rule_ref" + m.V"rule_range" + m.C(m.P(1))
}
p:match"rule_class" {
   m.P"[" * m.Cg((m.C(m.P"^"^-1)) * m.V"rule_item" * (m.V"rule_item" - "]")^0) * "]"
}
p:rule"rule_expr_follow" {
   m.P"|" + ")" + "}" + ":}" + "~}" + -1
}
p:match"rule_seq" {
  m.V"rule_prefix"^0 * (#m.V"rule_expr_follow" + p:error"pattern error");
}
p:rule"rule_prefix" {
     m.C"&" * s * m.V"rule_prefix"
   + m.C"!" * s * m.V"rule_prefix"
   + m.V"rule_suffix"
}
p:rule"rule_suffix" {
   m.Cf(
      m.Cg(m.V"rule_primary") * s * m.Cg((m.V"rule_rep" + m.V"rule_prod") * s)^1,
      function(a, o, b, ...)
         if o == '->' or o == '=>' then
            return gaia.parser.ASTNode{ tag = 'rule_prod', oper = o, a, b }
         else
            return gaia.parser.ASTNode{ tag = 'rule_rep', oper = o, a, b, ... }
         end
      end
   )
   + m.V"rule_primary" * s
}
p:rule"rule_primary" {
     m.V"rule_group"
   + m.V"rule_term"
   + m.V"rule_class"
   + m.V"rule_group_capt"
   + m.V"rule_back_capt"
   + m.V"rule_pos_capt"
   + m.V"rule_sub_capt"
   + m.V"rule_simple_capt"
   + m.V"rule_any"
   + m.V"rule_ref"
}
p:match"rule_term" {
   m.V"string"
}
p:rule"rule_rep" {
   m.C"+" + m.C"*" + m.C"?" + (m.C"^" * m.V"number")
}
p:rule"rule_prod" {
     m.C"->" * s * m.V"term"
   + m.C"=>" * s * m.V"term"
}
p:match"rule_group" {
   "(" * s * m.V"rule_expr" * s * ")"
}
p:match"rule_group_capt" {
   "{:" * m.Cg(m.V"ident" * ":" + m.Cc(nil), "name") * m.V"rule_expr" * ":}"
}
p:match"rule_back_capt" {
   "=" * m.V"ident"
}
p:match"rule_pos_capt" {
   m.P"{}"
}
p:match"rule_sub_capt" {
   "{~" * m.V"rule_expr" * "~}"
}
p:match"rule_simple_capt" {
   "{" * m.V"rule_expr" * "}"
}
p:match"rule_any" {
   m.P"."
}
p:match"rule_ref" {
   "<" * m.V"term" * ">"
}

------------------------------------------------------------------------------
-- Expressions
------------------------------------------------------------------------------
local expr_base = p:express"expr_base" :primary"term"

expr_base:op_infix("&&") :prec(3)
expr_base:op_infix("||") :prec(4)
expr_base:op_infix("|", "^", "&"):prec(6)
expr_base:op_infix("!=", "==", "instanceof" ):prec(7)
expr_base:op_infix(
   "<-", ">>>", ">>", "<<"
   ):prec(9)
expr_base:op_infix("~", "+", "-"):prec(10)
expr_base:op_infix("*", "/", "%"):prec(20)
expr_base:op_prefix(
   "typeof", "delete", "--", "++", "~", "!", "+", "-" --, "#"
   ):prec(30)
expr_base:op_infix("**"):prec(35)
expr_base:op_prefix("new", "<-"):prec(40)
expr_base:op_postfix("++", "--"):prec(35)
expr_base:op_ternary"?:":prec(2)

------------------------------------------------------------------------------
-- Full Expression
------------------------------------------------------------------------------
local expr = expr_base:clone"expr"
expr:op_infix(
   ">=", "<=>", "<=", "<", ">", "is", "in"
   ):prec(8)

------------------------------------------------------------------------------
-- No-in Expression
------------------------------------------------------------------------------
local expr_noin = expr_base:clone"expr_noin"
expr_noin:op_infix(
   ">=", "<=>", "<=", "<", ">", "is"
   ):prec(8)

------------------------------------------------------------------------------
-- List Expression
------------------------------------------------------------------------------
local list_expr = p:express"list_expr" :primary"expr"
list_expr:op_listfix"," :prec(1)

------------------------------------------------------------------------------
-- List No-in Expression
------------------------------------------------------------------------------
local list_expr_noin = p:express"list_expr_noin" :primary"expr_noin"
list_expr_noin:op_listfix"," :prec(1)

------------------------------------------------------------------------------
-- Guard Expressions
------------------------------------------------------------------------------
local guard_expr = p:express"guard_expr" :primary"guard_term"
guard_expr:op_infix("|", "&")  :prec(2)
guard_expr:op_prefix("?", "!") :prec(3)

function match(source)
   return assert(p:parse(source), "failed to parse")
end

