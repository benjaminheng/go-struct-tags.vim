" don't spam the user when Vim is started in Vi compatibility mode
let s:cpo_save = &cpo
set cpo&vim

" Configuration options with defaults
if !exists('g:go_struct_tags_transform')
  let g:go_struct_tags_transform = 'camelcase'
endif

if !exists('g:go_struct_tags_skip_unexported')
  let g:go_struct_tags_skip_unexported = 0
endif

command! -nargs=* -range=% -complete=customlist,<SID>TagsComplete GoAddTags
      \ call go_struct_tags#Add(<line1>, <line2>, <count>, <f-args>)

command! -nargs=* -range=% -complete=customlist,<SID>TagsComplete GoRemoveTags
      \ call go_struct_tags#Remove(<line1>, <line2>, <count>, <f-args>)

function! s:TagsComplete(lead, cmdline, cursor) abort
  let tags = ['json', 'yaml', 'xml', 'toml', 'bson', 'mapstructure', 'protobuf', 'db', 'url', 'validate']
  
  if empty(a:lead)
    return tags
  endif
  
  return filter(copy(tags), 'v:val =~ "^' . a:lead . '"')
endfunction

" restore Vi compatibility settings
let &cpo = s:cpo_save
unlet s:cpo_save

" vim: sw=2 ts=2 et
