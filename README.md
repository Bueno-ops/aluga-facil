# Aluga Fácil

**PWA de aluguel de máquinas e equipamentos de obra** feito do zero, em HTML único, CSS e JavaScript puro — sem frameworks, sem dependências externas e funcionando offline depois do primeiro acesso.

O app reúne betoneiras, andaimes, compactadores, ferramentas elétricas, equipamentos de jardinagem, limpeza e acesso em altura, organizados nas categorias **Acesso e elevação, Andaimes, Compactação, Concretagem, Ferramentas elétricas, Furação e demolição, Jardinagem, Limpeza, Motores e Outros**. Tem filtros, favoritos, cálculo do custo estimado, contato por WhatsApp e agendamento de retirada. Anúncios criados por você ficam salvos no próprio dispositivo.

> **Identidade visual (v16):** o app adotou uma paleta de loja de locação para obra — azul `#183C8F`, azul escuro `#0A1C59` e amarelo `#F7CE46` — com cartões, categorias e chamadas inspirados no segmento. A marca e os ícones são próprios do Aluga Fácil.

Há também uma **Área da empresa** com dois logins locais: **dono (admin)** e **gerente**. O painel mostra vendas, receita, lucro estimado, ticket médio, caução em aberto, gráfico dos últimos 6 meses, ranking de máquinas e registro manual de vendas/reservas. O dono tem acesso total, incluindo configurações do negócio, controle do acesso do gerente e backup dos dados.

Na mesma aba **Painel**, o **cliente** pode criar a própria conta, entrar, editar os dados, trocar a senha e acompanhar as reservas feitas com aquele cadastro. O cadastro aceita **pessoa física** ou **empresa (CNPJ)** — no caso de empresa, basta digitar o CNPJ e o app busca e preenche automaticamente os dados do estabelecimento.

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
- **Reserva de retirada**: data, horário, nome e WhatsApp; lista ordenada, com opção de cancelar e confirmar por WhatsApp. Se o cliente estiver logado, os dados são preenchidos automaticamente e a reserva fica vinculada à conta.
- **Anúncios (somente dono)**: o formulário não fica na barra inferior. O dono abre **Painel → Dono ou gerente → Administração → Publicar anúncio**, com validação, acessórios, publicação imediata na busca e lista dos anúncios (com exclusão).
- **Compartilhar máquina** por link direto (`#maquina=...`), com suporte ao compartilhamento nativo do celular.
- **Área da empresa** com login local de **dono (admin)** e **gerente**: receita realizada, a receber, lucro estimado, ticket médio, caução em aberto, custo estimado, receita por mês, máquinas mais alugadas, resumo do período e histórico de pedidos com concluir/reabrir/cancelar/reativar.
- **Administração (somente dono)**: configurações do negócio, redefinir senha do gerente, bloquear/liberar o acesso dele, ver os clientes cadastrados, publicar/excluir anúncios, exportar backup em JSON e apagar todos os dados.
- **Conta do cliente**: cadastro de **pessoa física** (nome, WhatsApp, e-mail opcional e cidade) ou **empresa** (só o CNPJ, com busca automática dos dados), login por e-mail, WhatsApp ou CNPJ, edição do perfil, troca de senha e painel com reservas agendadas, locações concluídas e total em locações.
- **Registro manual de venda/reserva** no painel, com cálculo automático do valor e data padrão de hoje.
- **Configurações do negócio**: nome exibido e custo operacional (% da receita) para o cálculo do lucro.
- **Tema claro/escuro** (segue a preferência do sistema na primeira visita).
- **PWA instalável** com funcionamento offline, ícones normais e maskable.
- **Acessibilidade**: navegação por teclado, rótulos ARIA, foco no modal e `Esc` para fechar.

## Estrutura

```
C:\Users\palot\OneDrive\Documentos\APP ALUGUEL
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
| `aluga:anuncios` | anúncios publicados pelo dono (admin) |
| `aluga:tema` | `claro` ou `escuro` |
| `aluga:gerente` | sessão ativa do painel (token aleatório, validade de 12 h e 2 h de inatividade) |
| `aluga:gerente-config` | usuário, nome, hash PBKDF2 da senha e situação do gerente |
| `aluga:admin-config` | usuário, nome e hash PBKDF2 da senha do dono (admin) |
| `aluga:negocio` | custo operacional (%) usado no lucro estimado |
| `aluga:clientes` | contas de clientes: tipo (`pf`/`pj`), nome/razão social, WhatsApp, e-mail, cidade, CNPJ e dados da empresa, além do hash PBKDF2 da senha |
| `aluga:cliente-sessao` | sessão do cliente (token aleatório, validade de 7 dias e 7 dias de inatividade) |
| `aluga:painel-modo` | último modo aberto na aba Painel (`cliente` ou `empresa`) |
| `aluga:seguranca` | histórico local de logins, falhas, bloqueios e contadores de tentativas |

### Acessos: dono (admin) e gerente

Abra a aba **Painel** na barra inferior. **Não existem mais senhas padrão**: no primeiro acesso o app pede para criar o usuário e a senha do dono. Depois, o dono cria ou libera o acesso do gerente.

| Acesso | Como entrar | O que pode fazer |
|---|---|---|
| **Dono / Administrador** | usuário e senha definidos no primeiro acesso | Tudo: painel completo, configurações do negócio, controle do acesso do gerente, histórico de segurança, **publicação/exclusão de anúncios**, backup e limpeza dos dados |
| **Gerente** | usuário e senha definidos pelo dono | Painel, vendas/reservas, dados de exemplo e troca da própria senha (não publica anúncios) |

- As contas antigas com as senhas `admin123` / `gerente123` são **invalidadas automaticamente** na atualização: o dono precisa criar uma senha nova e o gerente fica desativado até o dono redefinir.
- Contas antigas com senha própria continuam entrando uma vez com a senha atual e são **obrigadas a criar uma senha nova** (hash migrado para PBKDF2).
- A senha precisa ter **8 a 128 caracteres, com pelo menos uma letra e um número**, e não pode ser igual ao nome/usuário nem estar em uma lista de senhas comuns.
- **5 tentativas erradas** bloqueiam o acesso por **15 minutos**; novas falhas dobram o tempo até o limite de 60 minutos.
- O admin pode redefinir a senha do gerente e **bloquear/liberar** o acesso dele em **Administração do acesso**.
- O admin pode **exportar um backup** em JSON (sem senhas e sem sessões) e **apagar todos os dados** do dispositivo digitando `APAGAR` para confirmar.
- A sessão do painel dura 12 horas e expira após 2 horas sem atividade; a do cliente dura 7 dias. O botão **Sair** encerra na hora.
- O painel mostra apenas os pedidos **deste dispositivo** (o app é local-first). Para acompanhar o negócio no celular e no computador ao mesmo tempo seria necessário um backend — não existe sincronização.

### Anúncios (somente dono)

A opção **Anunciar** foi removida da barra inferior. Ninguém além do dono (admin) pode publicar ou excluir anúncios:

1. Entre em **Painel → Dono ou gerente**.
2. Abra o bloco **Anúncios** em **Administração**.
3. Toque em **Publicar anúncio**. O formulário abre na hora e o anúncio aparece na busca ao publicar.

O acesso é bloqueado também na lógica do app: gerentes, clientes e visitantes não conseguem abrir a tela de anúncio nem chamar as funções de publicar/excluir.

### Conta do cliente

Na aba **Painel**, a opção **Sou cliente** abre o cadastro:

1. Escolha **Pessoa física** ou **Empresa (CNPJ)**.
2. **Pessoa física:** criar conta com nome completo, WhatsApp, cidade e senha (e-mail é opcional).
3. **Empresa:** digite o CNPJ e toque em **Buscar** (a busca também começa sozinha ao completar os 14 números). O app consulta os dados públicos da empresa e preenche razão social, telefone, e-mail e cidade; o cartão com situação, atividade (CNAE), endereço e porte aparece logo abaixo. Confira, crie a senha e conclua o cadastro.
4. Depois é só entrar com **e-mail, WhatsApp ou CNPJ** e senha.
5. Em **Meus dados** o cliente edita nome/razão social, WhatsApp, e-mail e cidade. Para empresa, o cartão com os dados do CNPJ aparece no topo do painel.
6. Em **Minhas reservas** aparecem as reservas agendadas e concluídas da conta, com opção de cancelar.
7. A sessão do cliente dura **7 dias** (renovada enquanto ele usa o app); o botão **Sair** encerra na hora.
8. O dono vê todos os clientes cadastrados em **Clientes cadastrados**, no painel da empresa, com selo **PJ** e CNPJ para empresas.

### Cadastro de empresa (CNPJ)

- A consulta usa a **BrasilAPI** (`https://brasilapi.com.br/api/cnpj/v1/{cnpj}`) e, se ela falhar, a **publica.cnpj.ws** (`https://publica.cnpj.ws/cnpj/{cnpj}`).
- O CNPJ é validado pelos dígitos verificadores antes da consulta; máscara `00.000.000/0000-00` aplicada automaticamente.
- Os dados retornados são salvos como um **snapshot** em `cliente.empresa` (razão social, nome fantasia, situação cadastral, CNAE, natureza jurídica, porte, endereço, cidade/UF, CEP, telefone e e-mail).
- Quando existe **nome fantasia**, ele é usado como nome exibido no app; a razão social continua salva em `cliente.nome` e editável no perfil.
- O login de empresa aceita o **CNPJ** (com ou sem máscara) no campo de identificação.
- Se a consulta estiver indisponível (sem internet ou API fora do ar), o cadastro **não é bloqueado**: o app avisa e permite preencher os dados manualmente. A conta é criada como PJ e o CNPJ fica registrado.
- Não é possível cadastrar dois clientes com o mesmo CNPJ.

> Reservas antigas (feitas antes do cadastro) são vinculadas à conta pelo **WhatsApp** quando os números coincidem.

A base de exemplo está em `EQUIPAMENTOS_BASE`, no início do JavaScript de `app.html` (167 equipamentos inspirados no catálogo da Casa do Construtor, em Pelotas/RS, com diárias, descrições, categorias e acessórios editáveis pelo dono).

Para **zerar os dados**, abra o console do navegador e rode:

```js
localStorage.clear();
location.reload();
```

## Segurança (v13+)

O app não tem servidor: os dados e as contas ficam no `localStorage` **daquele dispositivo**. A v13 reforça a proteção local contra acesso casual e contra erros comuns, mas **não transforma o app em um sistema 100% seguro** — isso só existiria com backend e autenticação no servidor.

O que foi implementado:

- **Senhas com PBKDF2-SHA-256** (310.000 iterações) e salt aleatório por conta. A senha em texto puro nunca é salva.
- **Comparação em tempo constante** para reduzir ataques de temporização.
- **Fim das senhas padrão**: o primeiro acesso cria o dono; o gerente só entra depois que o dono define usuário e senha.
- **Migração segura**: hashes antigos são aceitos uma única vez e a pessoa é obrigada a criar uma senha nova; as senhas padrão antigas são invalidadas.
- **Política de senha**: 8 a 128 caracteres, com letra e número, sem repetir nome/usuário e sem senhas óbvias.
- **Bloqueio por tentativas**: 5 erros → 15 minutos; novas rodadas dobram o tempo até 60 minutos. Vale para o painel, para o login do cliente e para a troca de senha.
- **Sessões com token aleatório** (`crypto.getRandomValues`), expiração por tempo e por inatividade, e invalidação ao sair.
- **Ações de dono exigem sessão válida** (não basta uma variável antiga na tela): configurações, acesso do gerente, backup, histórico e limpeza.
- **CSP** restringindo scripts, estilos, imagens e conexões ao próprio app e às APIs de CNPJ.
- **Sanitização de entrada e escaping de saída** nos dados exibidos, incluindo o histórico de segurança.
- **Backup sem credenciais**: exporta reservas, vendas, anúncios, favoritos e configurações, mas remove senhas, hashes e sessões.
- **Confirmação forte para apagar tudo**: é preciso digitar `APAGAR`.
- **Histórico de segurança local** com logins, falhas, bloqueios, trocas de senha, backup e limpeza (sem enviar nada para a internet).

### O que ainda não é possível garantir

- Quem tem **acesso físico ao aparelho** ou ao navegador (DevTools) pode limpar o `localStorage`, alterar o código ou ler os dados. Use bloqueio de tela/PIN e mantenha o sistema atualizado.
- **Não há sincronização nem recuperação de senha por e-mail**: se esquecer a senha do dono, será preciso limpar os dados do app (e perder o que não estiver em backup).
- Um **backend com autenticação real** seria necessário para impedir invasão remota, limitar tentativas no servidor e proteger os dados de verdade.

## Atualizações e versão

O app **é o mesmo** no computador e no celular — não existe um projeto separado para Android. O que roda no celular é este PWA instalado; qualquer alteração publicada chega a ele automaticamente.

- A versão atual aparece no **rodapé** do app (ex.: `v18`).
- A partir da **v15**, o app **procura e aplica atualizações automaticamente**: ao abrir, ao voltar para o app e a cada 5 minutos com ele aberto. O service worker novo assume na hora (`skipWaiting`) e a página recarrega sozinha.
- A checagem busca `sw.js` e as páginas com a versão na URL e `cache: 'reload'`, para furar cache antigo do navegador e do GitHub Pages.
- Ao atualizar, favoritos, reservas, anúncios, contas e tema **são preservados** (ficam no `localStorage`, não no cache).
- A versão do rodapé (`VERSAO_APP` em `app.html`) deve ser igual à versão do `sw.js` (`VERSAO` e `CACHE`).
- Se o Android continuar na versão antiga, abra **instalar.html** e toque em **Forçar atualização do app**. Isso remove o service worker/cache antigos e abre a versão nova.

> **Importante:** o PWA só recebe atualizações se foi instalado pelo **link público** (`https://bueno-ops.github.io/aluga-facil/app.html`) ou por outro endereço HTTPS do mesmo projeto. Se foi instalado pelo link da rede local (`http://192.168.x.x:8099`), ele é outro endereço e **não atualiza**. Nesse caso, desinstale e instale de novo pelo QR principal.

## Personalização rápida

- **Cores**: variáveis CSS `--primaria`, `--destaque`, `--bg` etc. no topo de `app.html`.
- **Nome do app**: `<title>`, cabeçalho, `manifest.json` e `index.html`.
- **Máquinas de exemplo**: edite o array `EQUIPAMENTOS_BASE` em `app.html`.
- **Tipos e energias**: arrays `TIPOS` e `ENERGIAS`.
- **Acessórios**: array `ACESSORIOS`.
- **Ícones**: rode `gerar-icones.ps1` novamente após alterar o desenho.

## Limitações (propositalmente simples)

- Os logins (dono, gerente e cliente) são **proteção local do dispositivo** (PBKDF2 no `localStorage`), não uma autenticação de servidor. Quem tiver acesso técnico ao aparelho pode limpar ou alterar os dados — veja a seção **Segurança (v13+)**.
- Não há sincronização entre dispositivos: o painel vê só as reservas feitas/registradas naquele aparelho.
- Os anúncios são publicados apenas pelo dono e ficam apenas no navegador em que foram publicados.
- As imagens das máquinas são **ilustrações SVG** geradas por tipo, para o app funcionar 100% offline e sem imagens externas.
- A busca de CNPJ depende de internet e de APIs públicas de terceiros (BrasilAPI/publica.cnpj.ws). Sem conexão, o cadastro da empresa pode ser concluído com preenchimento manual.
- O contato real acontece via WhatsApp do anunciante.
- O servidor local é apenas para desenvolvimento/uso na rede local, não para produção.

## Publicar de graça (link fixo)

**Já publicado:** <https://bueno-ops.github.io/aluga-facil/>

- Repositório: <https://github.com/Bueno-ops/aluga-facil> (público)
- Publicação automática: `.github/workflows/pages.yml` roda a cada envio para a branch `main`.
- O site é servido de `dist/` (gerado no próprio workflow), então scripts e o `cloudflared.exe` não vão para o ar.

### Como atualizar o app publicado

```powershell
cd "C:\Users\palot\OneDrive\Documentos\APP ALUGUEL"
git add -A
git commit -m "descreva a mudança"
git push
```

Em cerca de 1 minuto o GitHub Pages publica. Quem já instalou pelo link público recebe a atualização **automaticamente** ao abrir o app (ou em até 5 minutos com ele aberto).

> Lembre-se de atualizar a versão em **dois lugares**: `VERSAO_APP` (app.html) e `VERSAO`/`CACHE` (sw.js). Isso força o celular a baixar os arquivos novos.

### Outros destinos (opcional)

- `preparar-publicacao.ps1` gera a pasta **`dist/`** (~0,25 MB) para arrastar no Netlify/Cloudflare.
- `netlify.toml` já configura cache correto do `sw.js` e do `manifest.json`.

Com um link HTTPS fixo, a instalação no Android funciona sempre — inclusive offline e sem depender do computador ligado.
