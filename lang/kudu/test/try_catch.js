class Error {
    var message
    var stack
    function this(message) {
        this.message = message
        this.stack   = Error.getInfoStack()
    }
    function trace() {
        var trace = ['traceback:']
        for i,info in this.stack {
            trace.push("\t"~info.source~':'~(info.name || '?')~':'~info.currentline)
        }
        return trace.join("\n")
    }

    static function getInfoAt(level) {
        var info = Lua::debug::getinfo(level)
        if (!info) return
        var lsrc = info.source
        var line = info.currentline
        if (lsrc.sub(1,1) == '@' || lsrc.sub(1,4) == '=[C]') {
            return info
        }
        var o = 0
        var stop = line - 1
        var offs = 0
        while (stop > 0) {
            stop = stop - 1
            o = lsrc.find("\n", offs + 1, true)
            if (o == nil) break
            offs = o
        }
        var _, _, file, line = lsrc.find("--%[%[(.-):(%d+)%]%]", offs + 1)
        return {
            source      = file,
            currentline = line,
            func        = info.func,
            name        = info.name,
            namewhat    = info.namewhat,
            what        = info.what,
        }
    }

    static function getInfoStack() {
        var level = 2
        var stack = [ ]
        while (true) {
            var info = Error.getInfoAt(level)
            if (info == nil) break
            stack.push(info)
            level++
        }
        return stack
    }

    static function __tostring() {
        var info = Error.getInfoAt(2)
        return 'Error: '~this.message~' at '~info.source~'-'~info.currentline
    }
}

function doit(num) {
    try {
        if (num < 0) {
            throw new Error("negative!")
        }
        else {
            return "zero or more!"
        }
    }
    catch (ex) {
        print("caught", ex)
        print(ex.trace())
    }
    finally {
        return "seen finally block"
    }
}

print(doit(1))
print(doit(-1))

