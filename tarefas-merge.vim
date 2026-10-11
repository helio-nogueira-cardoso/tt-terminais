" Revisão de uma atualização de tarefa recebida por e-mail — o "merge" do tt.
" Uso (o tt chama): vim -u vimrc-tt -S tarefas-merge.vim, com
"   TT_MERGE_PLANO   arquivo gerado por `tarefas-merge.py plano` (TSV; valores com \\ \n \t escapados)
"   TT_MERGE_SAIDA   onde gravar as decisões (id<TAB>escolha<TAB>valor) ao aplicar; nada é gravado ao cancelar
"   TT_MERGE_AUTO    inc | cur: resolve tudo sozinho e sai (testes e atalho sem tela)
" Tudo é clicável (botões [ ... ]) e tem tecla: r recebida · m minha · b as duas · e editar · u desfazer ·
" A aceitar tudo recebido · M manter tudo meu · Tab/Shift-Tab próximo/anterior · Ctrl+S ou ZZ aplicar · Q cancelar.
" Script em vimscript clássico (Vim 8+/Neovim).

if exists('g:tt_merge_carregado') | finish | endif
let g:tt_merge_carregado = 1
set nocompatible
set encoding=utf-8 fileencoding=utf-8 fileencodings=utf-8
set mouse=a
silent! set ttymouse=sgr          " cliques em qualquer coluna (o tmux e o terminal falam SGR); no Neovim já é assim
set nowrap nonumber nocursorline nolist
set laststatus=2 noshowmode noruler shortmess+=I
set nomodeline
set fillchars+=eob:\

let s:plano = $TT_MERGE_PLANO
let s:saida = $TT_MERGE_SAIDA
let s:itens = []
let s:alvo = ''
let s:titulo = ''
let s:de = ''
let s:acoes = {}      " lnum -> lista de [colini, colfim, tipo, indice]   (colunas de tela, 1-based)
let s:bloco = {}      " lnum -> índice do item
let s:inicio = []     " lnum inicial de cada item

function! s:desescapa(t) abort
  let r = '' | let i = 0 | let n = strlen(a:t)
  while i < n
    let c = a:t[i]
    if c ==# '\' && i + 1 < n
      let d = a:t[i + 1]
      let r .= d ==# 'n' ? "\n" : (d ==# 't' ? "\t" : d)
      let i += 2
    else
      let r .= c | let i += 1
    endif
  endwhile
  return r
endfunction

function! s:escapa(t) abort
  return substitute(substitute(substitute(a:t, '\\', '\\\\', 'g'), "\n", '\\n', 'g'), "\t", '\\t', 'g')
endfunction

function! s:ler() abort
  if empty(s:plano) || !filereadable(s:plano)
    echoerr 'TT_MERGE_PLANO ausente' | cquit
  endif
  for ln in readfile(s:plano)
    let p = split(ln, "\t", 1)
    if get(p, 0, '') ==# '#'
      let s:alvo = get(p, 2, '') | let s:titulo = s:desescapa(get(p, 3, '')) | let s:de = s:desescapa(get(p, 4, ''))
      continue
    endif
    if len(p) < 9 | continue | endif
    let it = {'id': p[0], 'grupo': p[1], 'rotulo': s:desescapa(p[2]), 'status': p[3], 'cur': s:desescapa(p[4]),
          \ 'inc': s:desescapa(p[5]), 'base': s:desescapa(p[6]), 'padrao': p[7], 'opcoes': split(p[8], ',', 1),
          \ 'manual': ''}
    let it.escolha = it.status ==# 'conflito' ? '' : it.padrao
    call add(s:itens, it)
  endfor
endfunction

" itens que o usuário revê (entrada e conflito); os 'minha' só contam no resumo
function! s:visiveis() abort
  return filter(range(len(s:itens)), 's:itens[v:val].status !=# "minha"')
endfunction

function! s:resumo() abort
  let ent = 0 | let conf = 0 | let pend = 0 | let min = 0
  for it in s:itens
    if it.status ==# 'entrada' | let ent += 1 | endif
    if it.status ==# 'conflito' | let conf += 1 | if empty(it.escolha) | let pend += 1 | endif | endif
    if it.status ==# 'minha' | let min += 1 | endif
  endfor
  return [ent, conf, pend, min]
endfunction

function! s:larg(t) abort
  return strdisplaywidth(a:t)
endfunction

" acrescenta uma linha; botoes = lista de [texto, tipo, indice, ligado]; devolve o número da linha
function! s:linha(lista, texto, botoes) abort
  let n = len(a:lista) + 1
  let col = s:larg(a:texto) + 1
  let linha = a:texto
  let mapa = []
  for b in a:botoes
    let rot = '[ ' . b[0] . ' ]'
    let linha .= rot . '  '
    call add(mapa, [col, col + s:larg(rot) - 1, b[1], b[2], b[3]])
    let col += s:larg(rot) + 2
  endfor
  call add(a:lista, linha)
  if !empty(mapa) | let s:acoes[n] = mapa | endif
  return n
endfunction

" botões que quebram de linha quando não cabem (celular: 63 colunas); cada linha leva o bloco `bloco` (ou -1)
function! s:botoes(lista, recuo, botoes, bloco) abort
  let atual = [] | let largura = s:larg(a:recuo)
  for b in a:botoes
    let w = s:larg(b[0]) + 6
    if !empty(atual) && largura + w > &columns - 1
      let k = len(a:lista) + 1
      call s:linha(a:lista, a:recuo, atual)
      if a:bloco >= 0 | let s:bloco[k] = a:bloco | endif
      let atual = [] | let largura = s:larg(a:recuo)
    endif
    call add(atual, b) | let largura += w
  endfor
  if !empty(atual)
    let k = len(a:lista) + 1
    call s:linha(a:lista, a:recuo, atual)
    if a:bloco >= 0 | let s:bloco[k] = a:bloco | endif
  endif
endfunction

" linhas de `a` que não existem em `b` (as que diferem), sem as vazias
function! s:so_em(a, b) abort
  let conhecidas = {}
  for l in split(a:b, "\n", 1) | let conhecidas[l] = 1 | endfor
  let r = []
  for l in split(a:a, "\n", 1)
    if substitute(l, '\s', '', 'g') !=# '' && !has_key(conhecidas, l) | call add(r, l) | endif
  endfor
  return r
endfunction

" o que mostrar de um lado: a descrição só mostra as linhas que diferem; o resto, o valor numa linha
function! s:mostrar(it, lado) abort
  let v = a:it[a:lado]
  if a:it.id ==# 'campo:desc'
    let outro = a:it[a:lado ==# 'cur' ? 'inc' : 'cur']
    let extra = s:so_em(v, outro)
    if empty(extra) | return [empty(v) ? '(vazio)' : '(as mesmas linhas, em outra ordem)'] | endif
    let m = max([20, &columns - 28])
    let r = map(extra[:4], '"+ " . (strchars(v:val) > m ? strcharpart(v:val, 0, m - 1) . "…" : v:val)')
    if len(extra) > 5 | call add(r, '… e mais ' . (len(extra) - 5) . ' linha(s)') | endif
    return r
  endif
  return [s:uma(split(v, "\n", 1))]
endfunction

function! s:render() abort
  let s:acoes = {} | let s:bloco = {} | let s:inicio = []
  let L = []
  let [ent, conf, pend, min] = s:resumo()
  call s:linha(L, '', [])
  call s:linha(L, '  ⇄  Atualização de ' . s:de, [])
  call s:linha(L, '     «' . s:titulo . '»', [])
  call s:linha(L, '', [])
  call s:botoes(L, '  ', [['✓ Aceitar tudo recebido', 'tudo', 'inc', 0], ['● Manter tudo meu', 'tudo', 'cur', 0],
        \ ['⏎ Aplicar', 'aplicar', 0, pend == 0], ['✕ Cancelar', 'cancelar', 0, 0]], -1)
  let partes = [ent . ' entram sozinhas', conf . ' conflito' . (conf == 1 ? '' : 's') . (pend > 0 ? ' (' . pend . ' sem decisão)' : '')]
  if min > 0 | call add(partes, min . ' suas mantidas') | endif
  let r = '  '
  for pt in partes
    if r !=# '  ' && s:larg(r . ' · ' . pt) > &columns - 1
      call s:linha(L, r, []) | let r = '  ' . pt
    else
      let r .= (r ==# '  ' ? '' : ' · ') . pt
    endif
  endfor
  call s:linha(L, r, [])
  call s:linha(L, '  ' . repeat('─', max([20, &columns - 4])), [])
  for i in s:visiveis()
    let it = s:itens[i]
    call add(s:inicio, len(L) + 1)
    call s:linha(L, '', [])
    let marca = it.status ==# 'conflito' ? (empty(it.escolha) ? '⚡' : '✔') : '←'
    let nota = it.status ==# 'conflito' ? (empty(it.escolha) ? 'conflito — escolha' : 'conflito resolvido') : 'entra sozinha'
    let cab = len(L) + 1
    call s:linha(L, '  ' . marca . ' ' . it.rotulo . '   (' . nota . ')', [])
    let s:bloco[cab] = i
    " as duas versões, lado a lado em linhas; a escolhida leva ● e cor
    let rc = it.escolha ==# 'cur' ? '●' : '○' | let ri = it.escolha ==# 'inc' ? '●' : '○'
    if it.grupo ==# 'campo' || it.status ==# 'conflito' || !empty(it.cur)
      let ls = s:mostrar(it, 'cur')
      for j in range(len(ls))
        let k = len(L) + 1 | call s:linha(L, '    ' . (j == 0 ? rc . ' minha     │ ' : '            │ ') . ls[j], []) | let s:bloco[k] = i
      endfor
    endif
    let ls = s:mostrar(it, 'inc')
    for j in range(len(ls))
      let k = len(L) + 1 | call s:linha(L, '    ' . (j == 0 ? ri . ' recebida  │ ' : '            │ ') . ls[j], []) | let s:bloco[k] = i
    endfor
    if it.escolha ==# 'manual'
      let k = len(L) + 1 | call s:linha(L, '    ● manual    │ ' . s:uma(split(it.manual, "\n", 1)), []) | let s:bloco[k] = i
    elseif it.escolha ==# 'ambas'
      let k = len(L) + 1 | call s:linha(L, '    ● as duas   │ (minha + recebida)', []) | let s:bloco[k] = i
    endif
    if !empty(it.base)
      let k = len(L) + 1 | call s:linha(L, '      original  │ ' . s:uma(split(it.base, "\n", 1)), []) | let s:bloco[k] = i
    endif
    let bt = []
    call add(bt, ['Aceitar recebida', 'esc', i . ':inc', it.escolha ==# 'inc'])
    call add(bt, ['Manter minha', 'esc', i . ':cur', it.escolha ==# 'cur'])
    if index(it.opcoes, 'ambas') >= 0 | call add(bt, ['Ficar com as duas', 'esc', i . ':ambas', it.escolha ==# 'ambas']) | endif
    if index(it.opcoes, 'manual') >= 0 | call add(bt, ['Editar…', 'esc', i . ':manual', it.escolha ==# 'manual']) | endif
    call s:botoes(L, '    ', bt, i)
  endfor
  if empty(s:visiveis())
    call s:linha(L, '', [])
    call s:linha(L, '  Nada a rever: tudo o que veio já está na sua tarefa ou foi mantido como você deixou.', [])
  endif
  call s:linha(L, '', [])
  call s:linha(L, '  r recebida · m minha · b as duas · e editar · u desfazer · A tudo recebido · M tudo meu · Tab próximo · Ctrl+S aplica · Q cancela', [])
  setlocal modifiable
  silent %delete _
  call setline(1, L)
  setlocal nomodifiable nomodified
  call s:cores()
endfunction

function! s:uma(partes) abort
  let t = join(map(copy(a:partes), 'substitute(v:val, "\\s\\+$", "", "")'), ' ⏎ ')
  let m = max([20, &columns - 24])
  return strchars(t) > m ? strcharpart(t, 0, m - 1) . '…' : (empty(t) ? '(vazio)' : t)
endfunction

function! s:cores() abort
  call clearmatches()
  highlight default TTTitulo ctermfg=147 guifg=#b4befe cterm=bold gui=bold
  highlight default TTBtn ctermfg=252 ctermbg=238 guifg=#cdd6f4 guibg=#45475a
  highlight default TTBtnOn ctermfg=234 ctermbg=114 guifg=#1e1e2e guibg=#a6e3a1 cterm=bold gui=bold
  highlight default TTBtnOk ctermfg=234 ctermbg=111 guifg=#1e1e2e guibg=#89b4fa cterm=bold gui=bold
  highlight default TTBtnOff ctermfg=243 ctermbg=236 guifg=#6c7086 guibg=#313244
  highlight default TTConf ctermfg=210 guifg=#f38ba8 cterm=bold gui=bold
  highlight default TTOk ctermfg=114 guifg=#a6e3a1 cterm=bold gui=bold
  highlight default TTEnt ctermfg=111 guifg=#89b4fa cterm=bold gui=bold
  highlight default TTDim ctermfg=243 guifg=#6c7086
  highlight default TTSel ctermfg=114 guifg=#a6e3a1
  call matchadd('TTTitulo', '^  ⇄.*$')
  call matchadd('TTConf', '^  ⚡.*$')
  call matchadd('TTOk', '^  ✔.*$')
  call matchadd('TTEnt', '^  ←.*$')
  call matchadd('TTDim', '^      original.*$\|^  ─\+$\|^  r recebida.*$')
  call matchadd('TTSel', '^    ● .*$')
  for [ln, mapa] in items(s:acoes)
    for b in mapa
      let grupo = b[2] ==# 'aplicar' ? (b[4] ? 'TTBtnOk' : 'TTBtnOff') : (b[4] ? 'TTBtnOn' : 'TTBtn')
      call matchadd(grupo, '\%' . ln . 'l\%>' . (b[0] - 1) . 'v\%<' . (b[1] + 1) . 'v', 20)
    endfor
  endfor
endfunction

" ---------------------------------------------------------------------------------------- ações
function! s:escolher(i, ch) abort
  let it = s:itens[a:i]
  if index(it.opcoes, a:ch) < 0 | return | endif
  if a:ch ==# 'manual'
    call s:editar(a:i) | return
  endif
  let it.escolha = a:ch
  call s:redesenha(a:i)
endfunction

function! s:redesenha(i) abort
  let pos = getpos('.')
  call s:render()
  call setpos('.', pos)
endfunction

function! s:tudo(ch) abort
  for it in s:itens
    if it.status ==# 'minha' | continue | endif
    if index(it.opcoes, a:ch) >= 0 | let it.escolha = a:ch | endif
  endfor
  call s:render()
endfunction

function! s:editar(i) abort
  let it = s:itens[a:i]
  let ini = !empty(it.manual) ? it.manual : (it.escolha ==# 'cur' || empty(it.escolha) ? it.cur : it.inc)
  let s:editando = a:i
  botright 12new
  setlocal buftype=acwrite bufhidden=wipe noswapfile nobuflisted modifiable nonumber wrap linebreak
  file [editar\ valor]
  call setline(1, split(ini, "\n", 1))
  setlocal nomodified
  let &l:statusline = ' ✎ ' . it.rotulo . '   —   Ctrl+S grava · :q! cancela '
  nnoremap <buffer> <silent> <C-s> :write<CR>
  inoremap <buffer> <silent> <C-s> <Esc>:write<CR>
  autocmd BufWriteCmd <buffer> call s:gravar_manual()
endfunction

function! s:gravar_manual() abort
  let it = s:itens[s:editando]
  let txt = join(getline(1, '$'), "\n")
  let txt = substitute(txt, '\n\+$', '', '')
  setlocal nomodified
  let it.manual = txt
  let it.escolha = 'manual'
  close
  call s:render()
endfunction

function! s:item_da_linha(l) abort
  return get(s:bloco, a:l, -1)
endfunction

function! s:proximo(dir) abort
  " próximo item sem decisão (ou, se todos decididos, o próximo bloco)
  let atual = line('.')
  let alvos = []
  for k in range(len(s:inicio))
    call add(alvos, s:inicio[k] + 1)
  endfor
  if empty(alvos) | return | endif
  let ordem = a:dir > 0 ? alvos : reverse(copy(alvos))
  for l in ordem
    if (a:dir > 0 && l > atual) || (a:dir < 0 && l < atual)
      call cursor(l, 1) | return
    endif
  endfor
  call cursor(ordem[0], 1)
endfunction

function! s:aplicar() abort
  let [ent, conf, pend, min] = s:resumo()
  if pend > 0
    echohl WarningMsg | echo pend . ' conflito(s) sem decisão — escolha (r/m/b/e) ou use A / M.' | echohl None
    for it in s:itens
      if it.status ==# 'conflito' && empty(it.escolha)
        for k in range(len(s:inicio))
          if s:bloco[s:inicio[k] + 1] == index(s:itens, it) | call cursor(s:inicio[k] + 1, 1) | break | endif
        endfor
        break
      endif
    endfor
    return
  endif
  let out = []
  for it in s:itens
    if it.status ==# 'minha' | continue | endif
    call add(out, it.id . "\t" . it.escolha . "\t" . s:escapa(it.manual))
  endfor
  call writefile(out, s:saida)
  qall!
endfunction

function! s:cancelar() abort
  if filereadable(s:saida) | call delete(s:saida) | endif
  cquit
endfunction

function! s:clique(l, c) abort
  if !has_key(s:acoes, a:l) | return | endif
  for b in s:acoes[a:l]
    if a:c >= b[0] && a:c <= b[1]
      if b[2] ==# 'tudo' | call s:tudo(b[3])
      elseif b[2] ==# 'aplicar' | call s:aplicar()
      elseif b[2] ==# 'cancelar' | call s:cancelar()
      elseif b[2] ==# 'esc'
        let [i, ch] = split(b[3], ':')
        call s:escolher(str2nr(i), ch)
      endif
      return
    endif
  endfor
endfunction

function! s:tecla(ch) abort
  let i = s:item_da_linha(line('.'))
  if i < 0 | echo 'ponha o cursor num bloco' | return | endif
  if a:ch ==# 'u'
    let it = s:itens[i] | let it.escolha = it.status ==# 'conflito' ? '' : it.padrao
    call s:redesenha(i) | return
  endif
  call s:escolher(i, a:ch)
endfunction

" ---------------------------------------------------------------------------------------- mapas
function! s:mapas() abort
  setlocal buftype=nofile bufhidden=wipe noswapfile nomodifiable
  nnoremap <buffer> <silent> <LeftMouse> <LeftMouse>:call <SID>clique(line('.'), virtcol('.'))<CR>
  nnoremap <buffer> <silent> r :call <SID>tecla('inc')<CR>
  nnoremap <buffer> <silent> m :call <SID>tecla('cur')<CR>
  nnoremap <buffer> <silent> b :call <SID>tecla('ambas')<CR>
  nnoremap <buffer> <silent> e :call <SID>tecla('manual')<CR>
  nnoremap <buffer> <silent> u :call <SID>tecla('u')<CR>
  nnoremap <buffer> <silent> A :call <SID>tudo('inc')<CR>
  nnoremap <buffer> <silent> M :call <SID>tudo('cur')<CR>
  nnoremap <buffer> <silent> <Tab> :call <SID>proximo(1)<CR>
  nnoremap <buffer> <silent> <S-Tab> :call <SID>proximo(-1)<CR>
  nnoremap <buffer> <silent> <C-s> :call <SID>aplicar()<CR>
  nnoremap <buffer> <silent> ZZ :call <SID>aplicar()<CR>
  nnoremap <buffer> <silent> <CR> :call <SID>aplicar_ou_botao()<CR>
  nnoremap <buffer> <silent> Q :call <SID>cancelar()<CR>
  nnoremap <buffer> <silent> ZQ :call <SID>cancelar()<CR>
  cnoremap <buffer> <C-s> <C-c>
  let &l:statusline = ' ⇄ revisão da atualização   Ctrl+S aplica · Q cancela '
endfunction

function! s:aplicar_ou_botao() abort
  call s:clique(line('.'), virtcol('.'))
  " ⏎ numa linha sem botão: não aplica (evita aplicar sem querer); Ctrl+S aplica
endfunction

" ---------------------------------------------------------------------------------------- início
call s:ler()
enew
call s:mapas()
call s:render()
autocmd VimEnter,VimResized * call s:redesenha(0)
call cursor(len(s:inicio) > 0 ? s:inicio[0] + 1 : 1, 1)

if $TT_MERGE_AUTO ==# 'inc' || $TT_MERGE_AUTO ==# 'cur'
  call s:tudo($TT_MERGE_AUTO)
  call s:aplicar()
endif
