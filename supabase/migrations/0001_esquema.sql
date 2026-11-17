-- ============================================================
-- Aluga Fácil — 0001: esquema base (PostgreSQL 15+ / Supabase)
-- Aplicar no SQL Editor do Supabase ou via `supabase db push`.
-- Idempotente: pode ser executado mais de uma vez com segurança.
-- ============================================================

begin;

-- Extensão de busca por similaridade (opcional: o banco funciona sem ela).
-- gen_random_uuid() é nativo do PostgreSQL 13+.
do $$
begin
  if not exists (select 1 from pg_namespace where nspname = 'extensions') then
    execute 'create schema extensions';
  end if;
  begin
    execute 'create extension if not exists pg_trgm with schema extensions';
  exception when others then
    raise notice 'pg_trgm indisponível: índices de busca por similaridade não serão criados.';
  end;
end $$;

-- ------------------------------------------------------------
-- Tipos fechados (espelham as listas do app)
-- ------------------------------------------------------------
do $$ begin
  create type public.papel_usuario as enum ('admin', 'gerente', 'cliente');
exception when duplicate_object then null; end $$;

do $$ begin
  create type public.status_reserva as enum ('confirmada', 'concluida', 'cancelada');
exception when duplicate_object then null; end $$;

do $$ begin
  create type public.status_entrega as enum ('preparando', 'saiu', 'em_transito', 'entregue');
exception when duplicate_object then null; end $$;

do $$ begin
  create type public.origem_equipamento as enum ('catalogo', 'anuncio');
exception when duplicate_object then null; end $$;

-- ------------------------------------------------------------
-- Perfis: 1 linha por usuário do Supabase Auth.
-- O papel 'admin' é o dono; 'gerente' é a equipe da loja;
-- 'cliente' é quem aluga.
-- ------------------------------------------------------------
create table if not exists public.perfis (
  id              uuid primary key references auth.users (id) on delete cascade,
  papel           public.papel_usuario not null default 'cliente',
  nome            text not null default '',
  telefone        text not null default '',
  email           text not null default '',
  tipo_pessoa     text not null default 'pf' check (tipo_pessoa in ('pf', 'pj')),
  cidade          text not null default '',
  uf              text not null default '',
  cnpj            text,
  nome_fantasia   text,
  empresa         jsonb,
  ativo           boolean not null default true,
  criado_em       timestamptz not null default now(),
  atualizado_em   timestamptz not null default now(),
  constraint perfis_nome_tam     check (char_length(nome) <= 80),
  constraint perfis_telefone_tam check (char_length(telefone) <= 20),
  constraint perfis_email_tam    check (char_length(email) <= 120),
  constraint perfis_cidade_tam   check (char_length(cidade) <= 60),
  constraint perfis_uf_tam       check (char_length(uf) <= 2),
  constraint perfis_cnpj_tam     check (cnpj is null or cnpj ~ '^[0-9]{14}$')
);

comment on table public.perfis is
  'Perfil de cada usuário autenticado. papel=admin é o dono do negócio.';

-- ------------------------------------------------------------
-- Equipamentos: catálogo + anúncios publicados pelo admin.
-- O id textual preserva os ids do app (c1..c167, meu-*, ...).
-- ------------------------------------------------------------
create table if not exists public.equipamentos (
  id                    text primary key check (id ~ '^[A-Za-z0-9_-]{1,64}$'),
  titulo                text not null check (char_length(titulo) between 3 and 120),
  tipo                  text not null default 'outros'
                          check (tipo in ('acesso-elevacao', 'andaimes', 'compactacao', 'concretagem',
                                          'ferramentas-eletricas', 'furacao-demolicao', 'jardinagem',
                                          'limpeza', 'motores', 'outros')),
  cidade                text not null default '' check (char_length(cidade) <= 60),
  uf                    text not null default '' check (uf ~ '^([A-Z]{2})?$'),
  bairro                text not null default '' check (char_length(bairro) <= 60),
  diaria                numeric(12, 2) not null default 0 check (diaria >= 0),
  frete                 numeric(12, 2) not null default 0 check (frete >= 0),
  caucao                numeric(12, 2) not null default 0 check (caucao >= 0),
  energia               text not null default ''
                          check (energia in ('', '110v', '220v', 'gasolina', 'bateria', 'pneumatico', 'manual')),
  potencia              text not null default '' check (char_length(potencia) <= 40),
  peso                  numeric(10, 2) not null default 0 check (peso >= 0),
  entrega               boolean not null default true,
  destaque              boolean not null default false,
  descricao             text not null default '' check (char_length(descricao) <= 1200),
  acessorios            text[] not null default '{}',
  anunciante_nome       text not null default 'Aluga Fácil' check (char_length(anunciante_nome) <= 80),
  anunciante_telefone   text not null default '' check (char_length(anunciante_telefone) <= 20),
  origem                public.origem_equipamento not null default 'catalogo',
  publicado             boolean not null default true,
  criado_por            uuid references public.perfis (id) on delete set null,
  criado_em             timestamptz not null default now(),
  atualizado_em         timestamptz not null default now()
);

comment on table public.equipamentos is
  'Catálogo da loja e anúncios. origem=catalogo vem do seed; origem=anuncio é criado pelo admin.';

-- ------------------------------------------------------------
-- Reservas: preço sempre calculado no servidor (nunca confiar no cliente).
-- ------------------------------------------------------------
create table if not exists public.reservas (
  id                            text primary key check (id ~ '^[A-Za-z0-9_-]{1,64}$'),
  equipamento_id                text not null references public.equipamentos (id) on delete restrict,
  cliente_id                    uuid references public.perfis (id) on delete set null,
  titulo                        text not null default '' check (char_length(titulo) <= 120),
  tipo                          text not null default 'outros',
  cidade                        text not null default '' check (char_length(cidade) <= 60),
  uf                            text not null default '' check (uf ~ '^([A-Z]{2})?$'),
  data                          date not null,
  hora                          time not null default '09:00',
  nome                          text not null default '' check (char_length(nome) <= 80),
  telefone                      text not null default '' check (char_length(telefone) <= 20),
  dias                          integer not null check (dias between 1 and 365),
  diaria                        numeric(12, 2) not null check (diaria >= 0),
  frete                         numeric(12, 2) not null check (frete >= 0),
  caucao                        numeric(12, 2) not null check (caucao >= 0),
  total                         numeric(12, 2) not null check (total >= 0),
  status                        public.status_reserva not null default 'confirmada',
  entrega_status                public.status_entrega not null default 'preparando',
  entrega_saiu_em               timestamptz,
  entrega_inicio                timestamptz,
  entrega_duracao_min           integer not null default 30 check (entrega_duracao_min between 5 and 1440),
  entrega_entregador            text not null default 'Equipe Aluga Fácil'
                                  check (char_length(entrega_entregador) <= 60),
  entrega_atualizado_em         timestamptz not null default now(),
  entrega_concluida_em          timestamptz,
  entrega_confirmada_pelo_cliente boolean not null default false,
  manual                        boolean not null default false,
  criado_em                     timestamptz not null default now(),
  atualizado_em                 timestamptz not null default now(),
  constraint reservas_hora_valida check (hora >= '00:00' and hora <= '23:59')
);

comment on table public.reservas is
  'Reservas de equipamentos. Criadas/canceladas apenas via funções RPC.';

-- ------------------------------------------------------------
-- Favoritos por cliente
-- ------------------------------------------------------------
create table if not exists public.favoritos (
  perfil_id       uuid not null references public.perfis (id) on delete cascade,
  equipamento_id  text not null references public.equipamentos (id) on delete cascade,
  criado_em       timestamptz not null default now(),
  primary key (perfil_id, equipamento_id)
);

-- ------------------------------------------------------------
-- Configuração do negócio (linha única).
-- custo_pct é indicador interno: só a equipe lê.
-- ------------------------------------------------------------
create table if not exists public.config_negocio (
  id             smallint primary key default 1 check (id = 1),
  empresa        text not null default 'Aluga Fácil' check (char_length(empresa) between 1 and 60),
  whatsapp       text not null default '5553991066321' check (whatsapp ~ '^[0-9]{10,15}$'),
  custo_pct      numeric(5, 2) not null default 35 check (custo_pct between 0 and 100),
  atualizado_em  timestamptz not null default now()
);

insert into public.config_negocio (id) values (1) on conflict (id) do nothing;

-- ------------------------------------------------------------
-- Linha do tempo das reservas (auditoria visível para a equipe)
-- ------------------------------------------------------------
create table if not exists public.reserva_eventos (
  id          bigserial primary key,
  reserva_id  text not null references public.reservas (id) on delete cascade,
  tipo        text not null check (char_length(tipo) <= 40),
  detalhe     text not null default '' check (char_length(detalhe) <= 200),
  autor_id    uuid references public.perfis (id) on delete set null,
  criado_em   timestamptz not null default now()
);

-- ------------------------------------------------------------
-- Eventos de segurança (login, falhas, exclusões). Nunca expostos ao cliente.
-- ------------------------------------------------------------
create table if not exists public.eventos_seguranca (
  id          bigserial primary key,
  perfil_id   uuid references public.perfis (id) on delete set null,
  tipo        text not null check (char_length(tipo) <= 40),
  detalhe     text not null default '' check (char_length(detalhe) <= 200),
  ip          inet,
  criado_em   timestamptz not null default now()
);

-- ------------------------------------------------------------
-- Índices
-- ------------------------------------------------------------
create index if not exists equipamentos_publicados_idx
  on public.equipamentos (publicado, tipo, diaria);
create index if not exists equipamentos_destaque_idx
  on public.equipamentos (destaque) where publicado;

do $$
declare
  v_schema text;
begin
  select n.nspname into v_schema
  from pg_extension e
  join pg_namespace n on n.oid = e.extnamespace
  where e.extname = 'pg_trgm';

  if v_schema is not null then
    execute format(
      'create index if not exists equipamentos_titulo_trgm_idx on public.equipamentos using gin (titulo %I.gin_trgm_ops)',
      v_schema
    );
    execute format(
      'create index if not exists equipamentos_descricao_trgm_idx on public.equipamentos using gin (descricao %I.gin_trgm_ops)',
      v_schema
    );
  end if;
end $$;

create index if not exists reservas_cliente_idx on public.reservas (cliente_id, data desc);
create index if not exists reservas_data_idx on public.reservas (data desc);
create index if not exists reservas_status_idx on public.reservas (status) where status = 'confirmada';
create index if not exists reservas_equipamento_idx on public.reservas (equipamento_id);

create index if not exists reserva_eventos_reserva_idx on public.reserva_eventos (reserva_id, criado_em);
create index if not exists eventos_seguranca_criado_idx on public.eventos_seguranca (criado_em desc);
create index if not exists eventos_seguranca_perfil_idx on public.eventos_seguranca (perfil_id, criado_em desc);

-- ------------------------------------------------------------
-- atualizado_em automático
-- ------------------------------------------------------------
create or replace function public.tocar_atualizado_em()
returns trigger
language plpgsql
as $$
begin
  new.atualizado_em := now();
  return new;
end;
$$;

drop trigger if exists perfis_atualizado_em on public.perfis;
create trigger perfis_atualizado_em
  before update on public.perfis
  for each row execute function public.tocar_atualizado_em();

drop trigger if exists equipamentos_atualizado_em on public.equipamentos;
create trigger equipamentos_atualizado_em
  before update on public.equipamentos
  for each row execute function public.tocar_atualizado_em();

drop trigger if exists reservas_atualizado_em on public.reservas;
create trigger reservas_atualizado_em
  before update on public.reservas
  for each row execute function public.tocar_atualizado_em();

drop trigger if exists config_negocio_atualizado_em on public.config_negocio;
create trigger config_negocio_atualizado_em
  before update on public.config_negocio
  for each row execute function public.tocar_atualizado_em();

-- ------------------------------------------------------------
-- Todo usuário novo do Auth ganha um perfil (papel cliente por padrão).
-- ------------------------------------------------------------
create or replace function public.criar_perfil_para_novo_usuario()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.perfis (id, nome, email, telefone)
  values (
    new.id,
    left(coalesce(new.raw_user_meta_data ->> 'nome', ''), 80),
    left(coalesce(new.email, ''), 120),
    left(coalesce(new.raw_user_meta_data ->> 'telefone', ''), 20)
  )
  on conflict (id) do nothing;
  return new;
end;
$$;

drop trigger if exists ao_criar_usuario on auth.users;
create trigger ao_criar_usuario
  after insert on auth.users
  for each row execute function public.criar_perfil_para_novo_usuario();

commit;
