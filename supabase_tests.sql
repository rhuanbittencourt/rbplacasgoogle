-- ====================================================================
-- BitDev CRM — Bateria de Testes SQL Reproduzíveis
-- Uso: Executar no SQL Editor do Supabase após aplicar o supabase_schema.sql
-- Objetivo: Comprovar empiricamente a segurança, RLS, concorrência e auditoria.
-- ====================================================================

-- Limpeza de registros de teste (se existirem)
do $$
begin
  -- Exclui apenas dados criados com prefixo de teste
  delete from public.plate_destination_history where plate_code like 'TEST-%';
  delete from public.sales where notes like 'TEST-%';
  delete from public.plates where code like 'TEST-%';
  delete from public.leads where name like 'TEST-%';
end $$;

-- --------------------------------------------------------------------
-- TESTE 1: Validação do Redirecionador (resolve_plate_redirect)
-- --------------------------------------------------------------------
-- Setup: Cria um lead e três placas de teste (Ativa, Inativa e com Link Inválido)
do $$
declare
  v_lead_id uuid;
  v_plate_active_id uuid;
begin
  insert into public.leads (name, stage)
  values ('TEST-Estabelecimento Piloto', 'Ganho')
  returning id into v_lead_id;

  -- 1. Placa Ativa com URL Válida
  insert into public.plates (code, lead_id, permanent_slug, destination_url, status)
  values ('TEST-PLQ-01', v_lead_id, 'test-slug-ativa', 'https://google.com/maps/place/bitdev', 'Ativa')
  returning id into v_plate_active_id;

  -- 2. Placa Inativa
  insert into public.plates (code, lead_id, permanent_slug, destination_url, status)
  values ('TEST-PLQ-02', v_lead_id, 'test-slug-inativa', 'https://instagram.com/bitdev', 'Inativa');

  -- 3. Placa com URL Maliciosa / Inválida
  insert into public.plates (code, lead_id, permanent_slug, destination_url, status)
  values ('TEST-PLQ-03', v_lead_id, 'test-slug-invalida', 'javascript:alert(1)', 'Ativa');

  -- 4. Placa com Soft Delete (deleted_at preenchido)
  insert into public.plates (code, lead_id, permanent_slug, destination_url, status, deleted_at)
  values ('TEST-PLQ-04', v_lead_id, 'test-slug-deletada', 'https://bitdev.com.br', 'Ativa', now());

  -- Cria registro de histórico de destino na placa ativa
  insert into public.plate_destination_history (plate_id, plate_code, old_destination_url, new_destination_url, change_note)
  values (v_plate_active_id, 'TEST-PLQ-01', null, 'https://google.com/maps/place/bitdev', 'Cadastro inicial');
end $$;

-- Verificação 1.1: Placa Ativa deve retornar URL e status 'Ativa'
select
  'Teste 1.1 - Placa Ativa' as caso_teste,
  destination_url = 'https://google.com/maps/place/bitdev' as destino_correto,
  status = 'Ativa' as status_correto
from public.resolve_plate_redirect('test-slug-ativa');

-- Verificação 1.2: Contador de acessos deve ter incrementado de 0 para 1
select
  'Teste 1.2 - Incremento do Contador' as caso_teste,
  scans_count = 1 as contador_incrementado
from public.plates
where permanent_slug = 'test-slug-ativa';

-- Verificação 1.3: Placa Inativa DEVE retornar destination_url como NULL
select
  'Teste 1.3 - Blindagem Placa Inativa' as caso_teste,
  destination_url is null as destino_oculto_corretamente,
  status = 'Inativa' as status_correto
from public.resolve_plate_redirect('test-slug-inativa');

-- Verificação 1.4: Placa com Link Inválido DEVE retornar destination_url como NULL
select
  'Teste 1.4 - Rejeição URL Inválida' as caso_teste,
  destination_url is null as destino_bloqueado,
  status = 'Destino invalido' as status_correto
from public.resolve_plate_redirect('test-slug-invalida');

-- Verificação 1.5: Placa Arquivada (Soft Deleted) DEVE retornar destination_url como NULL
select
  'Teste 1.5 - Placa Arquivada' as caso_teste,
  destination_url is null as destino_oculto,
  status = 'Inativa' as status_correto
from public.resolve_plate_redirect('test-slug-deletada');

-- Verificação 1.6: Slug Inexistente
select
  'Teste 1.6 - Slug Inexistente' as caso_teste,
  destination_url is null as destino_nulo,
  status = 'Nao encontrada' as status_correto
from public.resolve_plate_redirect('slug-que-nao-existe-xyz');

-- --------------------------------------------------------------------
-- TESTE 2: Preservação de Auditoria e Integridade Referencial
-- --------------------------------------------------------------------
-- Tenta excluir fisicamente a placa TEST-PLQ-01 (que possui histórico em plate_destination_history)
-- Deve falhar com erro de chave estrangeira RESTRICT.
do $$
begin
  delete from public.plates where code = 'TEST-PLQ-01';
  raise exception 'FALHA DE SEGURANÇA: A placa foi excluída violando a restrição de auditoria!';
exception
  when foreign_key_violation then
    raise notice 'SUCESSO NO TESTE 2: O banco impediu a exclusão física da placa com histórico (RESTRICT funcionou).';
end $$;

-- --------------------------------------------------------------------
-- TESTE 3: Verificação de RLS e Políticas
-- --------------------------------------------------------------------
-- Testa se usuário sem privilégios admin é bloqueado pelo is_admin()
select
  'Teste 3 - Função is_admin()' as caso_teste,
  public.is_admin() as resultado_esperado_false_para_usuario_anonimo;
