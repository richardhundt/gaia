local lpeg   = require "lpeg"
local util   = require "gaia.util"
local Parser = require "gaia.parser".Parser

module("kudu.grammar", package.seeall)

local m = lpeg
local p = Parser.new()
local s = m.V"skip"
local stmt_sep = s * m.P";"^-1
local line_comment = m.P"//" * (1 - m.V"NL")^0 * m.V"NL"
local span_comment = m.P"/*" * ((m.V"NL" + 1) - m.P"*/")^0 * m.P"*/"
local comment = line_comment + span_comment
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
   + m.V"if_stmt"       * stmt_sep
   + m.V"for_stmt"      * stmt_sep
   + m.V"for_in_stmt"   * stmt_sep
   + m.V"while_stmt"    * stmt_sep
   + m.V"return_stmt"   * stmt_sep
   + m.V"module_decl"   * stmt_sep
   + m.V"import_stmt"   * stmt_sep
   + m.V"export_stmt"   * stmt_sep
   + m.V"class_decl"    * stmt_sep
   + m.V"role_decl"     * stmt_sep
   + m.V"bind_stmt"     * stmt_sep
   + m.V"throw_stmt"    * stmt_sep
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
      m.P"var" + "function" + "class" + "is" + "with" + "new" + "object"
      + "null" + "true" + "false" + "typeof" + "return" + "in" + "for" + "throw"
      + "type" + "enum" + "like" + "delete" + "private" + "public" + "extends"
      + "break" + "continue" + "module" + "import" + "export"
   ) * -(m.V"alnum"+m.P"_")
}
p:match"ident" {
   m.C((m.V"alpha" + "_") * (m.V"alnum" + "_")^0) - m.V"keyword"
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
     m.P'"' * m.C((m.P'\\\\' + m.P'\\"' + (1 -m.P'"'))^0) * m.P'"'
   + m.P"'" * m.C((m.P"\\\\" + m.P"\\'" + (1 -m.P"'"))^0) * m.P"'"
}
p:rule"term" {
     m.V"ident"
   + m.V"range"
   + m.V"number"
   + m.V"string"
   + m.V"null"
   + m.V"rest"
   + m.V"true"
   + m.V"false"
   + m.V"array_literal"
   + m.V"table_literal"
   + m.V"func_literal"
}
p:match"null"  { m.P"null"  }
p:match"true"  { m.P"true"  }
p:match"false" { m.P"false" }
p:match"rest"  { m.P"..."   }

p:match"var_decl" {
   m.Cg(m.C"var" + m.C"let", "alloc") * s
   * m.V"name_list" * (s * m.P"=" * s * m.V"expr_list")^-1
}
p:match"name_list" {
   m.V"ident" * (s * "," * s * m.V"ident")^0
}
p:match"expr_list" {
   (m.V"expr" * (s * "," * s * m.V"expr")^0)
}
p:rule"expr_stmt" {
   m.V"expr" / function(node)
      if node[1].oper == nil then
         local format = "Syntax Error: %s on line %s"
         error(string.format(format, "bare term", node.locn.line))
      end
      return node
   end
}
p:rule"label" {
   m.Cg(m.V"ident", 'label') * m.P":"
}
p:match"for_stmt" {
   m.P"for" * s
   * p:expect"(" * s
   * m.V"ident" * s * "=" * s * m.V"expr" * s
   * p:expect"," * s * m.V"expr" * (s * "," * s * m.V"expr" + m.C(true)) * s
   * p:expect")" * s
   * m.V"cond_block"
   --* m.P"do"^-1 * s * m.V"cond_block"
}
p:match"for_in_stmt" {
   m.P"for" * s
   * p:expect"(" * s
   * m.V"for_in_vars" * s
   * "in" * s * m.V"list_expr_noin" * s
   * p:expect")" * s
   * m.V"cond_block"
   --* m.P"do"^-1 * s * m.V"cond_block"
}
p:match"for_in_vars" {
   m.V"ident" * (s * "," * s * m.V"ident")^0
}
p:match"while_stmt" {
   (m.V"label" * s)^-1 * m.P"while" * s * p:expect"(" * s
   * (m.V"expr" + m.C(true)) * s * p:expect")" * s
   * m.V"cond_block"
}
p:match"if_stmt" {
   m.P"if" * s * p:expect"(" * s * m.V"expr" * s * p:expect")" * s
   * m.V"cond_block" * s
   * (m.P"else" * s * m.P"if" * s
      * p:expect"(" * s * m.V"expr" * s * p:expect")" * s
      * m.V"cond_block" * s)^0
   * (m.P"else" * s * m.V"cond_block")^-1
}
p:match"throw_stmt" {
   m.P"throw" * s * m.V"expr"
}
p:match"try_catch" {
   m.P"try" * s * m.V"cond_block" * (s * m.V"catch_block")^-1 * (s * m.V"finally_block")^-1
}
p:match"catch_block" {
   m.P"catch" * s * p:expect"(" * s * m.V"func_params" * s * p:expect")" * s * m.V"cond_block"
}
p:match"finally_block" {
   m.P"finally" * s * m.V"cond_block"
}
p:match"break_stmt" {
   m.P"break" * (s * m.V"ident")^-1
}
p:match"continue_stmt" {
   m.P"continue" * (s * m.V"ident")^-1
}
p:match"cond_block" {
   m.P"{" * s * (m.V"statement" * stmt_sep)^0 * s * p:expect"}"
   + m.V"statement" * stmt_sep
}
p:match"array_literal" {
   m.P"[" * s * m.V"items"^-1 * s * p:expect"]"
}
p:rule"items" {
   m.V"expr" * (s * "," * s * m.V"expr")^0
}
p:match"table_literal" {
   m.P"{" * s * m.V"pairs"^-1 * s * p:expect"}"
}
p:rule"pairs" {
   m.V"pair" * (s * "," * s * m.V"pair")^0
}
p:rule"pair" {
   (m.C((m.V"alpha" + m.P'_') * (m.V"alnum" + m.P'_')^0) + m.P"[" * s * m.V"expr" * s * p:expect"]") * s
   * p:expect":" * s * m.V"expr"
}
p:match"expr_pairs" {
   m.V"pair" * (s * "," * s * m.V"pair")^0
}
p:match"range" {
   m.V"number" * s * ".." * s * m.V"number"
}
p:match"func_decl" {
   m.P"function" * s * m.V"ident" * s * m.V"func_common"
}
p:match"func_literal" {
   m.P"function" * s * m.V"func_common"
}
p:rule"func_common" {
   p:expect"(" * s
   * (m.V"func_params" * s + p:error"invalid parameter list")
   * p:expect")" * s
   * p:expect"{" * s * m.V"block" * s * p:expect"}"
}
p:match"func_params" {
   ((m.V"ident" * (s * "," * s * m.V"ident")^0)^-1
   * (s * "," * s * m.V"rest")^-1)
   + m.V"rest"
   + m.P(true)
}
p:match"return_stmt" {
   m.P"return" * s * m.V"expr_list"
}
p:match"class_decl" {
   m.P"class" * s * m.V"ident" * s
   * m.V"class_head" * s
   * p:expect"{" * s * m.V"class_body" * s * p:expect"}"
}
p:match"class_head" {
   m.V"class_from" * (s * m.V"class_with")^-1
}
p:match"class_body" {
   (m.V"class_body_stmt" * (stmt_sep * m.V"class_body_stmt")^0)^-1
}
p:rule"class_body_stmt" {
     m.Cg(m.P"public" + m.P"private", "attribute")^-1
   * (m.V"var_decl"  * stmt_sep + m.V"func_decl" * stmt_sep)
}
p:match"class_from" {
   m.P"extends" * s * m.V"ident"
   + m.Cc""
}
p:match"class_with" {
   m.P"with" * s * m.V"ident" * s * ("," * s * m.V"ident")^0
}
p:match"role_decl" {
   m.P"object" * s * m.V"ident" * s
   * m.V"role_head" * s
   * p:expect"{" * s * m.V"class_body" * s * p:expect"}"
}
p:match"role_head" {
   m.V"class_with"^-1
}
p:rule"member_term" {
   m.V"ident" + m.V"late_bind"
}
p:match"late_bind" {
   m.P"[" * m.V"expr" * p:expect"]"
}
p:match"bind_stmt" {
   m.Cf(
      m.Cg(m.V"expr_list") * s *m.Cg(m.C(
         m.P"+=" + "-=" + "**=" + "/=" + "%=" + "|=" + "&=" + "^=" + "~=" + "*=" + "="
      ) * s * m.V"expr_list")
   , gaia.parser.OpInfix.handler)
}
p:match"module_decl" {
   m.P"module" * s * m.V"ident" * (s * "." * s * m.V"ident")^0
}
p:match"import_stmt" {
   m.P"import" * s * m.V"ident" * (s * "." * s * m.V"ident")^0
}
p:match"export_stmt" {
   m.P"export" * s * m.V"ident" * (s * "," * s * m.V"ident")^0
}

------------------------------------------------------------------------------
-- Expressions
------------------------------------------------------------------------------
local expr_base = p:express"expr_base" :primary"term"
expr_base:op_infix("||", "&&"   ):prec(3)
expr_base:op_infix("|", "^", "&"):prec(6)
expr_base:op_infix("!=", "=="   ):prec(7)
expr_base:op_infix(
   ">>>", ">>", "<<"
   ):prec(9)
expr_base:op_infix("~", "+", "-"):prec(10)
expr_base:op_infix("*", "/", "%"):prec(20)
expr_base:op_prefix(
   "typeof", "delete", "--", "++", "~", "!", "+", "-"
   ):prec(30)
expr_base:op_infix("**"):prec(35)
expr_base:op_prefix"new":prec(40)
expr_base:op_postfix("++", "--"):prec(35)
expr_base:op_ternary"?:":prec(2)
expr_base:op_circumfix"()":prec(50)

-- this weirdness is needed to support foo.bar().baz() so
-- that we have '.' precedence *around* '()' precedence
expr_base:op_infix(".", "::"):prec(38) :expr"member_term"
expr_base:op_postcircumfix"()":prec(39) :expr"list_expr"
expr_base:op_infix(".", "::"):prec(40) :expr"member_term"

expr_base:op_postcircumfix"[]":prec(38)
expr_base:op_postcircumfix"[]":prec(40)

expr_base:op_postcircumfix"{}":prec(38) :expr"expr_pairs"
expr_base:op_postcircumfix"{}":prec(40) :expr"expr_pairs"

------------------------------------------------------------------------------
-- Full Expression
------------------------------------------------------------------------------
local expr = expr_base:clone"expr"
expr:op_infix(
   ">=", "<=>", "<=", "<", ">", "is", "like", "in"
   ):prec(8)

------------------------------------------------------------------------------
-- No-in Expression
------------------------------------------------------------------------------
local expr_noin = expr_base:clone"expr_noin"
expr_noin:op_infix(
   ">=", "<=>", "<=", "<", ">", "is", "like"
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

function match(source)
   return assert(p:parse(source), "failed to parse")
end
