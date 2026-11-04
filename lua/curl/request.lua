local M = {}

local long_value_options = {}
for name in ([=[
  abstract-unix-socket alt-svc aws-sigv4 cacert capath cert cert-type ciphers config
  connect-timeout connect-to continue-at cookie cookie-jar create-file-mode crlfile curves
  data data-ascii data-binary data-raw data-urlencode delegation dns-interface dns-ipv4-addr
  dns-ipv6-addr dns-servers doh-url dump-header egd-file engine etag-compare etag-save
  expect100-timeout form form-string ftp-account ftp-alternative-to-user ftp-method ftp-port
  ftp-ssl-ccc-mode happy-eyeballs-timeout-ms haproxy-clientip header help hostpubmd5 hostpubsha256
  hsts interface ipfs-gateway json keepalive-time key key-type krb libcurl limit-rate local-port
  login-options mail-auth mail-from mail-rcpt max-filesize max-redirs max-time netrc-file noproxy
  oauth2-bearer output output-dir parallel-max pass pinnedpubkey preproxy proto proto-default
  proto-redir proxy proxy-cacert proxy-capath proxy-cert proxy-cert-type proxy-ciphers proxy-crlfile
  proxy-header proxy-key proxy-key-type proxy-pass proxy-pinnedpubkey proxy-service-name
  proxy-tls13-ciphers proxy-tlsauthtype proxy-tlspassword proxy-tlsuser proxy-user proxy1.0 pubkey
  quote random-file range rate referer request request-target resolve retry retry-delay retry-max-time
  sasl-authzid service-name socks4 socks4a socks5 socks5-gssapi-service socks5-hostname speed-limit
  speed-time stderr telnet-option tftp-blksize time-cond tls-max tls13-ciphers tlsauthtype tlspassword
  tlsuser trace trace-ascii trace-config unix-socket upload-file url url-query user user-agent
  variable write-out
]=]):gmatch("%S+") do
  long_value_options[name] = true
end

local short_value_options = {}
for flag in ("EKCbcdDFPHhmoxUQreXYytzTuAw"):gmatch(".") do
  short_value_options[flag] = true
end

function M.parse(argv)
  local result = { urls = {}, headers = {} }
  local positional = false
  local i = 1

  local function capture(name, value)
    local field = name == "url" and "urls" or (name == "header" and "headers")
    if field and value ~= nil then
      table.insert(result[field], value)
    end
  end

  while i <= #argv do
    local arg = argv[i]
    if positional then
      table.insert(result.urls, arg)
    elseif arg == "--" then
      positional = true
    elseif arg:sub(1, 2) == "--" then
      local name, value = arg:match("^%-%-([^=]+)=(.*)$")
      if not name then
        name = arg:sub(3)
        if long_value_options[name] then
          i = i + 1
          value = argv[i]
        end
      end
      capture(name, value)
    elseif arg:sub(1, 1) == "-" and arg ~= "-" then
      for j = 2, #arg do
        local flag = arg:sub(j, j)
        if short_value_options[flag] then
          local value = arg:sub(j + 1)
          if value == "" then
            i = i + 1
            value = argv[i]
          end
          if flag == "H" then
            capture("header", value)
          end
          break
        end
      end
    else
      table.insert(result.urls, arg)
    end
    i = i + 1
  end

  return result
end

return M
