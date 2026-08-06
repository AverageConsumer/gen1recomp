-- HostShell's HTTP error reporting.  No pokered cite: host transport is
-- port-only plumbing.
--
-- A user hit the launcher's mod index against a rate-limited GitHub and all
-- they got was one line on the terminal:
--
--     curl: (56) The requested URL returned error: 403
--
-- That is curl talking to its own stderr.  It names no URL, so with an index
-- feed, a releases API and a page of thumbnails all in flight there was no way
-- to tell WHICH fetch failed, and the caller upstream got a generic "empty
-- response" that said even less.  HostShell now merges curl's stderr into the
-- pipe and asks for the status with --write-out, so every failure names its
-- URL and its HTTP code, and a 403 body ("API rate limit exceeded") reaches
-- the launcher's notice line where a user can act on it.
--
-- The seam is io.popen: these cases stub it to replay exactly what curl writes
-- for each outcome, which is the only way to pin the parsing without a network
-- and a cooperating server.
--   luajit tests/engine/host_shell_fetch_errors.lua

package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check = T.check
love = love or require("tests.love_stub")

local HostShell = require("src.core.HostShell")

-- The marker HostShell asks curl to print before the status code.  Spelled
-- here the way it arrives (a real newline), not the way it is passed to curl
-- (a backslash-n escape curl expands itself).
local MARK = "\n__gen1recomp_http__"

-- Replay `output` as the next popen's whole stdout.  `curl --version` is
-- answered separately so HostShell.haveCurl agrees a transport exists.
local realPopen = io.popen
local lastCommand
local function stubPopen(output)
  io.popen = function(cmd, mode)
    lastCommand = cmd
    if cmd:find("--version", 1, true) then
      return { read = function() return "curl 8.7.1 (test)" end,
               close = function() return true end }
    end
    return { read = function() return output end,
             close = function() return true end }
  end
end
local function restorePopen() io.popen = realPopen end

local URL = "https://api.github.com/repos/example/thing/releases"

-- ------------------------------------------------------------------- 200
stubPopen('{"tag_name":"v1.2.3"}' .. MARK .. "200")
local body, err = HostShell.httpGet(URL, "gen1recomp", nil, 10)
check(body == '{"tag_name":"v1.2.3"}',
  "a 200 returns the body with the status marker stripped: " .. tostring(body))
check(err == nil, "a 200 reports no error")
check(lastCommand:find("%-w ") ~= nil,
  "the GET asks curl for the status code")
check(lastCommand:find("2>&1", 1, true) ~= nil,
  "the GET captures curl's stderr instead of leaking it to the terminal")
check(lastCommand:find(" -f", 1, true) == nil,
  "the GET does NOT pass -f: the error body is the diagnosis")

-- ------------------------------------------------------------------- 403
-- What GitHub actually sends when the launcher has burned its unauthenticated
-- hourly allowance, with curl's own stderr merged in ahead of it.
stubPopen('{"message":"API rate limit exceeded for 203.0.113.7."}'
  .. MARK .. "403")
local body403, err403 = HostShell.httpGet(URL, "gen1recomp", nil, 10)
check(body403 == nil, "a 403 is a failure, not a body")
check(err403:find(URL, 1, true) ~= nil,
  "a 403 names the URL that failed: " .. tostring(err403))
check(err403:find("403", 1, true) ~= nil, "a 403 names the status code")
check(err403:find("rate limit", 1, true) ~= nil,
  "a 403 carries the server's own explanation through to the caller")

-- --------------------------------------------------- no response at all
-- DNS failure: curl writes its complaint and a http_code of 0.  Zero is not a
-- status, and reporting "HTTP 0" would bury the only useful line there is.
stubPopen("curl: (6) Could not resolve host: nope.invalid" .. MARK .. "0")
local bodyDns, errDns = HostShell.httpGet("https://nope.invalid/x", "ua", nil, 10)
check(bodyDns == nil, "an unresolvable host is a failure")
check(errDns:find("HTTP 0", 1, true) == nil,
  "a no-response failure is not reported as HTTP 0: " .. tostring(errDns))
check(errDns:find("https://nope.invalid/x", 1, true) ~= nil,
  "an unresolvable host still names the URL")
check(errDns:find("Could not resolve", 1, true) ~= nil,
  "an unresolvable host reports curl's own reason")

-- --------------------------------------------- a body containing the marker
-- The status is cut from the LAST marker only, so a payload that happens to
-- contain the token keeps every byte of its content.
local sneaky = "prefix" .. MARK .. "999" .. "suffix"
stubPopen(sneaky .. MARK .. "200")
local bodySneaky = HostShell.httpGet(URL, "gen1recomp", nil, 10)
check(bodySneaky == sneaky,
  "only the trailing status marker is stripped: " .. tostring(bodySneaky))

-- ------------------------------------------------------------- downloads
-- The download branch keeps -f (no error body is written to the file), but it
-- must still name the URL and the code rather than "download failed".
stubPopen("curl: (56) The requested URL returned error: 403" .. MARK .. "403")
local ok, dlErr = HostShell.httpDownload(URL, "/tmp/gen1recomp-test.bin",
  "gen1recomp", nil, 10)
check(ok == nil, "a 403 download fails")
check(dlErr:find(URL, 1, true) ~= nil,
  "a failed download names the URL: " .. tostring(dlErr))
check(dlErr:find("403", 1, true) ~= nil, "a failed download names the code")

stubPopen(MARK .. "200")
local ok2, dlErr2 = HostShell.httpDownload(URL, "/tmp/gen1recomp-test.bin",
  "gen1recomp", nil, 10)
check(ok2 == true, "a 200 download succeeds: " .. tostring(dlErr2))

restorePopen()

-- ---------------------------------------------------------------- pclose
-- Every pipe HostShell hands out must be closed through pclose: a bare
-- pipe:close() from one thread can free a FILE while another thread's popen
-- is walking libc's stream list, and that thread never wakes up again (the
-- launcher freezing on close after a visit to the mod tabs).  Nothing here can
-- exercise the race headlessly -- the test stub has no love.thread -- so this
-- pins the entry point's existence and its tolerance of junk.
check(type(HostShell.pclose) == "function", "HostShell exposes pclose")
local closed = false
HostShell.pclose({ close = function() closed = true return true end })
check(closed, "pclose closes the pipe it is given")
local okNil = pcall(HostShell.pclose, nil)
check(okNil, "pclose on nil is a no-op rather than an error")

T.finish("host shell fetch errors")
