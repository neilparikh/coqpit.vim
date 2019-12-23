" =============
" Coq Langugage
" =============

" - patterns

let s:COMMENT_START_regex = '(\*'
let s:COMMENT_END_regex = '\*)'
let s:STRING_DELIM_regex = '"'
let s:DOT_regex = '\.\%($\| \|\n\|\t\)\@='
let s:GOAL_SELECTOR_START = '\[\|\d\|{'
let s:BRACE_START_regex = '{'


" library for Coq as a language

" type Pos = [line, pos] : [int]
" type Range = [start, end] : [Pos]
"   NOTE: (left inclusive, right exclusive)
" type null has only v:null

" Pos | null means v:null is `never closed`



" - functions

function! coqlang#is_blank(char)
  return a:char == ' ' || a:char == "\n" || a:char == "\t"
endfunction


" Return range corresponding to one sentense.
" Assumeing sentense starts just `from_pos`.
"
"
" content : [string]
" from_pos : Pos
"
" return Range | null
" next_sentence_range(content, from_pos) {{{
function! coqlang#next_sentence_range(content, from_pos) abort
  let [line, col] = a:from_pos
  let end_pos = next_sentence(a:content, a:from_pos)
  if end_pos is v:null
    return v:null
  endif

  return [a:from_pos, end_pos]
endfunction
" }}}



" TODO
" content : [string]
" from_pos : Pos | null
"
" return Pos | null
" skip_blanks(content, from_pos) {{{
function! coqlang#skip_blanks(content, from_pos) abort
  if a:from_pos is v:null
    return v:null
  endif

  let [line, col] = a:from_pos
  let linenum = len(a:content)


  " reference : https://coq.inria.fr/refman/language/gallina-specification-language.html
  let blanks = ["\t", "\n", ' ']

  while line < linenum
    if col < len(a:content[line])
      if count(blanks, a:content[line][col])
        let col += 1
      else
        break
      endif
    else
      let line += 1
      let col = 0
    endif
  endwhile

  if line >= linenum
    return v:null
  endif

  return [line, col]
endfunction  " }}}



" Find next sentence after from_pos inclusive.
" Sentense is finishing with dot, one of braces, or one of dots.
" Assuming sentense can start `from_pos`.
" Returns the position right after sentence,
" namely exclusive in that line.
"
"
" content : [string]
" from_pos : Pos | null
"
" return Pos | null
" next_sentence(content, from_pos) {{{
function! coqlang#next_sentence(content, from_pos) abort
  let nonblank_pos = coqlang#skip_blanks(a:content, a:from_pos)
  if nonblank_pos is v:null
    return v:null
  endif

  let [line, col] = nonblank_pos

  " reference : https://coq.inria.fr/refman/proof-engine/proof-handling.html
  let bullets = ['-', '+', '*']

  " -- check whether encountering bullets or braces
  "  simply, we assume these as sentence even if outside proof mode
  "  it works well

  " brace start
  if match(a:content[line][col], s:BEFORE_BRACE_START_regex) == 0
    return coqlang#next_brace_start(a:content, [line, col])
  endif
  " brace end
  if a:content[line][col] == '}'
    return [line, col + 1]
  endif
  " bullets
  if count(bullets, a:content[line][col])
    let bullet = a:content[line][col]
    while bullet == a:content[line][col + 1]
      let col += 1
    endwhile
    return [line, col + 1]
  endif

  " -- skip commentary when encountered it
  "  before finding the sentence beginning
  let tail_len = len(a:content[line]) - col

  if a:content[line][col:col+1] == '(*'
    let com_end = coqlang#skip_comment(a:content, [line, col + 2])

    if com_end is v:null
      return v:null
    endif

    return next_sentence(a:content, com_end)
  endif

  return coqlang#next_pattern(a:content, [line, col], s:DOT_regex)
endfunction  " }}}


" Find next position whose nested level is zero. (exclusive)
" Return v:null if never close.
"
"
" content : [string]
" from_pos : Pos | null
" nested = 1 : int
"
" return Pos | null
" skip_comment(content, from_pos, nested) {{{
function! coqlang#skip_comment(content, from_pos, nested = 1) abort
  if a:nested == 0
    return a:from_pos
  endif

  let nonblank_pos = coqlang#skip_blanks(a:content, a:from_pos)
  if nonblank_pos is v:null
    return v:null
  endif

  let [line, col] = nonblank_pos

  let trail = a:content[line][col:]

  let next = sort([
    \   [match(trail, s:COMMENT_START_regex), 0],
    \   [match(trail, s:COMMENT_END_regex), 1],
    \   [match(trail, s:STRING_DELIM_regex), 2]
    \ ], function('s:pos_cmp'))

    for token in next
    if token[0] != -1
      let col += token[0]
      if token[1] == 0
        " comment start (*
        return coqlang#skip_comment(a:content, [line, col + 2], a:nested + 1)
      elseif token[1] == 1
        " comment end *)
        return coqlang#skip_comment(a:content, [line, col + 2], a:nested - 1)
      elseif token[1] == 2
        " string start "
        let pos = coqlang#skip_stirng(a:content, [line, col + 1])
        return coqlang#skip_comment(a:content, pos, a:nested)
      endif
    endif
  endfor
  return coqlang#skip_comment(a:content, [line + 1, 0], a:nested)
endfunction  " }}}


" Find next position where string ends. (exclusive)
" Return v:null if never close.
"
"
" content : [string]
" from_pos : Pos | null
"
" return Pos | null
" skip_stirng(content, from_pos) {{{
function! coqlang#skip_stirng(content, from_pos) abort
  let nonblank_pos = coqlang#skip_blanks(a:content, a:from_pos)
  if nonblank_pos is v:null
    return v:null
  endif

  let [line, col] = nonblank_pos

  let trail = a:content[line][col:]

  let str_end = match(trail, s:STRING_DELIM_regex)

  if str_end != -1
    let col += str_end
    if len(trail) > str_end + 1 && trail[str_end + 1] == '"'
      return coqlang#skip_stirng(a:content, [line, col + 2])
    else
      return [line, col + 1]
    endif
  endif

  return coqlang#skip_stirng(a:content, [line + 1, 0])
endfunction  " }}}



" Find next end pos of pattern appearing
"   with skipping comments and strings.
"
" content : [string]
" from_pos : Pos | null
" pattern : stirng
"
" return Pos | null
" next_pattern(content, from_pos, pattern) {{{
function! coqlang#next_pattern(content, from_pos, pattern) abort
  let nonblank_pos = coqlang#skip_blanks(a:content, a:from_pos)
  if nonblank_pos is v:null
    return v:null
  endif

  let [line, col] = nonblank_pos

  let trail = a:content[line][col:]

  let next = sort([
    \   [match(trail, s:COMMENT_START_regex), 0],
    \   [match(trail, s:STRING_DELIM_regex), 1],
    \   [match(trail, a:pattern), 2]
    \ ], function('s:pos_cmp'))

  for token in next
    if token[0] != -1
      let col += token[0]
      if token[1] == 0
        " comment start (*
        let com_end = coqlang#skip_comment(a:content, [line, col + 2], a:pattern)
        return coqlang#next_pattern(a:content, com_end)
      elseif token[1] == 1
        " string start "
        let str_end = coqlang#skip_stirng(a:content, [line, col + 1], a:pattern)
        return coqlang#next_pattern(a:content, str_end)
      elseif token[1] == 2
        " pattern
        return [line, col + 1]
      endif
    endif
  endfor
  return coqlang#next_pattern(a:content, [line + 1, 0], a:pattern)
endfunction  " }}}


" internal


function! s:pos_cmp(pos1, pos2) abort
  return a:pos1[0] != a:pos2[0] ? a:pos1[0] - a:pos2[0] : a:pos1[1] - a:pos2[1]
endfunction




" Test {{{
function! coqlang#Test()
  PAssert coqlang#skip_comment(["hi (**) ."], [0, 0], 0) == [0, 0]
  PAssert coqlang#skip_comment([" (* *) hello"], [0, 0], 0) == [0, 0]
  PAssert coqlang#skip_comment([" (* *) hello"], [0, 3]) == [0, 6]
  PAssert coqlang#skip_comment([" (* ", "(*", "*)*)--"], [0, 3]) == [2, 4]
  PAssert coqlang#skip_comment([' (* " "" *) "" " *) hello'], [0, 3]) == [0, 19]
  PAssert coqlang#skip_comment(['(**', ')'], [0, 2]) is v:null
  PAssert coqlang#skip_comment(['(**', '(*', '*)'], [0, 2]) is v:null

  PAssert coqlang#skip_stirng(['" "yo.'], [0, 1]) == [0, 3]
  PAssert coqlang#skip_stirng([' " ""', ' "" " hi'], [0, 2]) == [1, 5]
  PAssert coqlang#skip_stirng(['""'], [0, 1]) == [0, 2]
  PAssert coqlang#skip_stirng(['"'], [0, 1]) is v:null
  PAssert coqlang#skip_stirng(['"', '"'], [0, 1]) == [1, 1]
  PAssert coqlang#skip_stirng(['"""', '""'], [0, 1]) is v:null

  PAssert coqlang#next_pattern(["Hi."], [0, 0], s:DOT_regex) == [0, 3]
  PAssert coqlang#next_pattern(["Hi (* yay *, s:DOT_regex)", ' " *) hi" .'], [0, 4]) == [1, 11]
  PAssert coqlang#next_pattern(["ya.", "", "hi. x", "wo."], [0, 3], s:DOT_regex) == [2, 3]
  PAssert coqlang#next_pattern(['', "Compute 1."], [0, 0], s:DOT_regex) == [1, 10]
  PAssert coqlang#next_pattern(['A.', '', '', 'CC xx. DD. (* *)', '', 'E.'], [0, 2], s:DOT_regex) == [3, 6]

  PAssert coqlang#next_brace_start(['{'], [0, 0]) == [0, 1]
  PAssert coqlang#next_brace_start(['{(**)'], [0, 0]) == [0, 1]
  PAssert coqlang#next_brace_start(['0 : {'], [0, 0]) == [0, 5]
  PAssert coqlang#next_brace_start(['13:(**){'], [0, 0]) == [0, 8]
  PAssert coqlang#next_brace_start(['[(**)foo  ]: (*}*){'], [0, 0]) == [0, 19]
  PAssert coqlang#next_brace_start(['[ f_o_o(*', ' {{*) ] (* *) :{(* *)'], [0, 0]) == [1, 16]
  PAssert coqlang#next_brace_start(["[ ふー'", ' (*}]*)] (* *) :{(* *)'], [0, 0]) == [1, 17]

  PAssert next_sentence(["hi."], [0, 0]) == [0, 3]
  PAssert next_sentence(["ya.", "", "hi. x", "wo."], [0, 3]) == [2, 3]
  PAssert next_sentence(["hi.hey."], [0, 0]) == [0, 7]
  PAssert next_sentence(["hi.\they."], [0, 0]) == [0, 3]
  PAssert next_sentence(["hi.","hey."], [0, 0]) == [0, 3]
  PAssert next_sentence(["hi.(**)hey."], [0, 0]) == [0, 11]
  PAssert next_sentence([" hello."], [0, 0]) == [0, 7]
  PAssert next_sentence(["(* oh... *)","--."], [0, 0]) == [1, 2]
  PAssert next_sentence(["Axiom A.", "Variable B:Prob."], [0, 0]) == [0, 8]
  PAssert next_sentence(["", "Axiom A.", "Variable B:Prob."], [0, 0]) == [1, 8]
  PAssert next_sentence(["ya.", "", "Axiom A.", "Variable B:Prob."], [0, 3]) == [2, 8]
  PAssert next_sentence(["-", "Axiom A.", "Variable B:Prob."], [0, 0]) == [0, 1]
  PAssert next_sentence(["-", "Axiom A.", "Variable B:Prob."], [1, 0]) == [1, 8]
  PAssert next_sentence(["ya.", "", "Axiom A.", "Variable B:Prob."], [0, 3]) == [2, 8]
  PAssert next_sentence(['', "Compute 1."], [0, 0]) == [1, 10]
  PAssert next_sentence(['(*  *)', "Compute 1."], [0, 0]) == [1, 10]
  PAssert next_sentence(['(* "*)" *)', "Compute 1."], [0, 0]) == [1, 10]
  PAssert next_sentence(['(**){(**)'], [0, 0]) == [0, 5]
  PAssert next_sentence(['(**)}(**)'], [0, 0]) == [0, 5]
  PAssert next_sentence(['{simpl.'], [0, 0]) == [0, 1]
  PAssert next_sentence(['{-'], [0, 0]) == [0, 1]
  PAssert next_sentence(['-{'], [0, 0]) == [0, 1]
  PAssert next_sentence(['}simpl.'], [0, 0]) == [0, 1]
  PAssert next_sentence(['}-'], [0, 0]) == [0, 1]
  PAssert next_sentence(['-}'], [0, 0]) == [0, 1]
  PAssert next_sentence(['--}'], [0, 0]) == [0, 2]
  PAssert next_sentence(['(**)[a]:{simpl.'], [0, 0]) == [0, 9]
  " Hiragana is basically represented by 3 bytes in utf-8
  PAssert next_sentence(['(**)[fooわおbar]:{simpl.'], [0, 0]) == [0, 20]
  PAssert next_sentence(["(**)[__123__''(*'", '*)', ']:{(**)bar.'], [0, 0]) == [2, 3]

  PAssert next_sentence(['A.', '', 'C. D. (* *)', 'E.'], [0, 2]) == [2, 2]
  PAssert next_sentence(['A.', '', '', 'C. D. (* *)', 'E.'], [0, 2]) == [3, 2]
  PAssert next_sentence(['A.', '', '', 'C x. D. (* *)', 'E.'], [0, 2]) == [3, 4]
  PAssert next_sentence(['A.', '', '', 'C. D. (* *)', '', 'E.'], [0, 2]) == [3, 2]
  PAssert next_sentence(['A.', '', '', 'C x. D. (* *)', '', 'E.'], [0, 2]) == [3, 4]
  PAssert next_sentence(['A.', '', '', 'CC . DD. (* *)', '', 'E.'], [0, 2]) == [3, 4]
  PAssert next_sentence(['A.', '', '', 'CC x. (* *)', '', 'E.'], [0, 2]) == [3, 5]
  PAssert next_sentence(['A.', '', '', 'CC x. D. (* *)', '', 'E.'], [0, 2]) == [3, 5]
  PAssert next_sentence(['A.', '', '', 'CC x. DD. (* *)', '', 'E.'], [0, 2]) == [3, 5]
  PAssert next_sentence(['A.', '', '', 'CC xx. DD. (* *)', '', 'E.'], [0, 2]) == [3, 6]
  PAssert next_sentence(['A.', '', '', 'Goal True. Admitted. (* *)', '', 'E.'], [0, 2]) == [3, 10]

  PAssert next_sentence(['[nyan] : foo.', '{'], [0, 0]) == [0, 13]
  PAssert next_sentence(['[nyan] : {foo. }'], [0, 0]) == [0, 10]
  PAssert next_sentence(['[nyan] : { }'], [0, 0]) == [0, 10]

  for el in [
      \ '[mofu]:', '[(**)mofu]:', '[mofu (* *) ]:', 
      \ '1:', '1 : ', '123(**):(**)'
      \ '']
    PAssert next_sentence([el .. '{ admit. }'], [0, 0]) == [0, 10 + strlen(el)]
    PAssert next_sentence([el .. 'admit. {  }'], [0, 0]) == [0, 16 + strlen(el)]
    PAssert next_sentence([el .. 'refine (f _).'], [0, 0]) == [0, 23 + strlen(el)]
    PAssert next_sentence([el .. 'refine ({ _ ).'], [0, 0]) == [0, 25 + strlen(el)]
    PAssert next_sentence([el .. 'refine (:{ _ ).'], [0, 0]) == [0, 26 + strlen(el)]
    PAssert next_sentence([el .. 'refine (1:{ _ ).'], [0, 0]) == [0, 27 + strlen(el)]
    PAssert next_sentence([el .. 'refine (a:{ _ ).'], [0, 0]) == [0, 27 + strlen(el)]
    PAssert next_sentence([el .. 'refine ([a:{ _ ).'], [0, 0]) == [0, 28 + strlen(el)]
    PAssert next_sentence([el .. 'refine (a]:{ _ ).'], [0, 0]) == [0, 28 + strlen(el)]
    PAssert next_sentence([el .. 'refine ([a]:{ _ ).'], [0, 0]) == [0, 29 + strlen(el)]
  endfor
endfunction
}}}
