package std.regexp

var rex = magic::require("rex_onig")

class RegExp {

   private var pattern

   function this(patt, ...) {
      this.pattern = rex::['new'](patt, ...)
   }

   function match(subj, ...) {
      return rex::match(subj, this.pattern, ...)
   }

   function gmatch(subj, ...) {
      var matches = [ ]
      for (m in rex::gmatch(subj, this.pattern, ...)) {
         matches.push(m)
      }
      return matches
   }
   function find(subj, ...) {
      return rex::find(subj, this.pattern, ...)
   }
   function tfind(subj, ...) {
      return rex::tfind(subj, this.pattern, ...)
   }
   function gsub(subj, repl, ...) {
      return rex::gsub(subj, this.pattern, repl, ...)
   }
   function split(subj, ...) {
      var frags = [ ]
      for (s in rex::split(subj, this.pattern, ...)) {
         frags.push(s)
      }
      return frags
   }

}

