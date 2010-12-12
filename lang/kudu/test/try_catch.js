function doit(num) {
    try {
        if (num < 0) {
            throw "negative!"
        }
        else {
            return "zero or more!"
        }
    }
    catch (ex) {
        print("ARSE!", ex)
    }
    finally {
        return "seen finally block"
    }
}

print(doit(1))
print(doit(-1))

