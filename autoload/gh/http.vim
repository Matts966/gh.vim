" github
" Author: skanehira
" License: MIT
" reference https://github.com/vim-jp/vital.vim/blob/master/autoload/vital/__vital__/Web/HTTP.vim

" from Vital.Async.Promise-example-job help
let s:Promise = vital#vital#import('Async.Promise')
let s:HTTP = vital#vital#import('Web.HTTP')

function! s:_readfile(file) abort
  if filereadable(a:file)
    return join(readfile(a:file, 'b'), "\n")
  endif
  return ''
endfunction

function! s:parseHeader(headers) abort
  let header = {}
  for h in a:headers
    let matched = matchlist(h, '^\([^:]\+\):\s*\(.*\)$')
    if !empty(matched)
      let [name, value] = matched[1 : 2]
      let header[name] = value
    endif
  endfor
  return header
endfunction

function! s:_tempname() abort
  return tr(tempname(), '\', '/')
endfunction

function! s:read(chan, part) abort
  let out = []
  while ch_status(a:chan, {'part' : a:part}) =~# 'open\|buffered'
    call add(out, ch_read(a:chan, {'part' : a:part}))
  endwhile
  return join(out, "\r")
endfunction

function! s:sh(...) abort
  let cmd = join(a:000, ' ')

  return s:Promise.new({resolve, reject -> job_start(cmd, {
        \   'drop' : 'never',
        \   'close_cb' : {ch -> 'do nothing'},
        \   'exit_cb' : {ch, code ->
        \     code ? reject(s:read(ch, 'err')) : resolve(s:read(ch, 'out'))
        \   },
        \ })})
endfunction

function! s:make_response(body) abort
  let headerstr = s:_readfile(s:tmp_file.header)
  call delete(s:tmp_file.header)
  if has_key(s:tmp_file, 'body')
    call delete(s:tmp_file.body)
  endif

  let header_chunks = split(headerstr, "\r\n\r\n")
  let headers = map(header_chunks, 'split(v:val, "\r\n")')[0]
  let status = split(headers[0], " ")[1]
  let header = s:parseHeader(headers[1:])

  let body = a:body
  if header["Content-Type"] is# 'application/json; charset=utf-8'
    let body = json_decode(a:body)
    if status isnot# '200' && has_key(body, 'message')
        let body = body.message
    endif
  endif

  let resp = #{
        \ status: status,
        \ header: header,
        \ body: body,
        \ }

  return status is# '200' ? s:Promise.resolve(resp) : s:Promise.reject(resp)
endfunction

function! gh#http#get(url) abort
  let settings = #{
        \ url: a:url,
        \ }
  return gh#http#request(settings)
endfunction

function! gh#http#request(settings) abort
  let token = get(g:, 'gh_token', '')
  if empty(token)
    return s:Promise.reject('[qh.vim] g:gh_token is undefined')
  endif

  let method = has_key(a:settings, 'method') ? a:settings.method : 'GET'

  let s:tmp_file = #{
        \ header: s:_tempname(),
        \ }

  if method is# 'POST'
    let tmp = s:_tempname() 
    call writefile([json_encode(a:settings.data)], tmp)
    let s:tmp_file['body'] = tmp
  endif

  let cmd = ['curl', '-X', method, printf('--dump-header "%s"', s:tmp_file.header),
        \ '-H', printf('"Authorization: token %s"', token)]

  if has_key(a:settings, 'headers')
    for k in keys(a:settings.headers)
      let cmd += ['-H', printf('"%s: %s"', k, a:settings.headers[k])]
    endfor
  endif

  let cmd += [a:settings.url]

  if method is# 'POST'
    let cmd += ['-H', '"Content-Type: application/json"', '-d', '@' . s:tmp_file.body]
  endif

  return call('s:sh', cmd)
        \.then(function('s:make_response'))
endfunction
