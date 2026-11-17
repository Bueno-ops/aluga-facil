-- ============================================================
-- Aluga Fácil — 0002: RLS, permissões e políticas de acesso
-- Regra de ouro: o cliente só enxerga o que é dele; a equipe
-- (admin/gerente) enxerga a operação; só o admin publica anúncios
-- e mexe em contas/configuração.
-- ============================================================

begin;

-- ------------------------------------------------------------
-- Funções auxiliares de papel.
-- SECURITY DEFINER evita recursão de RLS ao consultar public.perfis.
-- ------------------------------------------------------------
create or replace function public.eh_admin()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.perfis p
    where p.id = auth.uid()
      and p.papel = 'admin'
      and p.ativo
  );
$$;

create or replace function public.eh_equipe()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.perfis p
    where p.id = auth.uid()
      and p.papel in ('admin', 'gerente')
      and p.ativo
  );
$$;

-- anon também executa: sem login as funções apenas retornam false.
revoke all on function public.eh_admin() from public;
revoke all on function public.eh_equipe() from public;
grant execute on function public.eh_admin() to anon, authenticated;
grant execute on function public.eh_equipe() to anon, authenticated;

-- ------------------------------------------------------------
-- Ativa RLS em tudo
-- ------------------------------------------------------------
alter table public.perfis            enable row level security;
alter table public.equipamentos      enable row level security;
alter table public.reservas          enable row level security;
alter table public.favoritos         enable row level security;
alter table public.config_negocio    enable row level security;
alter table public.reserva_eventos   enable row level security;
alter table public.eventos_seguranca enable row level security;

-- ------------------------------------------------------------
-- Limpa permissões herdadas e concede o mínimo necessário.
-- Sem GRANT, nem RLS ajuda: o PostgREST nem enxerga a tabela.
-- ------------------------------------------------------------
revoke all on public.perfis, public.equipamentos, public.reservas, public.favoritos,
              public.config_negocio, public.reserva_eventos, public.eventos_seguranca
  from anon, authenticated;

revoke all on sequence public.reserva_eventos_id_seq, public.eventos_seguranca_id_seq
  from anon, authenticated;

-- Catálogo é público (somente leitura).
grant select on public.equipamentos to anon, authenticated;

-- Configuração: o público vê apenas empresa e WhatsApp.
-- custo_pct fica de fora (indicador interno).
grant select (id, empresa, whatsapp, atualizado_em) on public.config_negocio to anon, authenticated;

-- Perfis: o usuário lê o próprio; a equipe lê todos.
grant select on public.perfis to authenticated;
grant update (nome, telefone, cidade, uf, tipo_pessoa, cnpj, nome_fantasia, empresa)
  on public.perfis to authenticated;

-- Reservas: leitura pela política; escrita só por RPC.
grant select on public.reservas to authenticated;

-- Favoritos: o dono gerencia os seus.
grant select, insert, delete on public.favoritos to authenticated;

-- Linha do tempo: leitura pela política; escrita só por RPC/trigger.
grant select on public.reserva_eventos to authenticated;

-- eventos_seguranca: nenhum acesso direto (nem select).

-- ------------------------------------------------------------
-- POLÍTICAS
-- ------------------------------------------------------------

-- perfis -----------------------------------------------------
drop policy if exists perfis_leitura on public.perfis;
create policy perfis_leitura on public.perfis
  for select to authenticated
  using (id = auth.uid() or public.eh_equipe());

drop policy if exists perfis_atualiza_proprio on public.perfis;
create policy perfis_atualiza_proprio on public.perfis
  for update to authenticated
  using (id = auth.uid())
  with check (id = auth.uid());

-- equipamentos ----------------------------------------------
drop policy if exists equipamentos_leitura_publica on public.equipamentos;
create policy equipamentos_leitura_publica on public.equipamentos
  for select to anon, authenticated
  using (publicado or public.eh_equipe());

drop policy if exists equipamentos_admin_insere on public.equipamentos;
create policy equipamentos_admin_insere on public.equipamentos
  for insert to authenticated
  with check (public.eh_admin());

drop policy if exists equipamentos_admin_atualiza on public.equipamentos;
create policy equipamentos_admin_atualiza on public.equipamentos
  for update to authenticated
  using (public.eh_admin())
  with check (public.eh_admin());

drop policy if exists equipamentos_admin_remove on public.equipamentos;
create policy equipamentos_admin_remove on public.equipamentos
  for delete to authenticated
  using (public.eh_admin());

-- reservas ---------------------------------------------------
drop policy if exists reservas_leitura on public.reservas;
create policy reservas_leitura on public.reservas
  for select to authenticated
  using (cliente_id = auth.uid() or public.eh_equipe());

-- favoritos --------------------------------------------------
drop policy if exists favoritos_dono on public.favoritos;
create policy favoritos_dono on public.favoritos
  for all to authenticated
  using (perfil_id = auth.uid())
  with check (perfil_id = auth.uid());

-- config_negocio ---------------------------------------------
drop policy if exists config_leitura on public.config_negocio;
create policy config_leitura on public.config_negocio
  for select to anon, authenticated
  using (true);

-- reserva_eventos --------------------------------------------
drop policy if exists reserva_eventos_leitura on public.reserva_eventos;
create policy reserva_eventos_leitura on public.reserva_eventos
  for select to authenticated
  using (
    public.eh_equipe()
    or exists (
      select 1 from public.reservas r
      where r.id = reserva_eventos.reserva_id
        and r.cliente_id = auth.uid()
    )
  );

-- eventos_seguranca: RLS sem nenhuma política = ninguém acessa direto.

commit;
