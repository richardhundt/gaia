
function doit(whom) {
    return function(greet) {
        greet("Hello", whom)
    }
}

doit ("Felix") {
    print(...)
}


