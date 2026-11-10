# Usando o Supabase Cloud no DevReview

Este fork usa **somente o Supabase Cloud** — o stack local (`npx supabase start`, Docker/Colima) não é usado.
Este guia explica o que muda em relação ao projeto-base do curso (que roda o Supabase local):

> **Regra de ouro do CLI 3.x:** comandos de banco (`db push`, `migration list`, `migration repair`…) miram o
> banco **local** por padrão. Para a nuvem, **sempre** acrescente `--remote`. Sem ele, o erro é
> `DbConnectError ... connect ECONNREFUSED 127.0.0.1:54322` — o CLI tentou o Docker local, não a nuvem.

| Item           | Valor                                                                   |
| -------------- | ----------------------------------------------------------------------- |
| URL da API     | `https://lruandogseofophefsum.supabase.co`                              |
| Project ref    | `lruandogseofophefsum`                                                  |
| Senha do banco | definida na criação do projeto — **nunca** gravar em arquivo versionado |

## Resumo

A pasta `supabase/` quase não muda: a migration e o seed são os mesmos. O que muda é **para onde** eles são
aplicados e **quais chaves** o app usa.

| O quê                                           | Local                            | Cloud                       | Ação                              |
| ----------------------------------------------- | -------------------------------- | --------------------------- | --------------------------------- |
| `supabase/migrations/00001_init_schema.sql`     | `db reset`                       | `db push --remote`          | nenhuma                           |
| `supabase/migrations/00002_data_api_grants.sql` | —                                | **obrigatória**             | já criada (ver passo 3)           |
| `supabase/seed.sql`                             | `db reset`                       | `db push --remote --include-seed` | nenhuma                           |
| `supabase/config.toml`                          | ports, auth, studio              | ignorado pela nuvem         | ajustar `major_version` (passo 2) |
| `supabase/.temp/`                               | —                                | criado pelo `supabase link` | já está no `.gitignore`           |
| `apps/web/.env`                                 | `localhost:54321` + anon demo    | URL cloud + publishable key | trocar valores                    |
| `apps/mcp-server/.env`                          | `localhost:54321` + service demo | URL cloud + secret key      | trocar valores                    |

> O `config.toml` só configura o stack **local** (portas, Studio, SMTP de teste, Auth). A nuvem só o lê se você
> rodar `supabase config push`. **Não rode**: ele sobrescreveria `auth.site_url` e
> `auth.additional_redirect_urls` do projeto cloud com os valores locais, e o app nem usa Auth (nenhuma aula
> do curso usa). Para comparar local × nuvem sem alterar nada, use `npx supabase config diff --agent no`.
>
> **CLI 3.x:** a seção `[inbucket]` foi renomeada para `[local_smtp]`; com o nome antigo, todo comando falha
> com `[inbucket] ... is no longer supported`. O `config.toml` deste fork já usa `[local_smtp]` (o do upstream
> ainda usa `[inbucket]` — atenção ao fazer merge).

## Passo 1 — Login e link do projeto

O Supabase CLI não está instalado globalmente; use via `npx` dentro de `devreview/`.

```bash
cd devreview
npx supabase login --agent no                                     # abre o navegador e gera um access token
npx supabase link --project-ref lruandogseofophefsum --agent no   # pede a senha do banco
```

> **Por que `--agent no`?** O CLI 3.x detecta agentes de IA (variáveis `CLAUDECODE`, `AI_AGENT`) e passa a
> responder em JSON, sem prompts interativos — o login falha com `NonInteractiveError: Cannot prompt for input
> in JSON output mode`. O terminal do app Claude herda essas variáveis. Use `--agent no` nos comandos
> interativos (`login`, `link`, `db push`) ou rode-os num terminal comum (Terminal.app, iTerm).
>
> Alternativa sem prompt: gere um *Personal Access Token* em **Dashboard → Account → Access Tokens** e use
> `npx supabase login --token sbp_...` (ou `export SUPABASE_ACCESS_TOKEN=sbp_...` só na sessão).

- O `link` grava metadados (project ref, URL do pooler) em `supabase/.temp/` — **sem** a senha. Essa pasta
  não deve ser versionada.
- Para não digitar a senha a cada comando, exporte-a só na sessão do terminal:
  `export SUPABASE_DB_PASSWORD='...'` (não coloque no `~/.zshrc` nem em `.env` versionado).

## Passo 2 — Alinhar a versão do Postgres

O `config.toml` declara `major_version = 15`, mas projetos novos na nuvem rodam uma versão mais recente.
Confira em **Dashboard → Project Settings → Infrastructure** ou rodando `select version();` no
**SQL Editor**. Na **Cloud do Supabase** a versão é `17.11.0.018`

Ajuste `[db] major_version` no `config.toml` para a mesma versão, para que o ambiente local reproduza a
nuvem. O próprio `supabase link` emite um aviso quando há divergência.

## Passo 3 — Permissões da Data API (obrigatório em projetos novos)

**A partir de 30/10/2026** o Supabase deixou de conceder automaticamente `SELECT/INSERT/UPDATE/DELETE` aos
papéis `anon`, `authenticated` e `service_role` em **tabelas novas** do schema `public`. Este projeto foi
criado depois disso, então, só com a `00001`, as tabelas existem mas a API REST responde:

```
permission denied for table review_rules   (código 42501)
```

Por isso o projeto tem `supabase/migrations/00002_data_api_grants.sql`, com permissões **mínimas**, conforme o
que cada parte do app faz:

| Quem                           | Papel / chave                               | Precisa de                                            |
| ------------------------------ | ------------------------------------------- | ----------------------------------------------------- |
| Frontend (`apps/web`)          | `anon` (publishable key, pública no bundle) | `SELECT` em `review_rules`, `review_history`, `adrs`  |
| MCP server (`apps/mcp-server`) | `service_role` (secret key, só no servidor) | `SELECT` nas 4 tabelas + `INSERT` em `review_history` |

```sql
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
```

Pontos importantes:

- **Não use** `grant all on all tables in schema public to anon` — é o "conserto" mais comum e expõe escrita
  para qualquer um que tenha a publishable key (que fica visível no JavaScript do navegador).
- As policies `using (true)` deixam os dados **legíveis publicamente**. Tudo bem para o seed de demonstração;
  com dados reais, filtre por time/usuário (exige Auth).
- A migration também roda no ambiente local (`db reset`) sem quebrar nada.
- O upstream do curso (`alura-cursos/devreview`) só tem a `00001` em todas as aulas, então o nome `00002`
  não conflita com as lições.

## Passo 4 — Aplicar schema e seed na nuvem

```bash
npx supabase migration list --remote --agent no                 # Local x Remote (antes: Remote vazio)
npx supabase db push --remote --dry-run --agent no              # mostra o que seria aplicado
npx supabase db push --remote --include-seed --agent no         # aplica 00001 + 00002 e roda o seed.sql
npx supabase migration list --remote --agent no                 # depois: Local = Remote
```

> **CLI 3.x: o alvo padrão é o banco LOCAL.** Sem `--remote`, `db push` e `migration list` tentam
> `127.0.0.1:54322` (o `supabase start`) mesmo com o projeto linkado. `--remote` usa o projeto linkado; a
> senha é pedida no prompt, ou passe `-p` / `SUPABASE_DB_PASSWORD`.

- A ordem importa: a `00002` dá `GRANT` nas tabelas criadas pela `00001`, por isso as duas sobem juntas.
- Se a `00001` falhar com `relation "teams" already exists`, as tabelas já foram criadas por fora (ex.: SQL
  Editor). Nesse caso, marque-a como aplicada sem rodar:
  `npx supabase migration repair 00001 --status applied --remote --agent no`, e repita o `db push`.
- **Não use `db reset --remote`** depois que houver dados reais: ele apaga o banco remoto.
- O `seed.sql` faz `insert` com IDs fixos: rodá-lo duas vezes falha por chave duplicada. Para recarregar os
  dados, limpe as tabelas antes, pelo **SQL Editor** ou `psql`.

## Passo 5 — Chaves de API e arquivos `.env`

Em **Dashboard → Project Settings → API Keys** há dois tipos de chave:

| Uso        | Chave nova (recomendada) | Equivalente legado (ainda válido) |
| ---------- | ------------------------ | --------------------------------- |
| Frontend   | `sb_publishable_...`     | `anon` (JWT `eyJ...`)             |
| MCP server | `sb_secret_...`          | `service_role` (JWT `eyJ...`)     |

Os **nomes** das variáveis não mudam; só os valores.

`apps/web/.env`:

```dotenv
VITE_SUPABASE_URL=https://lruandogseofophefsum.supabase.co
VITE_SUPABASE_ANON_KEY=sb_publishable_xxxxxxxxxxxxxxxx
```

`apps/mcp-server/.env`:

```dotenv
SUPABASE_URL=https://lruandogseofophefsum.supabase.co
SUPABASE_SERVICE_KEY=sb_secret_xxxxxxxxxxxxxxxx
```

- A **secret key** (ou `service_role`) ignora RLS: nunca coloque em variável `VITE_*`, porque o Vite embute
  essas variáveis no bundle do navegador. A secret key nova também recusa requisições vindas de browser.
- Os `.env` já estão no `.gitignore` (`.env` e `.env.*`, exceto `.env.example`). **Não** altere os
  `.env.example`: eles continuam apontando para o ambiente local, como o curso espera.
- Se algo falhar com as chaves novas, use as legadas (`anon` / `service_role`) enquanto ainda forem aceitas.

Como este fork usa **só a nuvem**, os valores acima vão direto em `apps/web/.env` e `apps/mcp-server/.env`;
`npm run dev` já sobe o frontend contra o Supabase Cloud. O MCP server lê `apps/mcp-server/.env` via
`node --env-file=...` (nas aulas finais).

## Passo 6 — MCP oficial do Supabase (aulas finais)

Nas últimas aulas o curso adiciona ao `.mcp.json` o servidor MCP oficial do Supabase, que usa o
**project ref**:

```json
"supabase": {
  "type": "http",
  "url": "https://mcp.supabase.com/mcp?project_ref=lruandogseofophefsum&read_only=true&feature_groups=database"
}
```

Use **o seu** project ref (o gabarito da Alura aponta para o projeto dela). O `read_only=true` impede que o
agente altere o banco. A autenticação é feita por OAuth no primeiro uso.

## Conexão direta com `psql` (opcional)

Use o botão **Connect** do dashboard para copiar a string exata. Há dois formatos:

```text
# Direta — só IPv6, a menos que o add-on de IPv4 esteja ativo
postgresql://postgres:[SENHA]@db.lruandogseofophefsum.supabase.co:5432/postgres

# Pooler (Supavisor), session mode — funciona em IPv4
postgresql://postgres.lruandogseofophefsum:[SENHA]@aws-<n>-<região>.pooler.supabase.com:5432/postgres
```

Isso permite, por exemplo, usar o seu `psql` do Postgres 18 local contra o banco da nuvem. A senha do banco
serve **só** para isso e para o CLI; o app nunca a usa.

## Checklist

- [ ] `npx supabase login` e `npx supabase link --project-ref lruandogseofophefsum`
- [ ] `major_version` do `config.toml` igual à versão da nuvem
- [x] `supabase/migrations/00002_data_api_grants.sql` criada
- [ ] `npx supabase db push --remote --include-seed` sem erros; `migration list --remote` com Local = Remote
- [ ] `apps/web/.env` e `apps/mcp-server/.env` com URL e chaves da nuvem
- [ ] Dashboard → **Advisors → Security** sem alertas de "RLS disabled"
- [ ] App em `http://localhost:5173` mostrando os dados sem o banner de erro

## Referências

- [Understanding API keys](https://supabase.com/docs/guides/api/api-keys)
- [Migrating to publishable and secret API keys](https://supabase.com/docs/guides/getting-started/migrating-to-new-api-keys)
- [Supabase Data API exposure changes on 30 October](https://dev.to/davekurian/supabase-data-api-exposure-changes-on-30-october-grant-tables-explicitly-2pe7)
- [GRANT ALL to anon is the wrong fix for 42501](https://dev.to/patchandship/grant-all-to-anon-is-the-wrong-fix-for-supabase-42501-after-oct-30-1bdm)
