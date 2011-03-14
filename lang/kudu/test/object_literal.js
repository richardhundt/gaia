object Friendly {
    function greet() {
        print("Hello from:", this)
    }
}

var s = "cheese" with Friendly
s.greet()
