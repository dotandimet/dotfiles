autocmd BufLeave,FocusLost * silent! wall
set guifont=Menlo\ Regular:h15 
set tabstop=2
set shiftwidth=2
set expandtab
colorscheme zenburn
syntax enable
autocmd BufRead *\.txt setlocal spell spelllang=en_us
autocmd BufRead *\.md setlocal spell spelllang=en_us syntax=markdown
set listchars=tab:▷⋅,trail:·
set list
set dir=~/tmp
set textwidth=120
set ruler

" Install vim-plug if it's missing:
let data_dir = has('nvim') ? stdpath('data') . '/site' : '~/.vim'
if empty(glob(data_dir . '/autoload/plug.vim'))
  silent execute '!curl -fLo '.data_dir.'/autoload/plug.vim --create-dirs  https://raw.githubusercontent.com/junegunn/vim-plug/master/plug.vim'
  autocmd VimEnter * PlugInstall --sync | source $MYVIMRC
endif

" Plugins!
call plug#begin(stdpath('data') .'/plugged')

Plug 'neoclide/coc.nvim', {'branch': 'release' }
Plug 'neoclide/coc-tsserver', {'branch': 'yarn install --frozen-lockfile'}
Plug 'posva/vim-vue'
Plug 'pangloss/vim-javascript'    " JavaScript support
Plug 'leafgarland/typescript-vim' " TypeScript syntax
Plug 'doums/darcula'

" Initialize plugin system
call plug#end()

function! PlugLoaded(name)
    return (
        \ has_key(g:plugs, a:name) &&
        \ isdirectory(g:plugs[a:name].dir) &&
        \ stridx(&runtimepath, trim(g:plugs[a:name].dir, "/")) >= 0)
endfunction

if PlugLoaded("coc.nvim")
    source ~/.config/nvim/coc.vim
endif

if PlugLoaded('darcula')
    colorscheme darcula
endif

