# BitDev CRM — Gestão de Placas NFC e QR Code

Sistema em nuvem para controle de prospecção comercial, vendas, auditoria e gerenciamento de placas inteligentes com links dinâmicos.

---

## Estrutura do Projeto

* `index.html`: Painel administrativo protegido por autenticação Supabase Auth e verificação de administrador (`is_admin`).
* `config.js`: Arquivo de credenciais de conexão com o Supabase (Project URL e chave pública `anon`).
* `go.html`: Motor ultrarrápido (< 3KB) para redirecionamento público de NFC e QR Codes com registro atômico de acessos (`scans_count`).
* `vercel.json`: Regras de reescrita de URL amigável (`/go/:slug` e `/r/:slug`).
* `supabase_schema.sql`: Script PostgreSQL com RLS, gatilhos automáticos, integridade referencial `RESTRICT` e função segura de redirecionamento (`SECURITY DEFINER` com `search_path = ''`).
* `supabase_tests.sql`: Bateria de testes SQL reproduzíveis para validação de segurança e auditoria.

---

## Como Funciona o Redirecionamento das Placas

1. A placa física (etiqueta NFC ou impressão do QR Code) aponta para o link permanente (exemplo: `https://seu-dominio.com.br/go.html?p=barbearia-silva` ou `https://go.bitdev.com.br/barbearia-silva`).
2. Quando o cliente escaneia o QR Code ou aproxima o celular da placa NFC:
   * O endpoint `go.html` chama a função segura `resolve_plate_redirect` no Supabase.
   * Se a placa estiver **Ativa**: o contador de acessos (`scans_count`) é incrementado atomicamente e o cliente é redirecionado instantaneamente para o link de destino (Google Avaliações, Instagram, WhatsApp, etc.).
   * Se a placa estiver **Inativa** ou **Em produção**: é exibida uma tela segura com a identidade visual da BitDev informando que a placa está em fase de ativação (o link de destino nunca é vazado).

---

## Publicação em Produção (Deploy Gratuito)

### Opção 1: Vercel (Recomendado)
1. Crie um repositório no GitHub (pode ser privado) e envie os arquivos desta pasta.
2. Acesse [vercel.com](https://vercel.com) e importe o repositório.
3. Clique em **Deploy**. As rotas amigáveis configuradas em `vercel.json` funcionarão automaticamente.
4. Adicione seu domínio próprio em **Settings > Domains**.

### Opção 2: Netlify (Deploy em 1 Minuto)
1. Acesse [app.netlify.com/drop](https://app.netlify.com/drop).
2. Arraste esta pasta diretamente para o navegador.
3. Seu site estará online com HTTPS automático.
