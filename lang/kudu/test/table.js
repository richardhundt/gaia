var t = { }
t.whom = "ME!"
t.answer = function(this) {
    print("Hello from: " ~ this.whom)
}
t.answer()
t.foo = function(...args) {
    print(...args)
}
t::['foo']("Hey", "World!")

var t = { foo = 'bar', baz = 'quux' }
for (k,v in t) {
    print(k, v)
}

