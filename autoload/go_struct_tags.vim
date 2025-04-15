" don't spam the user when Vim is started in Vi compatibility mode
let s:cpo_save = &cpo
set cpo&vim

" Get cursor offset in bytes for the current position
function! s:OffsetCursor() abort
  let l:col = col('.')
  let l:line = line('.')
  let l:offset = 0

  for l:lineNr in range(1, l:line-1)
    let l:offset += len(getline(l:lineNr)) + 1
  endfor

  let l:offset += l:col - 1
  return l:offset
endfunction

" Execute a command and return its output
function! s:Exec(cmd, ...) abort
  if len(a:000) > 0
    let l:input = a:1
    return system(join(a:cmd, ' '), l:input)
  endif
  
  return system(join(a:cmd, ' '))
endfunction

" Echo an error message
function! s:EchoError(msg) abort
  echohl ErrorMsg
  echom "go-struct-tags: " . a:msg
  echohl None
endfunction

" Get all lines from the current buffer
function! s:GetLines() abort
  return getline(1, '$')
endfunction

" Check if a binary exists in PATH
function! s:CheckBinPath(bin) abort
  if executable(a:bin)
    return a:bin
  endif
  
  call s:EchoError(a:bin . " not found in PATH. Please install it.")
  return ""
endfunction

" mapped to :GoAddTags
function! go_struct_tags#Add(start, end, count, ...) abort
  let fname = fnamemodify(expand("%"), ':p:gs?\\?/?')
  let offset = 0
  if a:count == -1
    let offset = s:OffsetCursor()
  endif

  let test_mode = 0
  call call("go_struct_tags#run", [a:start, a:end, offset, "add", fname, test_mode] + a:000)
endfunction

" mapped to :GoRemoveTags
function! go_struct_tags#Remove(start, end, count, ...) abort
  let fname = fnamemodify(expand("%"), ':p:gs?\\?/?')
  let offset = 0
  if a:count == -1
    let offset = s:OffsetCursor()
  endif

  let test_mode = 0
  call call("go_struct_tags#run", [a:start, a:end, offset, "remove", fname, test_mode] + a:000)
endfunction

" run runs gomodifytag
function! go_struct_tags#run(start, end, offset, mode, fname, test_mode, ...) abort
  " do not split this into multiple lines, somehow tests fail in that case
  let args = {'mode': a:mode,'start': a:start,'end': a:end,'offset': a:offset,'fname': a:fname,'cmd_args': a:000}

  if &modified
    let args["modified"] = 1
  endif

  let l:result = s:create_cmd(args)
  if has_key(result, 'err')
    call s:EchoError(result.err)
    return -1
  endif

  if &modified
    let filename = expand("%:p:gs!\\!/!")
    let content  = join(s:GetLines(), "\n")
    let in = filename . "\n" . strlen(content) . "\n" . content
    let l:out = s:Exec(l:result.cmd, in)
  else
    let l:out = s:Exec(l:result.cmd)
  endif

  " Check for errors in output
  if v:shell_error != 0
    call s:EchoError(l:out)
    return
  endif

  if a:test_mode
    exe 'edit ' . a:fname
  endif

  call s:write_out(l:out)

  if a:test_mode
    exe 'write! ' . a:fname
  endif
endfunc

" write_out writes back the given output to the current buffer
func s:write_out(out) abort
  " not a json output
  if a:out[0] !=# '{'
    return
  endif

  " nothing to do
  if empty(a:out) || type(a:out) != type("")
    return
  endif

  let result = json_decode(a:out)
  if type(result) != type({})
    call s:EchoError(printf("malformed output from gomodifytags: %s", a:out))
    return
  endif

  let lines = result['lines']
  let start_line = result['start']
  let end_line = result['end']

  let index = 0
  for line in range(start_line, end_line)
    call setline(line, lines[index])
    let index += 1
  endfor

  if has_key(result, 'errors')
    let l:errors = result['errors']
    for l:error in l:errors
      call s:EchoError(l:error)
    endfor
  endif
endfunc

" create_cmd returns a dict that contains the command to execute gomodifytags
func s:create_cmd(args) abort
  if !exists("*json_decode")
    return {'err': "requires 'json_decode'. Update your Vim/Neovim version."}
  endif

  let bin_path = s:CheckBinPath('gomodifytags')
  if empty(bin_path)
    return {'err': "gomodifytags does not exist"}
  endif

  let l:start = a:args.start
  let l:end = a:args.end
  let l:offset = a:args.offset
  let l:mode = a:args.mode
  let l:cmd_args = a:args.cmd_args
  
  " Default transform setting (camelcase, snakecase, etc)
  let l:modifytags_transform = get(g:, 'go_struct_tags_transform', 'camelcase')
  
  " Default setting for skipping unexported fields
  let l:modifytags_skip_unexported = get(g:, 'go_struct_tags_skip_unexported', 0)

  " start constructing the command
  let cmd = [bin_path]
  call extend(cmd, ["-format", "json"])
  call extend(cmd, ["-file", a:args.fname])
  call extend(cmd, ["-transform", l:modifytags_transform])

  if l:modifytags_skip_unexported
    call extend(cmd, ["-skip-unexported"])
  endif

  if has_key(a:args, "modified")
    call add(cmd, "-modified")
  endif

  if l:offset != 0
    call extend(cmd, ["-offset", l:offset])
  else
    let range = printf("%d,%d", l:start, l:end)
    call extend(cmd, ["-line", range])
  endif

  if l:mode == "add"
    let l:tags = []
    let l:options = []

    if !empty(l:cmd_args)
      for item in l:cmd_args
        let splitted = split(item, ",")

        " tag only
        if len(splitted) == 1
          call add(l:tags, splitted[0])
        endif

        " options only
        if len(splitted) == 2
          call add(l:tags, splitted[0])
          call add(l:options, printf("%s=%s", splitted[0], splitted[1]))
        endif
      endfor
    endif

    " default value
    if empty(l:tags)
      let l:tags = ["json"]
    endif

    " construct tags
    call extend(cmd, ["-add-tags", join(l:tags, ",")])

      " construct options
    if !empty(l:options)
      call extend(cmd, ["-add-options", join(l:options, ",")])
    endif
  elseif l:mode == "remove"
    if empty(l:cmd_args)
      call add(cmd, "-clear-tags")
    else
      let l:tags = []
      let l:options = []
      for item in l:cmd_args
        let splitted = split(item, ",")

        " tag only
        if len(splitted) == 1
          call add(l:tags, splitted[0])
        endif

        " options only
        if len(splitted) == 2
          call add(l:options, printf("%s=%s", splitted[0], splitted[1]))
        endif
      endfor

      " construct tags
      if !empty(l:tags)
        call extend(cmd, ["-remove-tags", join(l:tags, ",")])
      endif

      " construct options
      if !empty(l:options)
        call extend(cmd, ["-remove-options", join(l:options, ",")])
      endif
    endif
  else
    return {'err': printf("unknown mode: %s", l:mode)}
  endif

  return {'cmd': cmd}
endfunc

" restore Vi compatibility settings
let &cpo = s:cpo_save
unlet s:cpo_save

" vim: sw=2 ts=2 et
