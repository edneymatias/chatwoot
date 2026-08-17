# Production Secrets & Encryption Hardening

**Status**: Backlog / Placeholder — pending dedicated brainstorm session
**Data**: 2026-08-17
**Origem**: Levantado durante a revisão técnica de `docs/kanban/backlog/bot/spec60.md` (motor de agentes IA "Scout"), quando a decisão de tornar `ActiveRecord::Encryption` obrigatória para `api_key_override`/`auth_headers` do Scout expôs uma lacuna maior e pré-existente.

## Problema confirmado

- `ActiveRecord::Encryption` é **opcional** neste fork: `config/application.rb` só ativa `config.active_record.encryption.*` `if ENV['ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY'].present?` (linhas 80-83, guard replicado em `Chatwoot.encryption_configured?`, linha ~111-113).
- Confirmado que o `.env` local deste ambiente de dev **não tem** essas três chaves configuradas (`ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY` / `_DETERMINISTIC_KEY` / `_KEY_DERIVATION_SALT` comentadas em `.env.example:12-14`, ausentes no `.env` real).
- Consequência: todo campo já marcado `encrypts :campo if Chatwoot.encryption_configured?` no código atual (senha IMAP/SMTP em `channel/email.rb`, token do WhatsApp Business em `channel/whatsapp.rb`, `access_token` em `integrations/hook.rb`, webhook secrets) está sendo gravado **em texto plano** sempre que essas chaves não estão presentes — silenciosamente, sem erro.
- Em produção, o problema é maior: `docker-compose.production.yaml:6` usa `env_file: .env`, mas **Docker Swarm (`docker stack deploy`) não processa `env_file:`** de forma confiável — é uma limitação conhecida do modo swarm. O stack de produção do usuário (mantido fora deste repo) não tem essas variáveis configuradas hoje.

## O que precisa ser decidido/desenhado (fase futura)

1. **Geração das chaves**: `bin/rails db:encryption:init` gera as três chaves de forma seudoaleatória e segura.
2. **Onde/como armazenar em produção no Swarm**: `environment:` puro no stack file vs. **Docker Swarm secrets** (`docker secret create`) — recomendação preliminar é usar Swarm secrets para essas chaves especificamente, dado o impacto de vazamento (compromete todo dado criptografado, incluindo futuras chaves BYOK do Scout). A decisão final depende de como o stack atual já trata `SECRET_KEY_BASE`/`POSTGRES_PASSWORD` (consistência vs. melhor prática).
3. **Backfill de dados já gravados em texto plano**: ativar as chaves não recriptografa retroativamente linhas já existentes (ex. senha IMAP/SMTP salvas antes do fix). Precisa de uma estratégia de re-save/backfill nos registros afetados em produção.
4. **Bloqueio de instalação**: avaliar se o boot da aplicação deveria falhar/alertar quando `Chatwoot.encryption_configured?` for falso em `RAILS_ENV=production`, em vez de degradar silenciosamente para texto plano.
5. **Dependência do Scout**: a decisão (b) tomada em `spec60.md`/decomposição do Scout torna criptografia obrigatória para `api_key_override`/`auth_headers` — este item deve ser resolvido (ou pelo menos as chaves geradas e no stack de produção) **antes** de qualquer fase do Scout que grave esses campos em produção.

## Não-escopo (por ora)

- Rotação de chaves de criptografia.
- Gestão de segredos via Vault/KMS externo (fora do Docker Swarm nativo) — pode ser avaliado se justificado durante o brainstorm dedicado.

## Próximo passo

Retomar como sessão de brainstorm dedicada quando o trabalho do Scout chegar na fase que grava campos criptografados, ou antes se o usuário priorizar isoladamente.
