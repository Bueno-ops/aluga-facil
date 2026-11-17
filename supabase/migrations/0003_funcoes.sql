-- ============================================================
-- Aluga Fácil — 0003: funções de negócio (RPC)
-- Toda escrita sensível passa por aqui: o cliente não consegue
-- forjar preço, status, papel nem autoria.
-- ============================================================

begin;

-- ------------------------------------------------------------
-- Utilitário interno: registra evento de segurança.
-- Sem GRANT para clientes: só as funções abaixo usam.
-- ------------------------------------------------------------
create or replace function public.registrar_evento_seguranca(
  p_perfil_id uuid,
  p_tipo text,
  p_detalhe text default ''
)
returns void
language sql
security definer
set search_path = ''
as $$
  insert into public.eventos_seguranca (perfil_id, tipo, detalhe)
  values (p_perfil_id, left(coalesce(p_tipo, 'evento'), 40), left(coalesce(p_detalhe, ''), 200));
$$;

revoke all on function public.registrar_evento_seguranca(uuid, text, text) from public, anon, authenticated;

-- ------------------------------------------------------------
-- Reservar: preço, frete, caução e total calculados no servidor.
-- ------------------------------------------------------------
create or replace function public.criar_reserva(
  p_equipamento_id text,
  p_data date,
  p_hora time,
  p_dias integer,
  p_nome text,
  p_telefone text
)
returns public.reservas
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_perfil public.perfis;
  v_eq public.equipamentos;
  v_nome text;
  v_telefone text;
  v_dias integer;
  v_frete numeric(12, 2);
  v_ativas integer;
  v_recentes integer;
  -- Brasil não usa horário de verão desde 2019: UTC-3 o ano todo.
  v_hoje date := ((now() at time zone 'UTC') - interval '3 hours')::date;
  v_reserva public.reservas;
begin
  if v_uid is null then
    raise exception 'Entre na sua conta para reservar.' using errcode = '28000';
  end if;

  select * into v_perfil from public.perfis where id = v_uid;
  if not found or not v_perfil.ativo then
    raise exception 'Conta inativa ou não encontrada.' using errcode = '28000';
  end if;

  select * into v_eq
  from public.equipamentos
  where id = p_equipamento_id and publicado;
  if not found then
    raise exception 'Equipamento indisponível para reserva.' using errcode = 'P0002';
  end if;

  if p_data is null or p_data < v_hoje then
    raise exception 'Escolha uma data a partir de hoje.' using errcode = '22007';
  end if;
  if p_data > v_hoje + 365 then
    raise exception 'Data muito distante. Reserve com até 1 ano de antecedência.' using errcode = '22007';
  end if;
  if p_hora is null then
    raise exception 'Escolha um horário válido.' using errcode = '22007';
  end if;

  v_dias := greatest(1, least(coalesce(p_dias, 1), 60));

  v_nome := btrim(regexp_replace(coalesce(p_nome, ''), '\s+', ' ', 'g'));
  if char_length(v_nome) < 3 then
    raise exception 'Informe seu nome completo.' using errcode = '22023';
  end if;

  v_telefone := btrim(coalesce(p_telefone, ''));
  if char_length(regexp_replace(v_telefone, '\D', '', 'g')) < 10 then
    raise exception 'Informe um WhatsApp com DDD.' using errcode = '22023';
  end if;

  if exists (
    select 1 from public.reservas r
    where r.cliente_id = v_uid
      and r.equipamento_id = v_eq.id
      and r.data = p_data
      and r.hora = p_hora
      and r.status <> 'cancelada'
  ) then
    raise exception 'Você já tem uma reserva dessa máquina nesse horário.' using errcode = '23505';
  end if;

  select count(*) into v_ativas
  from public.reservas r
  where r.cliente_id = v_uid and r.status = 'confirmada' and r.data >= v_hoje;
  if v_ativas >= 5 then
    raise exception 'Limite de 5 reservas ativas. Cancele uma para continuar.' using errcode = '54000';
  end if;

  select count(*) into v_recentes
  from public.reservas r
  where r.cliente_id = v_uid and r.criado_em > now() - interval '24 hours';
  if v_recentes >= 10 then
    raise exception 'Muitas reservas em pouco tempo. Tente novamente mais tarde.' using errcode = '54000';
  end if;

  v_frete := case when v_eq.entrega then v_eq.frete else 0 end;

  insert into public.reservas (
    id, equipamento_id, cliente_id, titulo, tipo, cidade, uf, data, hora,
    nome, telefone, dias, diaria, frete, caucao, total,
    status, entrega_status, entrega_duracao_min, entrega_entregador,
    entrega_atualizado_em, criado_em, atualizado_em
  ) values (
    'r-' || replace(gen_random_uuid()::text, '-', ''),
    v_eq.id, v_uid, v_eq.titulo, v_eq.tipo, v_eq.cidade, v_eq.uf, p_data, p_hora,
    v_nome, v_telefone, v_dias, v_eq.diaria, v_frete, v_eq.caucao,
    (v_eq.diaria * v_dias) + v_frete,
    'confirmada', 'preparando', 30, 'Equipe Aluga Fácil',
    now(), now(), now()
  )
  returning * into v_reserva;

  insert into public.reserva_eventos (reserva_id, tipo, detalhe, autor_id)
  values (v_reserva.id, 'criada', 'Reserva criada pelo cliente', v_uid);

  return v_reserva;
end;
$$;

revoke all on function public.criar_reserva(text, date, time, integer, text, text) from public, anon;
grant execute on function public.criar_reserva(text, date, time, integer, text, text) to authenticated;

-- ------------------------------------------------------------
-- Cancelar: o próprio cliente ou a equipe.
-- ------------------------------------------------------------
create or replace function public.cancelar_reserva(p_id text)
returns public.reservas
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_reserva public.reservas;
begin
  if v_uid is null then
    raise exception 'Entre na sua conta para continuar.' using errcode = '28000';
  end if;

  select * into v_reserva from public.reservas where id = p_id for update;
  if not found then
    raise exception 'Reserva não encontrada.' using errcode = 'P0002';
  end if;
  if v_reserva.cliente_id <> v_uid and not public.eh_equipe() then
    raise exception 'Esta reserva não é da sua conta.' using errcode = '42501';
  end if;
  if v_reserva.status <> 'confirmada' then
    raise exception 'Só é possível cancelar reservas confirmadas.' using errcode = '22023';
  end if;

  update public.reservas
     set status = 'cancelada',
         atualizado_em = now()
   where id = p_id
  returning * into v_reserva;

  insert into public.reserva_eventos (reserva_id, tipo, detalhe, autor_id)
  values (p_id, 'cancelada', 'Reserva cancelada', v_uid);

  return v_reserva;
end;
$$;

revoke all on function public.cancelar_reserva(text) from public, anon;
grant execute on function public.cancelar_reserva(text) to authenticated;

-- ------------------------------------------------------------
-- Rastreamento da entrega: somente equipe.
-- ------------------------------------------------------------
create or replace function public.atualizar_entrega(
  p_id text,
  p_status text,
  p_entregador text default null,
  p_duracao_min integer default null
)
returns public.reservas
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_reserva public.reservas;
  v_status public.status_entrega;
begin
  if not public.eh_equipe() then
    raise exception 'Apenas a equipe da loja atualiza a entrega.' using errcode = '42501';
  end if;

  if p_status is null or p_status not in ('preparando', 'saiu', 'em_transito', 'entregue') then
    raise exception 'Status de entrega inválido.' using errcode = '22023';
  end if;
  v_status := p_status::public.status_entrega;

  select * into v_reserva from public.reservas where id = p_id for update;
  if not found then
    raise exception 'Reserva não encontrada.' using errcode = 'P0002';
  end if;

  update public.reservas
     set entrega_status = v_status,
         entrega_saiu_em = case
           when v_status = 'preparando' then null
           when v_status in ('saiu', 'em_transito', 'entregue') then coalesce(entrega_saiu_em, now())
           else entrega_saiu_em
         end,
         entrega_inicio = case
           when v_status = 'preparando' then null
           when v_status in ('em_transito', 'entregue') then coalesce(entrega_inicio, now())
           else entrega_inicio
         end,
         entrega_concluida_em = case
           when v_status = 'entregue' then coalesce(entrega_concluida_em, now())
           else null
         end,
         entrega_confirmada_pelo_cliente = case
           when v_status = 'entregue' then entrega_confirmada_pelo_cliente
           else false
         end,
         entrega_entregador = coalesce(nullif(btrim(coalesce(p_entregador, '')), ''), entrega_entregador),
         entrega_duracao_min = case
           when p_duracao_min is null then entrega_duracao_min
           else least(greatest(p_duracao_min, 5), 1440)
         end,
         entrega_atualizado_em = now(),
         atualizado_em = now()
   where id = p_id
  returning * into v_reserva;

  insert into public.reserva_eventos (reserva_id, tipo, detalhe, autor_id)
  values (p_id, 'entrega_' || v_status::text, 'Entrega atualizada para ' || v_status::text, v_uid);

  return v_reserva;
end;
$$;

revoke all on function public.atualizar_entrega(text, text, text, integer) from public, anon;
grant execute on function public.atualizar_entrega(text, text, text, integer) to authenticated;

-- ------------------------------------------------------------
-- Cliente confirma que recebeu o equipamento.
-- ------------------------------------------------------------
create or replace function public.confirmar_recebimento(p_id text)
returns public.reservas
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_reserva public.reservas;
begin
  if v_uid is null then
    raise exception 'Entre na sua conta para continuar.' using errcode = '28000';
  end if;

  select * into v_reserva from public.reservas where id = p_id for update;
  if not found then
    raise exception 'Reserva não encontrada.' using errcode = 'P0002';
  end if;
  if v_reserva.cliente_id <> v_uid then
    raise exception 'Esta reserva não é da sua conta.' using errcode = '42501';
  end if;
  if v_reserva.status <> 'confirmada' then
    raise exception 'Reserva não está ativa.' using errcode = '22023';
  end if;

  update public.reservas
     set entrega_status = 'entregue',
         entrega_saiu_em = coalesce(entrega_saiu_em, now()),
         entrega_inicio = coalesce(entrega_inicio, now()),
         entrega_concluida_em = coalesce(entrega_concluida_em, now()),
         entrega_confirmada_pelo_cliente = true,
         entrega_atualizado_em = now(),
         atualizado_em = now()
   where id = p_id
  returning * into v_reserva;

  insert into public.reserva_eventos (reserva_id, tipo, detalhe, autor_id)
  values (p_id, 'recebimento_confirmado', 'Cliente confirmou o recebimento', v_uid);

  return v_reserva;
end;
$$;

revoke all on function public.confirmar_recebimento(text) from public, anon;
grant execute on function public.confirmar_recebimento(text) to authenticated;

-- ------------------------------------------------------------
-- Equipe conclui a reserva (equipamento devolvido).
-- ------------------------------------------------------------
create or replace function public.concluir_reserva(p_id text)
returns public.reservas
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_reserva public.reservas;
begin
  if not public.eh_equipe() then
    raise exception 'Apenas a equipe da loja conclui reservas.' using errcode = '42501';
  end if;

  select * into v_reserva from public.reservas where id = p_id for update;
  if not found then
    raise exception 'Reserva não encontrada.' using errcode = 'P0002';
  end if;
  if v_reserva.status <> 'confirmada' then
    raise exception 'Só é possível concluir reservas confirmadas.' using errcode = '22023';
  end if;

  update public.reservas
     set status = 'concluida',
         atualizado_em = now()
   where id = p_id
  returning * into v_reserva;

  insert into public.reserva_eventos (reserva_id, tipo, detalhe, autor_id)
  values (p_id, 'concluida', 'Reserva concluída pela loja', v_uid);

  return v_reserva;
end;
$$;

revoke all on function public.concluir_reserva(text) from public, anon;
grant execute on function public.concluir_reserva(text) to authenticated;

-- ------------------------------------------------------------
-- Venda manual registrada pela equipe (balcão).
-- ------------------------------------------------------------
create or replace function public.registrar_venda(
  p_equipamento_id text,
  p_nome text,
  p_data date,
  p_dias integer,
  p_concluida boolean default false
)
returns public.reservas
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_eq public.equipamentos;
  v_nome text;
  v_dias integer;
  v_frete numeric(12, 2);
  v_reserva public.reservas;
begin
  if not public.eh_equipe() then
    raise exception 'Apenas a loja registra vendas.' using errcode = '42501';
  end if;

  select * into v_eq from public.equipamentos where id = p_equipamento_id and publicado;
  if not found then
    raise exception 'Escolha uma máquina válida.' using errcode = 'P0002';
  end if;

  v_nome := btrim(regexp_replace(coalesce(p_nome, ''), '\s+', ' ', 'g'));
  if char_length(v_nome) < 2 then
    raise exception 'Informe o nome do cliente.' using errcode = '22023';
  end if;
  if p_data is null then
    raise exception 'Informe uma data válida.' using errcode = '22007';
  end if;

  v_dias := greatest(1, least(coalesce(p_dias, 1), 60));
  v_frete := case when v_eq.entrega then v_eq.frete else 0 end;

  insert into public.reservas (
    id, equipamento_id, cliente_id, titulo, tipo, cidade, uf, data, hora,
    nome, telefone, dias, diaria, frete, caucao, total,
    status, entrega_status, entrega_duracao_min, entrega_entregador,
    entrega_atualizado_em, manual, criado_em, atualizado_em
  ) values (
    'venda-' || replace(gen_random_uuid()::text, '-', ''),
    v_eq.id, null, v_eq.titulo, v_eq.tipo, v_eq.cidade, v_eq.uf, p_data, '09:00',
    v_nome, '', v_dias, v_eq.diaria, v_frete, v_eq.caucao,
    (v_eq.diaria * v_dias) + v_frete,
    case when p_concluida then 'concluida' else 'confirmada' end,
    'preparando', 30, 'Equipe Aluga Fácil',
    now(), true, now(), now()
  )
  returning * into v_reserva;

  insert into public.reserva_eventos (reserva_id, tipo, detalhe, autor_id)
  values (v_reserva.id, 'venda_registrada', 'Venda registrada no balcão', v_uid);

  return v_reserva;
end;
$$;

revoke all on function public.registrar_venda(text, text, date, integer, boolean) from public, anon;
grant execute on function public.registrar_venda(text, text, date, integer, boolean) to authenticated;

-- ------------------------------------------------------------
-- Anúncios: só o admin publica e remove.
-- ------------------------------------------------------------
create or replace function public.publicar_anuncio(p_dados jsonb)
returns public.equipamentos
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_titulo text;
  v_tipo text;
  v_diaria numeric(12, 2);
  v_uf text;
  v_acessorios text[];
  v_config public.config_negocio;
  v_eq public.equipamentos;
  v_permitidos text[] := array[
    'Jogo de brocas', 'Ponteiro e cinzel', 'Extensão elétrica', 'Pé e enxada',
    'Plataforma', 'Rodízios', 'Protetor auricular', 'Mangueira 10 m',
    'Bico pulverizador', 'Disco de corte', 'Maleta de transporte', 'Manual de uso'
  ];
begin
  if not public.eh_admin() then
    raise exception 'Apenas o administrador publica anúncios.' using errcode = '42501';
  end if;

  v_titulo := btrim(regexp_replace(coalesce(p_dados ->> 'titulo', ''), '\s+', ' ', 'g'));
  if char_length(v_titulo) < 3 then
    raise exception 'Informe um título com pelo menos 3 caracteres.' using errcode = '22023';
  end if;

  v_tipo := coalesce(p_dados ->> 'tipo', 'outros');
  if v_tipo not in ('acesso-elevacao', 'andaimes', 'compactacao', 'concretagem',
                    'ferramentas-eletricas', 'furacao-demolicao', 'jardinagem',
                    'limpeza', 'motores', 'outros') then
    v_tipo := 'outros';
  end if;

  v_diaria := coalesce((p_dados ->> 'diaria')::numeric, 0);
  if v_diaria <= 0 or v_diaria > 1000000 then
    raise exception 'Informe uma diária válida.' using errcode = '22023';
  end if;

  v_uf := upper(coalesce(p_dados ->> 'uf', ''));
  if v_uf <> '' and v_uf not in ('AC','AL','AP','AM','BA','CE','DF','ES','GO','MA','MT','MS','MG',
                                 'PA','PB','PR','PE','PI','RJ','RN','RS','RO','RR','SC','SP','SE','TO') then
    v_uf := '';
  end if;

  select array_agg(a order by a) into v_acessorios
  from jsonb_array_elements_text(coalesce(p_dados -> 'acessorios', '[]'::jsonb)) a
  where a = any (v_permitidos);

  select * into v_config from public.config_negocio where id = 1;

  insert into public.equipamentos (
    id, titulo, tipo, cidade, uf, bairro, diaria, frete, caucao,
    energia, potencia, peso, entrega, destaque, descricao, acessorios,
    anunciante_nome, anunciante_telefone, origem, publicado, criado_por
  ) values (
    'meu-' || substr(replace(gen_random_uuid()::text, '-', ''), 1, 12),
    left(v_titulo, 120),
    v_tipo,
    left(coalesce(p_dados ->> 'cidade', ''), 60),
    v_uf,
    left(coalesce(p_dados ->> 'bairro', ''), 60),
    v_diaria,
    greatest(0, least(coalesce((p_dados ->> 'frete')::numeric, 0), 1000000)),
    greatest(0, least(coalesce((p_dados ->> 'caucao')::numeric, 0), 1000000)),
    case when coalesce(p_dados ->> 'energia', '') in ('110v', '220v', 'gasolina', 'bateria', 'pneumatico', 'manual')
         then p_dados ->> 'energia' else '' end,
    left(coalesce(p_dados ->> 'potencia', ''), 40),
    greatest(0, least(coalesce((p_dados ->> 'peso')::numeric, 0), 100000)),
    coalesce(
      case lower(coalesce(p_dados ->> 'entrega', 'true'))
        when 'true' then true when '1' then true when 'sim' then true when 'on' then true
        else false
      end,
      true
    ),
    coalesce((p_dados ->> 'destaque')::boolean, false),
    left(coalesce(p_dados ->> 'descricao', ''), 1200),
    coalesce(v_acessorios, '{}'::text[]),
    coalesce(nullif(left(v_config.empresa, 80), ''), 'Aluga Fácil'),
    coalesce(nullif(left(v_config.whatsapp, 20), ''), '5553991066321'),
    'anuncio', true, v_uid
  )
  returning * into v_eq;

  perform public.registrar_evento_seguranca(v_uid, 'anuncio_publicado', v_eq.id);

  return v_eq;
end;
$$;

revoke all on function public.publicar_anuncio(jsonb) from public, anon;
grant execute on function public.publicar_anuncio(jsonb) to authenticated;

create or replace function public.remover_anuncio(p_id text)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_eq public.equipamentos;
  v_tem_reserva boolean;
begin
  if not public.eh_admin() then
    raise exception 'Apenas o administrador remove anúncios.' using errcode = '42501';
  end if;

  select * into v_eq from public.equipamentos where id = p_id;
  if not found then
    raise exception 'Anúncio não encontrado.' using errcode = 'P0002';
  end if;
  if v_eq.origem <> 'anuncio' then
    raise exception 'Itens do catálogo não podem ser excluídos, apenas despublicados.' using errcode = '22023';
  end if;

  select exists (
    select 1 from public.reservas r
    where r.equipamento_id = p_id and r.status = 'confirmada'
  ) into v_tem_reserva;

  if v_tem_reserva then
    update public.equipamentos set publicado = false where id = p_id;
    perform public.registrar_evento_seguranca(v_uid, 'anuncio_despublicado', p_id);
    return 'despublicado';
  end if;

  delete from public.equipamentos where id = p_id;
  perform public.registrar_evento_seguranca(v_uid, 'anuncio_removido', p_id);
  return 'removido';
end;
$$;

revoke all on function public.remover_anuncio(text) from public, anon;
grant execute on function public.remover_anuncio(text) to authenticated;

-- ------------------------------------------------------------
-- Configuração do negócio (admin)
-- ------------------------------------------------------------
create or replace function public.salvar_config_negocio(
  p_empresa text,
  p_whatsapp text,
  p_custo_pct numeric
)
returns public.config_negocio
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_whatsapp text;
  v_config public.config_negocio;
begin
  if not public.eh_admin() then
    raise exception 'Apenas o administrador altera a configuração.' using errcode = '42501';
  end if;

  v_whatsapp := regexp_replace(coalesce(p_whatsapp, ''), '\D', '', 'g');
  if char_length(v_whatsapp) < 10 or char_length(v_whatsapp) > 15 then
    raise exception 'Informe o WhatsApp com DDI e DDD, só números.' using errcode = '22023';
  end if;

  update public.config_negocio
     set empresa = left(btrim(coalesce(p_empresa, 'Aluga Fácil')), 60),
         whatsapp = v_whatsapp,
         custo_pct = greatest(0, least(coalesce(p_custo_pct, 35), 100)),
         atualizado_em = now()
   where id = 1
  returning * into v_config;

  perform public.registrar_evento_seguranca(v_uid, 'config_alterada', 'config_negocio');
  return v_config;
end;
$$;

revoke all on function public.salvar_config_negocio(text, text, numeric) from public, anon;
grant execute on function public.salvar_config_negocio(text, text, numeric) to authenticated;

-- Somente a equipe lê o custo interno.
create or replace function public.config_equipe()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_config public.config_negocio;
begin
  if not public.eh_equipe() then
    raise exception 'Acesso restrito à equipe.' using errcode = '42501';
  end if;
  select * into v_config from public.config_negocio where id = 1;
  return jsonb_build_object(
    'empresa', v_config.empresa,
    'whatsapp', v_config.whatsapp,
    'custo_pct', v_config.custo_pct,
    'atualizado_em', v_config.atualizado_em
  );
end;
$$;

revoke all on function public.config_equipe() from public, anon;
grant execute on function public.config_equipe() to authenticated;

-- ------------------------------------------------------------
-- Gestão de contas (somente admin)
-- ------------------------------------------------------------
create or replace function public.definir_papel(p_perfil_id uuid, p_papel public.papel_usuario)
returns public.perfis
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_perfil public.perfis;
begin
  if not public.eh_admin() then
    raise exception 'Apenas o administrador altera papéis.' using errcode = '42501';
  end if;
  if p_perfil_id = v_uid then
    raise exception 'Você não pode alterar o seu próprio papel.' using errcode = '22023';
  end if;

  update public.perfis
     set papel = p_papel,
         ativo = case when p_papel = 'cliente' then ativo else true end
   where id = p_perfil_id
  returning * into v_perfil;

  if not found then
    raise exception 'Perfil não encontrado.' using errcode = 'P0002';
  end if;

  perform public.registrar_evento_seguranca(v_uid, 'papel_alterado', p_perfil_id::text || ' -> ' || p_papel::text);
  return v_perfil;
end;
$$;

revoke all on function public.definir_papel(uuid, public.papel_usuario) from public, anon;
grant execute on function public.definir_papel(uuid, public.papel_usuario) to authenticated;

create or replace function public.definir_ativo(p_perfil_id uuid, p_ativo boolean)
returns public.perfis
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_perfil public.perfis;
begin
  if not public.eh_admin() then
    raise exception 'Apenas o administrador ativa ou desativa contas.' using errcode = '42501';
  end if;
  if p_perfil_id = v_uid then
    raise exception 'Você não pode desativar a própria conta.' using errcode = '22023';
  end if;

  update public.perfis set ativo = coalesce(p_ativo, false)
   where id = p_perfil_id
  returning * into v_perfil;

  if not found then
    raise exception 'Perfil não encontrado.' using errcode = 'P0002';
  end if;

  perform public.registrar_evento_seguranca(v_uid, 'conta_ativada_ou_desativada',
    p_perfil_id::text || ' -> ' || coalesce(p_ativo, false)::text);
  return v_perfil;
end;
$$;

revoke all on function public.definir_ativo(uuid, boolean) from public, anon;
grant execute on function public.definir_ativo(uuid, boolean) to authenticated;

-- ------------------------------------------------------------
-- Promoção do primeiro administrador (uso único, via SQL Editor).
-- Sem GRANT: apenas o dono do banco (postgres/service_role) executa.
-- ------------------------------------------------------------
create or replace function public.promover_admin_por_email(p_email text)
returns public.perfis
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_perfil public.perfis;
begin
  update public.perfis
     set papel = 'admin', ativo = true
   where lower(email) = lower(btrim(p_email))
  returning * into v_perfil;

  if not found then
    raise exception 'Nenhum perfil com o e-mail %. Crie o usuário no Auth primeiro.', p_email;
  end if;
  return v_perfil;
end;
$$;

revoke all on function public.promover_admin_por_email(text) from public, anon, authenticated;

commit;
