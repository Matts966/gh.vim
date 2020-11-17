" projects
" Author: skanehira
" License: MIT

function! gh#projects#list() abort
  setlocal ft=gh-projects
  let m = matchlist(bufname(), 'gh://\(.*\)/\(.*\)/projects?*\(.*\)')

  let param = gh#http#decode_param(m[3])
  if !has_key(param, 'page')
    let param['page'] = 1
  endif

  if m[1] is# 'orgs'
    let type = 'org'
    let user_info = {'org': m[2]}
  else
    let type = 'user'
    let user_info = {'owner': m[1], 'repo': m[2]}
  endif

  call gh#gh#delete_buffer(s:, 'gh_project_list_bufid')
  let s:gh_project_list_bufid = bufnr()

  let s:project_list = {
        \ 'type': type,
        \ 'user_info': user_info,
        \ 'param': param,
        \ }

  call gh#gh#init_buffer()
  call gh#gh#set_message_buf('loading')

  call gh#github#projects#list(type, user_info, param)
        \.then(function('s:set_project_list_result'))
        \.then({-> execute("call gh#map#apply('gh-buffer-project-list')")})
        \.catch({err -> execute('call gh#gh#error_message(err.body)', '')})
        \.finally(function('gh#gh#global_buf_settings'))
endfunction

function! s:set_project_list_result(resp) abort
  if empty(a:resp.body)
    call gh#gh#set_message_buf('not found projects')
    return
  endif

  let s:projects = []
  let lines = []

  let dict = map(copy(a:resp.body), {_, v -> {
        \ 'number': printf('#%d', v.number),
        \ 'state': v.state,
        \ 'name': v.name,
        \ 'url': v.html_url,
        \ }})
  let format = gh#gh#dict_format(dict, ['number', 'state', 'name'])

  for project in a:resp.body
    call add(lines, printf(format,
          \ printf('#%d', project.number), project.state, project.name))
    call add(s:projects, {
          \ 'number': project.number,
          \ 'state': project.state,
          \ 'name': project.name,
          \ 'url': project.url,
          \ })
  endfor

  call setbufline(s:gh_project_list_bufid, 1, lines)
endfunction
