local T = MiniTest.new_set()
local parse = require("curl.request").parse
local eq = MiniTest.expect.equality

T["collects positional URLs including bare hosts and paths in order"] = function()
  eq(parse({ "https://first.test", "example.test/path", "localhost:8080/a", "relative/path", "/path" }), {
    urls = { "https://first.test", "example.test/path", "localhost:8080/a", "relative/path", "/path" },
    headers = {},
  })
end

T["collects repeated positional and explicit URLs and headers in order"] = function()
  eq(parse({
    "-H", "X-First: one", "https://first.test", "--url", "https://second.test",
    "--header", "X-Second: two", "--url=https://third.test", "-HX-Third: three",
    "--header=X-Fourth: four", "https://first.test", "-H", "X-First: one",
  }), {
    urls = { "https://first.test", "https://second.test", "https://third.test", "https://first.test" },
    headers = { "X-First: one", "X-Second: two", "X-Third: three", "X-Fourth: four", "X-First: one" },
  })
end

T["parses attached and separate values after bundled short flags"] = function()
  eq(parse({ "-sSHX-One: a b", "-ksSH", "X-Two: c d", "-sSXPOST", "-sSd", "https://data.test", "host/path" }), {
    urls = { "host/path" },
    headers = { "X-One: a b", "X-Two: c d" },
  })
end

T["skips attached and separate request methods and bodies"] = function()
  eq(parse({ "-XPOST", "-X", "POST", "-d", "foo", "-dhttps://body.test", "--data-raw", "https://not-a-url", "host" }), {
    urls = { "host" },
    headers = {},
  })
end

T["skips URL-looking values for long options in separate and equals forms"] = function()
  local names = {
    "data", "data-ascii", "data-binary", "data-raw", "data-urlencode", "json", "url-query",
    "proxy", "preproxy", "proxy1.0", "proxy-user", "proxy-header", "proxy-cacert", "proxy-key",
    "socks4", "socks4a", "socks5", "socks5-hostname", "noproxy", "referer", "doh-url", "ipfs-gateway",
    "request", "request-target", "resolve", "connect-to", "interface", "unix-socket", "abstract-unix-socket",
    "user", "user-agent", "cookie", "cookie-jar", "output", "output-dir", "upload-file", "form", "form-string",
    "config", "netrc-file", "cert", "cacert", "key", "dump-header", "write-out", "trace", "trace-ascii",
    "max-time", "connect-timeout", "retry", "retry-delay", "limit-rate", "variable", "mail-from", "mail-rcpt",
  }
  for _, name in ipairs(names) do
    eq(parse({ "--" .. name, "https://value.test", "host/path" }), { urls = { "host/path" }, headers = {} })
    eq(parse({ "--" .. name .. "=https://value.test", "host/path" }), { urls = { "host/path" }, headers = {} })
  end
end

T["skips attached and separate values for curl short options"] = function()
  for flag in ("EKCbcdDFPhmoxUQreXYytzTuAw"):gmatch(".") do
    eq(parse({ "-" .. flag, "https://value.test", "host" }), { urls = { "host" }, headers = {} })
    eq(parse({ "-sS" .. flag .. "https://value.test", "host" }), { urls = { "host" }, headers = {} })
  end
end

T["does not consume positional URLs after boolean flags"] = function()
  eq(parse({ "-sSILk", "--location", "--compressed", "--no-silent", "host/path" }), {
    urls = { "host/path" }, headers = {},
  })
end

T["treats everything after double dash as positional"] = function()
  eq(parse({ "-H", "Before: yes", "--", "--url", "-Hafter", "--next", "-", "host/path" }), {
    urls = { "--url", "-Hafter", "--next", "-", "host/path" }, headers = { "Before: yes" },
  })
end

T["consumes option-like values without treating them as flags"] = function()
  eq(parse({ "--header", "--", "-d", "--url", "-H", "-X", "--url", "-host", "actual-host" }), {
    urls = { "-host", "actual-host" }, headers = { "--", "-X" },
  })
end

T["flattens headers and URLs across long and short next options"] = function()
  eq(parse({ "-HFirst: a", "first", "--next", "--url=second", "--header=Second: b", "-:", "third" }), {
    urls = { "first", "second", "third" }, headers = { "First: a", "Second: b" },
  })
end

T["keeps header file references and shell syntax literal"] = function()
  local marker = vim.fn.tempname()
  local header_file = vim.fn.tempname()
  vim.fn.writefile({ "From-File: must not be loaded" }, header_file)
  local literal_url = "$(touch " .. marker .. ")/$HOST/{one,two}/*"
  local argv = { "-H@" .. header_file, "--header=@missing-headers", "-H", "X: $TOKEN `id`", literal_url, "~/$URL" }
  local before = vim.deepcopy(argv)
  local result = parse(argv)
  vim.fn.delete(header_file)
  eq(result, {
    urls = { literal_url, "~/$URL" },
    headers = { "@" .. header_file, "@missing-headers", "X: $TOKEN `id`" },
  })
  eq(vim.fn.filereadable(marker), 0)
  eq(argv, before)
end

T["keeps empty values and embedded equals signs"] = function()
  eq(parse({ "--header=", "--header=X: a=b", "--url=", "--url=https://host/?a=b", "-H", "" }), {
    urls = { "", "https://host/?a=b" }, headers = { "", "X: a=b", "" },
  })
end

T["tolerates empty argv unknown flags and missing values"] = function()
  eq(parse({}), { urls = {}, headers = {} })
  eq(parse({ "--future-flag", "-?", "--future-value=https://ignored", "host" }), { urls = { "host" }, headers = {} })
  for _, option in ipairs({ "-H", "--header", "--url", "-X", "--proxy", "-sSH" }) do
    eq(parse({ "host", option }), { urls = { "host" }, headers = {} })
  end
end

return T
