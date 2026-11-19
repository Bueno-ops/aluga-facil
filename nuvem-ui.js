/* ============================================================
   Aluga Fácil — ligação entre a nuvem e a interface local-first

   Carregado DEPOIS do script principal. Se a nuvem não estiver
   configurada, este arquivo não altera nada: o app segue igual
   à versão v21. Com a nuvem ativa, ele usa o banco como fonte
   da verdade e mantém o localStorage como cache offline.
   ============================================================ */
(function (global) {
  'use strict';

  if (!global.Nuvem || !Nuvem.configurada()) return;

  var orig = {};
  var catalogoNuvem = [];
  var sincronizando = false;

  function trocar(nome, novo) {
    var antigo = global[nome];
    if (typeof antigo !== 'function') return function () {};
    global[nome] = novo;
    return antigo;
  }

  function avisarErro(erro, acao) {
    try { avisar(Nuvem.mensagemErro(erro) + (acao ? ' ' + acao : ''), 'erro'); } catch (e) {}
  }

  function ocupar(botao, ocupado) {
    if (!botao) return;
    botao.disabled = !!ocupado;
    botao.setAttribute('aria-busy', ocupado ? 'true' : 'false');
  }

  function atualizarTela() {
    try { renderChips(); } catch (e) {}
    try { renderCidades(); } catch (e) {}
    try { renderBusca(); } catch (e) {}
    try { renderFavoritos(); } catch (e) {}
    try { renderReservas(); } catch (e) {}
    try { renderMeusAnuncios(); } catch (e) {}
    try { renderCliente(); } catch (e) {}
    try { renderGerente(); } catch (e) {}
    try { renderPainelGerente(); } catch (e) {}
    try { atualizarPontos(); } catch (e) {}
    atualizarCartaoNuvem();
  }

  function substituirReserva(v) {
    if (!v) return;
    var i = -1;
    for (var k = 0; k < reservas.length; k++) {
      if (reservas[k].id === v.id) { i = k; break; }
    }
    if (i >= 0) reservas[i] = v;
    else reservas.unshift(v);
    salvar(CHAVES.reservas, reservas);
  }

  function aplicar(resultado) {
    if (!resultado) return;
    if (Array.isArray(resultado.catalogo) && resultado.catalogo.length) {
      catalogoNuvem = resultado.catalogo;
      meusAnuncios = resultado.catalogo.filter(function (eq) { return eq.origem === 'anuncio'; });
      salvar(CHAVES.anuncios, meusAnuncios);
    }
    if (Array.isArray(resultado.reservas)) {
      reservas = resultado.reservas.slice();
      salvar(CHAVES.reservas, reservas);
    }
    if (Array.isArray(resultado.favoritos)) {
      favoritos = new Set(resultado.favoritos);
      salvar(CHAVES.favoritos, Array.from(favoritos));
    }
    if (resultado.perfil) {
      var cli = Nuvem.clienteLocal();
      if (cli) {
        var encontrou = false;
        for (var i = 0; i < clientes.length; i++) {
          if (clientes[i].id === cli.id) { clientes[i] = cli; encontrou = true; break; }
        }
        if (!encontrou) clientes.unshift(cli);
      }
    }
    if (resultado.config) {
      configNegocio = normalizarConfigNegocio({
        custoPct: resultado.config.custoPct,
        empresa: resultado.config.empresa
      });
      salvar(CHAVES.negocio, configNegocio);
    }
    atualizarTela();
  }

  function sincronizar(silent) {
    if (sincronizando) return Promise.resolve();
    sincronizando = true;
    var status = document.getElementById('nuvem-status');
    if (status && !silent) status.textContent = 'Sincronizando...';
    return Nuvem.sincronizar()
      .then(function (resultado) {
        aplicar(resultado);
        if (status) status.textContent = Nuvem.logado()
          ? 'Conectado. Dados sincronizados.'
          : 'Catálogo online. Entre para salvar favoritos e reservas na nuvem.';
      })
      .catch(function (erro) {
        if (status) status.textContent = Nuvem.mensagemErro(erro) + ' Exibindo os dados salvos neste dispositivo.';
      })
      .then(function () { sincronizando = false; });
  }

  /* ---------------- Cartão de conta na nuvem ---------------- */
  function injetarCartao() {
    var area = document.getElementById('cliente-area');
    if (!area || document.getElementById('nuvem-caixa')) return;

    var caixa = document.createElement('div');
    caixa.className = 'login-caixa';
    caixa.id = 'nuvem-caixa';
    caixa.style.cssText = 'margin:16px auto 0;padding:18px 16px;text-align:left';
    caixa.innerHTML = ''
      + '<h2 style="text-align:center">Conta na nuvem</h2>'
      + '<p class="login-sub" style="text-align:center">Entre para sincronizar reservas e favoritos entre todos os seus dispositivos. Dono e gerente devem entrar aqui e depois escolher "Dono ou gerente" no topo.</p>'
      + '<form class="formulario login-form" id="nuvem-form" novalidate>'
      +   '<div class="campo-grupo"><label for="nuvem-email">E-mail</label>'
      +     '<input class="campo" id="nuvem-email" type="email" autocomplete="email" maxlength="120" placeholder="voce@email.com" required></div>'
      +   '<div class="campo-grupo"><label for="nuvem-senha">Senha</label>'
      +     '<input class="campo" id="nuvem-senha" type="password" autocomplete="current-password" maxlength="128" required></div>'
      +   '<div class="campo-grupo" id="nuvem-nome-grupo" hidden><label for="nuvem-nome">Nome completo</label>'
      +     '<input class="campo" id="nuvem-nome" type="text" autocomplete="name" maxlength="80"></div>'
      +   '<div class="visita-acoes">'
      +     '<button class="btn-primario" type="submit" id="nuvem-entrar">Entrar</button>'
      +     '<button class="btn-secundario" type="button" id="nuvem-criar">Criar conta</button>'
      +     '<button class="btn-secundario" type="button" id="nuvem-sair" hidden>Sair</button>'
      +   '</div>'
      +   '<small class="campo-dica" id="nuvem-status"></small>'
      + '</form>';
    area.insertBefore(caixa, area.firstChild);

    var form = document.getElementById('nuvem-form');
    var modo = 'entrar';
    var status = document.getElementById('nuvem-status');
    var entrar = document.getElementById('nuvem-entrar');
    var criar = document.getElementById('nuvem-criar');
    var sair = document.getElementById('nuvem-sair');
    var nomeGrupo = document.getElementById('nuvem-nome-grupo');

    function alternarModo(novoModo) {
      modo = novoModo;
      nomeGrupo.hidden = modo !== 'criar';
      entrar.textContent = modo === 'criar' ? 'Criar conta' : 'Entrar';
      criar.textContent = modo === 'criar' ? 'Já tenho conta' : 'Criar conta';
      status.textContent = '';
    }

    criar.addEventListener('click', function () { alternarModo(modo === 'criar' ? 'entrar' : 'criar'); });

    form.addEventListener('submit', function (e) {
      e.preventDefault();
      var email = document.getElementById('nuvem-email').value;
      var senha = document.getElementById('nuvem-senha').value;
      var nome = document.getElementById('nuvem-nome').value;
      ocupar(entrar, true);
      ocupar(criar, true);
      status.textContent = 'Conectando...';
      var tarefa = modo === 'criar'
        ? Nuvem.criarConta(email, senha, nome)
        : Nuvem.entrar(email, senha);
      tarefa.then(function () {
        alternarModo('entrar');
        document.getElementById('nuvem-senha').value = '';
        return sincronizar(true);
      }).then(function () {
        avisar('Conectado à nuvem.');
      }).catch(function (erro) {
        avisarErro(erro);
        status.textContent = Nuvem.mensagemErro(erro);
      }).then(function () {
        ocupar(entrar, false);
        ocupar(criar, false);
      });
    });

    sair.addEventListener('click', function () {
      if (!window.confirm('Sair da conta na nuvem? Seus dados salvos neste dispositivo continuarão disponíveis offline.')) return;
      ocupar(sair, true);
      Nuvem.sair().then(function () {
        catalogoNuvem = [];
        var cache = null;
        try { cache = JSON.parse(localStorage.getItem('aluga:nuvem:cache') || 'null'); } catch (e) {}
        if (cache && Array.isArray(cache.catalogo)) catalogoNuvem = cache.catalogo;
        return sincronizar(true);
      }).then(function () {
        avisar('Você saiu da conta na nuvem.');
      }).catch(function (erro) {
        avisarErro(erro);
      }).then(function () { ocupar(sair, false); });
    });

    atualizarCartaoNuvem();
  }

  function atualizarCartaoNuvem() {
    var status = document.getElementById('nuvem-status');
    var sair = document.getElementById('nuvem-sair');
    var entrar = document.getElementById('nuvem-entrar');
    var criar = document.getElementById('nuvem-criar');
    var form = document.getElementById('nuvem-form');
    if (!form) return;
    var logado = Nuvem.logado();
    if (sair) sair.hidden = !logado;
    if (entrar) entrar.hidden = logado;
    if (criar) criar.hidden = logado;
    if (status && logado) {
      var p = Nuvem.perfil;
      status.textContent = 'Conectado como ' + (p && p.email ? p.email : 'conta da nuvem')
        + (p && p.papel === 'admin' ? ' (dono)' : (p && p.papel === 'gerente' ? ' (gerente)' : '')) + '.';
    }
  }

  /* ---------------- Adaptações das funções do app ---------------- */
  function instalarAdaptacoes() {
    // Catálogo: o banco substitui o catálogo embutido quando carregado.
    orig.todosEquipamentos = trocar('todosEquipamentos', function () {
      if (!catalogoNuvem.length) return orig.todosEquipamentos();
      return catalogoNuvem
        .filter(function (eq) { return eq.publicado !== false; })
        .map(function (eq) { return Object.assign({}, eq); });
    });

    // Cliente logado na nuvem passa a ser o "cliente atual" do app.
    orig.clienteAtual = trocar('clienteAtual', function () {
      if (Nuvem.logado() && Nuvem.perfil) return Nuvem.clienteLocal();
      return orig.clienteAtual();
    });

    orig.podeGerirEntrega = trocar('podeGerirEntrega', function () {
      return Nuvem.ehEquipe() || orig.podeGerirEntrega();
    });

    orig.adminValido = trocar('adminValido', function () {
      return Nuvem.ehAdmin() || orig.adminValido();
    });

    // Reservas: preço evalidade sempre calculados no servidor.
    orig.agendarReserva = trocar('agendarReserva', function (form) {
      if (!Nuvem.logado()) return orig.agendarReserva(form);
      var id = form.dataset.id;
      var eq = todosEquipamentos().find(function (item) { return item.id === id; });
      var data = dataValidaISO(document.getElementById('r-data').value);
      var hora = horaValida(document.getElementById('r-hora').value);
      var nome = limparTexto(document.getElementById('r-nome').value, 80);
      var telefone = limparTexto(document.getElementById('r-tel').value, 20);
      var hoje = new Date().toISOString().slice(0, 10);
      if (!eq) return;
      if (!data || data < hoje) { avisar('Escolha uma data a partir de hoje.', 'erro'); return; }
      if (!hora) { avisar('Escolha um horário válido.', 'erro'); return; }
      if (nome.length < 3) { avisar('Informe seu nome completo.', 'erro'); document.getElementById('r-nome').focus(); return; }
      if (soDigitos(telefone).length < 10) { avisar('Informe um WhatsApp com DDD.', 'erro'); document.getElementById('r-tel').focus(); return; }
      if (reservas.some(function (v) {
        return statusReserva(v) !== 'cancelada' && v.equipamentoId === id && v.data === data && v.hora === hora;
      })) { avisar('Você já tem uma reserva dessa máquina nesse horário.', 'erro'); return; }

      var botao = form.querySelector('button[type="submit"]');
      ocupar(botao, true);
      Nuvem.criarReserva({
        equipamentoId: id, data: data, hora: hora, dias: 1, nome: nome, telefone: telefone
      }).then(function (v) {
        substituirReserva(v);
        renderReservas();
        renderCliente();
        fecharModal();
        avisar('Reserva confirmada para ' + formatarData(v.data) + ' às ' + v.hora);
        irPara('reservas');
      }).catch(function (erro) {
        avisarErro(erro);
      }).then(function () { ocupar(botao, false); });
    });

    orig.cancelarReserva = trocar('cancelarReserva', function (id) {
      var v = reservas.find(function (item) { return item.id === id; });
      if (!v || !v.nuvem || !Nuvem.logado()) return orig.cancelarReserva(id);
      if (!podeVerReserva(v)) { avisar('Esta reserva não é da sua conta.', 'erro'); return; }
      if (!window.confirm('Cancelar a reserva de ' + formatarData(v.data) + ' às ' + v.hora + '?')) return;
      var botao = document.querySelector('[data-acao="cancelar-reserva"][data-id="' + id + '"]');
      ocupar(botao, true);
      Nuvem.cancelarReserva(id).then(function (atualizada) {
        substituirReserva(atualizada);
        renderReservas();
        renderCliente();
        atualizarPontos();
        avisar('Reserva cancelada');
      }).catch(function (erro) {
        avisarErro(erro);
      }).then(function () { ocupar(botao, false); });
    });

    orig.confirmarRecebimento = trocar('confirmarRecebimento', function (id) {
      var v = reservas.find(function (item) { return item.id === id; });
      if (!v || !v.nuvem || !Nuvem.logado()) return orig.confirmarRecebimento(id);
      if (!reservaPertenceAoCliente(v, clienteAtual()) && !podeGerirEntrega()) {
        avisar('Esta reserva não é da sua conta.', 'erro');
        return;
      }
      if (!window.confirm('Confirmar que você recebeu o equipamento?')) return;
      Nuvem.confirmarRecebimento(id).then(function (atualizada) {
        substituirReserva(atualizada);
        atualizarTelasEntrega(id);
        avisar('Recebimento confirmado. Obrigado!');
      }).catch(function (erro) { avisarErro(erro); });
    });

    orig.alterarStatusEntrega = trocar('alterarStatusEntrega', function (id, status) {
      var v = reservas.find(function (item) { return item.id === id; });
      if (!v || !v.nuvem || !Nuvem.logado()) return orig.alterarStatusEntrega(id, status);
      if (!podeGerirEntrega()) { avisar('Apenas a loja pode atualizar a entrega.', 'erro'); return; }
      if (!ETAPAS_ENTREGA.some(function (item) { return item.id === status; })) return;
      if (statusEntrega(v) === status) return;
      Nuvem.atualizarEntrega(id, status, v.entregaEntregador, v.entregaDuracaoMin)
        .then(function (atualizada) {
          substituirReserva(atualizada);
          atualizarTelasEntrega(id);
          var mensagens = {
            preparando: 'Entrega voltou para preparação',
            saiu: 'Equipamento saiu da loja',
            em_transito: 'Entrega em trânsito — o cliente já pode acompanhar',
            entregue: 'Entrega concluída'
          };
          avisar(mensagens[status] || 'Entrega atualizada');
        }).catch(function (erro) { avisarErro(erro); });
    });

    orig.alterarDuracaoEntrega = trocar('alterarDuracaoEntrega', function (id, minutos) {
      var v = reservas.find(function (item) { return item.id === id; });
      if (!v || !v.nuvem || !Nuvem.logado()) return orig.alterarDuracaoEntrega(id, minutos);
      if (!podeGerirEntrega()) return;
      var valor = Math.max(5, Math.min(240, Number(minutos) || 30));
      Nuvem.atualizarEntrega(id, v.entregaStatus, v.entregaEntregador, valor)
        .then(function (atualizada) {
          substituirReserva(atualizada);
          atualizarTelasEntrega(id);
          avisar('Tempo estimado: ' + valor + ' min');
        }).catch(function (erro) { avisarErro(erro); });
    });

    orig.salvarEntregador = trocar('salvarEntregador', function (id) {
      var v = reservas.find(function (item) { return item.id === id; });
      var campo = document.getElementById('entrega-entregador');
      if (!v || !campo || !v.nuvem || !Nuvem.logado()) return orig.salvarEntregador(id);
      if (!podeGerirEntrega()) return;
      var nome = limparTexto(campo.value, 60) || 'Equipe Aluga Fácil';
      Nuvem.atualizarEntrega(id, v.entregaStatus, nome, v.entregaDuracaoMin)
        .then(function (atualizada) {
          substituirReserva(atualizada);
          atualizarTelasEntrega(id);
          avisar('Entregador atualizado');
        }).catch(function (erro) { avisarErro(erro); });
    });

    orig.alterarStatusReserva = trocar('alterarStatusReserva', function (id, status) {
      var v = reservas.find(function (item) { return item.id === id; });
      if (!v || !v.nuvem || !Nuvem.logado()) return orig.alterarStatusReserva(id, status);
      if (!podeGerirEntrega()) { avisar('Apenas a loja pode alterar pedidos.', 'erro'); return; }
      if (STATUS_RESERVA.indexOf(status) < 0) return;
      if (status === 'cancelada' && !window.confirm('Cancelar este pedido? Ele sai da lista do cliente e continua no histórico do painel.')) return;
      if (status === 'confirmada') {
        avisar('A reabertura de pedidos concluídos não está disponível na nuvem.', 'erro');
        return;
      }
      var tarefa = status === 'concluida' ? Nuvem.concluirReserva(id) : Nuvem.cancelarReserva(id);
      tarefa.then(function (atualizada) {
        substituirReserva(atualizada);
        renderReservas();
        atualizarPontos();
        renderPainelGerente();
        avisar(status === 'concluida' ? 'Pedido concluído — entrou na receita realizada' : 'Pedido cancelado');
      }).catch(function (erro) { avisarErro(erro); });
    });

    orig.alternarFavorito = trocar('alternarFavorito', function (id) {
      var eq = todosEquipamentos().find(function (item) { return item.id === id; });
      if (!eq) return;
      var estava = favoritos.has(id);
      var queria = !estava;
      if (estava) { favoritos.delete(id); avisar('Removido dos favoritos'); }
      else { favoritos.add(id); avisar('Salvo nos favoritos'); }
      salvar(CHAVES.favoritos, Array.from(favoritos));
      renderBusca();
      renderFavoritos();
      atualizarPontos();
      var btn = document.querySelector('#modal [data-acao="favoritar"]');
      if (btn && btn.dataset.id === id) {
        var fav = favoritos.has(id);
        btn.innerHTML = icone('coracao') + (fav ? 'Salvo' : 'Favoritar');
        btn.classList.toggle('btn-favorito-ativo', fav);
      }
      if (!Nuvem.logado()) return;
      Nuvem.alternarFavorito(id, queria).catch(function (erro) {
        if (queria) favoritos.delete(id); else favoritos.add(id);
        salvar(CHAVES.favoritos, Array.from(favoritos));
        renderFavoritos();
        avisarErro(erro, 'O favorito ficou salvo apenas neste dispositivo.');
      });
    });

    orig.publicarAnuncio = trocar('publicarAnuncio', function (form) {
      if (!Nuvem.logado()) return orig.publicarAnuncio(form);
      if (!Nuvem.ehAdmin()) { avisar('Apenas o dono pode publicar anúncios.', 'erro'); irPara('gerente'); return; }
      var tipo = TIPOS.some(function (t) { return t.id === form.tipo.value; }) ? form.tipo.value : '';
      var energia = ENERGIAS.some(function (e) { return e.id === form.energia.value && e.id !== 'todas'; }) ? form.energia.value : '';
      var dados = {
        titulo: limparTexto(form.titulo.value, 120),
        tipo: tipo,
        cidade: limparTexto(form.cidade.value, 60),
        uf: ufSegura(form.uf.value),
        bairro: limparTexto(form.bairro.value, 60),
        diaria: numeroSeguro(form.diaria.value, 0, 1000000, 0),
        frete: numeroSeguro(form.frete.value, 0, 1000000, 0),
        caucao: numeroSeguro(form.caucao.value, 0, 1000000, 0),
        energia: energia,
        potencia: limparTexto(form.potencia.value, 40) || '—',
        peso: numeroSeguro(form.peso.value, 0, 100000, 0),
        entrega: form.entrega.checked,
        destaque: false,
        descricao: limparTexto(form.descricao.value, 1200),
        acessorios: Array.prototype.slice.call(document.querySelectorAll('#acessorios-anuncio input:checked'))
          .map(function (i) { return i.value; })
          .filter(function (item) { return ACESSORIOS.indexOf(item) >= 0; }),
        anunciante: {
          nome: limparTexto(form.anunciante.value, 80),
          telefone: limparTexto(form.telefone.value, 20)
        }
      };
      if (!tipo) { avisar('Escolha uma categoria válida.', 'erro'); form.tipo.focus(); return; }
      var erros = validarAnuncio(dados);
      marcarErros(erros);
      if (erros.length) { avisar('Revise os campos destacados.', 'erro'); return; }
      var botao = form.querySelector('button[type="submit"]');
      ocupar(botao, true);
      Nuvem.publicarAnuncio(dados).then(function (novo) {
        meusAnuncios.unshift(novo);
        if (catalogoNuvem.length) catalogoNuvem.unshift(novo);
        salvar(CHAVES.anuncios, meusAnuncios);
        form.reset();
        Array.prototype.forEach.call(document.querySelectorAll('#form-anuncio .campo-grupo'), function (g) {
          g.classList.remove('erro');
        });
        renderCidades();
        renderBusca();
        renderMeusAnuncios();
        avisar('Anúncio publicado com sucesso!');
      }).catch(function (erro) { avisarErro(erro); })
        .then(function () { ocupar(botao, false); });
    });

    orig.removerAnuncio = trocar('removerAnuncio', function (id) {
      var eq = meusAnuncios.find(function (item) { return item.id === id; });
      if (!eq || !Nuvem.logado()) return orig.removerAnuncio(id);
      if (!Nuvem.ehAdmin()) { avisar('Apenas o dono pode excluir anúncios.', 'erro'); return; }
      if (!window.confirm('Excluir o anúncio "' + eq.titulo + '"? Essa ação não pode ser desfeita.')) return;
      Nuvem.removerAnuncio(id).then(function (resultado) {
        if (resultado === 'despublicado') {
          meusAnuncios.forEach(function (item) { if (item.id === id) item.publicado = false; });
          catalogoNuvem = catalogoNuvem.filter(function (item) { return item.id !== id; });
          avisar('Anúncio despublicado: ele tem reserva ativa e ficará no histórico.');
        } else {
          meusAnuncios = meusAnuncios.filter(function (item) { return item.id !== id; });
          catalogoNuvem = catalogoNuvem.filter(function (item) { return item.id !== id; });
          if (favoritos.delete(id)) salvar(CHAVES.favoritos, Array.from(favoritos));
          avisar('Anúncio excluído');
        }
        salvar(CHAVES.anuncios, meusAnuncios);
        renderCidades();
        renderBusca();
        renderFavoritos();
        renderReservas();
        renderMeusAnuncios();
      }).catch(function (erro) { avisarErro(erro); });
    });

    orig.salvarPerfilCliente = trocar('salvarPerfilCliente', function (form) {
      var cliente = clienteAtual();
      if (!cliente || !cliente.nuvem) return orig.salvarPerfilCliente(form);
      var nome = limparTexto(form.nome.value, 80);
      var telefone = limparTexto(form.telefone.value, 20);
      var email = normalizarEmail(form.email.value).slice(0, 120);
      var cidade = limparTexto(form.cidade.value, 60);
      if (nome.length < 3) { avisar('Informe seu nome completo.', 'erro'); form.nome.focus(); return; }
      if (soDigitos(telefone).length < 10) { avisar('Informe um WhatsApp com DDD.', 'erro'); form.telefone.focus(); return; }
      if (email && !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) { avisar('Informe um e-mail válido.', 'erro'); form.email.focus(); return; }
      if (cidade.length < 2) { avisar('Informe a cidade.', 'erro'); form.cidade.focus(); return; }
      var botao = form.querySelector('button[type="submit"]');
      ocupar(botao, true);
      Nuvem.atualizarPerfil({
        nome: nome,
        telefone: telefone,
        cidade: cidade,
        uf: cliente.uf || ''
      }).then(function () {
        cliente.nome = nome;
        cliente.telefone = telefone;
        cliente.email = email;
        cliente.cidade = cidade;
        renderCliente();
        avisar('Dados salvos');
      }).catch(function (erro) { avisarErro(erro); })
        .then(function () { ocupar(botao, false); });
    });

    orig.salvarConfigNegocio = trocar('salvarConfigNegocio', function (form) {
      var nome = limparTexto(form.nome.value, 40);
      var custo = Number(form.custo.value);
      if (nome.length < 2) { avisar('Informe seu nome.', 'erro'); form.nome.focus(); return; }
      if (!isFinite(custo) || custo < 0 || custo > 100) { avisar('O custo deve ficar entre 0 e 100%.', 'erro'); form.custo.focus(); return; }
      if (!Nuvem.logado()) return orig.salvarConfigNegocio(form);
      if (!Nuvem.ehAdmin()) { avisar('Apenas o administrador pode alterar as configurações.', 'erro'); return; }
      var whatsapp = (Nuvem.config && Nuvem.config.whatsapp) || '5553991066321';
      Nuvem.salvarConfigNegocio(nome, whatsapp, custo).then(function () {
        configAdmin.nome = nome;
        configNegocio = { custoPct: custo, empresa: configNegocio.empresa };
        salvar(CHAVES.adminConfig, configAdmin);
        salvar(CHAVES.negocio, configNegocio);
        if (sessaoGerente) {
          sessaoGerente.nome = nome;
          salvarSessaoPainel(sessaoGerente);
        }
        renderGerente();
        avisar('Configurações salvas');
      }).catch(function (erro) { avisarErro(erro); });
    });
  }

  function iniciar() {
    instalarAdaptacoes();
    injetarCartao();
    Nuvem.iniciar()
      .then(function () { return sincronizar(true); })
      .then(function () { atualizarTela(); });

    global.addEventListener('online', function () {
      sincronizar(true).then(function () { avisar('Conexão restabelecida. Dados sincronizados.'); });
    });
    global.addEventListener('offline', function () {
      avisar('Você está offline. O catálogo salvo continua disponível.', 'erro');
    });
  }

  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', iniciar);
  else iniciar();
})(window);
