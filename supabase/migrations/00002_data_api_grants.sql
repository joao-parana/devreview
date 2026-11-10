-- 00002_data_api_grants.sql
-- Supabase (a partir de 2026-10-30) não expõe mais tabelas novas automaticamente à Data API.
-- Grants explícitos e mínimos + RLS.

-- service_role (MCP server): ignora RLS, mas ainda precisa de GRANT
grant select, insert, update, delete on teams, review_rules, review_history, adrs to service_role;

-- anon (frontend): somente leitura das tabelas exibidas
grant select on review_rules, review_history, adrs to anon;

-- RLS ligada em todas as tabelas; sem policy = nada passa para anon/authenticated
alter table teams          enable row level security;
alter table review_rules   enable row level security;
alter table review_history enable row level security;
alter table adrs           enable row level security;

create policy "anon lê regras"    on review_rules   for select to anon using (true);
create policy "anon lê histórico" on review_history for select to anon using (true);
create policy "anon lê ADRs"      on adrs           for select to anon using (true);
