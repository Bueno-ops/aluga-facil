/* ============================================================
   Aluga Fácil — cliente da nuvem (Supabase sem SDK)

   Usa apenas fetch + PostgREST + Auth REST. A anon key é pública
   e a RLS do banco é quem decide o que cada pessoa pode ver.
   A service_role key nunca aparece aqui.

   Este arquivo NÃO muda o comportamento do app enquanto
   ALUGA_NUVEM_CONFIG estiver vazio.
   ============================================================ */
(function (global) {
  'use strict';

  var CONF = global.ALUGA_NUVEM_CONFIG || {};
  var BASE = String(CONF.url || '').replace(/\/+$/, '');
  var ANON = String(CONF.anonKey || '').trim();
  var CHAVE_SESSAO = 'aluga:nuvem:sessao';
  var CHAVE_CACHE = 'aluga:nuvem:cache';

  var catalogo = [];
  var reservasNuvem = [];
  var favoritosNuvem = [];
  var perfilAtual = null;
  var configAtual = null;

  function ErroNuvem(mensagem, codigo, offline) {
    this.name = 'ErroNuvem';
    this.message = String(mensagem || 'Não foi possível concluir. Tente novamente.').slice(0, 300);
    this.codigo = codigo || '';
    this.offline = !!offline;
  }
  ErroNuvem.prototype = Object.create(Error.prototype);
  ErroNuvem.prototype.constructor = ErroNuvem;

  function configurada() {
    return /^https:\/\/[a-z0-9.-]+\.supabase\.co$/i.test(BASE) && ANON.length >= 20;
  }

  function digits(valor) {
    return String(valor == null ? '' : valor).replace(/\D/g, '');
  }

  function texto(valor, maximo) {
    var limpo = String(valor == null ? '' : valor).replace(/\s+/g, ' ').trim();
    return maximo ? limpo.slice(0, maximo) : limpo;
  }

  function numero(valor) {
    var n = Number(valor);
    return isFinite(n) ? n : 0;
  }

  function dataISO(valor) {
    var s = String(valor || '').slice(0, 10);
    return /^\d{4}-\d{2}-\d{2}$/.test(s) ? s : '';
  }

  function horaCurta(valor) {
    var s = String(valor || '');
    return /^([01]\d|2[0-3]):[0-5]\d/.test(s) ? s.slice(0, 5) : '';
  }

  // O banco guarda o WhatsApp em dígitos (config_negocio.whatsapp).
  function telefoneExibicao(valor) {
    var d = digits(valor);
    if (/^55\d{11}$/.test(d)) d = d.slice(2);
    if (d.length === 11) return '(' + d.slice(0, 2) + ') ' + d.slice(2, 7) + '-' + d.slice(7);
    if (d.length === 10) return '(' + d.slice(0, 2) + ') ' + d.slice(2, 6) + '-' + d.slice(6);
    return String(valor || '');
  }

  function mensagemErro(erro) {
    if (!erro) return 'Não foi possível concluir. Tente novamente.';
    if (erro.offline || erro.codigo === 'offline') {
      return 'Sem conexão com a internet. Tente novamente quando voltar.';
    }
    var codigo = String(erro.codigo || '');
    var mapa = {
      '28000': 'Entre na sua conta para continuar.',
      '42501': 'Você não tem permissão para fazer isso.',
      'P0002': 'Item não encontrado ou indisponível.',
      '22007': 'Data ou horário inválido.',
      '22023': 'Revise os dados informados.',
      '23505': 'Já existe um registro com esses dados.',
      '23503': 'Não é possível excluir: há reservas ligadas a este item.',
      '54000': 'Limite atingido. Tente novamente mais tarde.'
    };
    if (mapa[codigo]) return mapa[codigo];
    var textoErro = String(erro.message || '');
    if (/JWT|expired|refresh token|session not found/i.test(textoErro)) {
      return 'Sua sessão expirou. Entre novamente.';
    }
    if (/duplicate key|já (existe|cadastrado)/i.test(textoErro)) return mapa['23505'];
    if (/fetch failed|network|Failed to fetch/i.test(textoErro)) {
      return 'Sem conexão com a internet. Tente novamente quando voltar.';
    }
    return textoErro || 'Não foi possível concluir. Tente novamente.';
  }

  function erroDeResposta(payload, fallback) {
    var obj = payload && typeof payload === 'object' ? payload : {};
    var codigo = String(obj.code || obj.error_code || obj.status || '');
    var msg = String(obj.msg || obj.message || obj.error_description || obj.error || fallback || '');
    return new ErroNuvem(msg, codigo, false);
  }

  /* ---------------- Sessão local do Auth ---------------- */
  function lerSessao() {
    try {
      var bruto = global.localStorage.getItem(CHAVE_SESSAO);
      var s = bruto ? JSON.parse(bruto) : null;
      if (!s || typeof s !== 'object' || !s.access_token) return null;
      return {
        access_token: String(s.access_token).slice(0, 4096),
        refresh_token: String(s.refresh_token || '').slice(0, 4096),
        expires_at: Number(s.expires_at) || 0,
        user: s.user && typeof s.user === 'object' ? s.user : null
      };
    } catch (e) {
      return null;
    }
  }

  function salvarSessao(sessao) {
    try {
      if (!sessao) global.localStorage.removeItem(CHAVE_SESSAO);
      else global.localStorage.setItem(CHAVE_SESSAO, JSON.stringify(sessao));
    } catch (e) { /* armazenamento indisponível: sessão só dura a aba */ }
  }

  function sessaoValida() {
    var s = lerSessao();
    if (!s) return null;
    if (!s.expires_at || s.expires_at > (Date.now() / 1000) + 60) return s;
    return null;
  }

  function idUsuario() {
    var s = lerSessao();
    return s && s.user && s.user.id ? String(s.user.id) : '';
  }

  function logado() {
    return !!lerSessao();
  }

  /* ---------------- Cache offline ---------------- */
  function lerCache() {
    try {
      return JSON.parse(global.localStorage.getItem(CHAVE_CACHE) || '{}') || {};
    } catch (e) {
      return {};
    }
  }

  function salvarCache(chave, valor) {
    try {
      var cache = lerCache();
      cache[chave] = valor;
      cache.salvoEm = new Date().toISOString();
      global.localStorage.setItem(CHAVE_CACHE, JSON.stringify(cache));
    } catch (e) { /* cache é otimização: sem espaço o app segue funcionando */ }
  }

  /* ---------------- Requisições ---------------- */
  function buscar(caminho, opcoes, tokenFixo) {
    opcoes = opcoes || {};
    if (!configurada()) {
      return Promise.reject(new ErroNuvem('Backend ainda não configurado neste aplicativo.'));
    }
    if (global.navigator && global.navigator.onLine === false) {
      return Promise.reject(new ErroNuvem('Sem conexão com a internet.', 'offline', true));
    }

    var s = tokenFixo ? null : sessaoValida();
    var token = tokenFixo || (s ? s.access_token : ANON);
    var headers = {
      'apikey': ANON,
      'Authorization': 'Bearer ' + token,
      'Accept': 'application/json'
    };
    if (opcoes.body !== undefined) headers['Content-Type'] = 'application/json';
    if (opcoes.prefer) headers['Prefer'] = opcoes.prefer;

    return fetch(BASE + caminho, {
      method: opcoes.method || 'GET',
      headers: headers,
      body: opcoes.body !== undefined ? JSON.stringify(opcoes.body) : undefined,
      cache: 'no-store'
    }).then(function (resposta) {
      return resposta.text().then(function (texto) {
        var dados = null;
        if (texto) {
          try { dados = JSON.parse(texto); } catch (e) { dados = null; }
        }
        if (!resposta.ok) throw erroDeResposta(dados, 'Não foi possível concluir. Tente novamente.');
        return dados;
      });
    }).catch(function (erro) {
      if (erro instanceof ErroNuvem) throw erro;
      throw new ErroNuvem('Sem conexão com a internet.', 'offline', true);
    });
  }

  function garantirSessao() {
    var s = lerSessao();
    if (!s) return Promise.resolve(null);
    if (!s.expires_at || s.expires_at > (Date.now() / 1000) + 60) return Promise.resolve(s);
    if (!s.refresh_token) {
      salvarSessao(null);
      perfilAtual = null;
      return Promise.resolve(null);
    }
    return buscar('/auth/v1/token?grant_type=refresh_token', {
      method: 'POST',
      body: { refresh_token: s.refresh_token }
    }).then(function (novos) {
      if (!novos || !novos.access_token) throw new Error('sem token');
      var sessao = {
        access_token: novos.access_token,
        refresh_token: novos.refresh_token || s.refresh_token,
        expires_at: Number(novos.expires_at) || 0,
        user: novos.user || s.user
      };
      salvarSessao(sessao);
      return sessao;
    }).catch(function () {
      salvarSessao(null);
      perfilAtual = null;
      return null;
    });
  }

  function requisitar(caminho, opcoes) {
    return garantirSessao().then(function () {
      return buscar(caminho, opcoes);
    });
  }

  function rpc(nome, parametros) {
    return requisitar('/rest/v1/rpc/' + encodeURIComponent(nome), {
      method: 'POST',
      body: parametros || {}
    });
  }

  /* ---------------- Mapeamento banco -> app ---------------- */
  function paraEquipamento(row) {
    if (!row || !row.id) return null;
    return {
      id: String(row.id),
      titulo: texto(row.titulo, 120),
      tipo: texto(row.tipo, 40) || 'outros',
      cidade: texto(row.cidade, 60),
      uf: String(row.uf || '').toUpperCase().slice(0, 2),
      bairro: texto(row.bairro, 60),
      diaria: numero(row.diaria),
      frete: numero(row.frete),
      caucao: numero(row.caucao),
      energia: texto(row.energia, 20),
      potencia: texto(row.potencia, 40),
      peso: numero(row.peso),
      entrega: row.entrega !== false,
      destaque: row.destaque === true,
      descricao: texto(row.descricao, 1200),
      acessorios: Array.isArray(row.acessorios) ? row.acessorios.slice(0, 20) : [],
      criadoEm: dataISO(row.criado_em),
      anunciante: {
        nome: texto(row.anunciante_nome, 80) || 'Aluga Fácil',
        telefone: telefoneExibicao(row.anunciante_telefone) || '(53) 99106-6321'
      },
      origem: row.origem === 'anuncio' ? 'anuncio' : 'catalogo',
      publicado: row.publicado !== false
    };
  }

  function paraReserva(row) {
    if (!row || !row.id) return null;
    return {
      id: String(row.id),
      equipamentoId: String(row.equipamento_id || ''),
      titulo: texto(row.titulo, 120),
      tipo: texto(row.tipo, 40) || 'outros',
      cidade: texto(row.cidade, 60),
      uf: String(row.uf || '').toUpperCase().slice(0, 2),
      data: dataISO(row.data),
      hora: horaCurta(row.hora) || '09:00',
      nome: texto(row.nome, 80),
      telefone: texto(row.telefone, 20),
      clienteId: row.cliente_id ? String(row.cliente_id) : null,
      dias: Math.max(1, Math.min(365, Math.round(numero(row.dias)) || 1)),
      diaria: numero(row.diaria),
      frete: numero(row.frete),
      caucao: numero(row.caucao),
      total: numero(row.total),
      status: ['confirmada', 'cancelada', 'concluida'].indexOf(row.status) >= 0 ? row.status : 'confirmada',
      entregaStatus: ['preparando', 'saiu', 'em_transito', 'entregue'].indexOf(row.entrega_status) >= 0 ? row.entrega_status : 'preparando',
      entregaSaiuEm: row.entrega_saiu_em || null,
      entregaInicio: row.entrega_inicio || null,
      entregaDuracaoMin: Math.max(5, Math.min(1440, Math.round(numero(row.entrega_duracao_min)) || 30)),
      entregaEntregador: texto(row.entrega_entregador, 60) || 'Equipe Aluga Fácil',
      entregaAtualizadoEm: row.entrega_atualizado_em || '',
      entregaConcluidaEm: row.entrega_concluida_em || null,
      entregaConfirmadaPeloCliente: row.entrega_confirmada_pelo_cliente === true,
      manual: row.manual === true,
      criadoEm: row.criado_em || '',
      atualizadoEm: row.atualizado_em || '',
      nuvem: true
    };
  }

  function paraPerfil(row) {
    if (!row || !row.id) return null;
    return {
      id: String(row.id),
      papel: row.papel === 'admin' || row.papel === 'gerente' ? row.papel : 'cliente',
      nome: texto(row.nome, 80),
      telefone: texto(row.telefone, 20),
      email: texto(row.email, 120),
      tipo_pessoa: row.tipo_pessoa === 'pj' ? 'pj' : 'pf',
      cidade: texto(row.cidade, 60),
      uf: String(row.uf || '').toUpperCase().slice(0, 2),
      cnpj: digits(row.cnpj).slice(0, 14),
      nome_fantasia: texto(row.nome_fantasia, 120),
      empresa: row.empresa && typeof row.empresa === 'object' ? row.empresa : null,
      ativo: row.ativo !== false,
      criado_em: row.criado_em || ''
    };
  }

  function clienteLocal() {
    var p = perfilAtual;
    if (!p) return null;
    return {
      id: p.id,
      nome: p.nome || 'Cliente Aluga Fácil',
      telefone: p.telefone || '',
      email: p.email || '',
      tipo: p.tipo_pessoa,
      cidade: p.cidade || '',
      uf: p.uf || '',
      cnpj: p.cnpj || '',
      nomeFantasia: p.nome_fantasia || '',
      empresa: p.empresa,
      senha: null,
      precisaTrocarSenha: false,
      criadoEm: p.criado_em || '',
      nuvem: true
    };
  }

  function ehAdmin() {
    return !!(perfilAtual && perfilAtual.ativo && perfilAtual.papel === 'admin');
  }

  function ehEquipe() {
    return !!(perfilAtual && perfilAtual.ativo && (perfilAtual.papel === 'admin' || perfilAtual.papel === 'gerente'));
  }

  /* ---------------- Auth ---------------- */
  function salvarDadosAuth(dados) {
    if (!dados || !dados.access_token) return null;
    var sessao = {
      access_token: dados.access_token,
      refresh_token: dados.refresh_token || '',
      expires_at: Number(dados.expires_at) || 0,
      user: dados.user || null
    };
    salvarSessao(sessao);
    return sessao;
  }

  function entrar(email, senha) {
    var e = String(email || '').trim().toLowerCase();
    if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(e)) {
      return Promise.reject(new ErroNuvem('Informe um e-mail válido.', '22023'));
    }
    if (!senha || String(senha).length < 6) {
      return Promise.reject(new ErroNuvem('A senha deve ter pelo menos 6 caracteres.', '22023'));
    }
    return buscar('/auth/v1/token?grant_type=password', {
      method: 'POST',
      body: { email: e, password: String(senha) }
    }).then(function (dados) {
      if (!salvarDadosAuth(dados)) throw new ErroNuvem('E-mail ou senha incorretos.', '28000');
      return carregarPerfil();
    }).then(function (perfil) {
      perfilAtual = perfil;
      return perfil;
    });
  }

  function criarConta(email, senha, nome) {
    var e = String(email || '').trim().toLowerCase();
    if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(e)) {
      return Promise.reject(new ErroNuvem('Informe um e-mail válido.', '22023'));
    }
    if (!senha || String(senha).length < 8) {
      return Promise.reject(new ErroNuvem('Use uma senha com pelo menos 8 caracteres.', '22023'));
    }
    var nomeLimpo = texto(nome, 80);
    if (nomeLimpo.length < 3) {
      return Promise.reject(new ErroNuvem('Informe seu nome completo.', '22023'));
    }
    return buscar('/auth/v1/signup', {
      method: 'POST',
      body: {
        email: e,
        password: String(senha),
        data: { nome: nomeLimpo }
      }
    }).then(function (dados) {
      if (dados && dados.access_token) {
        salvarDadosAuth(dados);
        return carregarPerfil().then(function (perfil) {
          perfilAtual = perfil;
          return perfil;
        });
      }
      // Confirmação de e-mail habilitada no projeto: ainda não há sessão.
      throw new ErroNuvem('Conta criada! Confirme seu e-mail e depois entre.');
    });
  }

  function sair() {
    var s = lerSessao();
    perfilAtual = null;
    reservasNuvem = [];
    favoritosNuvem = [];
    catalogo = lerCache().catalogo || [];
    salvarSessao(null);
    if (!s || !s.access_token) return Promise.resolve();
    return buscar('/auth/v1/logout', { method: 'POST', body: {} }).catch(function () {});
  }

  /* ---------------- Leituras ---------------- */
  function carregarPerfil() {
    var uid = idUsuario();
    if (!uid) return Promise.resolve(null);
    return requisitar('/rest/v1/perfis?select=*&id=eq.' + encodeURIComponent(uid))
      .then(function (linhas) {
        var perfil = paraPerfil(linhas && linhas[0]);
        if (!perfil) throw new ErroNuvem('Perfil não encontrado. Refaça o login.', 'P0002');
        return perfil;
      });
  }

  function carregarCatalogo() {
    return requisitar('/rest/v1/equipamentos?select=*&order=criado_em.desc&limit=1000')
      .then(function (linhas) {
        var lista = (Array.isArray(linhas) ? linhas : [])
          .map(paraEquipamento)
          .filter(Boolean);
        catalogo = lista;
        salvarCache('catalogo', lista);
        return lista;
      });
  }

  function carregarReservas() {
    if (!logado()) return Promise.resolve([]);
    return requisitar('/rest/v1/reservas?select=*&order=data.desc&limit=1000')
      .then(function (linhas) {
        reservasNuvem = (Array.isArray(linhas) ? linhas : [])
          .map(paraReserva)
          .filter(Boolean);
        salvarCache('reservas', reservasNuvem);
        return reservasNuvem;
      });
  }

  function carregarFavoritos() {
    if (!logado()) return Promise.resolve([]);
    return requisitar('/rest/v1/favoritos?select=equipamento_id')
      .then(function (linhas) {
        favoritosNuvem = (Array.isArray(linhas) ? linhas : [])
          .map(function (item) { return String(item.equipamento_id || ''); })
          .filter(Boolean);
        salvarCache('favoritos', favoritosNuvem);
        return favoritosNuvem;
      });
  }

  function carregarConfig() {
    return requisitar('/rest/v1/config_negocio?select=id,empresa,whatsapp&id=eq.1')
      .then(function (linhas) {
        var row = linhas && linhas[0];
        configAtual = {
          empresa: texto(row && row.empresa, 60) || 'Aluga Fácil',
          whatsapp: digits(row && row.whatsapp).slice(0, 15) || '5553991066321'
        };
        // custo_pct é Sigiloso: só a equipe pode ler.
        if (ehEquipe()) {
          return rpc('config_equipe', {}).then(function (cfg) {
            if (cfg && typeof cfg === 'object') {
              configAtual.custoPct = numero(cfg.custo_pct);
              configAtual.whatsapp = digits(cfg.whatsapp).slice(0, 15) || configAtual.whatsapp;
            }
            return configAtual;
          }).catch(function () { return configAtual; });
        }
        return configAtual;
      });
  }

  function sincronizar() {
    var resultado = { catalogo: [], reservas: [], favoritos: [], perfil: null, config: null };
    return carregarCatalogo()
      .then(function (lista) {
        resultado.catalogo = lista;
        return carregarConfig().catch(function () { return null; });
      })
      .then(function (cfg) {
        resultado.config = cfg;
        if (!logado()) return null;
        return carregarPerfil().then(function (perfil) {
          perfilAtual = perfil;
          resultado.perfil = perfil;
          return Promise.all([carregarReservas(), carregarFavoritos()]);
        }).then(function (partes) {
          resultado.reservas = partes[0] || [];
          resultado.favoritos = partes[1] || [];
          return resultado;
        });
      })
      .then(function () { return resultado; });
  }

  /* ---------------- Escritas ---------------- */
  function criarReserva(dados) {
    return rpc('criar_reserva', {
      p_equipamento_id: String(dados.equipamentoId || ''),
      p_data: dataISO(dados.data),
      p_hora: horaCurta(dados.hora),
      p_dias: Math.round(numero(dados.dias)) || 1,
      p_nome: texto(dados.nome, 80),
      p_telefone: texto(dados.telefone, 20)
    }).then(paraReserva);
  }

  function cancelarReserva(id) {
    return rpc('cancelar_reserva', { p_id: String(id) }).then(paraReserva);
  }

  function confirmarRecebimento(id) {
    return rpc('confirmar_recebimento', { p_id: String(id) }).then(paraReserva);
  }

  function concluirReserva(id) {
    return rpc('concluir_reserva', { p_id: String(id) }).then(paraReserva);
  }

  function atualizarEntrega(id, status, entregador, duracaoMin) {
    var params = { p_id: String(id), p_status: String(status) };
    if (entregador) params.p_entregador = texto(entregador, 60);
    if (duracaoMin != null) params.p_duracao_min = Math.round(numero(duracaoMin));
    return rpc('atualizar_entrega', params).then(paraReserva);
  }

  function alternarFavorito(id, querAdicionar) {
    var equipamentoId = String(id || '');
    var uid = idUsuario();
    if (!equipamentoId || !uid) return Promise.reject(new ErroNuvem('Entre na sua conta para salvar favoritos.', '28000'));
    if (querAdicionar) {
      return requisitar('/rest/v1/favoritos?on_conflict=perfil_id,equipamento_id', {
        method: 'POST',
        prefer: 'resolution=ignore-duplicates,return=minimal',
        body: { perfil_id: uid, equipamento_id: equipamentoId }
      });
    }
    return requisitar('/rest/v1/favoritos?equipamento_id=eq.' + encodeURIComponent(equipamentoId), {
      method: 'DELETE',
      prefer: 'return=minimal'
    });
  }

  function publicarAnuncio(dados) {
    var envio = Object.assign({}, dados || {});
    delete envio.id;
    delete envio.criadoEm;
    delete envio.origem;
    delete envio.publicado;
    delete envio.nuvem;
    delete envio.meu;
    return rpc('publicar_anuncio', { p_dados: envio }).then(paraEquipamento);
  }

  function removerAnuncio(id) {
    return rpc('remover_anuncio', { p_id: String(id) });
  }

  function salvarConfigNegocio(empresa, whatsapp, custoPct) {
    return rpc('salvar_config_negocio', {
      p_empresa: texto(empresa, 60) || 'Aluga Fácil',
      p_whatsapp: digits(whatsapp).slice(0, 15),
      p_custo_pct: numero(custoPct)
    });
  }

  // O próprio usuário pode alterar estes campos do perfil (RLS permite).
  function atualizarPerfil(dados) {
    var uid = idUsuario();
    if (!uid) return Promise.reject(new ErroNuvem('Entre na sua conta para continuar.', '28000'));
    var corpo = {};
    ['nome', 'telefone', 'cidade', 'uf', 'tipo_pessoa', 'cnpj', 'nome_fantasia', 'empresa'].forEach(function (campo) {
      if (dados[campo] !== undefined) corpo[campo] = dados[campo];
    });
    return requisitar('/rest/v1/perfis?id=eq.' + encodeURIComponent(uid), {
      method: 'PATCH',
      prefer: 'return=representation',
      body: corpo
    }).then(function (linhas) {
      perfilAtual = paraPerfil(linhas && linhas[0]) || perfilAtual;
      return perfilAtual;
    });
  }

  function definirPapel(perfilId, papel) {
    return rpc('definir_papel', { p_perfil_id: String(perfilId), p_papel: String(papel) });
  }

  function definirAtivo(perfilId, ativo) {
    return rpc('definir_ativo', { p_perfil_id: String(perfilId), p_ativo: !!ativo });
  }

  function eventosReserva(id) {
    if (!logado()) return Promise.resolve([]);
    return requisitar('/rest/v1/reserva_eventos?select=*&reserva_id=eq.' + encodeURIComponent(String(id)) + '&order=criado_em.asc')
      .then(function (linhas) { return Array.isArray(linhas) ? linhas : []; });
  }

  function iniciar() {
    if (!configurada()) return Promise.resolve({ configurada: false, logado: false });
    var cache = lerCache();
    if (Array.isArray(cache.catalogo)) catalogo = cache.catalogo;
    if (!lerSessao()) return Promise.resolve({ configurada: true, logado: false });
    return carregarPerfil()
      .then(function (perfil) {
        perfilAtual = perfil;
        return { configurada: true, logado: !!perfil };
      })
      .catch(function () {
        salvarSessao(null);
        return { configurada: true, logado: false };
      });
  }

  global.Nuvem = {
    ErroNuvem: ErroNuvem,
    mensagemErro: mensagemErro,
    configurada: configurada,
    iniciar: iniciar,
    sincronizar: sincronizar,
    logado: logado,
    ehAdmin: ehAdmin,
    ehEquipe: ehEquipe,
    clienteLocal: clienteLocal,
    idUsuario: idUsuario,
    entrar: entrar,
    criarConta: criarConta,
    sair: sair,
    carregarCatalogo: carregarCatalogo,
    carregarReservas: carregarReservas,
    criarReserva: criarReserva,
    cancelarReserva: cancelarReserva,
    confirmarRecebimento: confirmarRecebimento,
    concluirReserva: concluirReserva,
    atualizarEntrega: atualizarEntrega,
    alternarFavorito: alternarFavorito,
    publicarAnuncio: publicarAnuncio,
    removerAnuncio: removerAnuncio,
    salvarConfigNegocio: salvarConfigNegocio,
    atualizarPerfil: atualizarPerfil,
    definirPapel: definirPapel,
    definirAtivo: definirAtivo,
    eventosReserva: eventosReserva,
    paraReserva: paraReserva,
    paraEquipamento: paraEquipamento,
    get perfil() { return perfilAtual; },
    get catalogo() { return catalogo; },
    get reservas() { return reservasNuvem; },
    get favoritos() { return favoritosNuvem; },
    get config() { return configAtual; }
  };
})(window);
