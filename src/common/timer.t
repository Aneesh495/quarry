-- Quarry high precision execution timer
-- Nanosecond resolution profiling using CLOCK_MONOTONIC.

local C = require("src.common.c").C

local timer = {}

-- Standard CLOCK_MONOTONIC identifier on POSIX systems
local CLOCK_MONOTONIC = 6 -- on macOS CLOCK_MONOTONIC is 6

struct Stopwatch {
    start_sec: int64,
    start_nsec: int64,
    stop_sec: int64,
    stop_nsec: int64,
    is_running: bool
}

terra Stopwatch:start() : void
    var ts : C.timespec
    C.clock_gettime(CLOCK_MONOTONIC, &ts)
    self.start_sec = ts.tv_sec
    self.start_nsec = ts.tv_nsec
    self.stop_sec = self.start_sec
    self.stop_nsec = self.start_nsec
    self.is_running = true
end

terra Stopwatch:stop() : void
    var ts : C.timespec
    C.clock_gettime(CLOCK_MONOTONIC, &ts)
    self.stop_sec = ts.tv_sec
    self.stop_nsec = ts.tv_nsec
    self.is_running = false
end

terra Stopwatch:elapsed_ns() : double
    var sec : double
    var nsec : double
    if self.is_running then
        var ts : C.timespec
        C.clock_gettime(CLOCK_MONOTONIC, &ts)
        sec = [double](ts.tv_sec - self.start_sec)
        nsec = [double](ts.tv_nsec - self.start_nsec)
    else
        sec = [double](self.stop_sec - self.start_sec)
        nsec = [double](self.stop_nsec - self.start_nsec)
    end
    return sec * 1000000000.0 + nsec
end

terra Stopwatch:elapsed_us() : double
    return self:elapsed_ns() / 1000.0
end

terra Stopwatch:elapsed_ms() : double
    return self:elapsed_ns() / 1000000.0
end

terra Stopwatch:elapsed_sec() : double
    return self:elapsed_ns() / 1000000000.0
end

timer.Stopwatch = Stopwatch
return timer
