# Aluga Fácil

**PWA de aluguel de máquinas e equipamentos de obra** feito do zero, em HTML único, CSS e JavaScript puro — sem frameworks, sem dependências externas e funcionando offline depois do primeiro acesso.

O app reúne betoneiras, marteletes, furadeiras, andaimes, compactadores, geradores, lavadoras, serras e escadas, com filtros, favoritos, cálculo do custo estimado, contato por WhatsApp e agendamento de retirada. Anúncios criados por você ficam salvos no próprio dispositivo.

Há também uma **Área do gerente** com login local: painel de vendas, receita, lucro estimado, ticket médio, caução em aberto, gráfico dos últimos 6 meses, ranking de máquinas e registro manual de vendas/reservas.

## Como abrir

### No computador (recomendado)

1. Dê **duplo clique em `abrir-app.bat`**.
2. O navegador abre em `http://localhost:8099/app.html`.
3. Para encerrar, volte à janela preta e pressione `Ctrl+C`.

Alternativa manual:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File ".\servidor-local.ps1"
```

> Abrir o `app.html` com duplo clique também funciona, mas o service worker e a instalação como app **só funcionam via http/https**. Por isso existe o servidor local.

### No celular (QR code)

O app está publicado em um **link fixo**:

**<https://bueno-ops.github.io/aluga-facil/app.html>**

Abra a página **`instalar.html`** (ou `abrir-no-celular.bat`) e escaneie o QR principal:

1. **Android/Chrome:** menu ⋮ → **Instalar app**.
2. **iPhone/Safari:** Compartilhar → **Adicionar à Tela de Início**.

O QR principal funciona em qualquer rede (Wi-Fi ou 4G) e permite a instalação completa, com cache offline. O segundo QR é opcional e aponta para a **rede local** (`http://IP-DO-PC:8099/app.html`): só funciona na mesma Wi-Fi e, no Android, oferece apenas *Adicionar à tela inicial*.

> O `abrir-no-celular.ps1` ainda cria um túnel temporário (`trycloudflare.com`) para testar sem publicar. Ele muda de endereço a cada execução e depende do computador ligado — use apenas como alternativa.

Se quiser abrir só na rede local, sem túnel:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File ".\servidor-local.ps1" -RedeLocal
```

O terminal mostra o endereço `http://IP-DO-PC:8099/app.html`. Autorize o PowerShell no firewall do Windows se ele perguntar.

## Funcionalidades

- **Busca e filtros**: texto livre, tipo de máquina, cidade, diária máxima, energia (110V, 220V, gasolina ou manual), entrega incluída e acessórios inclusos.
- **Ordenação**: relevância, menor/maior diária, mais leve e mais recentes.
- **Detalhes completos**: descrição, acessórios, potência, peso, energia e **custo estimado** (diária + entrega + caução) com total do primeiro dia.
- **Favoritos**: salvos no dispositivo, com contador na barra inferior.
- **Reserva de retirada**: data, horário, nome e WhatsApp; lista ordenada, com opção de cancelar e confirmar por WhatsApp.
- **Anunciar**: formulário com validação, acessórios, publicação imediata na busca e lista dos seus anúncios (com exclusão).
- **Compartilhar máquina** por link direto (`#maquina=...`), com suporte ao compartilhamento nativo do celular.
- **Área do gerente** (login local): receita realizada, a receber, lucro estimado, ticket médio, caução em aberto, custo estimado, receita por mês, máquinas mais alugadas, resumo do período e histórico de pedidos com concluir/reabrir/cancelar/reativar.
- **Registro manual de venda/reserva** no painel, com cálculo automático do valor e data padrão de hoje.
- **Configurações do negócio**: nome exibido e custo operacional (% da receita) para o cálculo do lucro.
- **Tema claro/escuro** (segue a preferência do sistema na primeira visita).
- **PWA instalável** com funcionamento offline, ícones normais e maskable.
- **Acessibilidade**: navegação por teclado, rótulos ARIA, foco no modal e `Esc` para fechar.

## Estrutura

```
F:\APP ALUGUEL
├── app.html                # aplicativo completo (HTML + CSS + JS)
├── index.html              # redireciona para app.html
├── instalar.html           # página com QR codes e passo a passo
├── qrcode-fixo.png         # QR do link fixo (GitHub Pages)
├── qrcode-instalar.png     # QR do link na rede local
├── qrcode-tunel.png        # QR do túnel temporário (gerado pelo script)
├── manifest.json           # manifesto do PWA (nome, ícones, cores)
├── sw.js                   # service worker (cache offline)
├── icon.svg                # ícone vetorial (engrenagem)
├── icon-*.png              # ícones 48 a 512 px
├── icon-maskable-*.png     # ícones para Android (maskable)
├── gerar-icones.ps1        # regenera os PNGs via System.Drawing
├── servidor-local.ps1      # servidor HTTP local (porta 8099)
├── abrir-app.bat           # atalho para abrir só no PC
├── abrir-no-celular.bat    # servidor + túnel HTTPS + QR
├── abrir-no-celular.ps1    # lógica do atalho acima
├── parar-tunel.ps1         # encerra servidor e túnel
├── preparar-publicacao.ps1 # gera a pasta dist/ para publicar
├── netlify.toml            # cache correto no Netlify
├── robots.txt              # indexação
├── .github/workflows/pages.yml  # publicação automática no GitHub Pages
├── ferramentas/
│   └── cloudflared.exe     # binário do túnel (não versionado)
├── dist/                   # gerado: apenas os arquivos do site
├── README.md
└── .gitignore
```

## Dados e armazenamento

O app é **local-first**: não há backend nem envio de dados para a internet. Tudo fica no `localStorage` do navegador:

| Chave | Conteúdo |
|---|---|
| `aluga:favoritos` | IDs das máquinas favoritadas |
| `aluga:reservas` | reservas e vendas (máquina, data, hora, contato, valores, status) |
| `aluga:anuncios` | anúncios criados por você |
| `aluga:tema` | `claro` ou `escuro` |
| `aluga:gerente` | sessão do gerente (validade de 12 h) |
| `aluga:gerente-config` | usuário, nome e hash da senha do gerente |
| `aluga:negocio` | custo operacional (%) usado no lucro estimado |

### Login do gerente

- Abra a aba **Gerente** na barra inferior.
- **Primeiro acesso:** usuário `gerente` e senha `gerente123`.
- Troque a senha em **Segurança** logo depois de entrar.
- A sessão dura 12 horas; o botão **Sair** encerra na hora.
- O painel mostra apenas os pedidos **deste dispositivo** (o app é local-first). Para acompanhar o negócio no celular e no computador ao mesmo tempo seria necessário um backend — não existe sincronização.

A base de exemplo está em `EQUIPAMENTOS_BASE`, no início do JavaScript de `app.html` (12 máquinas em São Paulo, Campinas, Curitiba, Belo Horizonte, Rio de Janeiro, Recife, Salvador e Barueri).

Para **zerar os dados**, abra o console do navegador e rode:

```js
localStorage.clear();
location.reload();
```

## Atualizações e versão

O app **é o mesmo** no computador e no celular — não existe um projeto separado para Android. O que roda no celular é este PWA instalado; qualquer alteração publicada chega a ele automaticamente.

- A versão atual aparece no **rodapé** do app (ex.: `v9`).
- Ao abrir com internet, o app procura uma versão nova. Se existir, aparece o aviso **“Nova versão disponível”** com o botão **Atualizar**.
- Ao atualizar, favoritos, reservas, anúncios e tema **são preservados** (ficam no `localStorage`, não no cache).
- A versão do rodapé (`VERSAO_APP` em `app.html`) deve ser igual à do `sw.js` (`CACHE`).

> Se o celular estiver mostrando uma versão antiga, feche e abra o app duas vezes com internet. Se ainda assim não mudar, desinstale e instale novamente pelo QR code.

## Personalização rápida

- **Cores**: variáveis CSS `--primaria`, `--destaque`, `--bg` etc. no topo de `app.html`.
- **Nome do app**: `<title>`, cabeçalho, `manifest.json` e `index.html`.
- **Máquinas de exemplo**: edite o array `EQUIPAMENTOS_BASE` em `app.html`.
- **Tipos e energias**: arrays `TIPOS` e `ENERGIAS`.
- **Acessórios**: array `ACESSORIOS`.
- **Ícones**: rode `gerar-icones.ps1` novamente após alterar o desenho.

## Limitações (propositalmente simples)

- O login do gerente é **proteção local do dispositivo** (hash no `localStorage`), não uma autenticação de servidor. Quem tiver acesso técnico ao aparelho pode limpar os dados.
- Não há sincronização entre dispositivos: o painel vê só as reservas feitas/registradas naquele aparelho.
- Os anúncios criados ficam apenas no navegador em que foram publicados.
- As imagens das máquinas são **ilustrações SVG** geradas por tipo, para o app funcionar 100% offline e sem imagens externas.
- O contato real acontece via WhatsApp do anunciante.
- O servidor local é apenas para desenvolvimento/uso na rede local, não para produção.

## Publicar de graça (link fixo)

**Já publicado:** <https://bueno-ops.github.io/aluga-facil/>

- Repositório: <https://github.com/Bueno-ops/aluga-facil> (público)
- Publicação automática: `.github/workflows/pages.yml` roda a cada envio para a branch `main`.
- O site é servido de `dist/` (gerado no próprio workflow), então scripts e o `cloudflared.exe` não vão para o ar.

### Como atualizar o app publicado

```powershell
cd "F:\APP ALUGUEL"
git add -A
git commit -m "descreva a mudança"
git push
```

Em cerca de 1 minuto o GitHub Pages publica. Quem já instalou no celular recebe o aviso **“Nova versão disponível”**.

> Lembre-se de atualizar a versão em **dois lugares**: `VERSAO_APP` (app.html) e `CACHE` (sw.js). Isso força o celular a baixar os arquivos novos.

### Outros destinos (opcional)

- `preparar-publicacao.ps1` gera a pasta **`dist/`** (~0,25 MB) para arrastar no Netlify/Cloudflare.
- `netlify.toml` já configura cache correto do `sw.js` e do `manifest.json`.

Com um link HTTPS fixo, a instalação no Android funciona sempre — inclusive offline e sem depender do computador ligado.
