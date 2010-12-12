class Hash {
    var answer

    function this() {
        this::data = { }
    }
    function __get_index(key) {
        return this::data[key]
        //return magic::rawget(this::data, key)
    }
    function __set_index(key, val) {
        this::data[key] = val
        //magic::rawset(this::data, key, val)
    }
    function keys() {
        var keys = [ ]
        for (k in this::data) {
            keys[keys.length+1] = k
        }
        return keys
    }
}

var f = new Hash
f.answer = "forty-two"
f["a"] = 1;
f["b"] = 2;
print(f.keys())

for (i in 1..10000000) {
    f["answer"] = 42
}
print("HERE:", f["answer"], f.answer)

var foo = { }
foo["answer"] = 42
for (i in 1..10) {
    foo.bar = i
}

print(foo.bar)
print(foo["answer"])
print(foo.answer)

print(foo::__get_index(foo, "answer"))

foo.["answer"] = 69
print(foo.["answer"])
foo.greet = function() { print("Hello from: ", this) }
foo.greet()

