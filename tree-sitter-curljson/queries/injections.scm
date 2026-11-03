((stdout_body) @injection.content
  (#match? @injection.content "^[ \t\r\n]*(\\{|\\[|\"|-?[0-9]|true[ \t\r\n]*$|false[ \t\r\n]*$|null[ \t\r\n]*$)")
  (#set! injection.language "json"))
