---
name: agendamento
title: Agendamento do lead qualificado
priority: 20
when_state:
  - opportunity_in_stage: qualified
  - contact_has_phone
  - playbook_not_completed: agendamento
trigger: >
  O lead foi qualificado e o próximo passo é agendar um atendimento.
requires: [scheduling, customer_registry]
needs: [politica_reagendamento]
exits:
  agendado:
    kind: terminal
    fields:
      inicio: datetime
  sem_horario:
    kind: terminal
    fields:
      motivo: string
---

## Fluxo de Agendamento

1. Localize ou crie o cadastro do cliente pelo telefone informado [[depends: customer_registry]]
2. Pergunte qual o dia de preferência para o atendimento da consulta.
3. Apresente no máximo três horários disponíveis para escolha do cliente [[depends: scheduling]]
4. Ao confirmar a escolha do cliente, registre a reserva e acione exit_agendado com o início escolhido [[depends: scheduling]]
5. Se não houver horário na janela desejada, ofereça a data mais próxima e registre exit_sem_horario caso todas as opções sejam recusadas [[depends: scheduling]]
6. Informe as políticas e regras para remarcação ou cancelamento da clínica [[depends: politica_reagendamento]]
7. Caso o cliente solicite falar com uma pessoa, declare urgência clínica, ou após duas tentativas sem conseguir localizar o cadastro, acione exit_handoff.
8. Se qualquer ação necessária estiver indisponível no sistema, não prometa a reserva e chame exit_handoff neste mesmo turno.
