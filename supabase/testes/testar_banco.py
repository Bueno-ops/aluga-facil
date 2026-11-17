"""Teste de integração do esquema Aluga Fácil em PostgreSQL real.

Sobe um PostgreSQL embutido, cria os stubs do Supabase (auth.users, auth.uid,
roles anon/authenticated), aplica as migrações + seed e exercita RLS e RPCs
como cada tipo de usuário.
"""

import glob
import os
import sys
import tempfile
import traceback
import uuid
from pathlib import Path

import pgserver
import psycopg

# Raiz do repositório (duas pastas acima de supabase/testes).
BASE = str(Path(__file__).resolve().parents[2])
MIGRACOES = sorted(glob.glob(os.path.join(BASE, "supabase", "migrations", "*.sql")))
SEED = os.path.join(BASE, "supabase", "seed.sql")

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")

resultados = []


def ok(nome, condicao, detalhe=""):
    resultados.append((bool(condicao), nome, detalhe))
    print(("PASS " if condicao else "FAIL ") + nome + ((" | " + str(detalhe)) if detalhe else ""))


def erro(cur, sql, params=None):
    try:
        cur.execute(sql, params)
        return None
    except Exception as exc:  # noqa: BLE001
        return exc


def main():
    pasta = tempfile.mkdtemp(prefix="pg_aluga_")
    db = pgserver.get_server(pasta)
    conn = psycopg.connect(db.get_uri(), autocommit=True)
    cur = conn.cursor()

    # ---------- stubs do ambiente Supabase ----------
    cur.execute(
        """
        create schema auth;
        create table auth.users (
          id uuid primary key,
          email text,
          raw_user_meta_data jsonb not null default '{}'::jsonb
        );
        create or replace function auth.uid() returns uuid
          language sql stable
          as $$ select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid $$;
        create role anon nologin;
        create role authenticated nologin;
        grant usage on schema auth to anon, authenticated;
        """
    )

    for arquivo in MIGRACOES + [SEED]:
        with open(arquivo, encoding="utf-8") as fh:
            cur.execute(fh.read())
        print("aplicado:", os.path.basename(arquivo))

    # ---------- utilidades ----------
    def como(papel, uid=None):
        cur.execute("reset role")
        cur.execute(f"set role {papel}")
        cur.execute("select set_config('request.jwt.claim.sub', %s, false)", (str(uid) if uid else "",))

    def um(sql, params=None):
        cur.execute(sql, params)
        return cur.fetchone()

    def todos(sql, params=None):
        cur.execute(sql, params)
        return cur.fetchall()

    # ---------- usuários ----------
    dono = str(uuid.uuid4())
    gerente = str(uuid.uuid4())
    alice = str(uuid.uuid4())
    bob = str(uuid.uuid4())
    for uid, email, nome in [
        (dono, "dono@alugafacil.test", "Dono"),
        (gerente, "gerente@alugafacil.test", "Gerente"),
        (alice, "alice@teste.test", "Alice Souza"),
        (bob, "bob@teste.test", "Bob Lima"),
    ]:
        cur.execute(
            "insert into auth.users (id, email, raw_user_meta_data) values (%s, %s, %s)",
            (uid, email, '{"nome": "%s", "telefone": "(53) 99999-0000"}' % nome),
        )

    ok("trigger cria perfil para novo usuário", um("select count(*) from public.perfis")[0] == 4)
    ok("perfil novo nasce como cliente", um("select papel::text from public.perfis where id = %s", (alice,))[0] == "cliente")

    cur.execute("update public.perfis set papel = 'admin' where id = %s", (dono,))
    cur.execute("update public.perfis set papel = 'gerente' where id = %s", (gerente,))

    # ---------- anônimo ----------
    como("anon")
    ok("anônimo lê o catálogo completo", um("select count(*) from public.equipamentos where publicado")[0] == 167)
    ok("anônimo lê empresa/whatsapp", um("select empresa, whatsapp from public.config_negocio") == ("Aluga Fácil", "5553991066321"))
    ok("anônimo NÃO lê custo interno", erro(cur, "select custo_pct from public.config_negocio") is not None)
    ok("anônimo NÃO lê reservas", erro(cur, "select * from public.reservas") is not None)
    ok("anônimo NÃO publica anúncio", erro(cur, "select public.publicar_anuncio('{}'::jsonb)") is not None)

    # ---------- cliente Alice ----------
    como("authenticated", alice)
    ok("cliente lê o próprio perfil", um("select count(*) from public.perfis")[0] == 1)
    ok("cliente não vê perfil dos outros", um("select count(*) from public.perfis where id <> %s", (alice,))[0] == 0)

    cur.execute(
        "select id, diaria, frete, caucao, total, status::text, entrega_status::text "
        "from public.criar_reserva('c1', current_date + 1, '09:00', 2, 'Alice Souza', '(53) 99999-1111')"
    )
    reserva = cur.fetchone()
    ok("cliente cria reserva", reserva is not None)
    rid = reserva[0]
    ok("preço calculado no servidor", float(reserva[4]) == 550 * 2 + 150, reserva[1:5])
    ok("reserva nasce confirmada e preparando", reserva[5:] == ("confirmada", "preparando"), reserva[5:])
    ok("id de reserva compatível com o app", rid.startswith("r-") and len(rid) <= 64, rid)

    ok("cliente não insere reserva direto", erro(cur, "insert into public.reservas (id, equipamento_id, data, dias, diaria, total) values ('x1','c1',current_date,1,1,1)") is not None)
    ok("cliente não altera status direto", erro(cur, "update public.reservas set total = 1 where id = %s", (rid,)) is not None)

    duplicada = erro(cur, "select public.criar_reserva('c1', current_date + 1, '09:00', 1, 'Alice', '(53) 99999-1111')")
    ok("bloqueia reserva duplicada no mesmo horário", duplicada is not None and getattr(duplicada, "sqlstate", "") == "23505", duplicada)

    ok("cliente não atualiza entrega", erro(cur, "select public.atualizar_entrega(%s, 'saiu')", (rid,)) is not None)
    ok("cliente não publica anúncio", erro(cur, "select public.publicar_anuncio('{\"titulo\":\"Teste\",\"diaria\":10}'::jsonb)") is not None)

    # ---------- cliente Bob ----------
    como("authenticated", bob)
    ok("outro cliente não vê a reserva da Alice", um("select count(*) from public.reservas")[0] == 0)
    ok("outro cliente não cancela reserva alheia", erro(cur, "select public.cancelar_reserva(%s)", (rid,)) is not None)
    ok("outro cliente não confirma recebimento alheio", erro(cur, "select public.confirmar_recebimento(%s)", (rid,)) is not None)

    # ---------- favoritos ----------
    cur.execute("insert into public.favoritos (perfil_id, equipamento_id) values (%s, 'c1')", (bob,))
    ok("cliente favorita item", um("select count(*) from public.favoritos")[0] == 1)
    ok("cliente não cria favorito em nome de outro", erro(cur, "insert into public.favoritos (perfil_id, equipamento_id) values (%s, 'c2')", (alice,)) is not None)

    # ---------- perfil ----------
    ok("cliente não se promove a admin", erro(cur, "update public.perfis set papel = 'admin' where id = %s", (bob,)) is not None)
    ok("cliente não se reativa se inativo", erro(cur, "update public.perfis set ativo = true where id = %s", (bob,)) is not None)
    cur.execute("update public.perfis set nome = 'Bob Lima Jr' where id = %s", (bob,))
    ok("cliente edita o próprio nome", um("select nome from public.perfis where id = %s", (bob,))[0] == "Bob Lima Jr")

    # ---------- equipe ----------
    como("authenticated", gerente)
    ok("gerente vê todas as reservas", um("select count(*) from public.reservas")[0] == 1)
    ok("gerente vê todos os perfis", um("select count(*) from public.perfis")[0] == 4)
    cur.execute("select entrega_status::text, entrega_saiu_em from public.atualizar_entrega(%s, 'saiu', 'Carlos', 45)", (rid,))
    e = cur.fetchone()
    ok("gerente marca entrega como saiu", e[0] == "saiu" and e[1] is not None, e)
    ok("gerente não altera configuração", erro(cur, "select public.salvar_config_negocio('X','5553991066321',10)") is not None)
    ok("gerente lê custo interno", um("select (public.config_equipe() ->> 'custo_pct')::numeric")[0] == 35)
    ok("gerente não altera papéis", erro(cur, "select public.definir_papel(%s, 'admin')", (bob,)) is not None)

    # ---------- cliente confirma recebimento ----------
    como("authenticated", alice)
    cur.execute("select entrega_status::text, entrega_confirmada_pelo_cliente from public.confirmar_recebimento(%s)", (rid,))
    c = cur.fetchone()
    ok("cliente confirma recebimento", c == ("entregue", True), c)
    ok("cliente vê a própria linha do tempo", um("select count(*) from public.reserva_eventos where reserva_id = %s", (rid,))[0] >= 3)

    # ---------- cancelamento ----------
    cur.execute("select id from public.criar_reserva('c2', current_date + 3, '10:00', 1, 'Alice Souza', '(53) 99999-1111')")
    rid2 = cur.fetchone()[0]
    cur.execute("select status::text from public.cancelar_reserva(%s)", (rid2,))
    ok("cliente cancela a própria reserva", cur.fetchone()[0] == "cancelada")
    ok("não cancela duas vezes", erro(cur, "select public.cancelar_reserva(%s)", (rid2,)) is not None)

    # ---------- admin ----------
    como("authenticated", dono)
    cur.execute(
        "select id, origem::text, anunciante_nome, anunciante_telefone, acessorios "
        "from public.publicar_anuncio(%s::jsonb)",
        (
            '{"titulo":"Betoneira 400L","tipo":"concretagem","cidade":"Pelotas","uf":"RS","bairro":"Centro",'
            '"diaria":120,"frete":50,"caucao":300,"energia":"220v","potencia":"1.500 W","peso":120,'
            '"entrega":true,"descricao":"Betoneira revisada.","acessorios":["Manual de uso","Item inventado"]}',
        ),
    )
    anuncio = cur.fetchone()
    ok("admin publica anúncio", anuncio is not None and anuncio[1] == "anuncio", anuncio[:4])
    ok("anúncio usa contato da configuração", anuncio[2:4] == ("Aluga Fácil", "5553991066321"), anuncio[2:4])
    ok("acessórios fora da lista são descartados", anuncio[4] == ["Manual de uso"], anuncio[4])
    aid = anuncio[0]
    ok("anúncio aparece no catálogo público", um("select count(*) from public.equipamentos where id = %s and publicado", (aid,))[0] == 1)

    ok("admin não exclui item do catálogo", erro(cur, "select public.remover_anuncio('c1')") is not None)
    cur.execute("select public.remover_anuncio(%s)", (aid,))
    ok("admin remove anúncio sem reservas", cur.fetchone()[0] == "removido")

    ok("admin não altera o próprio papel", erro(cur, "select public.definir_papel(%s, 'cliente')", (dono,)) is not None)
    cur.execute("select papel::text from public.definir_papel(%s, 'gerente')", (bob,))
    ok("admin promove cliente a gerente", cur.fetchone()[0] == "gerente")

    ok("admin não salva WhatsApp inválido", erro(cur, "select public.salvar_config_negocio('Aluga Fácil','123',35)") is not None)
    cur.execute("select empresa, whatsapp from public.salvar_config_negocio('Aluga Fácil','5553991066321',40)")
    ok("admin salva configuração", cur.fetchone() == ("Aluga Fácil", "5553991066321"))

    # ---------- despublicar item com reserva ativa ----------
    cur.execute(
        "select id from public.publicar_anuncio('{\"titulo\":\"Compactador 90kg\",\"tipo\":\"compactacao\",\"diaria\":90,\"entrega\":true,\"frete\":25}'::jsonb)"
    )
    aid2 = cur.fetchone()[0]
    como("authenticated", alice)
    cur.execute("select public.criar_reserva(%s, current_date + 5, '08:00', 1, 'Alice Souza', '(53) 99999-1111')", (aid2,))
    como("authenticated", dono)
    cur.execute("select public.remover_anuncio(%s)", (aid2,))
    ok("anúncio com reserva ativa é despublicado, não apagado", cur.fetchone()[0] == "despublicado")
    como("anon")
    ok("anúncio despublicado some do catálogo público", um("select count(*) from public.equipamentos where id = %s", (aid2,))[0] == 0)
    como("authenticated", dono)
    ok("equipe ainda vê o anúncio despublicado", um("select count(*) from public.equipamentos where id = %s", (aid2,))[0] == 1)

    # ---------- conta desativada ----------
    cur.execute("select ativo from public.definir_ativo(%s, false)", (bob,))
    ok("admin desativa conta", cur.fetchone()[0] is False)
    como("authenticated", bob)
    ok("conta desativada não reserva", erro(cur, "select public.criar_reserva('c3', current_date + 7, '09:00', 1, 'Bob Lima', '(53) 99999-2222')") is not None)
    como("authenticated", dono)
    cur.execute("select ativo from public.definir_ativo(%s, true)", (bob,))
    ok("admin reativa conta", cur.fetchone()[0] is True)

    ok("catálogo do seed segue com 167 itens", um("select count(*) from public.equipamentos where origem = 'catalogo'")[0] == 167)

    # ---------- RLS em eventos ----------
    como("authenticated", alice)
    ok("cliente não lê eventos de segurança", erro(cur, "select * from public.eventos_seguranca") is not None)

    como("authenticated", dono)
    ok("admin não lê eventos direto (só via auditoria do banco)", erro(cur, "select * from public.eventos_seguranca") is not None)

    # ---------- resumo ----------
    falhas = [r for r in resultados if not r[0]]
    print("\n==== %d testes, %d falhas ====" % (len(resultados), len(falhas)))
    for _, nome, detalhe in falhas:
        print("FALHOU:", nome, detalhe)

    cur.close()
    conn.close()
    db.cleanup()
    return 1 if falhas else 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception:
        traceback.print_exc()
        raise SystemExit(2)
