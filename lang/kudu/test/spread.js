function a(...args) {
    return ...args
}

print(a("a","B","see"))

var a,b,c = ...(1,2,3)
print(a,b,c)

function f() {
    return ('a','b','c')
}

var a, b, c = ...f()
print(a,b,c)
