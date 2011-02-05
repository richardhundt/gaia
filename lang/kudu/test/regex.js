//import std.regexp.RegExp

var rx = RegExp('(\w+) (\w+)')
var a,b = rx.match('foo bar')
var m = RegExp('\s+').split('foo bar baz')
for (i,v in m) {
    print("got:", v)
}

