# Backend do Aluga Fácil (Supabase / PostgreSQL)

Esta pasta é o banco de dados real do app: esquema, segurança por linha (RLS),
funções de negócio e o catálogo de 167 itens. O `app.html` continua funcionando
no modo local enquanto a nuvem não estiver configurada — os dois modelos convivem.

```
supabase/
├── migrations/
│   ├── 0001_esquema.sql    # tabelas, tipos, índices, triggers
│   ├── 0002_rls.sql        # RLS, permissões e políticas
│   └── 0003_funcoes.sql    # RPCs (reservar, entrega, anúncios, contas)
├── seed.sql                # catálogo real (167 itens) + configuração
├── testes/
│   └── testar_banco.py     # 55 testes em PostgreSQL real (RLS + RPCs)
└── README.md
```

## 1. Criar o projeto

1. Crie uma conta em <https://supabase.com> e um projeto novo.
2. Guarde a **senha do banco** (não vai no app).
3. Anote, em *Project Settings → API*:
   - **Project URL** — ex.: `https://xxxxxxxx.supabase.co`
   - **anon public key** — pode ir no app (é pública)
   - **service_role key** — **nunca** vai no app nem no Git

> O plano gratuito serve para começar. Faça backup antes de qualquer migração.

## 2. Aplicar o banco

No **SQL Editor**, execute nesta ordem, colando o conteúdo de cada arquivo:

1. `migrations/0001_esquema.sql`
2. `migrations/0002_rls.sql`
3. `migrations/0003_funcoes.sql`
4. `seed.sql`

Ou, com a CLI do Supabase instalada:

```bash
supabase link --project-ref SEU_REF
supabase db push
psql "$DATABASE_URL" -f supabase/seed.sql
```

Confira:

```sql
select count(*) from public.equipamentos where origem = 'catalogo'; -- 167
select count(*) from public.equipamentos where publicado;            -- 167
```

## 3. Criar o dono (admin)

1. Em *Authentication → Providers*, mantenha **Email** ativo.
2. Crie o usuário do dono (por *Authentication → Users → Add user* ou pelo
   cadastro do app).
3. No SQL Editor, promova o e-mail:

```sql
select public.promover_admin_por_email('dono@seudominio.com');
```

4. Para o gerente: crie o usuário e, logado como admin no app, use a tela de
   contas — ou no SQL Editor:

```sql
select public.definir_papel(id, 'gerente')
from public.perfis where email = 'gerente@seudominio.com';
```

A partir daí, todo usuário novo entra como **cliente**. O admin é o único que
publica/remove anúncios e altera configuração e papéis.

## 4. O que o banco garante

| Regra | Como é garantida |
|---|---|
| Cliente só vê as próprias reservas e favoritos | RLS em `reservas` e `favoritos` |
| Cliente não vê dados de outros clientes | RLS em `perfis` (`id = auth.uid()`) |
| Preço, frete, caução e total não podem ser forjados | calculados em `criar_reserva` |
| Cliente não muda status, entrega nem papel | sem GRANT de escrita; só RPC com checagem |
| Só o admin publica/remove anúncio | `publicar_anuncio` / `remover_anuncio` |
| Custo interno não vaza | coluna sem GRANT; só `config_equipe()` |
| Eventos de segurança não são expostos | tabela sem GRANT e sem política |
| Reserva duplicada no mesmo horário | checagem + erro `23505` |
| Abuso de reservas | limite de 5 ativas e 10 por 24 h |
| Anúncio com reserva ativa não é apagado | vira `publicado = false` |

O `service_role` **ignora RLS** por definição. Ele só deve ser usado em scripts
administrativos, nunca no navegador.

## 5. Modelo de dados

- `perfis` — 1 linha por usuário do Auth (`admin`, `gerente`, `cliente`).
- `equipamentos` — catálogo (`origem = 'catalogo'`) e anúncios (`origem = 'anuncio'`).
  Os IDs do app são preservados (`c1`…`c167`, `meu-*`).
- `reservas` — valores calculados no servidor + rastreamento de entrega.
- `reserva_eventos` — linha do tempo/auditoria de cada reserva.
- `favoritos` — por cliente.
- `config_negocio` — empresa, WhatsApp e custo (linha única).
- `eventos_seguranca` — auditoria interna (login, anúncio, papel, configuração).

Status de reserva: `confirmada`, `concluida`, `cancelada`.
Status de entrega: `preparando`, `saiu`, `em_transito`, `entregue`.

## 6. Funções (RPC) disponíveis ao app

| Função | Quem pode |
|---|---|
| `criar_reserva(equipamento, data, hora, dias, nome, telefone)` | cliente logado |
| `cancelar_reserva(id)` | dono da reserva ou equipe |
| `confirmar_recebimento(id)` | dono da reserva |
| `atualizar_entrega(id, status, entregador, duração)` | equipe |
| `concluir_reserva(id)` | equipe |
| `registrar_venda(equipamento, nome, data, dias, concluída)` | equipe |
| `publicar_anuncio(json)` / `remover_anuncio(id)` | admin |
| `salvar_config_negocio(empresa, whatsapp, custo)` | admin |
| `config_equipe()` | equipe |
| `definir_papel(id, papel)` / `definir_ativo(id, ativo)` | admin |

## 7. Testes

Os testes sobem um PostgreSQL 16 embutido, criam os stubs do Supabase
(`auth.users`, `auth.uid()`, papéis `anon`/`authenticated`), aplicam as
migrações e o seed e exercitam RLS e RPCs como cada tipo de usuário.

```powershell
python -m pip install pgserver "psycopg[binary]"
python supabase/testes/testar_banco.py
```

Resultado esperado: `55 testes, 0 falhas`.

## 8. Ligar o app ao banco (v22)

A camada cliente já está pronta e publicada: `nuvem-config.js`, `nuvem.js` e
`nuvem-ui.js`. Para ativar, preencha **somente** `nuvem-config.js` na raiz:

```js
window.ALUGA_NUVEM_CONFIG = {
  url: 'https://SEU_PROJETO.supabase.co',
  anonKey: 'eyJhbGciOiJIUzI1NiJ9....'
};
```

Depois publique (`git push` dispara o GitHub Pages). A URL e a anon key são
públicas por definição; a **service_role key nunca** entra nesses arquivos.

Com a nuvem ativa:

- O catálogo de 167 itens vem de `equipamentos` (o catálogo embutido vira cache
  offline). Um domínio configurado, mas fora do ar, não quebra o app.
- A aba *Painel → Sou cliente → Conta na nuvem* tem Entrar/Criar conta/Sair.
  Dono e gerente entram ali e depois selecionam *Dono ou gerente* no topo.
- Reserva, cancelamento, confirmação de recebimento, entrega, anúncios e
  configuração passam a usar as RPCs. Preço e total vêm do servidor.
- Favoritos e reservas são sincronizados no login e refetchados ao voltar a
  internet; o `localStorage` funciona como cache offline somente leitura.
- O CSP já liberou `https://*.supabase.co` em `app.html` e `netlify.toml`.

## 9. Limites

- **Criar a conta/projeto Supabase exige uma pessoa.** O fluxo de cadastro pede
  e-mail, verificação e aceite dos termos; um agente automatizado não pode
  fazer isso por você. Sem a URL e a anon key, o app permanece no modo local.
- **Contas antigas do modo local não migram.** As senhas locais usam PBKDF2 e
  não podem virar senhas do Supabase Auth; o cliente cria a conta na nuvem.
- **E-mail/telefone**: o Supabase Auth usa e-mail como login. O telefone do
  cliente fica em `perfis` e é usado no contato da reserva.
- **Reabrir pedido concluído** não existe no banco (não há RPC para isso); na
  nuvem a ação é bloqueada com aviso em vez de gravar só no dispositivo.
- **Troca de senha** na nuvem deve usar o fluxo de recuperação do Supabase Auth;
  os formulários locais de senha continuam valendo apenas para o modo local.
- **Tempo real**: a sincronização é feita no login, ao voltar a internet e
  depois de cada escrita. Não há assinatura Realtime/WebSocket.
- **LGPD**: o banco guarda nome, WhatsApp, e-mail e, para PJ, CNPJ. Defina prazo
  de retenção, política de privacidade e um processo de exclusão de conta.
- **Backup**: ative *Point in Time Recovery* no plano pago ou faça `pg_dump`
  periódico. RLS protege o acesso, não substitui backup.
- **XSS**: o CSP do app permite `'unsafe-inline'` por causa do HTML inline. Isso
  continua sendo o principal vetor de risco para tokens de sessão guardados no
  navegador. Nunca instale scripts de terceiros nesta página.
