/*
var h = { }
for (i=1,10000000) {
    h["answer"] = i
}
print(h["answer"])
*/

class Hash {
    function this() {
        this::table = { }
    }
    function __get_index(key) {
        return this::table::[key]
    }
    function __set_index(key, val) {
        this::table::[key] = val
    }
    function each(block) {
        for (k,v in this::table) {
            block(k, v)
        }
    }
}

var h = new Hash()
h['foo'] = 42
h["bar"] = 69
for (i=1,10000000) {
    h["answer"] = i
}

print(h["answer"])

h.each {
    var k,v = ...
    print("got: ", k~':'~v)
}

