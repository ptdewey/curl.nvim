module.exports = grammar({
  name: 'curljson',

  extras: $ => [],

  rules: {
    document: $ => seq(
      $.request,
      $.directory,
      $.status,
      $.elapsed,
      $._newline,
      $.stdout,
      optional($.stderr),
    ),

    request: $ => seq('Request:', ' ', field('title', $.request_title), $._newline),
    request_title: $ => /[^\r\n]+/,

    directory: $ => seq('Directory:', ' ', field('path', $.directory_path), $._newline),
    directory_path: $ => /[^\r\n]+/,

    status: $ => seq('Status:', ' ', field('value', choice($.exit_code, $.cancelled)), $._newline),
    exit_code: $ => /-?[0-9]+/,
    cancelled: $ => 'cancelled',

    elapsed: $ => seq('Elapsed:', ' ', field('duration', $.duration), $._newline),
    duration: $ => seq(/[0-9]+\.[0-9]+/, 's'),

    stdout: $ => seq($.stdout_header, optional(field('body', $.stdout_body))),
    stdout_header: $ => seq('stdout:', $._newline),
    stdout_body: $ => repeat1(choice($._line_text, $._newline)),

    stderr: $ => seq($.stderr_header, optional(field('body', $.stderr_body))),
    stderr_header: $ => token(prec(1, /stderr:\r?\n/)),
    stderr_body: $ => repeat1(choice($._line_text, $._newline)),

    _line_text: $ => /[^\n]+/,
    _newline: $ => /\r?\n/,
  },
});
