#!/usr/bin/env bash
# Re-apply per-agent AGENT_HOME on the deployed Paperclip. `paperclipai company import`
# only persists agent template-frontmatter fields and DROPS DB-only adapter_config.env —
# so run this AFTER every company import. Idempotent.
#
# WHY a script and not frontmatter: AGENT_HOME must embed the agent's OWN id
# (/home/agent/.paperclip/agents/<id>) for per-agent memory isolation, and the id is not
# known pre-import — so it can't be a static template literal. config.env is the LAST env
# writer in the adapter (server-utils.ts), so this override wins over the phantom
# control-plane AGENT_HOME and lands para-memory on the durable VPS home.
#
# Usage: bash reapply-agent-home.sh        (reads the deployed DB via ssh bento)
set -euo pipefail
printf '%s\n' "
UPDATE agents SET adapter_config = coalesce(adapter_config,'{}'::jsonb)
  || jsonb_build_object('env', coalesce(adapter_config->'env','{}'::jsonb)
       || jsonb_build_object('AGENT_HOME','/home/agent/.paperclip/agents/'||id::text))
  WHERE adapter_type='claude_local' AND status <> 'terminated';
SELECT 'AGENT_HOME set on '||count(*)||' claude_local agents' FROM agents
  WHERE adapter_type='claude_local' AND adapter_config#>>'{env,AGENT_HOME}' LIKE '/home/agent/%';
" | ssh bento 'C=$(docker ps --format "{{.Names}}" | grep -E "paperclip.*db" | head -1); docker exec -i "$C" psql -U paperclip -d paperclip -tA'
