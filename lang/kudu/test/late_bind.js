var o = { }
o.greet = function() { print("Hi from: ", this) }
var s = 'greet'
o.[s]()
o::[s]('Me!')

