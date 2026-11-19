/* ============================================================
   Aluga Fácil — configuração da nuvem (valores PÚBLICOS)

   A anon key do Supabase é pública por projeto: ela só entra nas
   políticas RLS. A service_role key NUNCA vai para o navegador.

   Enquanto url/anonKey estiverem vazios, o app continua 100%
   local-first, exatamente como na v21. Para ativar o backend,
   preencha os dois campos abaixo com os valores do seu projeto
   Supabase (Project URL e anon/public key) e publique.
   ============================================================ */
window.ALUGA_NUVEM_CONFIG = {
  url: '',
  anonKey: ''
};
