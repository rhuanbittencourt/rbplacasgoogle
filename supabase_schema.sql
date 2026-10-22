-- ====================================================================
-- BitDev CRM — Estrutura de Banco de Dados e Segurança (Supabase)
-- Versão: 1.4 (Auditoria Completa: search_path='', Concorrência e RLS Estrito)
-- Uso: Executar no SQL Editor do projeto Supabase.
-- Comandos destrutivos: NENHUM (preserva tabelas e dados existentes).
-- ====================================================================

-- 1. Extensões necessárias
create extension if not exists pgcrypto;

-- 2. Tabela de Administradores Autorizados
-- Apenas usuários explicitamente registrados nesta tabela possuem acesso ao CRM.
-- Novos administradores só podem ser adicionados por administradores já autorizados.
create table if not exists public.admin_users (
  user_id uuid primary key references auth.users(id) on delete cascade,
  email text not null unique,
  created_at timestamptz not null default now()
);

alter table public.admin_users enable row level security;

-- 3. Função de verificação se o usuário atual é administrador autorizado
-- Configurada com search_path = '' e nomes de objetos 100% qualificados.
create or replace function public.is_admin()
returns boolean
language sql
security definer
set search_path = ''
stable
as $$
  select exists (
    select 1 from public.admin_users
    where user_id = (select auth.uid())
  );
$$;

-- Permissões mínimas de public.is_admin()
revoke all on function public.is_admin() from public;
revoke all on function public.is_admin() from anon;
grant execute on function public.is_admin() to authenticated;

-- 4. Tabela de Clientes e Prospecção (Leads)
create table if not exists public.leads (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  contact_name text,
  phone text,
  email text,
  segment text,
  neighborhood text,
  address text,
  stage text not null default 'Novo lead'
    check (stage in ('Novo lead','Contato realizado','Proposta enviada','Em negociação','Ganho','Perdido')),
  next_contact date,
  google_url text,
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- 5. Tabela de Placas NFC / QR Code
create table if not exists public.plates (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,
  lead_id uuid not null references public.leads(id) on delete restrict,
  kind text not null default 'NFC + QR Code',
  permanent_slug text not null unique,
  permanent_url text,
  destination_url text,
  status text not null default 'Em produção'
    check (status in ('Em produção','Ativa','Inativa')),
  sold_date date,
  scans_count integer not null default 0,
  deleted_at timestamptz,
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- Compatibilidade idempotente: adiciona colunas caso a tabela já existisse
alter table public.plates
  add column if not exists scans_count integer not null default 0;

alter table public.plates
  add column if not exists deleted_at timestamptz;

-- 6. Tabela de Vendas e Financeiro
create table if not exists public.sales (
  id uuid primary key default gen_random_uuid(),
  lead_id uuid not null references public.leads(id) on delete restrict,
  plate_id uuid references public.plates(id) on delete set null,
  sale_date date not null default current_date,
  amount numeric(12,2) not null default 0 check (amount >= 0),
  cost numeric(12,2) not null default 0 check (cost >= 0),
  payment_status text not null default 'Pendente'
    check (payment_status in ('Pendente','Parcial','Pago','Cancelada')),
  payment_method text,
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- 7. Tabela de Histórico de Alterações de Destino das Placas (Auditoria)
-- on delete restrict impede que a exclusão física de uma placa apague o histórico
create table if not exists public.plate_destination_history (
  id uuid primary key default gen_random_uuid(),
  plate_id uuid not null references public.plates(id) on delete restrict,
  plate_code text,
  old_destination_url text,
  new_destination_url text,
  change_note text,
  changed_at timestamptz not null default now()
);

-- Compatibilidade idempotente: adiciona plate_code caso a tabela já existisse
alter table public.plate_destination_history
  add column if not exists plate_code text;

-- Migração de chave estrangeira com identificação cirúrgica:
-- Localiza especificamente a chave estrangeira plate_destination_history(plate_id) -> plates(id)
-- e apenas altera se o delete_rule for CASCADE ('c'), convertendo para RESTRICT ('r').
do $$
declare
  r_constraint record;
begin
  for r_constraint in (
    select c.conname, c.confdeltype
    from pg_catalog.pg_constraint c
    join pg_catalog.pg_attribute a
      on a.attrelid = c.conrelid and a.attnum = any(c.conkey)
    where c.conrelid = 'public.plate_destination_history'::regclass
      and c.confrelid = 'public.plates'::regclass
      and c.contype = 'f'
      and a.attname = 'plate_id'
  ) loop
    if r_constraint.confdeltype = 'c' then
      execute 'alter table public.plate_destination_history drop constraint ' || pg_catalog.quote_ident(r_constraint.conname);
      execute 'alter table public.plate_destination_history add constraint plate_destination_history_plate_id_fkey foreign key (plate_id) references public.plates(id) on delete restrict';
    end if;
  end loop;
end $$;

-- 8. Tabela de Histórico Geral de Atividades
create table if not exists public.activity_history (
  id uuid primary key default gen_random_uuid(),
  action text not null,
  detail text not null,
  related_type text,
  related_id uuid,
  created_at timestamptz not null default now()
);

-- 9. Trigger para atualização automática de updated_at
create or replace function public.handle_updated_at()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  new.updated_at = pg_catalog.now();
  return new;
end;
$$;

drop trigger if exists set_leads_updated_at on public.leads;
create trigger set_leads_updated_at
  before update on public.leads
  for each row execute function public.handle_updated_at();

drop trigger if exists set_plates_updated_at on public.plates;
create trigger set_plates_updated_at
  before update on public.plates
  for each row execute function public.handle_updated_at();

drop trigger if exists set_sales_updated_at on public.sales;
create trigger set_sales_updated_at
  before update on public.sales
  for each row execute function public.handle_updated_at();

-- 10. Configuração de RLS (Row Level Security)
alter table public.admin_users enable row level security;
alter table public.leads enable row level security;
alter table public.plates enable row level security;
alter table public.sales enable row level security;
alter table public.plate_destination_history enable row level security;
alter table public.activity_history enable row level security;

-- Revoga acessos diretos de tabelas de anon e public
revoke all on table public.admin_users from anon, public;
revoke all on table public.leads from anon, public;
revoke all on table public.plates from anon, public;
revoke all on table public.sales from anon, public;
revoke all on table public.plate_destination_history from anon, public;
revoke all on table public.activity_history from anon, public;

-- Concede permissões para authenticated (filtradas rigorosamente por RLS)
grant select, insert, update, delete on table public.admin_users to authenticated;
grant select, insert, update, delete on table public.leads to authenticated;
grant select, insert, update, delete on table public.plates to authenticated;
grant select, insert, update, delete on table public.sales to authenticated;
grant select, insert, update, delete on table public.plate_destination_history to authenticated;
grant select, insert, update, delete on table public.activity_history to authenticated;

-- Políticas de RLS: Apenas usuários confirmados em public.is_admin() operam no CRM
drop policy if exists "Admin gerencia admin_users" on public.admin_users;
create policy "Admin gerencia admin_users"
  on public.admin_users for all to authenticated
  using (public.is_admin()) with check (public.is_admin());

drop policy if exists "Admin gerencia leads" on public.leads;
create policy "Admin gerencia leads"
  on public.leads for all to authenticated
  using (public.is_admin()) with check (public.is_admin());

drop policy if exists "Admin gerencia placas" on public.plates;
create policy "Admin gerencia placas"
  on public.plates for all to authenticated
  using (public.is_admin()) with check (public.is_admin());

drop policy if exists "Admin gerencia vendas" on public.sales;
create policy "Admin gerencia vendas"
  on public.sales for all to authenticated
  using (public.is_admin()) with check (public.is_admin());

drop policy if exists "Admin gerencia historico destinos" on public.plate_destination_history;
create policy "Admin gerencia historico destinos"
  on public.plate_destination_history for all to authenticated
  using (public.is_admin()) with check (public.is_admin());

drop policy if exists "Admin gerencia historico atividades" on public.activity_history;
create policy "Admin gerencia historico atividades"
  on public.activity_history for all to authenticated
  using (public.is_admin()) with check (public.is_admin());

-- 11. Função Segura para Redirecionamento Público de Placas (RPC)
-- - Configurada com search_path = '' e objetos 100% qualificados.
-- - Utiliza FOR UPDATE para serializar requisições concorrentes e prevenir condições de corrida.
-- - Validação estrita de URL (POSIX regex sem escapes ambíguos, sem espaços, max 2048 chars).
-- - NUNCA expõe o destino de placas inativas, arquivadas (deleted_at) ou com link inválido.
drop function if exists public.resolve_plate_redirect(text);

create or replace function public.resolve_plate_redirect(p_slug text)
returns table (
  destination_url text,
  status text
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_plate record;
  v_is_valid_url boolean;
begin
  -- Higienização e rejeição imediata de slugs vazios
  if p_slug is null or pg_catalog.btrim(p_slug) = '' then
    return query select null::text, 'Slug invalido'::text;
    return;
  end if;

  -- Busca da placa com bloqueio de linha (FOR UPDATE) para proteger contra condições de corrida
  select p.id, p.destination_url, p.status, p.deleted_at
  into v_plate
  from public.plates p
  where p.permanent_slug = pg_catalog.btrim(p_slug)
  for update;

  -- Se a placa não existe
  if not found then
    return query select null::text, 'Nao encontrada'::text;
    return;
  end if;

  -- Se a placa foi desativada logicamente (soft delete)
  if v_plate.deleted_at is not null then
    return query select null::text, 'Inativa'::text;
    return;
  end if;

  -- Se o status não for 'Ativa': NUNCA retorna o destino
  if v_plate.status <> 'Ativa' then
    return query select null::text, v_plate.status;
    return;
  end if;

  -- Validação rigorosa de URL compatível com POSIX do PostgreSQL:
  -- 1. Tamanho máximo de 2048 caracteres
  -- 2. Não contém espaços em branco
  -- 3. Esquema estrito http:// ou https://
  -- 4. Host com domínio válido (hífen posicionado no início da classe para evitar ambiguidades) e TLD >= 2
  v_is_valid_url := (
    v_plate.destination_url is not null and
    pg_catalog.length(v_plate.destination_url) <= 2048 and
    v_plate.destination_url !~ '\s' and
    v_plate.destination_url ~* '^https?://([a-zA-Z0-9]([-a-zA-Z0-9]{0,61}[a-zA-Z0-9])?\.)+[a-zA-Z]{2,}(:[0-9]{1,5})?(/.*)?$'
  );

  if not v_is_valid_url then
    return query select null::text, 'Destino invalido'::text;
    return;
  end if;

  -- Incremento atômico protegido por lock
  update public.plates
  set scans_count = scans_count + 1
  where id = v_plate.id;

  -- Retorno seguro: apenas o destino validado e o status 'Ativa'
  return query select v_plate.destination_url, v_plate.status;
end;
$$;

-- Permissões da função de redirecionamento
revoke all on function public.resolve_plate_redirect(text) from public;
grant execute on function public.resolve_plate_redirect(text) to anon, authenticated;
